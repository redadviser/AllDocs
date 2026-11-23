import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/backup_service.dart';
import 'package:all_docs/services/backup_storage.dart';
import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/secure_zip_extractor.dart';
import 'package:all_docs/services/vault/document_vault.dart';
import 'package:all_docs/services/vault/vault_format.dart';

List<int> key(int seed) {
  final random = Random(seed);
  return [for (var i = 0; i < 32; i++) random.nextInt(256)];
}

class CountingStorage extends DeviceBackupStorage {
  CountingStorage(super.root);
  int uploads = 0;

  @override
  Future<void> upload(String path, File file) {
    if (path.startsWith('Current/')) uploads++;
    return super.upload(path, file);
  }
}

void main() {
  const store = LocalDocumentsStore();
  const service = BackupService(store: store);
  late Directory libraryDir;
  late Directory backupDir;
  late CountingStorage storage;

  Future<void> useLibrary(Directory dir, {int keySeed = 1}) async {
    LocalDocumentsStore.debugDirectory = dir;
    DocumentVault.activate('root', key(keySeed));
    await VaultMeta(
      keyCheck: VaultFormat(key(keySeed)).keyCheck,
      owner: 'local',
      migration: 'done',
    ).write(dir);
  }

  setUp(() async {
    libraryDir = Directory.systemTemp.createTempSync('backup_vault_lib_');
    backupDir = Directory.systemTemp.createTempSync('backup_vault_dest_');
    storage = CountingStorage(Directory('${backupDir.path}/AllDocs Backups'));
    DocumentVault.debugTempDirectory = libraryDir;
    await useLibrary(libraryDir);
  });

  tearDown(() {
    DocumentVault.deactivate();
    DocumentVault.debugTempDirectory = null;
    LocalDocumentsStore.debugDirectory = null;
    libraryDir.deleteSync(recursive: true);
    backupDir.deleteSync(recursive: true);
  });

  Future<void> add(String name, String content) =>
      store.importExtractedZipEntries([
        ExtractedZipEntry(fileName: name, bytes: utf8.encode(content)),
      ]);

  List<File> backupFiles() =>
      backupDir.listSync(recursive: true).whereType<File>().toList();

  Future<Directory> freshLibrary({int keySeed = 1}) async {
    final dir = Directory.systemTemp.createTempSync('backup_vault_new_');
    addTearDown(() => dir.deleteSync(recursive: true));
    await useLibrary(dir, keySeed: keySeed);
    return dir;
  }

  test('an encrypted library backs up only sealed files', () async {
    await add('Cartão Cidadão.txt', 'número 12345678');
    await add('IRS 2025.txt', 'reembolso 340');
    await service.backupTo(storage);

    for (final file in backupFiles()) {
      final name = file.uri.pathSegments.last;
      expect(
        name.endsWith('.adv') || name == 'alldocs-key.json',
        isTrue,
        reason: name,
      );
      final text = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
      for (final secret in ['12345678', 'Cidadão', 'IRS', 'reembolso']) {
        expect(text, isNot(contains(secret)), reason: file.path);
      }
    }
    expect(storage.uploads, 2);

    await service.backupTo(
      storage,
      now: DateTime.now().add(const Duration(seconds: 1)),
    );
    expect(storage.uploads, 2, reason: 'nothing changed, nothing sent');
  });

  test('restores into a new library with the same key, sealed', () async {
    await add('a.txt', 'primeiro');
    await add('b.txt', 'segundo');
    await service.backupTo(storage);

    final fresh = await freshLibrary();
    final snapshot = (await service.listSnapshots(storage)).first;
    final info = await service.restoreSnapshot(snapshot);
    expect(info.documentCount, 2);
    expect(info.missingCount, 0);

    LocalDocumentsStore.reload();
    final documents = (await store.loadSnapshot()).documents;
    expect(documents.every((d) => d.sealed), isTrue);
    expect(
      {
        for (final d in documents)
          utf8.decode(await DocumentVault.readBytes(d)),
      },
      {'primeiro', 'segundo'},
    );
    final names = Directory(
      '${fresh.path}/documents',
    ).listSync().map((f) => f.uri.pathSegments.last);
    expect(names.every((n) => n.endsWith('.adv')), isTrue);
  });

  test('another key: refused with a clear error, library untouched', () async {
    await add('a.txt', 'x');
    await service.backupTo(storage);
    await freshLibrary(keySeed: 2);
    final snapshot = (await service.listSnapshots(storage)).first;
    await expectLater(
      service.restoreSnapshot(snapshot),
      throwsA(isA<BackupKeyMismatchException>()),
    );
  });

  test('a tampered file is left out, the rest restores', () async {
    await add('a.txt', 'bom');
    await add('b.txt', 'estragado');
    await service.backupTo(storage);
    final blobs = Directory(
      '${storage.root.path}/Current/Files',
    ).listSync().whereType<File>().toList();
    final bad = blobs.first;
    final bytes = bad.readAsBytesSync();
    bytes[bytes.length - 1] ^= 1;
    bad.writeAsBytesSync(bytes);

    await freshLibrary();
    final info = await service.restoreSnapshot(
      (await service.listSnapshots(storage)).first,
    );
    expect(info.documentCount, 1);
    expect(info.missingCount, 1);
    LocalDocumentsStore.reload();
    final documents = (await store.loadSnapshot()).documents;
    expect(documents, hasLength(1));
    expect(await DocumentVault.readBytes(documents.single), isNotEmpty);
  });

  test('a plain backup restores into an encrypted library, sealed', () async {
    DocumentVault.deactivate();
    final plainDir = Directory.systemTemp.createTempSync('backup_vault_plain_');
    addTearDown(() => plainDir.deleteSync(recursive: true));
    LocalDocumentsStore.debugDirectory = plainDir;
    await add('antigo.txt', 'em claro');
    await service.backupTo(storage);

    final fresh = await freshLibrary();
    final info = await service.restoreSnapshot(
      (await service.listSnapshots(storage)).first,
    );
    expect(info.documentCount, 1);
    LocalDocumentsStore.reload();
    final document = (await store.loadSnapshot()).documents.single;
    expect(document.sealed, isTrue);
    expect(utf8.decode(await DocumentVault.readBytes(document)), 'em claro');
    final names = Directory(
      '${fresh.path}/documents',
    ).listSync().map((f) => f.uri.pathSegments.last);
    expect(names, ['${document.id}.adv']);
  });

  test(
    'old plain backups are deleted only on request; encrypted ones stay',
    () async {
      DocumentVault.deactivate();
      final plainDir = Directory.systemTemp.createTempSync(
        'backup_vault_plain_',
      );
      addTearDown(() => plainDir.deleteSync(recursive: true));
      LocalDocumentsStore.debugDirectory = plainDir;
      await add('antigo.txt', 'em claro');
      await service.backupTo(storage);
      expect(await service.hasPlainBackupsToDelete(storage), isFalse);

      await useLibrary(libraryDir);
      await add('novo.txt', 'selado');
      await service.backupTo(
        storage,
        now: DateTime.now().add(const Duration(seconds: 1)),
      );
      expect(await service.hasPlainBackupsToDelete(storage), isTrue);

      await service.deletePlainBackups(storage);
      expect(await service.hasPlainBackupsToDelete(storage), isFalse);
      for (final file in backupFiles()) {
        final name = file.uri.pathSegments.last;
        expect(
          name.endsWith('.adv') || name == 'alldocs-key.json',
          isTrue,
          reason: name,
        );
      }
      final snapshots = await service.listSnapshots(storage);
      expect(snapshots, hasLength(1));
      await freshLibrary();
      expect(
        (await service.restoreSnapshot(snapshots.single)).documentCount,
        1,
      );
    },
  );
}
