import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/local_documents_store.dart';

void main() {
  late Directory tempDir;
  const store = LocalDocumentsStore();
  const albums = [
    (name: 'Contratos', iconName: 'work'),
    (name: 'Faturas', iconName: 'receipt'),
  ];

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('alldocs_starter_test_');
    LocalDocumentsStore.debugDirectory = tempDir;
  });

  tearDown(() {
    LocalDocumentsStore.debugDirectory = null;
    tempDir.deleteSync(recursive: true);
  });

  test('a new library gets the Personal shelf with its albums', () async {
    expect(await store.ensureStarterShelf('Pessoal', albums), isTrue);

    final snapshot = await store.loadSnapshot();
    expect(snapshot.shelves.map((s) => s.name), ['Pessoal']);
    expect(snapshot.albums.map((a) => a.name), ['Contratos', 'Faturas']);
    expect(snapshot.albums.map((a) => a.id).toSet(), hasLength(2));
  });

  test('it only happens once, even after the shelf is deleted', () async {
    await store.ensureStarterShelf('Pessoal', albums);
    final shelfId = (await store.loadSnapshot()).shelves.single.id;
    await store.deleteShelf(shelfId);

    expect(await store.ensureStarterShelf('Pessoal', albums), isFalse);
    expect((await store.loadSnapshot()).shelves, isEmpty);
  });

  test('a library that already has shelves is left alone', () async {
    await store.createShelf('Trabalho');

    expect(await store.ensureStarterShelf('Pessoal', albums), isFalse);
    final snapshot = await store.loadSnapshot();
    expect(snapshot.shelves.map((s) => s.name), ['Trabalho']);
  });
}
