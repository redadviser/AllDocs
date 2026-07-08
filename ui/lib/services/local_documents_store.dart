import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

class LocalDocumentsStore {
  const LocalDocumentsStore();

  static Directory? debugDirectory;
  static Directory? _fallbackDirectory;
  static const _stateFileName = 'alldocs_state.json';
  static const _documentsFolderName = 'documents';
  static const _supportedExtensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'jpg',
    'jpeg',
    'png',
    'heic',
    'webp',
  ];
  static const _deviceFolderSpecs = [
    DeviceFolder(id: 'downloads', title: 'Downloads', itemCount: 0),
    DeviceFolder(id: 'documents', title: 'Documentos', itemCount: 0),
    DeviceFolder(id: 'whatsapp', title: 'WhatsApp', itemCount: 0),
    DeviceFolder(id: 'scans', title: 'Scans', itemCount: 0),
    DeviceFolder(id: 'drive', title: 'Drive', itemCount: 0),
  ];

  Future<DocumentsSnapshot> loadSnapshot() async {
    final state = await _readState();
    return _snapshotFromState(state);
  }

  Future<int> importDocuments({String? albumId}) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _supportedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return 0;

    final state = await _readState();
    final documents = _documentsRaw(state);
    var imported = 0;

    for (final picked in result.files) {
      final originalName = picked.name.trim().isEmpty
          ? 'documento_${DateTime.now().millisecondsSinceEpoch}.pdf'
          : picked.name.trim();
      final id = _newId('doc');
      final storedPath = await _copyPickedFile(
        id: id,
        originalName: originalName,
        pickedPath: picked.path,
        bytes: picked.bytes,
      );
      final importedDocument = await _documentFromStoredFile(
        id: id,
        fileName: originalName,
        storedPath: storedPath,
        albumId: albumId,
      );
      documents.add(importedDocument.toJson());

      if (albumId != null) _addDocumentToAlbum(state, albumId, id);
      imported++;
    }

    await _writeState(state);
    return imported;
  }

  Future<int> scanDocumentWithCamera({String? albumId}) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (picked == null) return 0;

    final state = await _readState();
    final documents = _documentsRaw(state);
    final id = _newId('doc');
    final fileName = 'scan_${_dateStamp(DateTime.now())}.jpg';
    final storedPath = await _copyPickedFile(
      id: id,
      originalName: fileName,
      pickedPath: picked.path,
      bytes: null,
    );
    final importedDocument = await _documentFromStoredFile(
      id: id,
      fileName: fileName,
      storedPath: storedPath,
      albumId: albumId,
    );
    documents.add(importedDocument.toJson());

    if (albumId != null) _addDocumentToAlbum(state, albumId, id);
    await _writeState(state);
    return 1;
  }

  Future<DeviceFolderScan?> openDeviceFolder(
    String folderId, {
    String? folderTitle,
    String? dialogTitle,
  }) async {
    final state = await _readState();
    final paths = _deviceFolderPathsRaw(state);
    final savedPath = paths[folderId]?.toString().trim();
    if (savedPath != null && savedPath.isNotEmpty) {
      final scan = await _scanDeviceFolder(
        folderId,
        savedPath,
        title: folderTitle,
      );
      if (scan != null) return scan;

      paths.remove(folderId);
      await _writeState(state);
    }

    final defaultPath = await _defaultDeviceFolderPath(folderId);
    if (defaultPath != null) {
      paths[folderId] = defaultPath;
      await _writeState(state);
      return _scanDeviceFolder(folderId, defaultPath, title: folderTitle);
    }

    final path = await FilePicker.getDirectoryPath(dialogTitle: dialogTitle);
    if (path == null || path.trim().isEmpty) return null;

    paths[folderId] = path;
    await _writeState(state);
    return _scanDeviceFolder(folderId, path, title: folderTitle);
  }

  Future<int> importScannedDocuments(
    List<DocumentFile> scannedDocuments, {
    String? albumId,
  }) async {
    if (scannedDocuments.isEmpty) return 0;

    final state = await _readState();
    final documents = _documentsRaw(state);
    var imported = 0;

    for (final scanned in scannedDocuments) {
      final sourcePath = scanned.localPath;
      if (sourcePath == null || sourcePath.isEmpty) continue;
      final source = File(sourcePath);
      if (!await source.exists()) continue;

      final id = _newId('doc');
      final storedPath = await _copyPickedFile(
        id: id,
        originalName: scanned.fileName,
        pickedPath: sourcePath,
        bytes: null,
      );
      final importedDocument = await _documentFromStoredFile(
        id: id,
        fileName: scanned.fileName,
        storedPath: storedPath,
        albumId: albumId,
      );
      documents.add(importedDocument.toJson());

      if (albumId != null) _addDocumentToAlbum(state, albumId, id);
      imported++;
    }

    await _writeState(state);
    return imported;
  }

  Future<void> createShelf(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;

    final state = await _readState();
    final shelves = _shelvesRaw(state);
    shelves.add(
      DocumentShelf(
        id: _newId('shelf'),
        name: normalized,
        position: shelves.length,
        albums: const [],
      ).toJson(),
    );
    await _writeState(state);
  }

  Future<void> createAlbum(
    String shelfId,
    String name, {
    int? colorValue,
    String iconName = 'folder',
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;

    final state = await _readState();
    final shelf = _findShelf(state, shelfId);
    if (shelf == null) return;

    final albums = _albumsRaw(shelf);
    albums.add(
      DocumentAlbum(
        id: _newId('album'),
        shelfId: shelfId,
        name: normalized,
        colorValue: colorValue ?? _albumColorFor(albums.length),
        iconName: iconName,
        position: albums.length,
        documentIds: const [],
      ).toJson(),
    );
    await _writeState(state);
  }

  Future<void> deleteShelf(String shelfId) async {
    final state = await _readState();
    final shelves = _shelvesRaw(state);
    final index = shelves.indexWhere((shelf) {
      return shelf is Map && shelf['id']?.toString() == shelfId;
    });
    if (index < 0) return;

    final shelf = Map<String, dynamic>.from(shelves.removeAt(index) as Map);
    final albumIds = _albumsList(shelf)
        .map((album) => album['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    _moveAlbumDocumentsToInbox(state, albumIds);
    _reindexShelves(state);
    await _writeState(state);
  }

  Future<void> deleteAlbum(String albumId) async {
    final state = await _readState();
    for (final shelf in _shelvesList(state)) {
      final albums = _albumsRaw(shelf);
      final index = albums.indexWhere((album) {
        return album is Map && album['id']?.toString() == albumId;
      });
      if (index < 0) continue;

      albums.removeAt(index);
      _moveAlbumDocumentsToInbox(state, {albumId});
      _reindexAlbums(shelf);
      await _writeState(state);
      return;
    }
  }

  Future<void> moveDocumentToAlbum(String documentId, String albumId) async {
    final state = await _readState();
    final documents = _documentsRaw(state);
    final index = documents.indexWhere((document) {
      return document is Map && document['id']?.toString() == documentId;
    });
    if (index < 0) return;

    final document = DocumentFile.fromJson(
      Map<String, dynamic>.from(documents[index] as Map),
    );
    _removeDocumentFromAlbums(state, documentId);
    _addDocumentToAlbum(state, albumId, documentId);
    documents[index] = document
        .copyWith(albumId: albumId, isNew: false, isImported: true)
        .toJson();
    await _writeState(state);
  }

  Future<void> moveDocumentToInbox(String documentId) async {
    final state = await _readState();
    final documents = _documentsRaw(state);
    final index = documents.indexWhere((document) {
      return document is Map && document['id']?.toString() == documentId;
    });
    if (index < 0) return;

    final document = DocumentFile.fromJson(
      Map<String, dynamic>.from(documents[index] as Map),
    );
    _removeDocumentFromAlbums(state, documentId);
    documents[index] = document
        .copyWith(clearAlbumId: true, isNew: true)
        .toJson();
    await _writeState(state);
  }

  Future<void> toggleFavorite(String documentId) async {
    final state = await _readState();
    final documents = _documentsRaw(state);
    final index = documents.indexWhere((document) {
      return document is Map && document['id']?.toString() == documentId;
    });
    if (index < 0) return;

    final document = DocumentFile.fromJson(
      Map<String, dynamic>.from(documents[index] as Map),
    );
    documents[index] = document
        .copyWith(isFavorite: !document.isFavorite)
        .toJson();
    await _writeState(state);
  }

  Future<void> deleteDocument(String documentId) async {
    final state = await _readState();
    final documents = _documentsRaw(state);
    final index = documents.indexWhere((document) {
      return document is Map && document['id']?.toString() == documentId;
    });
    if (index < 0) return;

    final document = DocumentFile.fromJson(
      Map<String, dynamic>.from(documents.removeAt(index) as Map),
    );
    _removeDocumentFromAlbums(state, documentId);
    final localPath = document.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (await file.exists()) await file.delete();
    }
    await _writeState(state);
  }

  Future<void> openDocument(DocumentFile document) async {
    final localPath = document.localPath;
    if (localPath == null || localPath.isEmpty) return;
    await OpenFilex.open(localPath);
  }

  Future<DocumentExportResult> exportDocuments({String? dialogTitle}) async {
    final state = await _readState();
    final documents = _documentsList(state)
        .map(DocumentFile.fromJson)
        .where((document) => document.localPath != null)
        .toList();
    if (documents.isEmpty) {
      return const DocumentExportResult(count: 0, path: null);
    }

    final targetRoot = await FilePicker.getDirectoryPath(
      dialogTitle: dialogTitle,
    );
    if (targetRoot == null || targetRoot.trim().isEmpty) {
      return const DocumentExportResult(count: 0, path: null);
    }

    final exportDir = Directory(
      '$targetRoot/AllDocs_Export_${_dateStamp(DateTime.now())}',
    );
    await exportDir.create(recursive: true);

    var exported = 0;
    for (final document in documents) {
      final localPath = document.localPath;
      if (localPath == null || localPath.isEmpty) continue;
      final source = File(localPath);
      if (!await source.exists()) continue;

      final target = await _uniqueExportFile(exportDir, document.fileName);
      await source.copy(target.path);
      exported++;
    }

    return DocumentExportResult(count: exported, path: exportDir.path);
  }

  Future<Map<String, dynamic>> _readState() async {
    final file = await _stateFile();
    if (!await file.exists()) {
      final initial = _initialState();
      await _writeState(initial);
      return initial;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        final migrated = _migrateState(decoded);
        if (migrated) await _writeState(decoded);
        return decoded;
      }
    } catch (_) {
      // Fall through to a clean state if the local JSON becomes unreadable.
    }

    final initial = _initialState();
    await _writeState(initial);
    return initial;
  }

  Future<void> _writeState(Map<String, dynamic> state) async {
    final file = await _stateFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(state));
  }

  Future<File> _stateFile() async {
    final dir = await _appDirectory();
    return File('${dir.path}/$_stateFileName');
  }

  Future<Directory> _documentsDirectory() async {
    final dir = await _appDirectory();
    final documentsDir = Directory('${dir.path}/$_documentsFolderName');
    await documentsDir.create(recursive: true);
    return documentsDir;
  }

  Future<Directory> _appDirectory() async {
    if (debugDirectory != null) return debugDirectory!;
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      _fallbackDirectory ??= await Directory.systemTemp.createTemp(
        'alldocs_local_store_',
      );
      return _fallbackDirectory!;
    }
  }

  Future<String> _copyPickedFile({
    required String id,
    required String originalName,
    required String? pickedPath,
    required Uint8List? bytes,
  }) async {
    final documentsDir = await _documentsDirectory();
    final safeName = _safeFileName(originalName);
    final target = File('${documentsDir.path}/${id}_$safeName');

    if (pickedPath != null && pickedPath.isNotEmpty) {
      await File(pickedPath).copy(target.path);
      return target.path;
    }

    if (bytes != null) {
      await target.writeAsBytes(bytes);
      return target.path;
    }

    throw Exception('Não foi possível ler o ficheiro selecionado.');
  }

  Future<DocumentFile> _documentFromStoredFile({
    required String id,
    required String fileName,
    required String storedPath,
    String? albumId,
  }) async {
    final file = File(storedPath);
    final sizeBytes = await file.length();
    final importedAt = DateTime.now();

    return DocumentFile(
      id: id,
      title: _titleFromFileName(fileName),
      fileName: fileName,
      type: documentTypeFromFileName(fileName),
      dateLabel: _dateLabel(importedAt),
      timeLabel: _timeLabel(importedAt),
      sizeLabel: _formatBytes(sizeBytes),
      localPath: storedPath,
      sizeBytes: sizeBytes,
      importedAt: importedAt,
      albumId: albumId,
      isNew: albumId == null,
      isImported: true,
    );
  }

  Future<DocumentsSnapshot> _snapshotFromState(
    Map<String, dynamic> state,
  ) async {
    final documents =
        _documentsList(state)
            .map(DocumentFile.fromJson)
            .where((document) => document.id.isNotEmpty)
            .toList()
          ..sort(_newestFirst);
    final shelves =
        _shelvesList(state)
            .map(DocumentShelf.fromJson)
            .where((shelf) => shelf.id.isNotEmpty)
            .map((shelf) {
              final albums = shelf.albums.toList()
                ..sort((a, b) => a.position.compareTo(b.position));
              return shelf.copyWith(albums: albums);
            })
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));

    final categories = <DocumentCategory>[
      for (final shelf in shelves)
        for (final album in shelf.albums)
          DocumentCategory(
            id: album.id,
            title: album.name,
            count: documents.where((doc) => doc.albumId == album.id).length,
            colorValue: album.colorValue,
            iconName: album.iconName,
          ),
    ];

    final recentDocuments = documents.take(5).toList();
    final favoriteDocuments = documents
        .where((document) => document.isFavorite)
        .take(5)
        .toList();
    final unorganizedDocuments = documents
        .where((document) => document.albumId == null || document.albumId == '')
        .toList();
    final recentImports = documents.take(4).toList();
    final usedBytes = documents.fold<int>(
      0,
      (total, document) => total + document.sizeBytes,
    );
    final deviceFolders = await _deviceFoldersFromState(state);

    return DocumentsSnapshot(
      shelves: shelves,
      documents: documents,
      categories: categories,
      recentDocuments: recentDocuments,
      favoriteDocuments: favoriteDocuments,
      unorganizedDocuments: unorganizedDocuments,
      deviceFolders: deviceFolders,
      recentImports: recentImports,
      profile: UserProfile(
        name: 'Paulo Cunha',
        email: 'paulo.cunha@email.com',
        planName: 'Premium',
        documentsCount: documents.length,
        categoriesCount: categories.length,
        favoritesCount: documents
            .where((document) => document.isFavorite)
            .length,
        storageSummary: StorageSummary(
          usedGb: usedBytes / 1024 / 1024 / 1024,
          totalGb: 10,
        ),
      ),
    );
  }

  Map<String, dynamic> _initialState() {
    return {
      'version': 2,
      'shelves': <Map<String, dynamic>>[],
      'documents': <Map<String, dynamic>>[],
      'device_folder_paths': <String, String>{},
    };
  }

  bool _migrateState(Map<String, dynamic> state) {
    final version = state['version'];
    if (version == 2) return false;

    const mockNames = {
      'Pessoais',
      'Trabalho',
      'Financeiros',
      'Estudos',
      'Saúde',
      'Imóveis',
      'Veículos',
    };
    final removedMockAlbumIds = <String>{};

    for (final shelf in _shelvesList(state)) {
      final albums = _albumsRaw(shelf);
      albums.removeWhere((album) {
        if (album is! Map) return false;
        final id = album['id']?.toString() ?? '';
        final name = album['name']?.toString() ?? '';
        final looksLikeSeedId = RegExp(r'^album_\d+_').hasMatch(id);
        final shouldRemove = looksLikeSeedId && mockNames.contains(name);
        if (shouldRemove && id.isNotEmpty) removedMockAlbumIds.add(id);
        return shouldRemove;
      });
      _reindexAlbums(shelf);
    }

    if (removedMockAlbumIds.isNotEmpty) {
      _moveAlbumDocumentsToInbox(state, removedMockAlbumIds);
    }

    _shelvesRaw(state).removeWhere((shelf) {
      if (shelf is! Map) return false;
      final name = shelf['name']?.toString() ?? '';
      final albums = shelf['albums'];
      final isEmpty = albums is List && albums.isEmpty;
      return name == 'Documentos' && isEmpty;
    });

    _reindexShelves(state);
    state['version'] = 2;
    return true;
  }

  List<dynamic> _shelvesRaw(Map<String, dynamic> state) {
    final value = state['shelves'];
    if (value is List<dynamic>) return value;
    final list = <dynamic>[];
    state['shelves'] = list;
    return list;
  }

  List<dynamic> _documentsRaw(Map<String, dynamic> state) {
    final value = state['documents'];
    if (value is List<dynamic>) return value;
    final list = <dynamic>[];
    state['documents'] = list;
    return list;
  }

  Map<String, dynamic> _deviceFolderPathsRaw(Map<String, dynamic> state) {
    final value = state['device_folder_paths'];
    if (value is Map<String, dynamic>) return value;
    final map = <String, dynamic>{};
    state['device_folder_paths'] = map;
    return map;
  }

  List<dynamic> _albumsRaw(Map<String, dynamic> shelf) {
    final value = shelf['albums'];
    if (value is List<dynamic>) return value;
    final list = <dynamic>[];
    shelf['albums'] = list;
    return list;
  }

  List<Map<String, dynamic>> _shelvesList(Map<String, dynamic> state) {
    return _shelvesRaw(state).whereType<Map<String, dynamic>>().toList();
  }

  List<Map<String, dynamic>> _documentsList(Map<String, dynamic> state) {
    return _documentsRaw(state).whereType<Map<String, dynamic>>().toList();
  }

  List<Map<String, dynamic>> _albumsList(Map<String, dynamic> shelf) {
    return _albumsRaw(shelf).whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic>? _findShelf(Map<String, dynamic> state, String shelfId) {
    for (final shelf in _shelvesList(state)) {
      if (shelf['id']?.toString() == shelfId) return shelf;
    }
    return null;
  }

  Map<String, dynamic>? _findAlbum(Map<String, dynamic> state, String albumId) {
    for (final shelf in _shelvesList(state)) {
      for (final album in _albumsList(shelf)) {
        if (album['id']?.toString() == albumId) return album;
      }
    }
    return null;
  }

  void _addDocumentToAlbum(
    Map<String, dynamic> state,
    String albumId,
    String documentId,
  ) {
    final album = _findAlbum(state, albumId);
    if (album == null) return;
    final ids = (album['document_ids'] as List<dynamic>? ?? [])
        .map((id) => id.toString())
        .toList();
    if (!ids.contains(documentId)) ids.add(documentId);
    album['document_ids'] = ids;
    album['cover_document_id'] ??= documentId;
  }

  void _removeDocumentFromAlbums(
    Map<String, dynamic> state,
    String documentId,
  ) {
    for (final shelf in _shelvesList(state)) {
      for (final album in _albumsList(shelf)) {
        final ids = (album['document_ids'] as List<dynamic>? ?? [])
            .map((id) => id.toString())
            .where((id) => id != documentId)
            .toList();
        album['document_ids'] = ids;
        if (album['cover_document_id']?.toString() == documentId) {
          album['cover_document_id'] = ids.isEmpty ? null : ids.first;
        }
      }
    }
  }

  void _moveAlbumDocumentsToInbox(
    Map<String, dynamic> state,
    Set<String> albumIds,
  ) {
    final documents = _documentsRaw(state);
    for (var i = 0; i < documents.length; i++) {
      final raw = documents[i];
      if (raw is! Map) continue;
      final document = DocumentFile.fromJson(Map<String, dynamic>.from(raw));
      if (!albumIds.contains(document.albumId)) continue;
      documents[i] = document
          .copyWith(clearAlbumId: true, isNew: true)
          .toJson();
    }
  }

  void _reindexShelves(Map<String, dynamic> state) {
    final shelves = _shelvesRaw(state);
    for (var i = 0; i < shelves.length; i++) {
      final shelf = shelves[i];
      if (shelf is Map) shelf['position'] = i;
    }
  }

  void _reindexAlbums(Map<String, dynamic> shelf) {
    final albums = _albumsRaw(shelf);
    for (var i = 0; i < albums.length; i++) {
      final album = albums[i];
      if (album is Map) album['position'] = i;
    }
  }

  int _newestFirst(DocumentFile a, DocumentFile b) {
    final aDate = a.importedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.importedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  }

  Future<List<DeviceFolder>> _deviceFoldersFromState(
    Map<String, dynamic> state,
  ) async {
    final paths = _deviceFolderPathsRaw(state);
    var changed = false;
    final folders = <DeviceFolder>[];

    for (final spec in _deviceFolderSpecs) {
      final path = paths[spec.id]?.toString().trim();
      String? linkedPath;
      var itemCount = 0;

      if (path != null && path.isNotEmpty) {
        final directory = Directory(path);
        if (await directory.exists()) {
          linkedPath = path;
          itemCount = await _countSupportedFiles(directory);
        } else {
          paths.remove(spec.id);
          changed = true;
        }
      }

      if (linkedPath == null) {
        final defaultPath = await _defaultDeviceFolderPath(spec.id);
        if (defaultPath != null) {
          linkedPath = defaultPath;
          paths[spec.id] = defaultPath;
          itemCount = await _countSupportedFiles(Directory(defaultPath));
          changed = true;
        }
      }

      folders.add(
        DeviceFolder(
          id: spec.id,
          title: spec.title,
          itemCount: itemCount,
          path: linkedPath,
        ),
      );
    }

    if (changed) await _writeState(state);
    return folders;
  }

  Future<String?> _defaultDeviceFolderPath(String folderId) async {
    if (!Platform.isAndroid) return null;

    for (final path in _defaultDeviceFolderCandidates(folderId)) {
      final directory = Directory(path);
      if (await directory.exists()) return path;
    }

    return null;
  }

  List<String> _defaultDeviceFolderCandidates(String folderId) {
    const root = '/storage/emulated/0';
    return switch (folderId) {
      'downloads' => const ['$root/Download', '$root/Downloads'],
      'documents' => const ['$root/Documents', '$root/Documentos'],
      'whatsapp' => const [
        '$root/Android/media/com.whatsapp/WhatsApp/Media',
        '$root/Android/media/com.whatsapp.w4b/WhatsApp Business/Media',
        '$root/WhatsApp/Media',
      ],
      'scans' => const [
        '$root/Documents/Scans',
        '$root/Documentos/Scans',
        '$root/Pictures/Scans',
        '$root/Scans',
      ],
      'drive' => const ['$root/Drive'],
      _ => const [],
    };
  }

  Future<DeviceFolderScan?> _scanDeviceFolder(
    String folderId,
    String path, {
    String? title,
  }) async {
    final directory = Directory(path);
    if (!await directory.exists()) return null;

    final documents = <DocumentFile>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final fileName = _fileNameFromPath(entity.path);
      if (!_isSupportedFile(fileName)) continue;

      try {
        final stat = await entity.stat();
        documents.add(
          DocumentFile(
            id: 'scan_${entity.path.hashCode}',
            title: _titleFromFileName(fileName),
            fileName: fileName,
            type: documentTypeFromFileName(fileName),
            dateLabel: _dateLabel(stat.modified),
            timeLabel: _timeLabel(stat.modified),
            sizeLabel: _formatBytes(stat.size),
            localPath: entity.path,
            sizeBytes: stat.size,
            importedAt: stat.modified,
          ),
        );
      } catch (_) {
        continue;
      }

      if (documents.length >= 250) break;
    }

    documents.sort(_newestFirst);
    return DeviceFolderScan(
      folderId: folderId,
      path: path,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : _fileNameFromPath(path),
      documents: documents,
    );
  }

  Future<int> _countSupportedFiles(Directory directory) async {
    var count = 0;
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (!_isSupportedFile(_fileNameFromPath(entity.path))) continue;
        count++;
        if (count >= 250) break;
      }
    } catch (_) {
      return 0;
    }
    return count;
  }

  String _newId(String prefix) {
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
  }

  int _albumColorFor(int index) {
    const colors = [
      0xFF2467D9,
      0xFFD61C73,
      0xFFC99112,
      0xFF1B9E47,
      0xFF1397A9,
      0xFF6A45E7,
      0xFFD72D4C,
    ];
    return colors[index % colors.length];
  }

  String _fileNameFromPath(String path) {
    final parts = path.split(Platform.pathSeparator)
      ..removeWhere((part) => part.isEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  bool _isSupportedFile(String fileName) {
    final lower = fileName.toLowerCase();
    return _supportedExtensions.any((ext) => lower.endsWith('.$ext'));
  }

  String _safeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }

  String _titleFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    return base.replaceAll('_', ' ').trim();
  }

  String _dateLabel(DateTime value) {
    return '${_two(value.day)}/${_two(value.month)}/${value.year}';
  }

  String _dateStamp(DateTime value) {
    return '${value.year}${_two(value.month)}${_two(value.day)}_'
        '${_two(value.hour)}${_two(value.minute)}${_two(value.second)}';
  }

  String _timeLabel(DateTime value) {
    return '${_two(value.hour)}:${_two(value.minute)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).round()} KB';
    }
    return '$bytes B';
  }

  Future<File> _uniqueExportFile(Directory directory, String fileName) async {
    final safeName = _safeFileName(fileName);
    final dot = safeName.lastIndexOf('.');
    final base = dot > 0 ? safeName.substring(0, dot) : safeName;
    final extension = dot > 0 ? safeName.substring(dot) : '';

    var candidate = File('${directory.path}/$safeName');
    var index = 2;
    while (await candidate.exists()) {
      candidate = File('${directory.path}/${base}_$index$extension');
      index++;
    }
    return candidate;
  }
}
