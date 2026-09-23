import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'app_settings.dart';
import 'cloud/cloud_provider.dart';
import 'local_documents_store.dart';

class BackupInfo {
  const BackupInfo({required this.createdAt, required this.documentCount});
  final DateTime createdAt;
  final int documentCount;
}

class InvalidBackupException implements Exception {
  const InvalidBackupException();
}

/// Backup of the whole app (files + organization) as a single zip:
///
///     documents/<stored files>
///     database/alldocs_state.json
///     metadata/manifest.json   {version, created_at, documents, albums, tags}
///
/// It can be written to a folder on the device or to a cloud account's
/// app folder, and restored on a new phone. Separate from cloud *import*
/// (cloud → app); this is app → cloud.
class BackupService {
  const BackupService({this.store = const LocalDocumentsStore()});

  final LocalDocumentsStore store;
  static const manifestVersion = 1;
  static const _manifestPath = 'metadata/manifest.json';
  static const _statePath = 'database/alldocs_state.json';
  static const _documentsPrefix = 'documents/';
  static const autoBackupInterval = Duration(hours: 24);

  String backupFileName(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'AllDocs_backup_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}.zip';
  }

  /// Builds the backup zip in the temp folder and returns it.
  Future<File> createBackupFile() async {
    final state = await store.exportState();
    final temp = await getTemporaryDirectory();
    final now = DateTime.now();
    final zipPath = '${temp.path}/${backupFileName(now)}';

    final documents = (state['documents'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => DocumentFile.fromJson(Map<String, dynamic>.from(raw)))
        .toList();
    final shelves = (state['shelves'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => DocumentShelf.fromJson(Map<String, dynamic>.from(raw)))
        .toList();
    final manifest = {
      'version': manifestVersion,
      'app': 'AllDocs',
      'created_at': now.toIso8601String(),
      'documents': [
        for (final document in documents)
          {
            'id': document.id,
            'title': document.title,
            'file_name': document.fileName,
            'stored_name': _baseName(document.localPath ?? ''),
            'album_ids': document.albumIds,
            'tags': document.tags,
            'archived': document.isArchived,
            'favorite': document.isFavorite,
            'checksum': document.checksum,
          },
      ],
      'albums': [
        for (final shelf in shelves)
          for (final album in shelf.albums)
            {'id': album.id, 'name': album.name, 'shelf': shelf.name},
      ],
      'tags': {for (final document in documents) ...document.tags}.toList(),
    };

    final encoder = ZipFileEncoder()..create(zipPath);
    try {
      encoder.addArchiveFile(
        ArchiveFile.string(_manifestPath, jsonEncode(manifest)),
      );
      encoder.addArchiveFile(ArchiveFile.string(_statePath, jsonEncode(state)));
      for (final document in documents) {
        final path = document.localPath;
        if (path == null) continue;
        final file = File(path);
        if (!await file.exists()) continue;
        await encoder.addFile(file, '$_documentsPrefix${_baseName(path)}');
      }
    } finally {
      await encoder.close();
    }
    return File(zipPath);
  }

  Future<CloudItem> backupToCloud(CloudProvider provider) async {
    final file = await createBackupFile();
    try {
      final item = await provider.uploadBackup(_baseName(file.path), file);
      await AppSettings.setLastBackupAt(DateTime.now());
      return item;
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  /// Lets the user pick a folder and writes the backup zip there.
  Future<String?> saveBackupToDevice({String? dialogTitle}) async {
    final target = await FilePicker.getDirectoryPath(dialogTitle: dialogTitle);
    if (target == null || target.trim().isEmpty) return null;
    final file = await createBackupFile();
    try {
      final destination = '$target/${_baseName(file.path)}';
      await file.copy(destination);
      await AppSettings.setLastBackupAt(DateTime.now());
      return destination;
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<BackupInfo?> pickAndRestoreFromDevice() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = picked?.files.single.path;
    if (path == null) return null;
    return restoreFromFile(File(path));
  }

  Future<BackupInfo> restoreFromCloud(
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
      return await restoreFromFile(file);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  /// Replaces AllDocs' current documents and organization with the backup.
  Future<BackupInfo> restoreFromFile(File zip) async {
    final input = InputFileStream(zip.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final manifestFile = archive.findFile(_manifestPath);
      final stateFile = archive.findFile(_statePath);
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
        if (!entry.isFile || !entry.name.startsWith(_documentsPrefix)) continue;
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

  /// Runs a cloud backup when auto-backup is on and the last one is older
  /// than [autoBackupInterval]. Silent and best-effort.
  Future<bool> runAutoBackupIfDue(
    CloudProvider? Function(String id) providerFor,
  ) async {
    if (!AppSettings.autoBackup.value) return false;
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

  String _baseName(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }
}
