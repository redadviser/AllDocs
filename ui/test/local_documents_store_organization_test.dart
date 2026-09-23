import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/models/models.dart';
import 'package:all_docs/services/document_search.dart';
import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/secure_zip_extractor.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('alldocs_organization_test_');
    LocalDocumentsStore.debugDirectory = tempDir;
  });

  tearDown(() {
    LocalDocumentsStore.debugDirectory = null;
    tempDir.deleteSync(recursive: true);
  });

  const store = LocalDocumentsStore();

  Future<DocumentFile> importText(String name, String content) async {
    final result = await store.importExtractedZipEntries([
      ExtractedZipEntry(fileName: name, bytes: utf8.encode(content)),
    ]);
    return result.documents.single;
  }

  Future<String> newAlbum(String name) async {
    return (await store.createAlbum(null, name))!;
  }

  test('a document can be in several albums without being copied', () async {
    final document = await importText('contrato_joao.txt', 'Contrato');
    final clients = await newAlbum('Clientes');
    final contracts = await newAlbum('Contratos');

    await store.addDocumentsToAlbum([document.id], clients);
    await store.addDocumentsToAlbum([document.id], contracts);

    var snapshot = await store.loadSnapshot();
    expect(snapshot.documentsForAlbum(clients), hasLength(1));
    expect(snapshot.documentsForAlbum(contracts), hasLength(1));
    expect(snapshot.documents, hasLength(1));
    expect(snapshot.unorganizedDocuments, isEmpty);
    expect(Directory('${tempDir.path}/documents').listSync(), hasLength(1));

    await store.removeDocumentFromAlbum(document.id, clients);
    snapshot = await store.loadSnapshot();
    expect(snapshot.documentsForAlbum(clients), isEmpty);
    expect(snapshot.documentsForAlbum(contracts), hasLength(1));
  });

  test('archiving hides from the gallery without moving the file', () async {
    final document = await importText('recibo.txt', 'Recibo');

    await store.setArchived([document.id], true);
    var snapshot = await store.loadSnapshot();
    expect(snapshot.documents, isEmpty);
    expect(snapshot.archivedDocuments.single.id, document.id);
    expect(File(document.localPath!).existsSync(), isTrue);

    await store.setArchived([document.id], false);
    snapshot = await store.loadSnapshot();
    expect(snapshot.documents.single.id, document.id);
  });

  test('recycle bin keeps the file until deleted permanently', () async {
    final document = await importText('fatura.txt', 'Fatura');
    final album = await newAlbum('Faturas');
    await store.addDocumentsToAlbum([document.id], album);

    await store.moveToTrash([document.id]);
    var snapshot = await store.loadSnapshot();
    expect(snapshot.documents, isEmpty);
    expect(snapshot.trashDocuments.single.id, document.id);
    expect(snapshot.documentsForAlbum(album), isEmpty);
    expect(File(document.localPath!).existsSync(), isTrue);

    await store.restoreFromTrash([document.id]);
    snapshot = await store.loadSnapshot();
    expect(snapshot.documentsForAlbum(album), hasLength(1));

    await store.moveToTrash([document.id]);
    await store.emptyTrash();
    snapshot = await store.loadSnapshot();
    expect(snapshot.trashDocuments, isEmpty);
    expect(File(document.localPath!).existsSync(), isFalse);
  });

  test('importing the exact same file twice is skipped', () async {
    await importText('a.txt', 'same content');
    final second = await store.importExtractedZipEntries([
      ExtractedZipEntry(fileName: 'b.txt', bytes: utf8.encode('same content')),
    ]);

    expect(second.count, 0);
    expect(second.skippedDuplicates, 1);
    expect((await store.loadSnapshot()).documents, hasLength(1));
  });

  test('text inside documents is searchable', () async {
    await importText('IMG_29482.txt', 'Vodafone Portugal\nFatura n.º 128282');
    await importText('notas.txt', 'Lista de compras');

    final snapshot = await store.loadSnapshot();
    final hits = searchDocuments(
      snapshot.documents,
      const DocumentSearchFilter(query: 'vodafone'),
    );

    expect(hits.single.document.fileName, 'IMG_29482.txt');
    expect(hits.single.textSnippet, contains('Vodafone'));
  });

  test('details (name, tags, favorite, albums) are saved together', () async {
    final document = await importText('orcamento.txt', 'Orçamento');
    final album = await newAlbum('Trabalho');

    await store.updateDocument(
      document.id,
      title: 'Orçamento Cliente A',
      tags: ['Cliente A', '2026', 'cliente a'],
      isFavorite: true,
      albumIds: [album],
    );

    final updated = (await store.loadSnapshot()).documents.single;
    expect(updated.title, 'Orçamento Cliente A');
    expect(updated.tags, ['Cliente A', '2026']);
    expect(updated.isFavorite, isTrue);
    expect(updated.albumIds, [album]);
  });
}
