import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'document_classifier.dart';
import 'document_scanner_service.dart';
import 'document_search.dart';
import 'document_text_extractor.dart';
import 'document_text_indexer.dart';
import 'expiry_reminder_service.dart';
import 'secure_zip_extractor.dart';
import 'storage_permission_service.dart';

final _expiryReminderService = ExpiryReminderService();

/// What kind of files a picker call should offer.
enum ImportPickKind { documents, images, zip }

class LocalDocumentsStore {
  const LocalDocumentsStore();

  /// How long a document stays in the recycle bin before it's removed for
  /// good on the next load.
  static const trashRetention = Duration(days: 30);

  /// Longest "search the whole device" runs before showing what it found.
  static const wholeDeviceScanLimit = Duration(seconds: 12);

  static Directory? _debugDirectory;

  // A setter (not a plain field) so tests swapping in a fresh sandbox
  // directory per-case also drop the in-memory state cache below — without
  // this, a later test would read the previous test's cached state instead
  // of its own directory's file.
  static Directory? get debugDirectory => _debugDirectory;
  static set debugDirectory(Directory? value) {
    _debugDirectory = value;
    _cachedState = null;
    _cachedDeviceFolders = null;
    _deviceFoldersCountedAt = null;
  }

  static Directory? _fallbackDirectory;

  /// Called after background work (OCR indexing) changes the stored state,
  /// so the UI can reload. Set by [DocumentsService].
  static void Function()? onBackgroundUpdate;
  static bool _indexing = false;

  // Every mutation (favoriting, importing, moving a document, ...) used to
  // re-read and fully re-parse the whole state JSON from disk — and since
  // all tabs stay mounted (IndexedStack) and share one DocumentsService, a
  // single change fired that reload several times over. As the document
  // list grows this JSON blob grows with it (extracted text is stored per
  // document), so that repeated parsing was a real, scaling source of jank.
  // Caching the parsed state in memory turns every read after the first
  // into a plain map lookup; only genuine writes still touch disk.
  static Map<String, dynamic>? _cachedState;
  static const stateFileName = 'alldocs_state.json';
  static const documentsFolderName = 'documents';
  static const _stateVersion = 3;
  static const _documentExtensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'rtf',
    'csv',
    'odt',
    'ods',
    'odp',
  ];
  static const _imageExtensions = ['jpg', 'jpeg', 'png', 'heic', 'webp'];

  /// Everything that can be stored in AllDocs: documents plus images (a
  /// receipt photo, a screenshot of a QR code, ...). Device-folder scans
  /// still only surface documents (except the Screenshots folder) so the
  /// camera roll doesn't flood the results — photos are AllPhotos' job.
  static const importableExtensions = [
    ..._documentExtensions,
    ..._imageExtensions,
  ];
  static const _screenshotsFolderId = 'screenshots';
  static const _deviceFolderSpecs = [
    DeviceFolder(id: 'downloads', title: 'Downloads', itemCount: 0),
    DeviceFolder(id: 'documents', title: 'Documentos', itemCount: 0),
    DeviceFolder(id: 'whatsapp', title: 'WhatsApp', itemCount: 0),
    DeviceFolder(id: 'scans', title: 'Scans', itemCount: 0),
    DeviceFolder(id: 'drive', title: 'Drive', itemCount: 0),
    DeviceFolder(id: _screenshotsFolderId, title: 'Screenshots', itemCount: 0),
  ];

  static List<String> _allowedExtensionsFor(String folderId) {
    return folderId == _screenshotsFolderId
        ? importableExtensions
        : _documentExtensions;
  }

  static bool isImportable(String fileName) {
    final lower = fileName.toLowerCase();
    return importableExtensions.any((ext) => lower.endsWith('.$ext'));
  }

  Future<DocumentsSnapshot> loadSnapshot() async {
    final state = await _readState();
    if (await _purgeExpiredTrash(state)) await _writeState(state);
    unawaited(_indexPendingDocuments());
    return _snapshotFromState(state);
  }

  // ---------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------

  /// Just the system file picker — importing is a separate step so the UI
  /// can detect a .zip among the picked files and route it through the
  /// extract-preview-select flow (see [extractZipPreview]) instead of
  /// silently importing it whole. On Android the system picker also lists
  /// cloud providers (Drive, OneDrive, Dropbox...), which is the "quick
  /// import" path from the cloud.
  Future<List<PlatformFile>> pickFilesForImport({
    ImportPickKind kind = ImportPickKind.documents,
    bool allowMultiple = true,
  }) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: allowMultiple,
      type: kind == ImportPickKind.images ? FileType.image : FileType.custom,
      allowedExtensions: switch (kind) {
        ImportPickKind.images => null,
        ImportPickKind.zip => const ['zip'],
        ImportPickKind.documents => const [...importableExtensions, 'zip'],
      },
      withData: true,
    );
    return result?.files ?? const [];
  }

  Future<ImportResult> importPickedFiles(
    List<PlatformFile> files, {
    String? albumId,
    DocumentSource source = DocumentSource.local,
  }) async {
    if (files.isEmpty) return ImportResult.empty;

    final state = await _readState();
    final imported = <DocumentFile>[];
    var duplicates = 0;

    for (final picked in files) {
      final originalName = picked.name.trim().isEmpty
          ? 'documento_${DateTime.now().millisecondsSinceEpoch}.pdf'
          : picked.name.trim();
      final document = await _importOne(
        state,
        originalName: originalName,
        sourcePath: picked.path,
        bytes: picked.bytes,
        albumId: albumId,
        source: source,
      );
      document == null ? duplicates++ : imported.add(document);
    }

    return _finishImport(state, imported, duplicates);
  }

  /// Imports files already on disk (e.g. shared into AllDocs from another
  /// app), copying them into AllDocs' own storage.
  Future<ImportResult> importFilePaths(
    List<String> paths, {
    String? albumId,
    DocumentSource source = DocumentSource.shared,
  }) async {
    final state = await _readState();
    final imported = <DocumentFile>[];
    var duplicates = 0;

    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final name = _fileNameFromPath(path);
      if (!isImportable(name)) continue;
      final document = await _importOne(
        state,
        originalName: name,
        sourcePath: path,
        albumId: albumId,
        source: source,
      );
      document == null ? duplicates++ : imported.add(document);
    }

    return _finishImport(state, imported, duplicates);
  }

  /// Imports a single in-memory file, e.g. downloaded from a cloud provider.
  Future<ImportResult> importBytes(
    String fileName,
    Uint8List bytes, {
    String? albumId,
    DocumentSource source = DocumentSource.local,
    String? cloudFileId,
    String? cloudVersion,
  }) async {
    final state = await _readState();
    final document = await _importOne(
      state,
      originalName: fileName,
      bytes: bytes,
      albumId: albumId,
      source: source,
      cloudFileId: cloudFileId,
      cloudVersion: cloudVersion,
    );
    return _finishImport(state, [?document], document == null ? 1 : 0);
  }

  /// Lists the supported documents inside a .zip without importing anything
  /// yet — the UI shows these to the user (how many, which ones) so they
  /// pick what actually lands in AllDocs via [importExtractedZipEntries].
  /// Decoding/decompressing runs on a background isolate so a large zip
  /// doesn't freeze the UI thread while it's processed.
  Future<List<ExtractedZipEntry>> extractZipPreview(Uint8List zipBytes) {
    return const SecureZipExtractor().extractInBackground(
      zipBytes,
      allowedExtensions: importableExtensions,
    );
  }

  /// Same as [extractZipPreview], reading the zip from a file already on
  /// disk — used for a zip found via "search the whole device" scanning or
  /// shared from another app, where there's a path instead of bytes.
  Future<List<ExtractedZipEntry>> extractZipPreviewFromPath(String path) async {
    final file = File(path);
    if (!await file.exists()) return const [];
    return extractZipPreview(await file.readAsBytes());
  }

  Future<ImportResult> importExtractedZipEntries(
    List<ExtractedZipEntry> entries, {
    String? albumId,
  }) async {
    if (entries.isEmpty) return ImportResult.empty;

    final state = await _readState();
    final imported = <DocumentFile>[];
    var duplicates = 0;

    for (final entry in entries) {
      final document = await _importOne(
        state,
        originalName: entry.fileName,
        bytes: entry.bytes,
        albumId: albumId,
        source: DocumentSource.zip,
      );
      document == null ? duplicates++ : imported.add(document);
    }

    return _finishImport(state, imported, duplicates);
  }

  Future<ImportResult> scanDocumentWithCamera({
    String? albumId,
    ScanFilterChooser? chooseFilter,
  }) async {
    final scanned = await const DocumentScannerService().scanDocument(
      chooseFilter: chooseFilter,
    );
    if (scanned == null) return ImportResult.empty;

    final state = await _readState();
    final document = await _importOne(
      state,
      originalName: scanned.fileName,
      sourcePath: scanned.filePath,
      albumId: albumId,
      source: DocumentSource.scan,
      pageCount: scanned.pageCount,
      isSearchable: scanned.searchable,
      ocrText: scanned.ocrText,
      semanticType: scanned.semanticType,
      classificationConfidence: scanned.classificationConfidence,
      validityDate: scanned.validityDate,
    );
    await scanned.cleanup();
    return _finishImport(state, [?document], 0);
  }

  /// Imports documents found via device-folder scanning. A .zip among
  /// [scannedDocuments] is skipped here — the UI routes those through
  /// [extractZipPreviewFromPath]/[importExtractedZipEntries] instead, so the
  /// user sees what's inside before anything is added.
  Future<ImportResult> importScannedDocuments(
    List<DocumentFile> scannedDocuments, {
    String? albumId,
  }) async {
    if (scannedDocuments.isEmpty) return ImportResult.empty;

    final state = await _readState();
    final imported = <DocumentFile>[];
    var duplicates = 0;

    for (final scanned in scannedDocuments) {
      if (scanned.fileName.toLowerCase().endsWith('.zip')) continue;

      final sourcePath = scanned.localPath;
      if (sourcePath == null || sourcePath.isEmpty) continue;
      if (!await File(sourcePath).exists()) continue;

      final document = await _importOne(
        state,
        originalName: scanned.fileName,
        sourcePath: sourcePath,
        albumId: albumId,
        source: DocumentSource.device,
      );
      document == null ? duplicates++ : imported.add(document);
    }

    return _finishImport(state, imported, duplicates);
  }

  /// Copies one file into AllDocs' storage, fingerprints it, extracts its
  /// text when that's cheap, and appends it to [state]. Returns null when
  /// the exact same file is already in AllDocs (it isn't imported twice).
  Future<DocumentFile?> _importOne(
    Map<String, dynamic> state, {
    required String originalName,
    String? sourcePath,
    Uint8List? bytes,
    String? albumId,
    required DocumentSource source,
    String? cloudFileId,
    String? cloudVersion,
    int? pageCount,
    bool isSearchable = false,
    String? ocrText,
    DocumentSemanticType? semanticType,
    double? classificationConfidence,
    DateTime? validityDate,
  }) async {
    final id = _newId('doc');
    final storedPath = await _copyPickedFile(
      id: id,
      originalName: originalName,
      pickedPath: sourcePath,
      bytes: bytes,
    );

    final checksum = await _checksumOf(storedPath);
    if (checksum != null && _findByChecksum(state, checksum) != null) {
      try {
        await File(storedPath).delete();
      } catch (_) {}
      return null;
    }

    var text = ocrText;
    var textIndexed = text != null;
    if (text == null && DocumentTextExtractor.canExtract(originalName)) {
      text = await const DocumentTextIndexer().extractPlainText(storedPath);
      textIndexed = true;
    }

    var type = semanticType;
    var confidence = classificationConfidence;
    var validity = validityDate;
    if (type == null && text != null && text.trim().isNotEmpty) {
      final classification = const DocumentClassifier().classify(text);
      type = classification.semanticType;
      confidence = classification.confidence;
      validity = classification.validityDate;
    }

    final document = await _documentFromStoredFile(
      id: id,
      fileName: originalName,
      storedPath: storedPath,
      albumId: albumId,
      pageCount: pageCount,
      isSearchable: isSearchable || (text != null && text.isNotEmpty),
      ocrText: text,
      semanticType: type,
      classificationConfidence: confidence,
      validityDate: validity,
      checksum: checksum,
      source: source,
      cloudFileId: cloudFileId,
      cloudVersion: cloudVersion,
    );

    final json = document.toJson();
    if (textIndexed) json['text_indexed'] = true;
    _documentsRaw(state).add(json);
    if (albumId != null) _addDocumentToAlbum(state, albumId, id);
    return document;
  }

  Future<ImportResult> _finishImport(
    Map<String, dynamic> state,
    List<DocumentFile> imported,
    int duplicates,
  ) async {
    if (imported.isNotEmpty) await _writeState(state);
    for (final document in imported) {
      if (document.validityDate != null) {
        unawaited(_syncReminderBestEffort(document));
      }
    }
    if (imported.isNotEmpty) unawaited(_indexPendingDocuments());
    return ImportResult(documents: imported, skippedDuplicates: duplicates);
  }

  Future<String?> _checksumOf(String path) async {
    try {
      return await Isolate.run(() async {
        final digest = await sha256.bind(File(path).openRead()).first;
        return digest.toString();
      });
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _findByChecksum(
    Map<String, dynamic> state,
    String checksum,
  ) {
    for (final raw in _documentsList(state)) {
      if (raw['checksum'] == checksum && raw['deleted_at'] == null) return raw;
    }
    return null;
  }

  /// OCR for PDFs/images that have no text yet, one at a time in the
  /// background. Best-effort: failures just leave the document unindexed
  /// (it is marked so it isn't retried on every load).
  Future<void> _indexPendingDocuments() async {
    if (_indexing || debugDirectory != null) return;
    const indexer = DocumentTextIndexer();
    if (!DocumentTextIndexer.ocrAvailable) return;
    _indexing = true;
    try {
      while (true) {
        final state = await _readState();
        final pending = _documentsList(state).where((raw) {
          if (raw['text_indexed'] == true) return false;
          if (raw['deleted_at'] != null) return false;
          final text = raw['ocr_text']?.toString() ?? '';
          if (text.isNotEmpty) return false;
          return indexer.needsOcr(
            documentTypeFromName(raw['type']?.toString()),
          );
        }).firstOrNull;
        if (pending == null) break;

        final path = pending['local_path']?.toString();
        String? text;
        if (path != null && await File(path).exists()) {
          text = await indexer.recognizeText(
            path,
            documentTypeFromName(pending['type']?.toString()),
          );
        }

        // The entry may have been replaced (renamed, moved...) while OCR
        // ran; update whatever is current for this id.
        final target =
            _findDocument(state, pending['id']?.toString() ?? '') ?? pending;
        target['text_indexed'] = true;
        if (text != null && text.isNotEmpty) {
          target['ocr_text'] = text;
          target['is_searchable'] = true;
          if (target['semantic_type'] == null) {
            final classification = const DocumentClassifier().classify(text);
            target['semantic_type'] = classification.semanticType.name;
            target['classification_confidence'] = classification.confidence;
            target['validity_date'] = classification.validityDate
                ?.toIso8601String();
          }
        }
        await _writeState(state);
        final document = DocumentFile.fromJson(target);
        if (document.validityDate != null) {
          unawaited(_syncReminderBestEffort(document));
        }
        onBackgroundUpdate?.call();
      }
    } catch (_) {
      // Indexing is an enhancement; never let it surface as an error.
    } finally {
      _indexing = false;
    }
  }

  // ---------------------------------------------------------------------
  // Device folders and device search
  // ---------------------------------------------------------------------

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
    _deviceFoldersCountedAt = null;
    await _writeState(state);
    return _scanDeviceFolder(folderId, path, title: folderTitle);
  }

  Future<List<Directory>> _deviceSearchRoots() async {
    final state = await _readState();
    final paths = _deviceFolderPathsRaw(state);
    final rootPaths = <String>[];
    final seenPaths = <String>{};

    void addPath(String path) {
      final normalized = path.trim();
      if (normalized.isEmpty || !seenPaths.add(normalized)) return;
      rootPaths.add(normalized);
    }

    for (final folderId in const [
      'documents',
      'downloads',
      'scans',
      'drive',
      'whatsapp',
    ]) {
      for (final candidate in _defaultDeviceFolderCandidates(folderId)) {
        addPath(candidate);
      }
    }

    for (final path in paths.values) {
      addPath(path.toString());
    }

    if (Platform.isAndroid) addPath('/storage/emulated/0');

    final roots = <Directory>[];
    for (final path in rootPaths) {
      final directory = Directory(path);
      if (await directory.exists()) roots.add(directory);
    }
    return roots;
  }

  Future<DeviceFolderScan?> scanAllDeviceDocuments({String? title}) async {
    final roots = await _deviceSearchRoots();
    if (roots.isEmpty) roots.add(await _appDirectory());

    // Unlike the per-folder scans, "search the whole device" also surfaces
    // .zip files — a common user downloading one often doesn't realize it
    // needs extracting, and this is the one place broad enough to run into
    // a forgotten zip anywhere on the device. Importing one still extracts
    // its contents instead of storing the zip itself (see importDocuments
    // and importScannedDocuments).
    final documents = await _scanDirectories(
      roots,
      limit: 1800,
      preferDocuments: true,
      allowedExtensions: [..._documentExtensions, 'zip'],
      // A whole phone can hold tens of thousands of folders. Roots are
      // walked documents/downloads first, so stopping after this long
      // still returns the likely files instead of making the user wait.
      timeLimit: wholeDeviceScanLimit,
    );
    documents.sort(_newestFirst);

    return DeviceFolderScan(
      folderId: 'device',
      path: roots.first.path,
      title: title?.trim().isNotEmpty == true ? title!.trim() : 'Dispositivo',
      documents: documents,
    );
  }

  /// Finds files anywhere on the device whose name — or, for text-based
  /// formats (txt, csv, docx, xlsx, pptx, OpenDocument), whose contents —
  /// contain every word of [query]. Files already in AllDocs are skipped.
  Future<DeviceFolderScan?> searchDevice(String query, {String? title}) async {
    final tokens = searchTokens(query);
    if (tokens.isEmpty) return null;
    final roots = await _deviceSearchRoots();
    if (roots.isEmpty) return null;

    final appPath = (await _appDirectory()).path;
    final rootPaths = roots.map((directory) => directory.path).toList();
    final results = await Isolate.run(() {
      return _searchDevicePaths(
        rootPaths: rootPaths,
        tokens: tokens,
        excludePath: appPath,
        allowedExtensions: [..._documentExtensions, ..._imageExtensions, 'zip'],
        limit: 300,
      );
    });

    final documents = results
        .map((json) => DocumentFile.fromJson(Map<String, dynamic>.from(json)))
        .toList();
    return DeviceFolderScan(
      folderId: 'search',
      path: roots.first.path,
      title: title ?? query,
      documents: documents,
    );
  }

  // ---------------------------------------------------------------------
  // Shelves and albums
  // ---------------------------------------------------------------------

  /// Gives a new library a starting shelf with a few albums, so a new
  /// account isn't an empty screen. Runs once per library (remembered in
  /// the state, so deleting the shelf doesn't bring it back) and never
  /// touches a library that already has shelves. Returns whether it added
  /// anything.
  Future<bool> ensureStarterShelf(
    String shelfName,
    List<({String name, String iconName})> albums,
  ) async {
    final state = await _readState();
    if (state['starter_shelf_created'] == true) return false;
    state['starter_shelf_created'] = true;
    final shelves = _shelvesRaw(state);
    if (shelves.isNotEmpty) {
      await _writeState(state);
      return false;
    }
    final shelfId = _newId('shelf');
    shelves.add(
      DocumentShelf(
        id: shelfId,
        name: shelfName,
        position: 0,
        albums: [
          for (final (index, album) in albums.indexed)
            DocumentAlbum(
              id: '${_newId('album')}$index',
              shelfId: shelfId,
              name: album.name,
              colorValue: _albumColorFor(index),
              iconName: album.iconName,
              position: index,
              documentIds: const [],
            ),
        ],
      ).toJson(),
    );
    await _writeState(state);
    return true;
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

  Future<void> renameShelf(String shelfId, String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    final state = await _readState();
    final shelf = _findShelf(state, shelfId);
    if (shelf == null) return;
    shelf['name'] = normalized;
    await _writeState(state);
  }

  /// Creates an album and returns its id. When there is no shelf yet (or
  /// [shelfId] is null) the first shelf is used, creating a default one.
  Future<String?> createAlbum(
    String? shelfId,
    String name, {
    int? colorValue,
    String iconName = 'folder',
    String defaultShelfName = 'Documentos',
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return null;

    final state = await _readState();
    var shelf = shelfId == null ? null : _findShelf(state, shelfId);
    if (shelf == null) {
      final shelves = _shelvesList(state);
      if (shelves.isNotEmpty) {
        shelf = shelves.first;
      } else {
        final created = DocumentShelf(
          id: _newId('shelf'),
          name: defaultShelfName,
          position: 0,
          albums: const [],
        ).toJson();
        _shelvesRaw(state).add(created);
        shelf = created;
      }
    }

    final albums = _albumsRaw(shelf);
    final id = _newId('album');
    albums.add(
      DocumentAlbum(
        id: id,
        shelfId: shelf['id'].toString(),
        name: normalized,
        colorValue: colorValue ?? _albumColorFor(albums.length),
        iconName: iconName,
        position: albums.length,
        documentIds: const [],
      ).toJson(),
    );
    await _writeState(state);
    return id;
  }

  Future<void> updateAlbum(
    String albumId, {
    String? name,
    int? colorValue,
    String? iconName,
  }) async {
    final state = await _readState();
    final album = _findAlbum(state, albumId);
    if (album == null) return;
    if (name != null && name.trim().isNotEmpty) album['name'] = name.trim();
    if (colorValue != null) album['color_value'] = colorValue;
    if (iconName != null) album['icon_name'] = iconName;
    await _writeState(state);
  }

  Future<void> reorderShelves(List<String> shelfIds) async {
    final state = await _readState();
    final shelves = _shelvesRaw(state);
    int rank(dynamic shelf) {
      final index = shelfIds.indexOf((shelf as Map)['id']?.toString() ?? '');
      return index < 0 ? shelfIds.length : index;
    }

    shelves.sort((a, b) => rank(a).compareTo(rank(b)));
    _reindexShelves(state);
    await _writeState(state);
  }

  Future<void> reorderAlbums(String shelfId, List<String> albumIds) async {
    final state = await _readState();
    final shelf = _findShelf(state, shelfId);
    if (shelf == null) return;
    final albums = _albumsRaw(shelf);
    int rank(dynamic album) {
      final index = albumIds.indexOf((album as Map)['id']?.toString() ?? '');
      return index < 0 ? albumIds.length : index;
    }

    albums.sort((a, b) => rank(a).compareTo(rank(b)));
    _reindexAlbums(shelf);
    await _writeState(state);
  }

  Future<void> sortAlbumsByName(String shelfId) async {
    final state = await _readState();
    final shelf = _findShelf(state, shelfId);
    if (shelf == null) return;
    _albumsRaw(shelf).sort(
      (a, b) => normalizeForSearch(
        (a as Map)['name']?.toString() ?? '',
      ).compareTo(normalizeForSearch((b as Map)['name']?.toString() ?? '')),
    );
    _reindexAlbums(shelf);
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

  // ---------------------------------------------------------------------
  // Document changes
  // ---------------------------------------------------------------------

  /// Replaces the full set of albums [documentId] belongs to.
  Future<void> setDocumentAlbums(
    String documentId,
    List<String> albumIds,
  ) async {
    final state = await _readState();
    if (!_setAlbums(state, documentId, albumIds)) return;
    await _writeState(state);
  }

  /// Adds documents to one more album, keeping every album they're in.
  Future<void> addDocumentsToAlbum(
    List<String> documentIds,
    String albumId,
  ) async {
    final state = await _readState();
    var changed = false;
    for (final id in documentIds) {
      final raw = _findDocument(state, id);
      if (raw == null) continue;
      final document = DocumentFile.fromJson(raw);
      changed |= _setAlbums(
        state,
        id,
        {...document.albumIds, albumId}.toList(),
      );
    }
    if (changed) await _writeState(state);
  }

  Future<void> removeDocumentFromAlbum(
    String documentId,
    String albumId,
  ) async {
    final state = await _readState();
    final raw = _findDocument(state, documentId);
    if (raw == null) return;
    final document = DocumentFile.fromJson(raw);
    _setAlbums(
      state,
      documentId,
      document.albumIds.where((id) => id != albumId).toList(),
    );
    await _writeState(state);
  }

  Future<void> moveDocumentToAlbum(String documentId, String albumId) {
    return setDocumentAlbums(documentId, [albumId]);
  }

  Future<void> moveDocumentToInbox(String documentId) {
    return setDocumentAlbums(documentId, const []);
  }

  bool _setAlbums(
    Map<String, dynamic> state,
    String documentId,
    List<String> albumIds,
  ) {
    final documents = _documentsRaw(state);
    final index = documents.indexWhere((document) {
      return document is Map && document['id']?.toString() == documentId;
    });
    if (index < 0) return false;

    final raw = Map<String, dynamic>.from(documents[index] as Map);
    final document = DocumentFile.fromJson(raw);
    final validIds = albumIds
        .where((id) => _findAlbum(state, id) != null)
        .toSet()
        .toList();
    _removeDocumentFromAlbums(state, documentId);
    for (final albumId in validIds) {
      _addDocumentToAlbum(state, albumId, documentId);
    }
    documents[index] = _mergeJson(
      raw,
      document
          .copyWith(
            albumIds: validIds,
            isNew: validIds.isEmpty,
            isImported: true,
          )
          .toJson(),
    );
    return true;
  }

  /// Edits name/tags/favorite/albums in one write — used by the details
  /// sheet shown after importing and from a document's menu.
  Future<void> updateDocument(
    String documentId, {
    String? title,
    List<String>? tags,
    bool? isFavorite,
    List<String>? albumIds,
  }) async {
    final state = await _readState();
    if (albumIds != null) _setAlbums(state, documentId, albumIds);
    final changed = _updateDocumentJson(state, documentId, (document) {
      return document.copyWith(
        title: title == null || title.trim().isEmpty ? null : title.trim(),
        tags: tags == null ? null : _normalizeTags(tags),
        isFavorite: isFavorite,
      );
    });
    if (changed || albumIds != null) await _writeState(state);
  }

  Future<void> renameDocument(String documentId, String title) {
    return updateDocument(documentId, title: title);
  }

  Future<void> toggleFavorite(String documentId) async {
    final state = await _readState();
    final changed = _updateDocumentJson(state, documentId, (document) {
      return document.copyWith(isFavorite: !document.isFavorite);
    });
    if (changed) await _writeState(state);
  }

  Future<void> dismissSuggestion(String documentId) async {
    final state = await _readState();
    final changed = _updateDocumentJson(state, documentId, (document) {
      return document.copyWith(suggestionDismissed: true);
    });
    if (changed) await _writeState(state);
  }

  Future<void> setArchived(List<String> documentIds, bool archived) async {
    final state = await _readState();
    var changed = false;
    for (final id in documentIds) {
      changed |= _updateDocumentJson(state, id, (document) {
        return document.copyWith(isArchived: archived);
      });
    }
    if (changed) await _writeState(state);
  }

  /// Moves documents to the recycle bin. Files stay on disk (and in their
  /// albums) so restoring puts everything back exactly as it was.
  Future<void> moveToTrash(List<String> documentIds) async {
    final state = await _readState();
    final now = DateTime.now();
    var changed = false;
    for (final id in documentIds) {
      changed |= _updateDocumentJson(state, id, (document) {
        return document.copyWith(deletedAt: now);
      });
      unawaited(_cancelReminderBestEffort(id));
    }
    if (changed) await _writeState(state);
  }

  Future<void> restoreFromTrash(List<String> documentIds) async {
    final state = await _readState();
    final restored = <DocumentFile>[];
    for (final id in documentIds) {
      _updateDocumentJson(state, id, (document) {
        final updated = document.copyWith(clearDeletedAt: true);
        restored.add(updated);
        return updated;
      });
    }
    if (restored.isEmpty) return;
    await _writeState(state);
    for (final document in restored) {
      if (document.validityDate != null) {
        unawaited(_syncReminderBestEffort(document));
      }
    }
  }

  /// Removes documents and their files for good.
  Future<void> deletePermanently(List<String> documentIds) async {
    final state = await _readState();
    var changed = false;
    for (final id in documentIds) {
      changed |= await _deleteDocumentAndFile(state, id);
    }
    if (changed) await _writeState(state);
  }

  Future<void> emptyTrash() async {
    final state = await _readState();
    final ids = _documentsList(state)
        .where((raw) => raw['deleted_at'] != null)
        .map((raw) => raw['id'].toString())
        .toList();
    if (ids.isEmpty) return;
    for (final id in ids) {
      await _deleteDocumentAndFile(state, id);
    }
    await _writeState(state);
  }

  /// Permanent delete of a single document (kept for existing callers).
  Future<void> deleteDocument(String documentId) {
    return deletePermanently([documentId]);
  }

  Future<bool> _deleteDocumentAndFile(
    Map<String, dynamic> state,
    String documentId,
  ) async {
    final documents = _documentsRaw(state);
    final index = documents.indexWhere((document) {
      return document is Map && document['id']?.toString() == documentId;
    });
    if (index < 0) return false;

    final document = DocumentFile.fromJson(
      Map<String, dynamic>.from(documents.removeAt(index) as Map),
    );
    _removeDocumentFromAlbums(state, documentId);
    final localPath = document.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      try {
        final file = File(localPath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    unawaited(_cancelReminderBestEffort(documentId));
    return true;
  }

  Future<bool> _purgeExpiredTrash(Map<String, dynamic> state) async {
    final cutoff = DateTime.now().subtract(trashRetention);
    final expired = _documentsList(state)
        .where((raw) {
          final deletedAt = DateTime.tryParse(
            raw['deleted_at']?.toString() ?? '',
          );
          return deletedAt != null && deletedAt.isBefore(cutoff);
        })
        .map((raw) => raw['id'].toString())
        .toList();
    for (final id in expired) {
      await _deleteDocumentAndFile(state, id);
    }
    return expired.isNotEmpty;
  }

  /// Swaps a document's file for a newer version (cloud sync "Update"),
  /// keeping its albums, tags and history.
  Future<void> replaceDocumentContent(
    String documentId,
    Uint8List bytes, {
    String? cloudVersion,
  }) async {
    final state = await _readState();
    final raw = _findDocument(state, documentId);
    if (raw == null) return;
    final document = DocumentFile.fromJson(raw);
    final path = document.localPath;
    if (path == null) return;
    await File(path).writeAsBytes(bytes, flush: true);
    final checksum = await _checksumOf(path);
    String? text;
    if (DocumentTextExtractor.canExtract(document.fileName)) {
      text = await const DocumentTextIndexer().extractPlainText(path);
    }
    _updateDocumentJson(state, documentId, (document) {
      return document.copyWith(
        sizeBytes: bytes.length,
        sizeLabel: _formatBytes(bytes.length),
        checksum: checksum,
        cloudVersion: cloudVersion,
        ocrText: text,
      );
    });
    final updated = _findDocument(state, documentId);
    if (updated != null && text == null) {
      updated['text_indexed'] = false;
      updated['ocr_text'] = null;
    }
    await _writeState(state);
    unawaited(_indexPendingDocuments());
  }

  /// "Keep current version": remember the remote version the user saw so
  /// the same update isn't offered again.
  Future<void> setCloudVersion(String documentId, String? version) async {
    final state = await _readState();
    final changed = _updateDocumentJson(state, documentId, (document) {
      return document.copyWith(cloudVersion: version);
    });
    if (changed) await _writeState(state);
  }

  bool _updateDocumentJson(
    Map<String, dynamic> state,
    String documentId,
    DocumentFile Function(DocumentFile document) update,
  ) {
    final documents = _documentsRaw(state);
    final index = documents.indexWhere((document) {
      return document is Map && document['id']?.toString() == documentId;
    });
    if (index < 0) return false;
    final raw = Map<String, dynamic>.from(documents[index] as Map);
    documents[index] = _mergeJson(
      raw,
      update(DocumentFile.fromJson(raw)).toJson(),
    );
    return true;
  }

  // toJson() only knows model fields; keep store-only bookkeeping keys
  // (like `text_indexed`) that the raw map carries.
  Map<String, dynamic> _mergeJson(
    Map<String, dynamic> raw,
    Map<String, dynamic> updated,
  ) {
    return {...raw, ...updated};
  }

  List<String> _normalizeTags(List<String> tags) {
    final seen = <String>{};
    return [
      for (final tag in tags)
        if (tag.trim().isNotEmpty && seen.add(normalizeForSearch(tag.trim())))
          tag.trim(),
    ];
  }

  Future<void> _syncReminderBestEffort(DocumentFile document) async {
    try {
      await _expiryReminderService.syncReminder(document);
    } catch (_) {
      // Scheduling a local notification is best-effort and must never break
      // the scan/import flow it's attached to.
    }
  }

  Future<void> _cancelReminderBestEffort(String documentId) async {
    try {
      await _expiryReminderService.cancelReminder(documentId);
    } catch (_) {
      // Best-effort; a stray notification for a deleted document is a minor
      // annoyance, not worth surfacing an error for.
    }
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
        .where((document) => document.localPath != null && !document.isDeleted)
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

  // ---------------------------------------------------------------------
  // Backup support
  // ---------------------------------------------------------------------

  Future<Directory> appDirectory() => _appDirectory();

  Future<Directory> documentsDirectory() => _documentsDirectory();

  /// Deep copy of the current state, for writing into a backup.
  Future<Map<String, dynamic>> exportState() async {
    final state = await _readState();
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(state)) as Map);
  }

  /// Replaces the whole state with one from a backup. Stored file paths are
  /// rewritten to this device's documents folder (a backup made on another
  /// phone has that phone's absolute paths).
  Future<void> restoreState(Map<String, dynamic> restored) async {
    final documentsDir = await _documentsDirectory();
    for (final raw in _documentsList(restored)) {
      final path = raw['local_path']?.toString();
      if (path == null || path.isEmpty) continue;
      raw['local_path'] =
          '${documentsDir.path}/${_fileNameFromPath(path.replaceAll('\\', '/'))}';
    }
    _migrateState(restored);
    await _writeState(restored);
  }

  // ---------------------------------------------------------------------
  // State persistence
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> _readState() async {
    final cached = _cachedState;
    if (cached != null) return cached;

    final file = await _stateFile();
    if (!await file.exists()) {
      final initial = _initialState();
      await _writeState(initial);
      return initial;
    }

    try {
      // Parsing runs off the UI thread — with enough accumulated documents
      // (each carrying its own extracted text) this file stops being "small
      // JSON", and this is only the cold path anyway: every read after this
      // one is served straight from _cachedState.
      final raw = await file.readAsString();
      final decoded = await Isolate.run(() => jsonDecode(raw));
      if (decoded is Map<String, dynamic>) {
        final migrated = _migrateState(decoded);
        if (migrated) await _writeState(decoded);
        _cachedState = decoded;
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
    _cachedState = state;
    final file = await _stateFile();
    await file.parent.create(recursive: true);
    // Encoding also runs off the UI thread, and compact rather than
    // indented — nothing reads this file by hand, and both save real time
    // once it's carrying a large document history. Written to a temp file
    // first so a crash mid-write can't leave a truncated state file.
    final encoded = await Isolate.run(() => jsonEncode(state));
    // Unique name: background indexing can write while the UI does.
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temp.writeAsString(encoded, flush: true);
    await temp.rename(file.path);
  }

  Future<File> _stateFile() async {
    final dir = await _appDirectory();
    return File('${dir.path}/$stateFileName');
  }

  Future<Directory> _documentsDirectory() async {
    final dir = await _appDirectory();
    final documentsDir = Directory('${dir.path}/$documentsFolderName');
    await documentsDir.create(recursive: true);
    return documentsDir;
  }

  Future<Directory> _appDirectory() async {
    if (debugDirectory != null) return debugDirectory!;
    final persistent = _persistentDirectory;
    if (persistent != null) return persistent;
    if (Platform.isAndroid) {
      final adopted = await (_adoptingPersistent ??= _adoptPersistentLibrary());
      _adoptingPersistent = null;
      if (adopted != null) return adopted;
    }
    return _internalDirectory();
  }

  Future<Directory> _internalDirectory() async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      _fallbackDirectory ??= await Directory.systemTemp.createTemp(
        'alldocs_local_store_',
      );
      return _fallbackDirectory!;
    }
  }

  // The app's private folder is wiped when AllDocs is uninstalled, taking
  // every document and album with it. On Android (where AllDocs already
  // holds all-files access) the library lives in a hidden folder on shared
  // storage instead, so reinstalling finds it again. `.nomedia` keeps the
  // stored photos out of the phone's gallery apps.
  static const persistentLibraryPath = '/storage/emulated/0/Documents/.AllDocs';
  static Directory? _persistentDirectory;
  static Future<Directory?>? _adoptingPersistent;

  /// Switches to the persistent library once storage access is granted,
  /// merging in anything saved in the private folder before that (older
  /// versions, or a fresh install used before granting access).
  Future<Directory?> _adoptPersistentLibrary() async {
    try {
      if (!await const StoragePermissionService().hasAllFilesAccess()) {
        return null;
      }
      final library = Directory(persistentLibraryPath);
      final libraryDocuments = Directory(
        '${library.path}/$documentsFolderName',
      );
      await libraryDocuments.create(recursive: true);
      final noMedia = File('${library.path}/.nomedia');
      if (!await noMedia.exists()) await noMedia.create();

      final libraryState = await _readStateFile(
        File('${library.path}/$stateFileName'),
      );
      final internal = await _internalDirectory();
      final internalStateFile = File('${internal.path}/$stateFileName');
      final internalState = await _readStateFile(internalStateFile);

      final state = libraryState ?? internalState ?? _initialState();
      if (internalState != null && libraryState != null) {
        _mergeStateInto(libraryState, internalState);
      }
      if (internalState != null) {
        await _moveStoredFiles(state, libraryDocuments);
      }
      _relinkStoredFiles(state, libraryDocuments);

      _persistentDirectory = library;
      await _writeState(state);
      if (await internalStateFile.exists()) await internalStateFile.delete();
      return library;
    } catch (_) {
      // Storage not reachable (unmounted, permission revoked mid-way...):
      // keep using the private folder rather than failing the load.
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readStateFile(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      _migrateState(decoded);
      return decoded;
    } catch (_) {
      return null;
    }
  }

  /// Adds [other]'s documents and albums that [state] doesn't have yet.
  void _mergeStateInto(Map<String, dynamic> state, Map<String, dynamic> other) {
    final documents = _documentsRaw(state);
    final ids = {for (final raw in _documentsList(state)) raw['id']};
    final checksums = {
      for (final raw in _documentsList(state))
        if (raw['checksum'] != null) raw['checksum'],
    };
    for (final raw in _documentsList(other)) {
      if (ids.contains(raw['id'])) continue;
      if (raw['checksum'] != null && checksums.contains(raw['checksum'])) {
        continue;
      }
      documents.add(raw);
    }

    for (final shelf in _shelvesList(other)) {
      final target = _findShelf(state, shelf['id']?.toString() ?? '');
      if (target == null) {
        _shelvesRaw(state).add(shelf);
        continue;
      }
      for (final album in _albumsList(shelf)) {
        final existing = _findAlbum(state, album['id']?.toString() ?? '');
        if (existing == null) {
          _albumsRaw(target).add(album);
          continue;
        }
        existing['document_ids'] = {
          ...(existing['document_ids'] as List<dynamic>? ?? []),
          ...(album['document_ids'] as List<dynamic>? ?? []),
        }.toList();
      }
      _reindexAlbums(target);
    }
    _reindexShelves(state);
  }

  /// Copies files still outside [target] into it (the private folder and
  /// shared storage are different filesystems, so no plain rename).
  Future<void> _moveStoredFiles(
    Map<String, dynamic> state,
    Directory target,
  ) async {
    for (final raw in _documentsList(state)) {
      final path = raw['local_path']?.toString();
      if (path == null || path.isEmpty || path.startsWith(target.path)) {
        continue;
      }
      final source = File(path);
      if (!await source.exists()) continue;
      final destination = '${target.path}/${_fileNameFromPath(path)}';
      if (!await File(destination).exists()) await source.copy(destination);
      raw['local_path'] = destination;
      try {
        await source.delete();
      } catch (_) {}
    }
  }

  /// Points documents whose stored path no longer exists at the same file
  /// name inside [documentsDir] (e.g. a path saved by an older install).
  void _relinkStoredFiles(Map<String, dynamic> state, Directory documentsDir) {
    for (final raw in _documentsList(state)) {
      final path = raw['local_path']?.toString();
      if (path == null || path.isEmpty || File(path).existsSync()) continue;
      final candidate =
          '${documentsDir.path}/${_fileNameFromPath(path.replaceAll('\\', '/'))}';
      if (File(candidate).existsSync()) raw['local_path'] = candidate;
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
    int? pageCount,
    bool isSearchable = false,
    String? ocrText,
    DocumentSemanticType? semanticType,
    double? classificationConfidence,
    DateTime? validityDate,
    String? checksum,
    DocumentSource source = DocumentSource.local,
    String? cloudFileId,
    String? cloudVersion,
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
      albumIds: [?albumId],
      isNew: albumId == null,
      isImported: true,
      pageCount: pageCount,
      isSearchable: isSearchable,
      ocrText: ocrText,
      semanticType: semanticType,
      classificationConfidence: classificationConfidence,
      validityDate: validityDate,
      checksum: checksum,
      source: source,
      cloudFileId: cloudFileId,
      cloudVersion: cloudVersion,
    );
  }

  Future<DocumentsSnapshot> _snapshotFromState(
    Map<String, dynamic> state,
  ) async {
    final allDocuments =
        _documentsList(state)
            .map(DocumentFile.fromJson)
            .where((document) => document.id.isNotEmpty)
            .toList()
          ..sort(_newestFirst);
    final documents = allDocuments.where((d) => d.isActive).toList();
    final archivedDocuments = allDocuments
        .where((d) => d.isArchived && !d.isDeleted)
        .toList();
    final trashDocuments = allDocuments.where((d) => d.isDeleted).toList()
      ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

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

    // One pass to count documents per album, instead of the album loop
    // below re-scanning the full document list once per album — that was
    // O(albums × documents), and both grow as the archive fills up.
    final albumDocumentCounts = <String, int>{};
    for (final document in documents) {
      for (final albumId in document.albumIds) {
        albumDocumentCounts[albumId] = (albumDocumentCounts[albumId] ?? 0) + 1;
      }
    }

    final categories = <DocumentCategory>[
      for (final shelf in shelves)
        for (final album in shelf.albums)
          DocumentCategory(
            id: album.id,
            title: album.name,
            count: albumDocumentCounts[album.id] ?? 0,
            colorValue: album.colorValue,
            iconName: album.iconName,
          ),
    ];

    final favoriteDocumentsAll = documents
        .where((document) => document.isFavorite)
        .toList();
    final favoriteDocuments = favoriteDocumentsAll.take(5).toList();
    final unorganizedDocuments = documents
        .where((document) => document.albumIds.isEmpty)
        .toList();
    final recentCutoff = DateTime.now().subtract(
      DocumentsSnapshot.recentWindow,
    );
    final recentDocuments = unorganizedDocuments
        .where(
          (document) => document.importedAt?.isAfter(recentCutoff) ?? false,
        )
        .toList();
    final recentImports = documents.take(4).toList();
    final expiringDocuments =
        documents.where((document) => document.validityDate != null).toList()
          ..sort((a, b) => a.validityDate!.compareTo(b.validityDate!));
    final usedBytes = allDocuments.fold<int>(
      0,
      (total, document) => total + document.sizeBytes,
    );
    final tags =
        {for (final document in allDocuments) ...document.tags}.toList()..sort(
          (a, b) => normalizeForSearch(a).compareTo(normalizeForSearch(b)),
        );

    final albums = [for (final shelf in shelves) ...shelf.albums];
    final suggestions = <AlbumSuggestion>[];
    for (final document in unorganizedDocuments) {
      final type = document.semanticType;
      if (type == null ||
          type == DocumentSemanticType.other ||
          document.suggestionDismissed ||
          (document.classificationConfidence ?? 0) < 0.4) {
        continue;
      }
      suggestions.add(
        AlbumSuggestion(
          document: document,
          semanticType: type,
          album: albumForSemanticType(type, albums),
        ),
      );
      if (suggestions.length >= 5) break;
    }

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
      expiringDocuments: expiringDocuments.take(5).toList(),
      archivedDocuments: archivedDocuments,
      trashDocuments: trashDocuments,
      tags: tags,
      suggestions: suggestions,
      // Overwritten with the real signed-in user's name/email/plan by
      // DocumentsService.loadSnapshot() — these are just the fallback values
      // if that overlay is skipped (e.g. calling this store directly).
      profile: UserProfile(
        name: 'AllDocs',
        email: '',
        planName: 'Free',
        documentsCount: documents.length,
        categoriesCount: categories.length,
        favoritesCount: favoriteDocumentsAll.length,
        storageSummary: StorageSummary(
          usedGb: usedBytes / 1024 / 1024 / 1024,
          totalGb: 10,
        ),
      ),
    );
  }

  Map<String, dynamic> _initialState() {
    return {
      'version': _stateVersion,
      'shelves': <Map<String, dynamic>>[],
      'documents': <Map<String, dynamic>>[],
      'device_folder_paths': <String, String>{},
    };
  }

  bool _migrateState(Map<String, dynamic> state) {
    final version = state['version'];
    if (version == _stateVersion) return false;

    if (version is! int || version < 2) _migrateToV2(state);

    // v3: documents can belong to several albums (`album_ids`). Rebuild it
    // from the albums' own `document_ids`, which already allowed that.
    final membership = <String, List<String>>{};
    for (final shelf in _shelvesList(state)) {
      for (final album in _albumsList(shelf)) {
        final albumId = album['id']?.toString() ?? '';
        for (final id in (album['document_ids'] as List<dynamic>? ?? [])) {
          membership.putIfAbsent(id.toString(), () => []).add(albumId);
        }
      }
    }
    for (final raw in _documentsList(state)) {
      final id = raw['id']?.toString() ?? '';
      final ids = <String>{
        ...?membership[id],
        if (raw['album_id'] != null && raw['album_id'].toString().isNotEmpty)
          raw['album_id'].toString(),
      }.toList();
      raw['album_ids'] = ids;
      raw['album_id'] = ids.isEmpty ? null : ids.first;
    }

    state['version'] = _stateVersion;
    return true;
  }

  void _migrateToV2(Map<String, dynamic> state) {
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

  Map<String, dynamic>? _findDocument(
    Map<String, dynamic> state,
    String documentId,
  ) {
    for (final raw in _documentsList(state)) {
      if (raw['id']?.toString() == documentId) return raw;
    }
    return null;
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
      final json = Map<String, dynamic>.from(raw);
      final document = DocumentFile.fromJson(json);
      if (!document.albumIds.any(albumIds.contains)) continue;
      final remaining = document.albumIds
          .where((id) => !albumIds.contains(id))
          .toList();
      documents[i] = _mergeJson(
        json,
        document
            .copyWith(albumIds: remaining, isNew: remaining.isEmpty)
            .toJson(),
      );
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

  // Counting files walks up to thousands of directories per folder; doing
  // that on every snapshot (i.e. every favorite tap) made the whole app
  // sluggish. The snapshot now uses the last counts and refreshes them in
  // the background at most every [_deviceFolderRefresh].
  static List<DeviceFolder>? _cachedDeviceFolders;
  static DateTime? _deviceFoldersCountedAt;
  static bool _countingDeviceFolders = false;
  static const _deviceFolderRefresh = Duration(minutes: 2);

  Future<List<DeviceFolder>> _deviceFoldersFromState(
    Map<String, dynamic> state,
  ) async {
    final cached = _cachedDeviceFolders;
    final countedAt = _deviceFoldersCountedAt;
    final stale =
        countedAt == null ||
        DateTime.now().difference(countedAt) > _deviceFolderRefresh;
    if (cached != null && !stale) return cached;
    if (cached != null) {
      unawaited(_refreshDeviceFolders(state));
      return cached;
    }
    return _refreshDeviceFolders(state);
  }

  Future<List<DeviceFolder>> _refreshDeviceFolders(
    Map<String, dynamic> state,
  ) async {
    if (_countingDeviceFolders && _cachedDeviceFolders != null) {
      return _cachedDeviceFolders!;
    }
    _countingDeviceFolders = true;
    try {
      final previous = _cachedDeviceFolders;
      final folders = await _countDeviceFolders(state);
      _cachedDeviceFolders = folders;
      _deviceFoldersCountedAt = DateTime.now();
      final changed =
          previous != null &&
          [
            for (var i = 0; i < folders.length; i++)
              i < previous.length &&
                  previous[i].itemCount == folders[i].itemCount &&
                  previous[i].path == folders[i].path,
          ].contains(false);
      if (changed) onBackgroundUpdate?.call();
      return folders;
    } finally {
      _countingDeviceFolders = false;
    }
  }

  Future<List<DeviceFolder>> _countDeviceFolders(
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
          itemCount = await _countSupportedFiles(
            directory,
            allowedExtensions: _allowedExtensionsFor(spec.id),
          );
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
          itemCount = await _countSupportedFiles(
            Directory(defaultPath),
            allowedExtensions: _allowedExtensionsFor(spec.id),
          );
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
      _screenshotsFolderId => const [
        '$root/Pictures/Screenshots',
        '$root/DCIM/Screenshots',
        '$root/Screenshots',
      ],
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

    final documents = await _scanDirectories(
      [directory],
      limit: 500,
      allowedExtensions: _allowedExtensionsFor(folderId),
    );

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

  Future<int> _countSupportedFiles(
    Directory directory, {
    required List<String> allowedExtensions,
  }) async {
    try {
      return await Isolate.run(() {
        return _countSupportedFilesInPath(
          directory.path,
          limit: 250,
          allowedExtensions: allowedExtensions,
        );
      });
    } catch (_) {
      return 0;
    }
  }

  Future<List<DocumentFile>> _scanDirectories(
    List<Directory> roots, {
    required int limit,
    bool preferDocuments = false,
    required List<String> allowedExtensions,
    Duration? timeLimit,
  }) async {
    final rootPaths = roots.map((directory) => directory.path).toList();
    final jsonDocuments = await Isolate.run(() {
      return _scanDirectoryPaths(
        rootPaths: rootPaths,
        limit: limit,
        preferDocuments: preferDocuments,
        allowedExtensions: allowedExtensions,
        timeLimit: timeLimit,
      );
    });

    return jsonDocuments
        .map((json) => DocumentFile.fromJson(Map<String, dynamic>.from(json)))
        .toList();
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

List<Map<String, Object?>> _scanDirectoryPaths({
  required List<String> rootPaths,
  required int limit,
  required bool preferDocuments,
  required List<String> allowedExtensions,
  Duration? timeLimit,
}) {
  final clock = Stopwatch()..start();
  final documents = <Map<String, Object?>>[];
  final seenFiles = <String>{};
  final seenDirectories = <String>{};
  final queue = ListQueue<Directory>.of([
    for (final path in rootPaths) Directory(path),
  ]);
  final typeCounts = <String, int>{};
  final typeCaps = preferDocuments
      ? const {
          'pdf': 800,
          'word': 500,
          'excel': 500,
          'presentation': 300,
          'archive': 150,
          'image': 250,
        }
      : const <String, int>{};
  final directoryLimit = preferDocuments ? 9000 : 2400;
  var scannedDirectories = 0;

  while (queue.isNotEmpty &&
      documents.length < limit &&
      scannedDirectories < directoryLimit &&
      (timeLimit == null || clock.elapsed < timeLimit)) {
    final directory = queue.removeFirst();
    final directoryPath = directory.path;
    if (!seenDirectories.add(directoryPath)) continue;
    if (_scanShouldSkipDirectory(directoryPath)) continue;
    scannedDirectories++;

    late final List<FileSystemEntity> children;
    try {
      children = directory.listSync(followLinks: false);
    } catch (_) {
      continue;
    }

    final childDirectories = <Directory>[];
    final childFiles = <File>[];
    for (final child in children) {
      if (child is File) {
        childFiles.add(child);
      } else if (child is Directory) {
        childDirectories.add(child);
      }
    }

    childDirectories.sort((a, b) {
      final priority = _scanDirectoryPriority(
        a.path,
      ).compareTo(_scanDirectoryPriority(b.path));
      if (priority != 0) return priority;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    queue.addAll(childDirectories);

    childFiles.sort((a, b) {
      final typePriority = _scanFileTypePriority(
        a.path,
      ).compareTo(_scanFileTypePriority(b.path));
      if (typePriority != 0) return typePriority;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });

    for (final file in childFiles) {
      final path = file.path;
      if (!seenFiles.add(path)) continue;

      final fileName = _scanFileNameFromPath(path);
      if (!_scanIsSupportedFile(fileName, allowedExtensions)) continue;
      final type = documentTypeFromFileName(fileName).name;
      final cap = typeCaps[type];
      if (cap != null && (typeCounts[type] ?? 0) >= cap) continue;

      try {
        final stat = file.statSync();
        typeCounts[type] = (typeCounts[type] ?? 0) + 1;
        documents.add({
          'id': 'scan_${path.hashCode}',
          'title': _scanTitleFromFileName(fileName),
          'file_name': fileName,
          'type': type,
          'date_label': _scanDateLabel(stat.modified),
          'time_label': _scanTimeLabel(stat.modified),
          'size_label': _scanFormatBytes(stat.size),
          'local_path': path,
          'size_bytes': stat.size,
          'imported_at': stat.modified.toIso8601String(),
        });
      } catch (_) {
        continue;
      }

      if (documents.length >= limit) break;
    }
  }

  return documents;
}

int _countSupportedFilesInPath(
  String rootPath, {
  required int limit,
  required List<String> allowedExtensions,
}) {
  var count = 0;
  var scannedDirectories = 0;
  final queue = ListQueue<Directory>.of([Directory(rootPath)]);
  final seenDirectories = <String>{};

  while (queue.isNotEmpty && count < limit && scannedDirectories < 2400) {
    final directory = queue.removeFirst();
    final directoryPath = directory.path;
    if (!seenDirectories.add(directoryPath)) continue;
    if (_scanShouldSkipDirectory(directoryPath)) continue;
    scannedDirectories++;

    late final List<FileSystemEntity> children;
    try {
      children = directory.listSync(followLinks: false);
    } catch (_) {
      continue;
    }

    for (final child in children) {
      if (child is File) {
        if (!_scanIsSupportedFile(
          _scanFileNameFromPath(child.path),
          allowedExtensions,
        )) {
          continue;
        }
        count++;
        if (count >= limit) break;
      } else if (child is Directory) {
        queue.add(child);
      }
    }
  }

  return count;
}

int _scanDirectoryPriority(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  if (normalized.endsWith('/documents') ||
      normalized.endsWith('/documentos') ||
      normalized.contains('/documents/') ||
      normalized.contains('/documentos/')) {
    return 0;
  }
  if (normalized.endsWith('/download') ||
      normalized.endsWith('/downloads') ||
      normalized.contains('/download/') ||
      normalized.contains('/downloads/')) {
    return 1;
  }
  if (normalized.contains('/scans') || normalized.contains('/scanner')) {
    return 2;
  }
  if (normalized.contains('/android/data') ||
      normalized.contains('/android/media')) {
    return 3;
  }
  if (normalized.contains('/whatsapp')) return 4;
  if (normalized.contains('/dcim') ||
      normalized.contains('/pictures') ||
      normalized.contains('/movies') ||
      normalized.contains('/music')) {
    return 8;
  }
  return 5;
}

int _scanFileTypePriority(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.pdf')) return 0;
  if (lower.endsWith('.doc') || lower.endsWith('.docx')) return 1;
  if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return 2;
  return 3;
}

bool _scanShouldSkipDirectory(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  return normalized.contains('/android/obb') ||
      // AllDocs' own library (see LocalDocumentsStore.persistentLibraryPath).
      normalized.endsWith('/.alldocs') ||
      normalized.contains('/.alldocs/') ||
      normalized.endsWith('/.thumbnails') ||
      normalized.contains('/.thumbnails/') ||
      normalized.endsWith('/cache') ||
      normalized.contains('/cache/') ||
      normalized.endsWith('/code_cache') ||
      normalized.contains('/code_cache/');
}

bool _scanIsSupportedFile(String fileName, List<String> allowedExtensions) {
  final lower = fileName.toLowerCase();
  return allowedExtensions.any((ext) => lower.endsWith('.$ext'));
}

String _scanFileNameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/')..removeWhere((part) => part.isEmpty);
  return parts.isEmpty ? path : parts.last;
}

String _scanTitleFromFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  return base.replaceAll('_', ' ').trim();
}

String _scanDateLabel(DateTime value) {
  return '${_scanTwo(value.day)}/${_scanTwo(value.month)}/${value.year}';
}

String _scanTimeLabel(DateTime value) {
  return '${_scanTwo(value.hour)}:${_scanTwo(value.minute)}';
}

String _scanTwo(int value) => value.toString().padLeft(2, '0');

String _scanFormatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

/// Device-wide search: files whose name contains every token, or — for the
/// text-based formats [DocumentTextExtractor] understands, up to a few MB —
/// whose contents do. Runs inside an isolate.
List<Map<String, Object?>> _searchDevicePaths({
  required List<String> rootPaths,
  required List<String> tokens,
  required String excludePath,
  required List<String> allowedExtensions,
  required int limit,
  Duration timeLimit = const Duration(seconds: 20),
}) {
  final clock = Stopwatch()..start();
  const maxContentChecks = 400;
  const maxContentBytes = 4 * 1024 * 1024;
  final results = <Map<String, Object?>>[];
  final seenFiles = <String>{};
  final seenDirectories = <String>{};
  final queue = ListQueue<Directory>.of([
    for (final path in rootPaths) Directory(path),
  ]);
  final normalizedExclude = excludePath.replaceAll(r'\', '/').toLowerCase();
  var scannedDirectories = 0;
  var contentChecks = 0;
  const extractor = DocumentTextExtractor();

  bool matchesAll(String haystack) => tokens.every(haystack.contains);

  while (queue.isNotEmpty &&
      results.length < limit &&
      scannedDirectories < 9000 &&
      clock.elapsed < timeLimit) {
    final directory = queue.removeFirst();
    final directoryPath = directory.path;
    if (!seenDirectories.add(directoryPath)) continue;
    if (_scanShouldSkipDirectory(directoryPath)) continue;
    if (directoryPath
        .replaceAll(r'\', '/')
        .toLowerCase()
        .startsWith(normalizedExclude)) {
      continue;
    }
    scannedDirectories++;

    late final List<FileSystemEntity> children;
    try {
      children = directory.listSync(followLinks: false);
    } catch (_) {
      continue;
    }

    for (final child in children) {
      if (child is Directory) {
        queue.add(child);
        continue;
      }
      if (child is! File) continue;
      final path = child.path;
      if (!seenFiles.add(path)) continue;
      final fileName = _scanFileNameFromPath(path);
      if (!_scanIsSupportedFile(fileName, allowedExtensions)) continue;

      String? snippet;
      var matched = matchesAll(normalizeForSearch(fileName));
      if (!matched &&
          contentChecks < maxContentChecks &&
          DocumentTextExtractor.canExtract(fileName)) {
        try {
          if (child.lengthSync() <= maxContentBytes) {
            contentChecks++;
            final text = extractor.extractFromPath(path, maxChars: 60000);
            if (text != null) {
              final normalized = normalizeForSearch(text);
              if (matchesAll(normalized)) {
                matched = true;
                final index = normalized.indexOf(tokens.first);
                final start = (index - 30).clamp(0, text.length);
                final end = (index + 70).clamp(0, text.length);
                snippet = text
                    .substring(start, end)
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();
              }
            }
          }
        } catch (_) {}
      }
      if (!matched) continue;

      try {
        final stat = child.statSync();
        results.add({
          'id': 'scan_${path.hashCode}',
          'title': _scanTitleFromFileName(fileName),
          'file_name': fileName,
          'type': documentTypeFromFileName(fileName).name,
          'date_label': _scanDateLabel(stat.modified),
          'time_label': _scanTimeLabel(stat.modified),
          'size_label': _scanFormatBytes(stat.size),
          'local_path': path,
          'size_bytes': stat.size,
          'imported_at': stat.modified.toIso8601String(),
          'ocr_text': snippet,
        });
      } catch (_) {
        continue;
      }
      if (results.length >= limit) break;
    }
  }

  results.sort((a, b) {
    return (b['imported_at'] as String).compareTo(a['imported_at'] as String);
  });
  return results;
}
