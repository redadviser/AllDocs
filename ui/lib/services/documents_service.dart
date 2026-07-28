import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'local_documents_store.dart';

class DocumentsService {
  DocumentsService.local() : _store = const LocalDocumentsStore();

  final revision = ValueNotifier<int>(0);
  final LocalDocumentsStore _store;
  final Map<String, StreamSubscription<FileSystemEvent>> _folderWatchers = {};
  Timer? _folderWatchDebounce;

  Future<DocumentsSnapshot> loadSnapshot() async {
    final snapshot = await _store.loadSnapshot();
    _syncDeviceFolderWatchers(snapshot.deviceFolders);
    return snapshot;
  }

  Future<int> importDocuments({String? albumId}) async {
    final imported = await _store.importDocuments(albumId: albumId);
    if (imported > 0) _notifyChanged();
    return imported;
  }

  Future<int> scanDocumentWithCamera({String? albumId}) async {
    final imported = await _store.scanDocumentWithCamera(albumId: albumId);
    if (imported > 0) _notifyChanged();
    return imported;
  }

  Future<DeviceFolderScan?> openDeviceFolder(
    DeviceFolder folder, {
    String? folderTitle,
    String? dialogTitle,
  }) async {
    final scan = await _store.openDeviceFolder(
      folder.id,
      folderTitle: folderTitle ?? folder.title,
      dialogTitle: dialogTitle,
    );
    if (scan != null) _notifyChanged();
    return scan;
  }

  Future<DeviceFolderScan?> scanAllDeviceDocuments({String? title}) {
    return _store.scanAllDeviceDocuments(title: title);
  }

  Future<int> importScannedDocuments(
    List<DocumentFile> documents, {
    String? albumId,
  }) async {
    final imported = await _store.importScannedDocuments(
      documents,
      albumId: albumId,
    );
    if (imported > 0) _notifyChanged();
    return imported;
  }

  Future<void> createShelf(String name) async {
    await _store.createShelf(name);
    _notifyChanged();
  }

  Future<void> createAlbum(
    String shelfId,
    String name, {
    int? colorValue,
    String iconName = 'folder',
  }) async {
    await _store.createAlbum(
      shelfId,
      name,
      colorValue: colorValue,
      iconName: iconName,
    );
    _notifyChanged();
  }

  Future<void> deleteShelf(String shelfId) async {
    await _store.deleteShelf(shelfId);
    _notifyChanged();
  }

  Future<void> deleteAlbum(String albumId) async {
    await _store.deleteAlbum(albumId);
    _notifyChanged();
  }

  Future<void> moveDocumentToAlbum(String documentId, String albumId) async {
    await _store.moveDocumentToAlbum(documentId, albumId);
    _notifyChanged();
  }

  Future<void> moveDocumentToInbox(String documentId) async {
    await _store.moveDocumentToInbox(documentId);
    _notifyChanged();
  }

  Future<void> toggleFavorite(String documentId) async {
    await _store.toggleFavorite(documentId);
    _notifyChanged();
  }

  Future<void> deleteDocument(String documentId) async {
    await _store.deleteDocument(documentId);
    _notifyChanged();
  }

  Future<void> openDocument(DocumentFile document) {
    return _store.openDocument(document);
  }

  Future<DocumentExportResult> exportDocuments({String? dialogTitle}) {
    return _store.exportDocuments(dialogTitle: dialogTitle);
  }

  void dispose() {
    for (final watcher in _folderWatchers.values) {
      watcher.cancel();
    }
    _folderWatchers.clear();
    _folderWatchDebounce?.cancel();
    revision.dispose();
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
