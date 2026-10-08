import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/secure_zip_extractor.dart';

void main() {
  late Directory tempDir;
  const store = LocalDocumentsStore();
  const hiddenShelf = LocalDocumentsStore.defaultHiddenShelfId;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('alldocs_hidden_test_');
    LocalDocumentsStore.debugDirectory = tempDir;
  });

  tearDown(() {
    LocalDocumentsStore.debugDirectory = null;
    tempDir.deleteSync(recursive: true);
  });

  Future<String> importText(String name, int length) async {
    final result = await store.importExtractedZipEntries([
      ExtractedZipEntry(fileName: name, bytes: utf8.encode(name[0] * length)),
    ]);
    return result.documents.single.id;
  }

  Future<String> shelfNamed(String name) async {
    final snapshot = await store.loadSnapshot();
    return [
      ...snapshot.shelves,
      ...snapshot.hiddenShelves,
    ].firstWhere((shelf) => shelf.name == name).id;
  }

  test('"Hidden" is always there, even before anything is hidden', () async {
    final snapshot = await store.loadSnapshot();
    expect(snapshot.hiddenShelves.single.id, hiddenShelf);
    expect(snapshot.hiddenShelves.single.isDefaultHidden, isTrue);
    expect(snapshot.shelves, isEmpty);
  });

  test('a hidden album and its documents only show behind the PIN', () async {
    final secret = await importText('secret.txt', 100);
    final both = await importText('both.txt', 200);
    final open = await importText('open.txt', 300);
    await store.createShelf('Casa');
    final home = await shelfNamed('Casa');
    final privateAlbum = (await store.createAlbum(home, 'Médico'))!;
    final publicAlbum = (await store.createAlbum(home, 'Contas'))!;
    await store.addDocumentsToAlbum([secret, both], privateAlbum);
    await store.addDocumentsToAlbum([both, open], publicAlbum);
    await store.addTagToDocuments('saude', [secret]);
    await store.toggleFavorite(secret);

    await store.hideAlbum(privateAlbum);
    var snapshot = await store.loadSnapshot();

    expect(snapshot.albums.map((a) => a.id), [publicAlbum]);
    // With no hidden shelf of its own yet, it goes to "Hidden".
    expect(snapshot.hiddenShelves.single.albums.map((a) => a.id), [
      privateAlbum,
    ]);
    expect(snapshot.albumById(privateAlbum)!.hidden, isTrue);
    // In a hidden album wins over being in a visible one too.
    expect(snapshot.documents.map((d) => d.id), [open]);
    expect(
      snapshot.documentsForAlbum(privateAlbum).map((d) => d.id).toSet(),
      {secret, both},
    );
    expect(snapshot.favoriteDocuments, isEmpty);
    expect(snapshot.tags, isEmpty);
    // Still takes space.
    expect(snapshot.profile.storageSummary.countedBytes, 600);

    // Shown again, it goes back to the shelf it came from.
    expect(await store.unhideDestination(privateAlbum), home);
    await store.moveAlbumToShelf(privateAlbum, home);
    snapshot = await store.loadSnapshot();
    expect(snapshot.hiddenAlbums, isEmpty);
    expect(snapshot.documents, hasLength(3));
    expect(snapshot.tags, ['saude']);
  });

  test('an album made hidden asks where to go, then remembers', () async {
    await store.createShelf('Casa');
    await store.createShelf('Saúde', hidden: true);
    final home = await shelfNamed('Casa');
    final health = await shelfNamed('Saúde');
    final album = (await store.createAlbum(health, 'Análises'))!;

    // Never on a visible shelf: the user picks one.
    expect(await store.unhideDestination(album), isNull);
    await store.moveAlbumToShelf(album, home);
    expect((await store.loadSnapshot()).albumById(album)!.hidden, isFalse);

    // Hidden again: back to the hidden shelf it was made on.
    await store.hideAlbum(album);
    var snapshot = await store.loadSnapshot();
    expect(snapshot.shelfById(health)!.albums.map((a) => a.id), [album]);

    // Once that shelf is gone, "Hidden" takes it.
    await store.moveAlbumToShelf(album, home);
    await store.deleteShelf(health);
    await store.hideAlbum(album);
    snapshot = await store.loadSnapshot();
    expect(snapshot.shelfById(hiddenShelf)!.albums.map((a) => a.id), [album]);
  });

  test('deleting a hidden shelf keeps its albums hidden on "Hidden"', () async {
    final doc = await importText('x.txt', 10);
    await store.createShelf('Pessoal', hidden: true);
    final personal = await shelfNamed('Pessoal');
    final album = (await store.createAlbum(personal, 'Diário'))!;
    await store.addDocumentsToAlbum([doc], album);

    await store.deleteShelf(personal);
    await store.deleteShelf(hiddenShelf); // "Hidden" itself can't go.
    final snapshot = await store.loadSnapshot();
    expect(snapshot.shelfById(personal), isNull);
    expect(snapshot.shelfById(hiddenShelf)!.albums.map((a) => a.id), [album]);
    expect(snapshot.documents, isEmpty);
    expect(snapshot.hiddenDocuments.map((d) => d.id), [doc]);
  });

  test('hidden and visible shelves reorder independently', () async {
    await store.createShelf('A');
    await store.createShelf('Oculta 1', hidden: true);
    await store.createShelf('B');
    await store.createShelf('Oculta 2', hidden: true);
    final a = await shelfNamed('A');
    final b = await shelfNamed('B');
    final h1 = await shelfNamed('Oculta 1');
    final h2 = await shelfNamed('Oculta 2');

    await store.reorderShelves([h2, h1]);
    var snapshot = await store.loadSnapshot();
    expect(snapshot.shelves.map((s) => s.id), [a, b]);
    expect(snapshot.hiddenShelves.map((s) => s.id), [hiddenShelf, h2, h1]);

    await store.reorderShelves([b, a]);
    snapshot = await store.loadSnapshot();
    expect(snapshot.shelves.map((s) => s.id), [b, a]);
    expect(snapshot.hiddenShelves.map((s) => s.id), [hiddenShelf, h2, h1]);
  });

  test('an album made without a shelf never lands on a hidden one', () async {
    await store.createShelf('Pessoal', hidden: true);
    final album = (await store.createAlbum(null, 'Faturas'))!;
    final snapshot = await store.loadSnapshot();
    expect(snapshot.albumById(album)!.hidden, isFalse);
    expect(snapshot.shelves.single.albums.map((a) => a.id), [album]);
  });
}
