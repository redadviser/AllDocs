import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/vault/document_vault.dart';
import 'package:all_docs/services/vault/vault_format.dart';
import 'package:all_docs/services/vault/vault_migration.dart';

List<int> key(int seed) {
  final random = Random(seed);
  return [for (var i = 0; i < 32; i++) random.nextInt(256)];
}

class Crash implements Exception {}

void main() {
  const store = LocalDocumentsStore();
  late Directory library;
  late File deviceFile;
  final contents = {
    'cc.txt': 'cartão de cidadão',
    'nif.txt': 'número fiscal',
    'grande.bin': String.fromCharCodes(List.filled(3 * 1024 * 1024, 65)),
  };

  setUp(() async {
    library = Directory.systemTemp.createTempSync('migration_test_');
    LocalDocumentsStore.debugDirectory = library;
    DocumentVault.debugTempDirectory = library;
    // A plain library, as every one is before this version.
    for (final entry in contents.entries) {
      await store.importBytes(
        entry.key,
        Uint8List.fromList(utf8.encode(entry.value)),
      );
    }
    // A device-folder document: referenced, never copied in.
    deviceFile = File('${library.path}/../device_${library.hashCode}.txt')
      ..writeAsStringSync('do telemóvel');
    final state =
        jsonDecode(
              File('${library.path}/alldocs_state.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    (state['documents'] as List).add({
      'id': 'device_1',
      'file_name': 'device.txt',
      'local_path': deviceFile.path,
    });
    File(
      '${library.path}/alldocs_state.json',
    ).writeAsStringSync(jsonEncode(state));
    LocalDocumentsStore.reload();

    DocumentVault.activate('root', key(1));
    await VaultMeta(
      keyCheck: VaultFormat(key(1)).keyCheck,
      owner: 'local',
      migration: 'pending',
    ).write(library);
  });

  tearDown(() {
    DocumentVault.deactivate();
    DocumentVault.debugTempDirectory = null;
    LocalDocumentsStore.debugDirectory = null;
    library.deleteSync(recursive: true);
    if (deviceFile.existsSync()) deviceFile.deleteSync();
  });

  VaultMigration migration({
    void Function(String step)? failAt,
    int? free,
    VaultFormat? previous,
  }) => VaultMigration(
    store,
    freeSpace: (_) async => free,
    debugFailAt: failAt,
    previous: previous,
  );

  Future<void> expectFullySealed() async {
    LocalDocumentsStore.reload();
    final snapshot = await store.loadSnapshot();
    final byName = {for (final d in snapshot.documents) d.fileName: d};
    for (final entry in contents.entries) {
      final document = byName[entry.key]!;
      expect(document.sealed, isTrue, reason: entry.key);
      final plain = await DocumentVault.openRead(
        document,
      ).expand((d) => d).toList();
      expect(utf8.decode(plain), entry.value, reason: entry.key);
      expect(sha256.convert(plain).toString(), document.checksum);
    }
    final device = byName['device.txt']!;
    expect(device.sealed, isFalse);
    expect(device.localPath, deviceFile.path);
    expect(deviceFile.readAsStringSync(), 'do telemóvel');

    final names = Directory(
      '${library.path}/documents',
    ).listSync().map((f) => f.uri.pathSegments.last);
    expect(names.every((n) => n.endsWith('.adv')), isTrue, reason: '$names');
    expect(names, hasLength(contents.length));
    expect(File('${library.path}/alldocs_state.json').existsSync(), isFalse);
    expect((await VaultMeta.read(library))!.migrated, isTrue);
  }

  test('seals every library document and leaves device files alone', () async {
    final progress = <MigrationProgress>[];
    final result = await migration().run(onProgress: progress.add);
    expect(result.outcome, MigrationOutcome.done);
    expect(progress.last.done, contents.length);
    expect(progress.last.fraction, 1);
    await expectFullySealed();
  });

  for (final step in ['state', 'part', 'rename', 'before-save', 'after-save']) {
    test('stopped at "$step", then run again: nothing lost', () async {
      var crashed = false;
      await expectLater(
        migration(
          failAt: (s) {
            if (s == step && !crashed) {
              crashed = true;
              throw Crash();
            }
          },
        ).run(),
        throwsA(isA<Crash>()),
      );
      // The app restarts: nothing in memory survives.
      LocalDocumentsStore.reload();
      expect((await migration().run()).outcome, MigrationOutcome.done);
      await expectFullySealed();
    });
  }

  test('not enough room: does not start and changes nothing', () async {
    final before = File(
      '${library.path}/alldocs_state.json',
    ).readAsStringSync();
    final result = await migration(free: 1024).run();
    expect(result.outcome, MigrationOutcome.noSpace);
    expect(result.missingBytes, greaterThan(0));
    expect(
      File('${library.path}/alldocs_state.json').readAsStringSync(),
      before,
    );
    expect((await VaultMeta.read(library))!.migration, 'pending');
  });

  test('disk full mid-way: the original stays, the rest waits', () async {
    var calls = 0;
    final result = await migration(
      failAt: (s) {
        if (s == 'part' && ++calls == 2) {
          throw const FileSystemException('write', '', OSError('No space', 28));
        }
      },
    ).run();
    expect(result.outcome, MigrationOutcome.noSpace);
    LocalDocumentsStore.reload();
    final snapshot = await store.loadSnapshot();
    for (final document in snapshot.documents) {
      final plain = await DocumentVault.openRead(
        document,
      ).expand((d) => d).toList();
      expect(utf8.decode(plain), isNotEmpty);
    }
    expect((await migration().run()).outcome, MigrationOutcome.done);
    await expectFullySealed();
  });

  test('re-sealing moves every file to the new key', () async {
    await migration().run();
    final old = VaultFormat(key(1));
    DocumentVault.activate('root', key(2));
    LocalDocumentsStore.reload();
    var crashed = false;
    await expectLater(
      migration(
        previous: old,
        failAt: (s) {
          if (s == 'rename' && !crashed) {
            crashed = true;
            throw Crash();
          }
        },
      ).run(),
      throwsA(isA<Crash>()),
    );
    LocalDocumentsStore.reload();
    expect(
      (await migration(previous: old).run()).outcome,
      MigrationOutcome.done,
    );
    await expectFullySealed();
    // Nothing opens with the old key any more.
    final anyDoc = Directory('${library.path}/documents').listSync().first;
    await expectLater(
      DocumentVault.openSealed(anyDoc.path, using: old).toList(),
      throwsA(isA<VaultFormatException>()),
    );
  });
}
