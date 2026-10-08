import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/local_documents_store.dart';

void main() {
  late Directory tempDir;
  const store = LocalDocumentsStore();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('alldocs_tags_test_');
    LocalDocumentsStore.debugDirectory = tempDir;
  });

  tearDown(() {
    LocalDocumentsStore.debugDirectory = null;
    tempDir.deleteSync(recursive: true);
  });

  Future<String> addDocument(String name) async {
    final result = await store.importBytes(
      name,
      Uint8List.fromList(utf8.encode('content of $name')),
    );
    return result.documents.single.id;
  }

  Future<Map<String, List<String>>> tagsById() async {
    final snapshot = await store.loadSnapshot();
    return {for (final d in snapshot.documents) d.id: d.tags};
  }

  test('a tag can be added to several documents at once', () async {
    final a = await addDocument('a.txt');
    final b = await addDocument('b.txt');
    final c = await addDocument('c.txt');

    await store.addTagToDocuments('Seguro', [a, b]);
    await store.addTagToDocuments('seguro', [b]); // same tag, no duplicate

    final tags = await tagsById();
    expect(tags[a], ['Seguro']);
    expect(tags[b], ['Seguro']);
    expect(tags[c], isEmpty);
    expect((await store.loadSnapshot()).tags, ['Seguro']);
  });

  test('renaming a tag updates every document and merges duplicates', () async {
    final a = await addDocument('a.txt');
    final b = await addDocument('b.txt');
    await store.addTagToDocuments('saude', [a, b]);
    await store.addTagToDocuments('Médico', [b]);

    await store.renameTag('Saúde', 'Médico'); // matched ignoring accents

    final tags = await tagsById();
    expect(tags[a], ['Médico']);
    expect(tags[b], ['Médico']);
  });

  test('deleting a tag removes it from documents but keeps them', () async {
    final a = await addDocument('a.txt');
    await store.addTagToDocuments('casa', [a]);
    await store.addTagToDocuments('2024', [a]);

    await store.deleteTag('Casa');

    final snapshot = await store.loadSnapshot();
    expect(snapshot.documents.map((d) => d.id), [a]);
    expect(snapshot.documents.single.tags, ['2024']);
    expect(snapshot.tags, ['2024']);
  });
}
