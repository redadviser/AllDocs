import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/local_documents_store.dart';

void main() {
  late Directory tempDir;
  const store = LocalDocumentsStore();
  const albums = <StarterAlbum>[
    (name: 'Contratos', iconName: 'work', since: 1),
    (name: 'Faturas', iconName: 'receipt', since: 1),
    (name: 'Identificação', iconName: 'person', since: 2),
  ];

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('alldocs_starter_test_');
    LocalDocumentsStore.debugDirectory = tempDir;
  });

  tearDown(() {
    LocalDocumentsStore.debugDirectory = null;
    tempDir.deleteSync(recursive: true);
  });

  /// A library seeded by the first starter set (Contratos + Faturas), saved
  /// the way that version left it.
  void writeV1Library({required List<String> albumNames}) {
    File('${tempDir.path}/alldocs_state.json').writeAsStringSync(
      jsonEncode({
        'version': 3,
        'starter_shelf_created': true,
        'documents': [],
        'shelves': [
          {
            'id': 'shelf_1',
            'name': 'Pessoal',
            'position': 0,
            'albums': [
              for (final (i, name) in albumNames.indexed)
                {
                  'id': 'album_$i',
                  'shelf_id': 'shelf_1',
                  'name': name,
                  'color_value': 0xFF2467D9,
                  'icon_name': 'folder',
                  'position': i,
                  'document_ids': [],
                },
            ],
          },
        ],
      }),
    );
  }

  test('a new library gets the Personal shelf with its albums', () async {
    expect(await store.ensureStarterShelf('Pessoal', albums), isTrue);

    final snapshot = await store.loadSnapshot();
    expect(snapshot.shelves.map((s) => s.name), ['Pessoal']);
    expect(snapshot.albums.map((a) => a.name), [
      'Contratos',
      'Faturas',
      'Identificação',
    ]);
    expect(snapshot.albums.map((a) => a.id).toSet(), hasLength(3));
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

  test('a library from the first starter set gets just the new album, '
      'without bringing back a deleted one', () async {
    writeV1Library(albumNames: ['Contratos']); // "Faturas" was deleted

    expect(await store.ensureStarterShelf('Pessoal', albums), isTrue);
    final names = (await store.loadSnapshot()).albums.map((a) => a.name);
    expect(names, ['Contratos', 'Identificação']);

    // And only once.
    expect(await store.ensureStarterShelf('Pessoal', albums), isFalse);
  });

  test('an old library whose starter shelf is gone gets nothing', () async {
    writeV1Library(albumNames: ['Contratos', 'Faturas']);
    final shelfId = (await store.loadSnapshot()).shelves.single.id;
    await store.renameShelf(shelfId, 'Casa');

    expect(await store.ensureStarterShelf('Pessoal', albums), isFalse);
    expect((await store.loadSnapshot()).albums.map((a) => a.name), [
      'Contratos',
      'Faturas',
    ]);
  });
}
