import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/models/models.dart';
import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/vault/document_vault.dart';

List<int> testKey([int seed = 1]) {
  final random = Random(seed);
  return [for (var i = 0; i < 32; i++) random.nextInt(256)];
}

void main() {
  late Directory dir;
  late Directory temp;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vault_test_');
    temp = Directory('${dir.path}/tmp')..createSync();
    DocumentVault.debugTempDirectory = temp;
    DocumentVault.activate('root', testKey());
  });

  tearDown(() {
    DocumentVault.deactivate();
    DocumentVault.debugTempDirectory = null;
    dir.deleteSync(recursive: true);
  });

  Future<DocumentFile> sealed(
    List<int> bytes, {
    String name = 'CC frente.pdf',
  }) async {
    final target = File('${dir.path}/doc_1.adv');
    await DocumentVault.sealTo(Stream.value(bytes), target);
    return DocumentFile(
      id: 'doc_1',
      title: 'x',
      fileName: name,
      type: DocumentType.pdf,
      dateLabel: '',
      timeLabel: '',
      sizeLabel: '',
      localPath: target.path,
      sealed: true,
    );
  }

  test('sealed: the disk holds no plain bytes, reads give them back', () async {
    final plain = utf8.encode('número do cartão 12345678');
    final document = await sealed(plain);
    final onDisk = File(document.localPath!).readAsBytesSync();
    expect(
      utf8.decode(onDisk, allowMalformed: true),
      isNot(contains('12345678')),
    );
    expect(await DocumentVault.readBytes(document), plain);
    expect(
      await DocumentVault.openRead(document).expand((d) => d).toList(),
      plain,
    );
    expect(File('${document.localPath}.part').existsSync(), isFalse);
  });

  test('the checksum is of the plain content', () async {
    final plain = utf8.encode('conteúdo');
    final result = await DocumentVault.sealTo(
      Stream.value(plain),
      File('${dir.path}/x.adv'),
      verify: true,
    );
    expect(result.checksum, sha256.convert(plain).toString());
    expect(result.size, plain.length);
  });

  test(
    'materialize decrypts under the original name; release deletes it',
    () async {
      final document = await sealed(utf8.encode('pdf'));
      final opened = await DocumentVault.materialize(document);
      expect(opened.file.path, endsWith('/CC frente.pdf'));
      expect(opened.file.readAsStringSync(), 'pdf');
      await opened.release();
      expect(opened.file.existsSync(), isFalse);
    },
  );

  test('a handoff copy stays until purgeTemp', () async {
    final document = await sealed(utf8.encode('pdf'));
    final opened = await DocumentVault.materialize(document, handoff: true);
    await opened.release();
    expect(opened.file.existsSync(), isTrue);
    await DocumentVault.purgeTemp();
    expect(Directory('${temp.path}/alldocs_open').existsSync(), isFalse);
  });

  test('a file that is not sealed passes through as it is', () async {
    final plainFile = File('${dir.path}/device.pdf')..writeAsStringSync('dev');
    final document = DocumentFile(
      id: 'd',
      title: 'd',
      fileName: 'device.pdf',
      type: DocumentType.pdf,
      dateLabel: '',
      timeLabel: '',
      sizeLabel: '',
      localPath: plainFile.path,
    );
    final opened = await DocumentVault.materialize(document);
    expect(opened.file.path, plainFile.path);
    await opened.release();
    expect(plainFile.existsSync(), isTrue);
    expect(utf8.decode(await DocumentVault.readBytes(document)), 'dev');
  });

  test('readBytes refuses more than 20 MB', () async {
    final document = await sealed(
      Uint8List(DocumentVault.memoryLimit + 200000),
    );
    await expectLater(
      DocumentVault.readBytes(document),
      throwsA(isA<DocumentTooLargeForMemory>()),
    );
  });

  test('sealed survives the JSON round trip; unsealed stays out of it', () {
    final json = DocumentFile.fromJson({
      'id': 'a',
      'file_name': 'a.pdf',
      'local_path': '/x/a.adv',
      'sealed': true,
    }).toJson();
    expect(json['sealed'], isTrue);
    expect(
      DocumentFile.fromJson({'id': 'b'}).toJson().containsKey('sealed'),
      isFalse,
    );
  });

  group('store with the library unlocked', () {
    const store = LocalDocumentsStore();
    late Directory library;

    setUp(() {
      library = Directory('${dir.path}/library')..createSync();
      LocalDocumentsStore.debugDirectory = library;
    });

    tearDown(() => LocalDocumentsStore.debugDirectory = null);

    test(
      'imports are sealed under <id>.adv, state sealed, nothing plain',
      () async {
        final result = await store.importBytes(
          'Contrato Casa.txt',
          Uint8List.fromList(utf8.encode('renda 950 euros')),
        );
        final document = result.documents.single;
        expect(document.sealed, isTrue);
        expect(document.localPath, endsWith('/${document.id}.adv'));

        final names = Directory(
          '${library.path}/documents',
        ).listSync().map((f) => f.uri.pathSegments.last).toList();
        expect(names, ['${document.id}.adv']);
        expect(File('${library.path}/alldocs_state.adv').existsSync(), isTrue);
        expect(
          File('${library.path}/alldocs_state.json').existsSync(),
          isFalse,
        );
        for (final file
            in library.listSync(recursive: true).whereType<File>()) {
          final text = utf8.decode(
            file.readAsBytesSync(),
            allowMalformed: true,
          );
          expect(text, isNot(contains('renda 950')), reason: file.path);
          expect(text, isNot(contains('Contrato Casa')), reason: file.path);
        }

        LocalDocumentsStore.reload();
        final snapshot = await store.loadSnapshot();
        expect(snapshot.documents.single.fileName, 'Contrato Casa.txt');
        expect(
          utf8.decode(await DocumentVault.readBytes(snapshot.documents.single)),
          'renda 950 euros',
        );
      },
    );

    test('the same file twice is still caught as a duplicate', () async {
      final bytes = Uint8List.fromList(utf8.encode('igual'));
      await store.importBytes('a.txt', bytes);
      final again = await store.importBytes('b.txt', bytes);
      expect(again.skippedDuplicates, 1);
    });

    test('locked: refuses to load and never writes over the state', () async {
      await store.importBytes('a.txt', Uint8List.fromList([1, 2, 3]));
      final stateFile = File('${library.path}/alldocs_state.adv');
      final before = stateFile.readAsBytesSync();

      DocumentVault.deactivate();
      LocalDocumentsStore.reload();
      await expectLater(
        store.loadSnapshot(),
        throwsA(isA<VaultLockedException>()),
      );
      expect(stateFile.readAsBytesSync(), before);
      expect(File('${library.path}/alldocs_state.json').existsSync(), isFalse);
    });
  });

  test(
    'purgeTemp clears decrypted copies, scratch and staged imports',
    () async {
      final scratch = await DocumentVault.scratch();
      File('${scratch.path}/x.pdf').writeAsStringSync('claro');
      final staged = Directory('${temp.path}/alldocs_import')..createSync();
      File('${staged.path}/y.pdf').writeAsStringSync('claro');
      await DocumentVault.purgeTemp();
      expect(scratch.existsSync(), isFalse);
      expect(staged.existsSync(), isFalse);
    },
  );

  test(
    'a sealed file is on disk (no .part left) once sealTo returns',
    () async {
      await DocumentVault.sealTo(
        Stream.value([1, 2, 3]),
        File('${dir.path}/z.adv'),
      );
      final leftovers = dir.listSync().where((e) => e.path.endsWith('.part'));
      expect(leftovers, isEmpty);
    },
  );
}
