import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/secure_zip_extractor.dart';

void main() {
  late Directory tempDir;
  const store = LocalDocumentsStore();

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

  test('a hidden album and its documents only show behind the PIN', () async {
    final secret = await importText('secret.txt', 100);
    final both = await importText('both.txt', 200);
    final open = await importText('open.txt', 300);
    final privateAlbum = (await store.createAlbum(null, 'Médico'))!;
    final publicAlbum = (await store.createAlbum(null, 'Casa'))!;
    await store.addDocumentsToAlbum([secret, both], privateAlbum);
    await store.addDocumentsToAlbum([both, open], publicAlbum);
    await store.addTagToDocuments('saude', [secret]);
    await store.toggleFavorite(secret);

    await store.setAlbumHidden(privateAlbum, true);
    var snapshot = await store.loadSnapshot();

    expect(snapshot.albums.map((a) => a.id), [publicAlbum]);
    expect(snapshot.hiddenAlbums.map((a) => a.id), [privateAlbum]);
    // In a hidden album wins over being in a visible one too.
    expect(snapshot.documents.map((d) => d.id), [open]);
    expect(snapshot.documentsForAlbum(publicAlbum).map((d) => d.id), [open]);
    expect(snapshot.documentsForAlbum(privateAlbum).map((d) => d.id).toSet(), {
      secret,
      both,
    });
    expect(snapshot.favoriteDocuments, isEmpty);
    expect(snapshot.tags, isEmpty);
    // Still takes space.
    expect(snapshot.profile.storageSummary.countedBytes, 600);

    await store.setAlbumHidden(privateAlbum, false);
    snapshot = await store.loadSnapshot();
    expect(snapshot.hiddenAlbums, isEmpty);
    expect(snapshot.documents, hasLength(3));
    expect(snapshot.tags, ['saude']);
  });
}
