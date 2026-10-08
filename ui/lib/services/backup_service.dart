import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'app_settings.dart';
import 'backup_storage.dart';
import 'cloud/cloud_provider.dart';
import 'local_documents_store.dart';
import 'plan_service.dart';

class BackupInfo {
  const BackupInfo({
    required this.createdAt,
    required this.documentCount,
    this.missingCount = 0,
  });
  final DateTime createdAt;
  final int documentCount;

  /// Documents of the backup whose file could no longer be found anywhere
  /// in the backup folder; they're left out of the restored library.
  final int missingCount;
}

class InvalidBackupException implements Exception {
  const InvalidBackupException();
}

/// One restore point of the history.
class BackupSnapshot {
  const BackupSnapshot({
    required this.name,
    required this.createdAt,
    this.storage,
    this.isLatest = false,
    this.legacyProvider,
    this.legacyCloudItem,
    this.legacyFile,
  });

  /// The "Backup ..." folder inside the backup root, or a legacy zip's name.
  final String name;
  final DateTime createdAt;

  /// Where the snapshot lives (null for a legacy zip).
  final BackupStorage? storage;

  /// The newest snapshot: what `Current` holds right now.
  final bool isLatest;

  /// A single-zip backup made before backups became a folder tree.
  final CloudProvider? legacyProvider;
  final CloudItem? legacyCloudItem;
  final File? legacyFile;

  bool get isLegacy => legacyCloudItem != null || legacyFile != null;
}

/// Backup of the whole library as a browsable folder tree, kept the same way
/// AllPhotos keeps its Drive backups:
///
///     AllDocs Backups/
///       Current/                      the library as it is now
///         alldocs-current.json        index of Current (path → checksum)
///         Gallery/                    every document of the gallery
///         Archive/                    archived documents (when there are)
///         <album>/                    one folder per album, with its documents
///       Removed/                      files gone from the library that an
///                                     older backup still lists
///       Backup 2026-10-06 14-30-05/   one restore point per backup run
///         alldocs-state.json          the library's organization at the time
///         alldocs-backup.json         what was in it, file by file
///
/// Only `Current` holds document files, and a backup run only sends what
/// changed since the previous one. A "Backup ..." folder is just JSON: its
/// documents are found again by checksum, in `Current` or, once deleted
/// from the library, in `Removed` — kept for as long as any retained
/// backup still needs them.
///
/// The same tree is written to a folder on the phone or to a cloud
/// account (see [BackupStorage]).
class BackupService {
  const BackupService({this.store = const LocalDocumentsStore()});

  final LocalDocumentsStore store;
  static const manifestVersion = 2;
  static const rootFolderName = 'AllDocs Backups';
  static const currentFolder = 'Current';
  static const removedFolder = 'Removed';
  static const galleryFolder = 'Gallery';
  static const archiveFolder = 'Archive';
  static const liveManifestName = 'alldocs-current.json';
  static const backupManifestName = 'alldocs-backup.json';
  static const stateFileName = 'alldocs-state.json';
  static const backupFolderPrefix = 'Backup ';
  static const autoBackupInterval = Duration(hours: 24);

  /// Restore points kept; older ones are deleted after each backup run (and
  /// with them, the removed files only they still needed).
  static const keptBackups = 10;

  static const _legacyPrefix = 'AllDocs_backup_';
  static const _parallelTransfers = 4;

  String backupFolderName(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '$backupFolderPrefix${time.year}-${two(time.month)}-'
        '${two(time.day)} ${two(time.hour)}-${two(time.minute)}-'
        '${two(time.second)}';
  }

  // ---------------------------------------------------------------------
  // Backing up
  // ---------------------------------------------------------------------

  Future<void> backupToCloud(CloudProvider provider) async {
    await backupTo(provider.backupStorage());
    await AppSettings.setLastBackupAt(DateTime.now());
  }

  /// Lets the user pick a folder and backs up into its "AllDocs Backups"
  /// folder. Picking the same folder again only adds what changed.
  Future<String?> saveBackupToDevice({String? dialogTitle}) async {
    final target = await FilePicker.getDirectoryPath(dialogTitle: dialogTitle);
    if (target == null || target.trim().isEmpty) return null;
    final root = deviceBackupRoot(target);
    await backupTo(DeviceBackupStorage(root));
    await AppSettings.setLastBackupAt(DateTime.now());
    return root.path;
  }

  /// The "AllDocs Backups" folder for a folder the user picked — the picked
  /// folder itself when that's already it.
  Directory deviceBackupRoot(String picked) {
    final trimmed = picked.endsWith('/')
        ? picked.substring(0, picked.length - 1)
        : picked;
    return _baseName(trimmed) == rootFolderName
        ? Directory(trimmed)
        : Directory('$trimmed/$rootFolderName');
  }

  /// Brings `Current` in line with the library, then files a new restore
  /// point and drops the ones past [keptBackups].
  Future<void> backupTo(BackupStorage storage, {DateTime? now}) async {
    final createdAt = now ?? DateTime.now();
    final state = await store.exportState();
    // The recycle bin isn't backed up: those documents are on their way out.
    _dropDocuments(state, {
      for (final raw in _documentsList(state))
        if (raw['deleted_at'] != null) raw['id']?.toString() ?? '',
    });
    final plan = await _plan(state);
    _dropDocuments(state, plan.unavailableIds);

    await _syncCurrent(storage, plan);

    final rootEntries = await storage.list('');
    final taken = {
      for (final entry in rootEntries)
        if (entry.isFolder) entry.name,
    };
    var folder = backupFolderName(createdAt);
    for (var n = 2; taken.contains(folder); n++) {
      folder = '${backupFolderName(createdAt)} ($n)';
    }
    await storage.writeText('$folder/$stateFileName', jsonEncode(state));
    // Written last: a folder without it is an interrupted run.
    await storage.writeText(
      '$folder/$backupManifestName',
      jsonEncode(_manifest(plan, createdAt)),
    );

    try {
      await _pruneHistory(storage, keep: folder);
    } catch (_) {
      // Best-effort: a failed cleanup must not turn a good backup into an
      // error. The next run tries again.
    }
  }

  Future<_BackupPlan> _plan(Map<String, dynamic> state) async {
    final documents =
        _documentsList(state)
            .map(DocumentFile.fromJson)
            .where((document) => !document.isDeleted)
            .toList()
          // Oldest first, so the "(2)" of a repeated name stays put.
          ..sort((a, b) {
            final byDate = (a.importedAt ?? DateTime(1970)).compareTo(
              b.importedAt ?? DateTime(1970),
            );
            return byDate != 0 ? byDate : a.id.compareTo(b.id);
          });
    final shelves =
        (state['shelves'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (raw) => DocumentShelf.fromJson(Map<String, dynamic>.from(raw)),
            )
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));

    // Folder names are compared ignoring case: the phone's storage, Dropbox
    // and Windows all treat "Faturas" and "faturas" as the same folder.
    final takenFolders = {
      galleryFolder.toLowerCase(),
      archiveFolder.toLowerCase(),
    };
    final albums = <_PlannedAlbum>[];
    for (final shelf in shelves) {
      final sorted = [...shelf.albums]
        ..sort((a, b) => a.position.compareTo(b.position));
      for (final album in sorted) {
        final folder = _uniqueName(
          _sanitize(album.name, fallback: 'Album'),
          takenFolders,
        );
        albums.add(_PlannedAlbum(album: album, shelf: shelf, folder: folder));
      }
    }
    final albumById = {for (final album in albums) album.album.id: album};

    final takenNames = <String, Set<String>>{};
    String place(String folder, DocumentFile document) {
      final taken = takenNames.putIfAbsent(folder, () => {});
      return '$currentFolder/$folder/'
          '${_uniqueName(_displayFileName(document), taken)}';
    }

    final files = <_PlannedFile>[];
    final unavailable = <String>{};
    for (final document in documents) {
      final path = document.localPath;
      final file = path == null ? null : File(path);
      if (file == null || !await file.exists()) {
        unavailable.add(document.id);
        continue;
      }
      final checksum = document.checksum ?? await _checksumOf(file);
      if (checksum == null) {
        unavailable.add(document.id);
        continue;
      }
      final documentAlbums = [
        for (final id in document.albumIds) ?albumById[id],
      ];
      files.add(
        _PlannedFile(
          document: document,
          file: file,
          checksum: checksum,
          canonicalPath: place(
            document.isArchived ? archiveFolder : galleryFolder,
            document,
          ),
          albumPaths: [
            for (final album in documentAlbums) place(album.folder, document),
          ],
        ),
      );
    }
    return _BackupPlan(
      files: files,
      albums: albums,
      unavailableIds: unavailable,
    );
  }

  Future<void> _syncCurrent(BackupStorage storage, _BackupPlan plan) async {
    final previous = await _readLiveIndex(storage);
    final desiredFolders = {
      galleryFolder,
      if (plan.files.any((file) => file.document.isArchived)) archiveFolder,
      for (final album in plan.albums) album.folder,
    };
    final currentFolders = {
      for (final entry in await storage.list(currentFolder))
        if (entry.isFolder) entry.name,
    };

    // Every file of Current that matters, by path.
    final occupied = <String>{};
    for (final folder in {...desiredFolders, ...currentFolders}) {
      for (final entry in await storage.list('$currentFolder/$folder')) {
        if (!entry.isFolder) {
          occupied.add('$currentFolder/$folder/${entry.name}');
        }
      }
    }
    for (final folder in desiredFolders) {
      await storage.ensureFolder('$currentFolder/$folder');
    }
    bool upToDate(String path, String checksum) =>
        occupied.contains(path) && previous[path] == checksum;

    // Gallery and Archive: the one copy of each document.
    final canonical = {
      for (final file in plan.files) file.canonicalPath: file.checksum,
    };
    final pending = {
      for (final entry in canonical.entries)
        if (!upToDate(entry.key, entry.value)) entry.key: entry.value,
    };
    final keptChecksums = canonical.values.toSet();
    final removed = _RemovedFolder(storage);

    // A renamed, archived or unarchived document is moved, not sent again;
    // a file nothing in the library needs any more goes to Removed.
    Future<void> relocateOrRetire(String path) async {
      final checksum = previous[path];
      if (checksum != null) {
        final target = pending.entries
            .where(
              (entry) =>
                  entry.value == checksum && !occupied.contains(entry.key),
            )
            .map((entry) => entry.key)
            .firstOrNull;
        if (target != null) {
          await storage.move(path, target);
          occupied
            ..remove(path)
            ..add(target);
          pending.remove(target);
          return;
        }
        if (!keptChecksums.contains(checksum)) {
          await removed.retire(path, checksum);
          occupied.remove(path);
          return;
        }
      }
      await storage.delete(path);
      occupied.remove(path);
    }

    bool isCanonical(String path) =>
        path.startsWith('$currentFolder/$galleryFolder/') ||
        path.startsWith('$currentFolder/$archiveFolder/');
    // Stale content sitting where a document has to go first...
    for (final target in pending.keys.toList()) {
      if (pending.containsKey(target) && occupied.contains(target)) {
        await relocateOrRetire(target);
      }
    }
    // ...then whatever is left over from the previous run.
    for (final path in occupied.where(isCanonical).toList()) {
      if (!canonical.containsKey(path) && occupied.contains(path)) {
        await relocateOrRetire(path);
      }
    }
    final byPath = {for (final file in plan.files) file.canonicalPath: file};
    await _inParallel(pending.keys.toList(), (path) async {
      await storage.upload(path, byPath[path]!.file);
      occupied.add(path);
    });

    // Albums: server-side copies of the Gallery/Archive file.
    final albumCopies = {
      for (final file in plan.files)
        for (final path in file.albumPaths) path: file,
    };
    for (final path in occupied.where((path) => !isCanonical(path)).toList()) {
      final wanted = albumCopies[path];
      if (wanted == null || previous[path] != wanted.checksum) {
        await storage.delete(path);
        occupied.remove(path);
      }
    }
    await _inParallel(
      albumCopies.entries
          .where((entry) => !upToDate(entry.key, entry.value.checksum))
          .toList(),
      (entry) async {
        await storage.copy(entry.value.canonicalPath, entry.key);
        occupied.add(entry.key);
      },
    );

    // Albums that no longer exist, and Archive once nothing is archived.
    for (final folder in currentFolders.difference(desiredFolders)) {
      await storage.delete('$currentFolder/$folder');
    }

    await storage.writeText(
      '$currentFolder/$liveManifestName',
      jsonEncode({
        'app': 'AllDocs',
        'version': manifestVersion,
        'updated_at': DateTime.now().toIso8601String(),
        'files': {
          ...canonical,
          for (final entry in albumCopies.entries)
            entry.key: entry.value.checksum,
        },
      }),
    );
  }

  /// Current's own index: which checksum each file there has.
  Future<Map<String, String>> _readLiveIndex(BackupStorage storage) async {
    try {
      final text = await storage.readText('$currentFolder/$liveManifestName');
      if (text == null) return {};
      final json = jsonDecode(text);
      final files = json is Map ? json['files'] : null;
      if (files is! Map) return {};
      return {
        for (final entry in files.entries)
          entry.key.toString(): entry.value.toString(),
      };
    } on FormatException {
      // Unreadable: everything is sent again.
      return {};
    }
  }

  Map<String, dynamic> _manifest(_BackupPlan plan, DateTime createdAt) {
    return {
      'version': manifestVersion,
      'app': 'AllDocs',
      'created_at': createdAt.toIso8601String(),
      'document_count': plan.files.length,
      'documents': [
        for (final file in plan.files)
          {
            'id': file.document.id,
            'title': file.document.title,
            'file_name': file.document.fileName,
            'stored_name': _baseName(file.file.path),
            'checksum': file.checksum,
            'path': file.canonicalPath,
            'album_paths': file.albumPaths,
            'album_ids': file.document.albumIds,
            'tags': file.document.tags,
            'archived': file.document.isArchived,
            'favorite': file.document.isFavorite,
          },
      ],
      'albums': [
        for (final album in plan.albums)
          {
            'id': album.album.id,
            'name': album.album.name,
            'shelf': album.shelf.name,
            'folder': '$currentFolder/${album.folder}',
          },
      ],
      'tags': {for (final file in plan.files) ...file.document.tags}.toList(),
    };
  }

  /// Keeps the newest [keptBackups] complete restore points, deletes the
  /// rest (and interrupted ones), then empties Removed of every file no
  /// kept restore point lists any more.
  Future<void> _pruneHistory(
    BackupStorage storage, {
    required String keep,
  }) async {
    final folders = [
      for (final entry in await storage.list(''))
        if (entry.isFolder && entry.name.startsWith(backupFolderPrefix))
          entry.name,
    ]..sort((a, b) => b.compareTo(a));

    final referenced = <String>{};
    var kept = 0;
    for (final folder in folders) {
      if (kept >= keptBackups && folder != keep) {
        await storage.delete(folder);
        continue;
      }
      final manifest = await storage.readText('$folder/$backupManifestName');
      if (manifest == null) {
        if (folder != keep) await storage.delete(folder);
        continue;
      }
      kept++;
      for (final document in _manifestDocuments(jsonDecode(manifest))) {
        final checksum = document['checksum']?.toString();
        if (checksum != null) referenced.add(_RemovedFolder.prefix(checksum));
      }
    }

    for (final entry in await storage.list(removedFolder)) {
      if (entry.isFolder) continue;
      final prefix = _RemovedFolder.prefixOf(entry.name);
      if (prefix == null || !referenced.contains(prefix)) {
        await storage.delete('$removedFolder/${entry.name}');
      }
    }
  }

  /// Runs a cloud backup when auto-backup is on and the last one is older
  /// than [autoBackupInterval]. Silent and best-effort.
  Future<bool> runAutoBackupIfDue(
    CloudProvider? Function(String id) providerFor,
  ) async {
    if (!AppSettings.autoBackup.value) return false;
    // Automatic backup is a paid feature (Folio and up).
    if (!PlanService.current.value.has(PlanFeature.autoBackup)) return false;
    final providerId = AppSettings.backupProvider.value;
    if (providerId == null) return false;
    final last = AppSettings.lastBackupAt.value;
    if (last != null && DateTime.now().difference(last) < autoBackupInterval) {
      return false;
    }
    final provider = providerFor(providerId);
    if (provider == null || !await provider.isConnected()) return false;
    try {
      await backupToCloud(provider);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------

  /// The restore points in [storage], newest first.
  Future<List<BackupSnapshot>> listSnapshots(BackupStorage storage) async {
    final snapshots = <BackupSnapshot>[];
    for (final entry in await storage.list('')) {
      if (!entry.isFolder || !entry.name.startsWith(backupFolderPrefix)) {
        continue;
      }
      final createdAt = _dateFromFolderName(entry.name);
      if (createdAt == null) continue;
      final complete = (await storage.list(
        entry.name,
      )).any((file) => file.name == backupManifestName);
      if (!complete) continue;
      snapshots.add(
        BackupSnapshot(
          name: entry.name,
          createdAt: createdAt,
          storage: storage,
        ),
      );
    }
    snapshots.sort((a, b) => b.name.compareTo(a.name));
    return [
      for (final (index, snapshot) in snapshots.indexed)
        BackupSnapshot(
          name: snapshot.name,
          createdAt: snapshot.createdAt,
          storage: storage,
          isLatest: index == 0,
        ),
    ];
  }

  /// Restore points of a cloud account, plus its old single-zip backups.
  Future<List<BackupSnapshot>> listCloudSnapshots(
    CloudProvider provider,
  ) async {
    final legacy = <BackupSnapshot>[];
    try {
      for (final item in await provider.listLegacyBackups()) {
        if (!item.name.startsWith(_legacyPrefix)) continue;
        legacy.add(
          BackupSnapshot(
            name: item.name,
            createdAt:
                _dateFromLegacyName(item.name) ??
                item.modifiedAt ??
                DateTime(1970),
            legacyProvider: provider,
            legacyCloudItem: item,
          ),
        );
      }
    } catch (_) {
      // Old backups are a bonus; the current ones still list.
    }
    return [
      ...await listSnapshots(provider.backupStorage()),
      ...legacy..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    ];
  }

  /// Asks for the folder a backup was saved to (the "AllDocs Backups"
  /// folder or the one containing it).
  Future<Directory?> pickDeviceBackupFolder({String? dialogTitle}) async {
    final picked = await FilePicker.getDirectoryPath(dialogTitle: dialogTitle);
    if (picked == null || picked.trim().isEmpty) return null;
    return Directory(picked);
  }

  /// Restore points saved in [picked], plus old backup zips lying there.
  Future<List<BackupSnapshot>> listDeviceSnapshots(Directory picked) async {
    final root = deviceBackupRoot(picked.path);
    final legacy = <BackupSnapshot>[];
    for (final dir in {picked.path, root.path, root.parent.path}) {
      final directory = Directory(dir);
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(followLinks: false)) {
        final name = _baseName(entity.path);
        if (entity is! File ||
            !name.startsWith(_legacyPrefix) ||
            !name.endsWith('.zip') ||
            legacy.any((snapshot) => snapshot.name == name)) {
          continue;
        }
        legacy.add(
          BackupSnapshot(
            name: name,
            createdAt:
                _dateFromLegacyName(name) ?? (await entity.lastModified()),
            legacyFile: entity,
          ),
        );
      }
    }
    return [
      ...await listSnapshots(DeviceBackupStorage(root)),
      ...legacy..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    ];
  }

  // ---------------------------------------------------------------------
  // Restoring
  // ---------------------------------------------------------------------

  /// Replaces AllDocs' current documents and organization with [snapshot].
  Future<BackupInfo> restoreSnapshot(BackupSnapshot snapshot) async {
    final legacyFile = snapshot.legacyFile;
    if (legacyFile != null) return _restoreLegacyZip(legacyFile);
    final legacyItem = snapshot.legacyCloudItem;
    final legacyProvider = snapshot.legacyProvider;
    if (legacyItem != null && legacyProvider != null) {
      return _restoreLegacyCloudZip(legacyProvider, legacyItem);
    }
    final storage = snapshot.storage;
    if (storage == null) throw const InvalidBackupException();

    final manifestText = await storage.readText(
      '${snapshot.name}/$backupManifestName',
    );
    final stateText = await storage.readText('${snapshot.name}/$stateFileName');
    if (manifestText == null || stateText == null) {
      throw const InvalidBackupException();
    }
    final Object? manifest;
    final Object? state;
    try {
      manifest = jsonDecode(manifestText);
      state = jsonDecode(stateText);
    } on FormatException {
      throw const InvalidBackupException();
    }
    if (manifest is! Map ||
        manifest['app'] != 'AllDocs' ||
        state is! Map<String, dynamic>) {
      throw const InvalidBackupException();
    }

    // Where each file can be now: wherever Current has that checksum, or
    // Removed once it left the library.
    final byChecksum = <String, String>{};
    for (final entry in (await _readLiveIndex(storage)).entries) {
      final isCanonical =
          entry.key.startsWith('$currentFolder/$galleryFolder/') ||
          entry.key.startsWith('$currentFolder/$archiveFolder/');
      if (isCanonical || !byChecksum.containsKey(entry.value)) {
        byChecksum[entry.value] = entry.key;
      }
    }
    final removedByPrefix = <String, String>{
      for (final entry in await storage.list(removedFolder))
        if (!entry.isFolder && _RemovedFolder.prefixOf(entry.name) != null)
          _RemovedFolder.prefixOf(entry.name)!: '$removedFolder/${entry.name}',
    };

    final staging = await Directory.systemTemp.createTemp('alldocs_restore_');
    try {
      final restored = <String, File>{};
      final missing = <String>{};
      final documents = _manifestDocuments(manifest).toList();
      await _inParallel(documents, (document) async {
        final id = document['id']?.toString() ?? '';
        final checksum = document['checksum']?.toString();
        final storedName = _baseName(document['stored_name']?.toString() ?? '');
        if (id.isEmpty ||
            checksum == null ||
            storedName.isEmpty ||
            storedName == '.' ||
            storedName == '..') {
          missing.add(id);
          return;
        }
        final candidates = {
          ?byChecksum[checksum],
          ?removedByPrefix[_RemovedFolder.prefix(checksum)],
          ?document['path']?.toString(),
          for (final path in (document['album_paths'] as List? ?? const []))
            path.toString(),
        };
        final target = File('${staging.path}/$storedName');
        for (final path in candidates) {
          try {
            await storage.download(path, target);
          } on BackupNotFoundException {
            continue;
          }
          // A path from an older run may hold another file by now.
          if (await _checksumOf(target) == checksum) {
            restored[id] = target;
            return;
          }
        }
        missing.add(id);
      });

      final documentsDir = await store.documentsDirectory();
      for (final file in restored.values) {
        final destination = '${documentsDir.path}/${_baseName(file.path)}';
        try {
          await file.rename(destination);
        } on FileSystemException {
          await file.copy(destination);
        }
      }
      _dropDocuments(state, {
        ...missing,
        for (final raw in _documentsList(state))
          if (!restored.containsKey(raw['id']?.toString()))
            ?raw['id']?.toString(),
      });
      await store.restoreState(state);
      return BackupInfo(
        createdAt:
            DateTime.tryParse(manifest['created_at']?.toString() ?? '') ??
            snapshot.createdAt,
        documentCount: restored.length,
        missingCount: missing.length,
      );
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<BackupInfo> _restoreLegacyCloudZip(
    CloudProvider provider,
    CloudItem backup,
  ) async {
    final downloaded = await provider.download(backup);
    final temp = await getTemporaryDirectory();
    final file = File(
      '${temp.path}/restore_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    await file.writeAsBytes(downloaded.bytes);
    try {
      return await _restoreLegacyZip(file);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  /// Backups made before the folder tree: one zip with
  /// `documents/<stored files>`, `database/alldocs_state.json` and
  /// `metadata/manifest.json`.
  Future<BackupInfo> _restoreLegacyZip(File zip) async {
    const manifestPath = 'metadata/manifest.json';
    const statePath = 'database/alldocs_state.json';
    const documentsPrefix = 'documents/';
    final input = InputFileStream(zip.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final manifestFile = archive.findFile(manifestPath);
      final stateFile = archive.findFile(statePath);
      if (manifestFile == null || stateFile == null) {
        throw const InvalidBackupException();
      }
      final manifest = jsonDecode(utf8.decode(manifestFile.content));
      if (manifest is! Map || manifest['app'] != 'AllDocs') {
        throw const InvalidBackupException();
      }
      final state = jsonDecode(utf8.decode(stateFile.content));
      if (state is! Map<String, dynamic>) throw const InvalidBackupException();

      final documentsDir = await store.documentsDirectory();
      for (final entry in archive.files) {
        if (!entry.isFile || !entry.name.startsWith(documentsPrefix)) continue;
        // Only the base name is used, so a crafted entry like
        // "documents/../../x" can't write outside the documents folder.
        final name = _baseName(entry.name);
        if (name.isEmpty || name == '.' || name == '..') continue;
        final output = OutputFileStream('${documentsDir.path}/$name');
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
        }
      }

      await store.restoreState(state);
      return BackupInfo(
        createdAt:
            DateTime.tryParse(manifest['created_at']?.toString() ?? '') ??
            DateTime.now(),
        documentCount: (manifest['documents'] as List?)?.length ?? 0,
      );
    } finally {
      await input.close();
    }
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  List<Map<String, dynamic>> _documentsList(Map<String, dynamic> state) {
    return [
      for (final raw in (state['documents'] as List? ?? const []))
        if (raw is Map<String, dynamic>) raw,
    ];
  }

  Iterable<Map> _manifestDocuments(Object? manifest) {
    final documents = manifest is Map ? manifest['documents'] : null;
    return documents is List ? documents.whereType<Map>() : const [];
  }

  /// Removes [ids] from [state], albums included.
  void _dropDocuments(Map<String, dynamic> state, Set<String> ids) {
    if (ids.isEmpty) return;
    (state['documents'] as List?)?.removeWhere(
      (raw) => raw is Map && ids.contains(raw['id']?.toString()),
    );
    for (final shelf in (state['shelves'] as List? ?? const [])) {
      if (shelf is! Map) continue;
      for (final album in (shelf['albums'] as List? ?? const [])) {
        if (album is! Map) continue;
        (album['document_ids'] as List?)?.removeWhere(
          (id) => ids.contains(id.toString()),
        );
        if (ids.contains(album['cover_document_id']?.toString())) {
          album['cover_document_id'] = null;
        }
      }
    }
  }

  Future<String?> _checksumOf(File file) async {
    try {
      final path = file.path;
      return await Isolate.run(() async {
        final digest = await sha256.bind(File(path).openRead()).first;
        return digest.toString();
      });
    } catch (_) {
      return null;
    }
  }

  /// Runs [work] over [items], a few at a time.
  Future<void> _inParallel<T>(
    List<T> items,
    Future<void> Function(T item) work,
  ) async {
    final iterator = items.iterator;
    Future<void> worker() async {
      while (iterator.moveNext()) {
        await work(iterator.current);
      }
    }

    await Future.wait([for (var i = 0; i < _parallelTransfers; i++) worker()]);
  }

  /// The name a document gets in the backup: its title, keeping the
  /// original file's extension.
  String _displayFileName(DocumentFile document) {
    final extension = _extensionOf(document.fileName);
    var name = _sanitize(document.title, fallback: '');
    if (name.isEmpty) name = _sanitize(document.fileName, fallback: 'Document');
    if (extension.isNotEmpty &&
        !name.toLowerCase().endsWith(extension.toLowerCase())) {
      name = '$name$extension';
    }
    return name;
  }

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return '';
    final extension = fileName.substring(dot);
    return extension.length <= 10 && !extension.contains(' ') ? extension : '';
  }

  /// Safe as a file or folder name on every storage (Windows rules being the
  /// strictest: no \ / : * ? " < > |, no trailing dot or space).
  String _sanitize(String value, {required String fallback}) {
    var name = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (name.length > 120) name = name.substring(0, 120).trim();
    return name.isEmpty ? fallback : name;
  }

  /// [name], or "name (2).ext", "name (3).ext"... when already in [taken]
  /// (compared ignoring case). Adds the result to [taken].
  String _uniqueName(String name, Set<String> taken) {
    var candidate = name;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    for (var n = 2; taken.contains(candidate.toLowerCase()); n++) {
      candidate = '$base ($n)$extension';
    }
    taken.add(candidate.toLowerCase());
    return candidate;
  }

  DateTime? _dateFromFolderName(String name) {
    final match = RegExp(
      r'^Backup (\d{4})-(\d{2})-(\d{2}) (\d{2})-(\d{2})-(\d{2})',
    ).firstMatch(name);
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  }

  DateTime? _dateFromLegacyName(String name) {
    final match = RegExp(
      r'^AllDocs_backup_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})',
    ).firstMatch(name);
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
    return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]);
  }

  String _baseName(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }
}

class _PlannedAlbum {
  const _PlannedAlbum({
    required this.album,
    required this.shelf,
    required this.folder,
  });
  final DocumentAlbum album;
  final DocumentShelf shelf;

  /// Folder name inside Current.
  final String folder;
}

class _PlannedFile {
  const _PlannedFile({
    required this.document,
    required this.file,
    required this.checksum,
    required this.canonicalPath,
    required this.albumPaths,
  });
  final DocumentFile document;
  final File file;
  final String checksum;

  /// `Current/Gallery/...` or `Current/Archive/...`.
  final String canonicalPath;
  final List<String> albumPaths;
}

class _BackupPlan {
  const _BackupPlan({
    required this.files,
    required this.albums,
    required this.unavailableIds,
  });
  final List<_PlannedFile> files;
  final List<_PlannedAlbum> albums;

  /// Documents whose file is gone from this phone: left out of the backup.
  final Set<String> unavailableIds;
}

/// `Removed/<first 16 hex of the checksum> <name>`: the checksum in the name
/// is what restoring an older backup looks it up by.
class _RemovedFolder {
  _RemovedFolder(this.storage);

  final BackupStorage storage;
  Set<String>? _prefixes;

  static String prefix(String checksum) =>
      checksum.length > 16 ? checksum.substring(0, 16) : checksum;

  static String? prefixOf(String name) {
    final match = RegExp(r'^([0-9a-f]{16}) ').firstMatch(name);
    return match?.group(1);
  }

  Future<void> retire(String path, String checksum) async {
    final prefixes = _prefixes ??= {
      for (final entry in await storage.list(BackupService.removedFolder))
        if (!entry.isFolder) ?prefixOf(entry.name),
    };
    final key = prefix(checksum);
    if (prefixes.contains(key)) {
      await storage.delete(path);
      return;
    }
    await storage.move(
      path,
      '${BackupService.removedFolder}/$key ${splitBackupPath(path).name}',
    );
    prefixes.add(key);
  }
}
