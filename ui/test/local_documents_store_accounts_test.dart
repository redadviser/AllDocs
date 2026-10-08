import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/current_user.dart';
import 'package:all_docs/services/local_documents_store.dart';

void main() {
  late Directory tempDir;
  const store = LocalDocumentsStore();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('alldocs_accounts_test_');
    LocalDocumentsStore.debugDirectory = tempDir;
    CurrentUser.setEmail(null);
  });

  tearDown(() {
    CurrentUser.setEmail(null);
    LocalDocumentsStore.debugDirectory = null;
    tempDir.deleteSync(recursive: true);
  });

  Future<void> addDocument(String name) async {
    final result = await store.importBytes(
      name,
      Uint8List.fromList(utf8.encode('content of $name')),
    );
    expect(result.documents, hasLength(1));
  }

  Future<List<String>> documentNames() async {
    final snapshot = await store.loadSnapshot();
    return snapshot.documents.map((d) => d.fileName).toList();
  }

  test('each account on the phone has its own library', () async {
    CurrentUser.setEmail('ana@example.com');
    await addDocument('ana.txt');
    await store.createShelf('Ana');

    CurrentUser.setEmail('rui@example.com');
    expect(await documentNames(), isEmpty);
    expect((await store.loadSnapshot()).shelves, isEmpty);
    await addDocument('rui.txt');

    CurrentUser.setEmail('ANA@example.com '); // same account
    expect(await documentNames(), ['ana.txt']);
    expect((await store.loadSnapshot()).shelves.map((s) => s.name), ['Ana']);
  });

  test('the library from before accounts were separate goes to the first '
      'account that signs in, and only to it', () async {
    // Old layout: the library straight in the root, nobody signed in.
    await addDocument('old.txt');
    await store.createShelf('Pessoal');

    CurrentUser.setEmail('ana@example.com');
    expect(await documentNames(), ['old.txt']);
    final document = (await store.loadSnapshot()).documents.single;
    expect(File(document.localPath!).existsSync(), isTrue);
    expect(document.localPath, contains('/users/'));

    CurrentUser.setEmail('rui@example.com');
    expect(await documentNames(), isEmpty);
    expect((await store.loadSnapshot()).shelves, isEmpty);
  });
}
