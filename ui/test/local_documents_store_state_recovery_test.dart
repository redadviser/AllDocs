import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/local_documents_store.dart';

void main() {
  late Directory tempDir;
  const store = LocalDocumentsStore();

  File stateFile() =>
      File('${tempDir.path}/${LocalDocumentsStore.stateFileName}');

  List<File> setAside() => tempDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('.unreadable-'))
      .toList();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('alldocs_state_test_');
    LocalDocumentsStore.debugDirectory = tempDir;
  });

  tearDown(() {
    LocalDocumentsStore.debugDirectory = null;
    tempDir.deleteSync(recursive: true);
  });

  test('an unreadable state file is set aside, never written over', () async {
    await store.importBytes('a.txt', Uint8List.fromList(utf8.encode('a')));
    final good = stateFile().readAsStringSync();
    // Truncated mid-write, or damaged on disk.
    stateFile().writeAsStringSync(good.substring(0, good.length ~/ 2));
    final damaged = stateFile().readAsStringSync();
    LocalDocumentsStore.debugDirectory = tempDir; // drop the cached state

    final snapshot = await store.loadSnapshot();

    expect(snapshot.documents, isEmpty);
    expect(setAside(), hasLength(1));
    expect(setAside().single.readAsStringSync(), damaged);
    expect(jsonDecode(stateFile().readAsStringSync()), isA<Map>());
  });

  test('bytes that are not UTF-8 are set aside too', () async {
    stateFile().writeAsBytesSync([0xff, 0xfe, 0x00, 0x7b]);

    await store.loadSnapshot();

    expect(setAside(), hasLength(1));
    expect(setAside().single.readAsBytesSync(), [0xff, 0xfe, 0x00, 0x7b]);
  });

  test('a readable state file is kept as it is', () async {
    await store.importBytes('a.txt', Uint8List.fromList(utf8.encode('a')));
    LocalDocumentsStore.debugDirectory = tempDir;

    final snapshot = await store.loadSnapshot();

    expect(snapshot.documents.single.fileName, 'a.txt');
    expect(setAside(), isEmpty);
  });
}
