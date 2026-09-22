import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/models/models.dart';
import 'package:all_docs/services/local_documents_store.dart';

Uint8List _buildZip(List<(String name, String content)> entries) {
  final archive = Archive();
  for (final (name, content) in entries) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('alldocs_zip_import_test_');
    LocalDocumentsStore.debugDirectory = tempDir;
  });

  tearDown(() {
    LocalDocumentsStore.debugDirectory = null;
    tempDir.deleteSync(recursive: true);
  });

  const store = LocalDocumentsStore();

  test('extractZipPreview finds only the supported documents inside', () async {
    final zip = _buildZip([
      ('invoice.pdf', 'pdf content'),
      ('notes.txt', 'text content'),
      ('photo.jpg', 'image bytes'),
    ]);

    final entries = await store.extractZipPreview(zip);

    expect(entries.map((e) => e.fileName).toSet(), {'invoice.pdf', 'notes.txt'});
  });

  test(
    'importExtractedZipEntries lands the chosen entries as unorganized documents',
    () async {
      final zip = _buildZip([
        ('invoice.pdf', 'pdf content'),
        ('notes.txt', 'text content'),
      ]);
      final entries = await store.extractZipPreview(zip);

      // Only "import" the pdf, as if the user unchecked notes.txt in the
      // preview sheet — the txt file must never reach the store.
      final selected = entries.where((e) => e.fileName == 'invoice.pdf').toList();
      final imported = await store.importExtractedZipEntries(selected);

      expect(imported, 1);

      final snapshot = await store.loadSnapshot();
      expect(snapshot.documents, hasLength(1));
      final document = snapshot.documents.single;
      expect(document.fileName, 'invoice.pdf');
      expect(document.type, DocumentType.pdf);
      // No albumId given, so it must show up unfiled — the "por organizar"
      // behavior the import flow relies on when no album is specified.
      expect(document.albumId, isNull);
      expect(
        snapshot.unorganizedDocuments.map((d) => d.id),
        contains(document.id),
      );

      // The bytes actually landed on disk as AllDocs' own copy, not just an
      // entry in the JSON index.
      expect(File(document.localPath!).existsSync(), isTrue);
    },
  );

  test('importExtractedZipEntries respects an explicit albumId', () async {
    await store.createShelf('Shelf');
    var snapshot = await store.loadSnapshot();
    final shelfId = snapshot.shelves.single.id;
    await store.createAlbum(shelfId, 'Album');
    snapshot = await store.loadSnapshot();
    final albumId = snapshot.shelves.single.albums.single.id;

    final zip = _buildZip([('invoice.pdf', 'pdf content')]);
    final entries = await store.extractZipPreview(zip);
    await store.importExtractedZipEntries(entries, albumId: albumId);

    snapshot = await store.loadSnapshot();
    expect(snapshot.documentsForAlbum(albumId), hasLength(1));
    expect(snapshot.unorganizedDocuments, isEmpty);
  });

  test('importScannedDocuments skips a .zip instead of importing it whole', () async {
    final zipFile = File('${tempDir.path}/bundle.zip')
      ..writeAsBytesSync(_buildZip([('invoice.pdf', 'pdf content')]));

    final zipDocument = DocumentFile(
      id: 'scan_1',
      title: 'bundle',
      fileName: 'bundle.zip',
      type: DocumentType.archive,
      dateLabel: '01/01/2024',
      sizeLabel: '1 KB',
      localPath: zipFile.path,
    );

    final imported = await store.importScannedDocuments([zipDocument]);

    expect(imported, 0);
    final snapshot = await store.loadSnapshot();
    expect(snapshot.documents, isEmpty);
  });
}
