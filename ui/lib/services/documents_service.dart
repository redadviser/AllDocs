import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import 'auth_service.dart';
import 'backup_service.dart';
import 'cloud/cloud_provider.dart';
import 'cloud/cloud_service.dart';
import 'document_scanner_service.dart';
import 'local_documents_store.dart';
import 'secure_zip_extractor.dart';
import 'security_lock_service.dart';

class DocumentsService {
  DocumentsService.local() : _store = const LocalDocumentsStore() {
    LocalDocumentsStore.onBackgroundUpdate = _notifyChangedSoon;
  }

  final revision = ValueNotifier<int>(0);
  final LocalDocumentsStore _store;
  late final CloudService cloud = CloudService(store: _store);
  late final BackupService backup = BackupService(store: _store);
  final Map<String, StreamSubscription<FileSystemEvent>> _folderWatchers = {};
  Timer? _folderWatchDebounce;

  Future<DocumentsSnapshot>? _snapshot;
  int _snapshotRevision = -1;

  /// Every tab listens to [revision]; they all get the same snapshot future
  /// for a given revision instead of each rebuilding it.
  Future<DocumentsSnapshot> loadSnapshot() {
    final cached = _snapshot;
    if (cached != null && _snapshotRevision == revision.value) return cached;
    _snapshotRevision = revision.value;
    final future = _buildSnapshot();
    _snapshot = future;
    future.catchError((Object _) {
      if (identical(_snapshot, future)) _snapshot = null;
      return future;
    });
    return future;
  }

  Future<DocumentsSnapshot> _buildSnapshot() async {
    final snapshot = await _store.loadSnapshot();
    _syncDeviceFolderWatchers(snapshot.deviceFolders);
    return _withSignedInProfile(snapshot);
  }

  Future<DocumentsSnapshot> _withSignedInProfile(
    DocumentsSnapshot snapshot,
  ) async {
    final name = await AuthService.displayName();
    final email = await AuthService.email();
    final plan = await AuthService.plan();
    final avatarUrl = await AuthService.avatarUrl();

    return snapshot.copyWith(
      profile: snapshot.profile.copyWith(
        name: name,
        email: email,
        planName: plan == null ? null : _planLabel(plan),
        avatarUrl: avatarUrl,
      ),
    );
  }

  String _planLabel(String plan) {
    if (plan.isEmpty) return plan;
    return plan[0].toUpperCase() + plan.substring(1);
  }

  // Import --------------------------------------------------------------

  Future<List<PlatformFile>> pickFilesForImport({
    ImportPickKind kind = ImportPickKind.documents,
    bool allowMultiple = true,
  }) {
    return SecurityLockService.withoutAutoLock(
      () => _store.pickFilesForImport(kind: kind, allowMultiple: allowMultiple),
    );
  }

  Future<ImportResult> importPickedFiles(
    List<PlatformFile> files, {
    String? albumId,
  }) {
    return _notifyIfImported(_store.importPickedFiles(files, albumId: albumId));
  }

  Future<ImportResult> importFilePaths(
    List<String> paths, {
    String? albumId,
    DocumentSource source = DocumentSource.shared,
  }) {
    return _notifyIfImported(
      _store.importFilePaths(paths, albumId: albumId, source: source),
    );
  }

  Future<List<ExtractedZipEntry>> extractZipPreview(Uint8List zipBytes) {
    return _store.extractZipPreview(zipBytes);
  }

  Future<List<ExtractedZipEntry>> extractZipPreviewFromPath(String path) {
    return _store.extractZipPreviewFromPath(path);
  }

  Future<ImportResult> importExtractedZipEntries(
    List<ExtractedZipEntry> entries, {
    String? albumId,
  }) {
    return _notifyIfImported(
      _store.importExtractedZipEntries(entries, albumId: albumId),
    );
  }

  Future<ImportResult> scanDocumentWithCamera({
    String? albumId,
    ScanFilterChooser? chooseFilter,
  }) {
    return _notifyIfImported(
      SecurityLockService.withoutAutoLock(
        () => _store.scanDocumentWithCamera(
          albumId: albumId,
          chooseFilter: chooseFilter,
        ),
      ),
    );
  }

  Future<DeviceFolderScan?> openDeviceFolder(
    DeviceFolder folder, {
    String? folderTitle,
    String? dialogTitle,
  }) async {
    final scan = await SecurityLockService.withoutAutoLock(
      () => _store.openDeviceFolder(
        folder.id,
        folderTitle: folderTitle ?? folder.title,
        dialogTitle: dialogTitle,
      ),
    );
    if (scan != null) _notifyChanged();
    return scan;
  }

  Future<DeviceFolderScan?> scanAllDeviceDocuments({String? title}) {
    return _store.scanAllDeviceDocuments(title: title);
  }

  Future<DeviceFolderScan?> searchDevice(String query, {String? title}) {
    return _store.searchDevice(query, title: title);
  }

  Future<ImportResult> importScannedDocuments(
    List<DocumentFile> documents, {
    String? albumId,
  }) {
    return _notifyIfImported(
      _store.importScannedDocuments(documents, albumId: albumId),
    );
  }

  Future<ImportResult> importFromCloud(
    CloudProvider provider,
    List<CloudItem> items, {
    String? albumId,
    void Function(int done, int total)? onProgress,
  }) {
    return _notifyIfImported(
      cloud.importItems(
        provider,
        items,
        albumId: albumId,
        onProgress: onProgress,
      ),
    );
  }

  Future<ImportResult> _notifyIfImported(Future<ImportResult> import) async {
    final result = await import;
    if (!result.isEmpty) _notifyChanged();
    return result;
  }

  // Organization ----------------------------------------------------------

  Future<void> createShelf(String name) => _mutate(_store.createShelf(name));

  Future<void> ensureStarterShelf(
    String shelfName,
    List<({String name, String iconName})> albums,
  ) async {
    if (await _store.ensureStarterShelf(shelfName, albums)) _notifyChanged();
  }

  Future<void> renameShelf(String shelfId, String name) {
    return _mutate(_store.renameShelf(shelfId, name));
  }

  Future<String?> createAlbum(
    String? shelfId,
    String name, {
    int? colorValue,
    String iconName = 'folder',
  }) async {
    final id = await _store.createAlbum(
      shelfId,
      name,
      colorValue: colorValue,
      iconName: iconName,
    );
    _notifyChanged();
    return id;
  }

  Future<void> updateAlbum(
    String albumId, {
    String? name,
    int? colorValue,
    String? iconName,
  }) {
    return _mutate(
      _store.updateAlbum(
        albumId,
        name: name,
        colorValue: colorValue,
        iconName: iconName,
      ),
    );
  }

  Future<void> reorderShelves(List<String> shelfIds) {
    return _mutate(_store.reorderShelves(shelfIds));
  }

  Future<void> reorderAlbums(String shelfId, List<String> albumIds) {
    return _mutate(_store.reorderAlbums(shelfId, albumIds));
  }

  Future<void> sortAlbumsByName(String shelfId) {
    return _mutate(_store.sortAlbumsByName(shelfId));
  }

  Future<void> deleteShelf(String shelfId) {
    return _mutate(_store.deleteShelf(shelfId));
  }

  Future<void> deleteAlbum(String albumId) {
    return _mutate(_store.deleteAlbum(albumId));
  }

  Future<void> setDocumentAlbums(String documentId, List<String> albumIds) {
    return _mutate(_store.setDocumentAlbums(documentId, albumIds));
  }

  Future<void> addDocumentsToAlbum(List<String> documentIds, String albumId) {
    return _mutate(_store.addDocumentsToAlbum(documentIds, albumId));
  }

  Future<void> removeDocumentFromAlbum(String documentId, String albumId) {
    return _mutate(_store.removeDocumentFromAlbum(documentId, albumId));
  }

  Future<void> moveDocumentToAlbum(String documentId, String albumId) {
    return _mutate(_store.moveDocumentToAlbum(documentId, albumId));
  }

  Future<void> moveDocumentToInbox(String documentId) {
    return _mutate(_store.moveDocumentToInbox(documentId));
  }

  Future<void> updateDocument(
    String documentId, {
    String? title,
    List<String>? tags,
    bool? isFavorite,
    List<String>? albumIds,
  }) {
    return _mutate(
      _store.updateDocument(
        documentId,
        title: title,
        tags: tags,
        isFavorite: isFavorite,
        albumIds: albumIds,
      ),
    );
  }

  Future<void> toggleFavorite(String documentId) {
    return _mutate(_store.toggleFavorite(documentId));
  }

  Future<void> dismissSuggestion(String documentId) {
    return _mutate(_store.dismissSuggestion(documentId));
  }

  Future<void> setArchived(List<String> documentIds, bool archived) {
    return _mutate(_store.setArchived(documentIds, archived));
  }

  Future<void> moveToTrash(List<String> documentIds) {
    return _mutate(_store.moveToTrash(documentIds));
  }

  Future<void> restoreFromTrash(List<String> documentIds) {
    return _mutate(_store.restoreFromTrash(documentIds));
  }

  Future<void> deletePermanently(List<String> documentIds) {
    return _mutate(_store.deletePermanently(documentIds));
  }

  Future<void> emptyTrash() => _mutate(_store.emptyTrash());

  Future<void> deleteDocument(String documentId) {
    return _mutate(_store.deleteDocument(documentId));
  }

  // Cloud sync --------------------------------------------------------------

  Future<List<CloudUpdate>> checkCloudUpdates(List<DocumentFile> documents) {
    return cloud.checkForUpdates(documents);
  }

  Future<void> applyCloudUpdate(CloudUpdate update) {
    return _mutate(cloud.applyUpdate(update));
  }

  Future<void> keepCurrentVersion(CloudUpdate update) {
    return _mutate(
      _store.setCloudVersion(update.document.id, update.remote.version),
    );
  }

  /// Restores a backup and reloads everything.
  Future<BackupInfo?> restoreBackup(Future<BackupInfo?> restore) async {
    final info = await restore;
    if (info != null) _notifyChanged();
    return info;
  }

  // Files ---------------------------------------------------------------------

  Future<void> openDocument(DocumentFile document) {
    return SecurityLockService.withoutAutoLock(
      () => _store.openDocument(document),
    );
  }

  Future<void> shareDocuments(List<DocumentFile> documents) async {
    final files = [
      for (final document in documents)
        if (document.localPath != null &&
            File(document.localPath!).existsSync())
          XFile(document.localPath!, name: document.fileName),
    ];
    if (files.isEmpty) return;
    await SecurityLockService.withoutAutoLock(
      () => SharePlus.instance.share(ShareParams(files: files)),
    );
  }

  Future<DocumentExportResult> exportDocuments({String? dialogTitle}) {
    return SecurityLockService.withoutAutoLock(
      () => _store.exportDocuments(dialogTitle: dialogTitle),
    );
  }

  /// Re-reads the signed-in profile fields (name/email/plan/avatar) into the
  /// next snapshot — used after something outside the local store changes,
  /// like picking a new profile photo.
  void refreshProfile() => _notifyChanged();

  void dispose() {
    for (final watcher in _folderWatchers.values) {
      watcher.cancel();
    }
    _folderWatchers.clear();
    _folderWatchDebounce?.cancel();
    if (LocalDocumentsStore.onBackgroundUpdate == _notifyChangedSoon) {
      LocalDocumentsStore.onBackgroundUpdate = null;
    }
    revision.dispose();
  }

  Future<void> _mutate(Future<void> change) async {
    await change;
    _notifyChanged();
  }

  void _notifyChanged() {
    revision.value++;
  }

  void _syncDeviceFolderWatchers(List<DeviceFolder> folders) {
    final linkedFolders = {
      for (final folder in folders)
        if (folder.isLinked) folder.id: folder.path!,
    };

    for (final id in _folderWatchers.keys.toList()) {
      if (linkedFolders.containsKey(id)) continue;
      _folderWatchers.remove(id)?.cancel();
    }

    for (final entry in linkedFolders.entries) {
      if (_folderWatchers.containsKey(entry.key)) continue;
      try {
        _folderWatchers[entry.key] = Directory(entry.value)
            .watch(recursive: true)
            .listen((_) => _notifyChangedSoon(), onError: (_) {});
      } catch (_) {
        // Some mobile folder providers do not expose filesystem watch events.
      }
    }
  }

  void _notifyChangedSoon() {
    _folderWatchDebounce?.cancel();
    _folderWatchDebounce = Timer(const Duration(milliseconds: 500), () {
      _notifyChanged();
    });
  }
}
