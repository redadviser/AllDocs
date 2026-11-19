import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/models/models.dart';
import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/secure_zip_extractor.dart';

void main() {
  late Directory tempDir;
  const store = LocalDocumentsStore();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('alldocs_storage_test_');
    LocalDocumentsStore.debugDirectory = tempDir;
  });

  tearDown(() {
    LocalDocumentsStore.debugDirectory = null;
    tempDir.deleteSync(recursive: true);
  });

  Future<String> importText(String name, int length) async {
    final result = await store.importExtractedZipEntries([
      ExtractedZipEntry(fileName: name, bytes: utf8.encode('x' * length)),
    ]);
    return result.documents.single.id;
  }

  test('storage counts every document file the app holds, on disk', () async {
    final inAlbum = await importText('a.txt', 100);
    await importText('b.txt', 200);
    final archived = await importText('c.txt', 300);
    final deleted = await importText('d.txt', 400);
    final album = (await store.createAlbum(null, 'Faturas'))!;
    await store.addDocumentsToAlbum([inAlbum], album);
    await store.setArchived([archived], true);
    await store.moveToTrash([deleted]);

    final summary = (await store.loadSnapshot()).profile.storageSummary;
    expect(summary.inAlbums.count, 1);
    expect(summary.inAlbums.bytes, 100);
    expect(summary.withoutAlbum.count, 1);
    expect(summary.withoutAlbum.bytes, 200);
    expect(summary.archivedOrDeleted.count, 2);
    expect(summary.archivedOrDeleted.bytes, 700);
    expect(summary.documentCount, 4);
    expect(summary.usedBytes, 1000);
    // The recycle bin is shown but doesn't count towards the plan's limit.
    expect(summary.trashBytes, 400);
    expect(summary.trashCount, 1);
    expect(summary.countedDocuments, 3);
    expect(
      summary.limitDocuments,
      PlanCatalog.builtIn.byId(AppPlan.free).maxDocuments,
    );
  });

  test('a library is full once what counts reaches the limit', () {
    const summary = StorageSummary(
      limitDocuments: 3,
      withoutAlbum: StorageBucket(count: 2, bytes: 900),
      archivedOrDeleted: StorageBucket(count: 1, bytes: 500),
      trashBytes: 500,
      trashCount: 1,
    );
    expect(summary.countedDocuments, 2);
    expect(summary.freeDocuments, 1);
    expect(summary.hasRoomFor(1), isTrue);
    expect(summary.hasRoomFor(2), isFalse);
    expect(summary.isFull, isFalse);
    expect(summary.withLimit(2).isFull, isTrue);
    expect(summary.withLimit(null).hasRoomFor(1000), isTrue);
  });
}
