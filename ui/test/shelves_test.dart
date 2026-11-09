import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/secure_zip_extractor.dart';

void main() {
  late Directory tempDir;
  const store = LocalDocumentsStore();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('alldocs_shelves_test_');
    LocalDocumentsStore.debugDirectory = tempDir;
  });

  tearDown(() {
    LocalDocumentsStore.debugDirectory = null;
    tempDir.deleteSync(recursive: true);
  });

  test('createShelf returns the new shelf id', () async {
    final id = await store.createShelf('Casa');
    expect(id, isNotNull);
    expect((await store.loadSnapshot()).shelfById(id!)!.name, 'Casa');
    expect(await store.createShelf('   '), isNull);
  });

  test('an album moves to another shelf with its documents', () async {
    final home = (await store.createShelf('Casa'))!;
    final work = (await store.createShelf('Trabalho'))!;
    final invoices = (await store.createAlbum(home, 'Faturas'))!;
    final bills = (await store.createAlbum(home, 'Contas'))!;
    final clients = (await store.createAlbum(work, 'Clientes'))!;
    final imported = await store.importExtractedZipEntries([
      ExtractedZipEntry(fileName: 'fatura.txt', bytes: utf8.encode('f')),
    ]);
    await store.addDocumentsToAlbum([
      imported.documents.single.id,
    ], invoices);

    await store.moveAlbumToShelf(invoices, work);
    final snapshot = await store.loadSnapshot();

    expect(snapshot.shelfById(home)!.albums.map((a) => a.id), [bills]);
    expect(snapshot.shelfById(work)!.albums.map((a) => a.id), [
      clients,
      invoices,
    ]);
    final moved = snapshot.albumById(invoices)!;
    expect(moved.shelfId, work);
    expect(moved.hidden, isFalse);
    expect(snapshot.shelfById(work)!.albums.map((a) => a.position), [0, 1]);
    expect(snapshot.shelfById(home)!.albums.single.position, 0);
    expect(snapshot.documentsForAlbum(invoices), hasLength(1));
  });

  test('a new album can go straight onto a new shelf', () async {
    await store.createShelf('Casa');
    final fresh = (await store.createShelf('Carro'))!;
    final album = (await store.createAlbum(fresh, 'Seguro'))!;
    final snapshot = await store.loadSnapshot();
    expect(snapshot.albumById(album)!.shelfId, fresh);
    expect(snapshot.shelfById(fresh)!.albums.map((a) => a.id), [album]);
  });

  test('a dragged album lands at the place it was dropped', () async {
    final home = (await store.createShelf('Casa'))!;
    final work = (await store.createShelf('Trabalho'))!;
    final invoices = (await store.createAlbum(home, 'Faturas'))!;
    final clients = (await store.createAlbum(work, 'Clientes'))!;
    final projects = (await store.createAlbum(work, 'Projetos'))!;

    await store.moveAlbumToShelf(invoices, work, index: 1);
    var albums = (await store.loadSnapshot()).shelfById(work)!.albums;
    expect(albums.map((a) => a.id), [clients, invoices, projects]);
    expect(albums.map((a) => a.position), [0, 1, 2]);

    // Past the end it goes last.
    await store.moveAlbumToShelf(invoices, home);
    await store.moveAlbumToShelf(invoices, work, index: 99);
    albums = (await store.loadSnapshot()).shelfById(work)!.albums;
    expect(albums.map((a) => a.id), [clients, projects, invoices]);
  });
}
