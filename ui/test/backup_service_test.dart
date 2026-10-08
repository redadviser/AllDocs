import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/models/models.dart';
import 'package:all_docs/services/backup_service.dart';
import 'package:all_docs/services/backup_storage.dart';
import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/secure_zip_extractor.dart';

void main() {
  late Directory libraryDir;
  late Directory backupDir;
  late DeviceBackupStorage storage;
  const store = LocalDocumentsStore();
  const service = BackupService(store: store);

  setUp(() {
    libraryDir = Directory.systemTemp.createTempSync('alldocs_backup_lib_');
    backupDir = Directory.systemTemp.createTempSync('alldocs_backup_dest_');
    LocalDocumentsStore.debugDirectory = libraryDir;
    storage = DeviceBackupStorage(
      Directory('${backupDir.path}/AllDocs Backups'),
    );
  });

  tearDown(() {
    LocalDocumentsStore.debugDirectory = null;
    libraryDir.deleteSync(recursive: true);
    backupDir.deleteSync(recursive: true);
  });

  Future<DocumentFile> importText(String name, String content) async {
    final result = await store.importExtractedZipEntries([
      ExtractedZipEntry(fileName: name, bytes: utf8.encode(content)),
    ]);
    return result.documents.single;
  }

  Set<String> filesIn(String folder) {
    final dir = Directory('${storage.root.path}/$folder');
    if (!dir.existsSync()) return {};
    return {
      for (final entity in dir.listSync())
        if (entity is File) entity.uri.pathSegments.last,
    };
  }

  String read(String path) =>
      File('${storage.root.path}/$path').readAsStringSync();

  test(
    'Current holds the gallery and every album, history holds JSON',
    () async {
      final invoice = await importText('fatura.txt', 'Fatura 1');
      final contract = await importText('contrato.txt', 'Contrato');
      final invoices = (await store.createAlbum(null, 'Faturas'))!;
      final clients = (await store.createAlbum(null, 'Clientes'))!;
      await store.addDocumentsToAlbum([invoice.id], invoices);
      await store.addDocumentsToAlbum([invoice.id, contract.id], clients);

      await service.backupTo(storage, now: DateTime(2026, 10, 6, 14, 30, 5));

      expect(filesIn('Current/Gallery'), {'fatura.txt', 'contrato.txt'});
      expect(filesIn('Current/Faturas'), {'fatura.txt'});
      expect(filesIn('Current/Clientes'), {'fatura.txt', 'contrato.txt'});
      expect(read('Current/Clientes/contrato.txt'), 'Contrato');
      expect(filesIn('Current'), {'alldocs-current.json'});

      final backup = 'Backup 2026-10-06 14-30-05';
      expect(filesIn(backup), {'alldocs-backup.json', 'alldocs-state.json'});
      final manifest = jsonDecode(read('$backup/alldocs-backup.json')) as Map;
      expect(manifest['document_count'], 2);
      final snapshots = await service.listSnapshots(storage);
      expect(snapshots.single.name, backup);
      expect(snapshots.single.isLatest, isTrue);
    },
  );

  test('a second backup only moves what changed and keeps the history '
      'restorable', () async {
    final invoice = await importText('fatura.txt', 'Fatura 1');
    final contract = await importText('contrato.txt', 'Contrato');
    final clients = (await store.createAlbum(null, 'Clientes'))!;
    await store.addDocumentsToAlbum([contract.id], clients);
    await service.backupTo(storage, now: DateTime(2026, 10, 6, 10));

    final galleryFile = File('${storage.root.path}/Current/Gallery/fatura.txt');
    final firstModified = galleryFile.lastModifiedSync();

    // Rename one and delete the other.
    await store.renameDocument(invoice.id, 'Fatura da luz');
    await store.moveToTrash([contract.id]);
    await service.backupTo(storage, now: DateTime(2026, 10, 7, 10));

    expect(filesIn('Current/Gallery'), {'Fatura da luz.txt'});
    expect(filesIn('Current'), {'alldocs-current.json'});
    expect(
      Directory('${storage.root.path}/Current/Clientes').existsSync(),
      isTrue,
    );
    expect(filesIn('Current/Clientes'), isEmpty);
    // The deleted document waits in Removed for the older backup.
    expect(filesIn('Removed'), hasLength(1));
    expect(filesIn('Removed').single, endsWith(' contrato.txt'));
    // Renamed in place, not written again.
    expect(
      File(
        '${storage.root.path}/Current/Gallery/Fatura da luz.txt',
      ).lastModifiedSync(),
      firstModified,
    );

    final snapshots = await service.listSnapshots(storage);
    expect(snapshots.map((s) => s.name), [
      'Backup 2026-10-07 10-00-00',
      'Backup 2026-10-06 10-00-00',
    ]);

    // Restoring the first one brings the deleted contract back, in its album.
    final info = await service.restoreSnapshot(snapshots.last);
    expect(info.documentCount, 2);
    expect(info.missingCount, 0);
    final snapshot = await store.loadSnapshot();
    final restoredContract = snapshot.documents.singleWhere(
      (document) => document.id == contract.id,
    );
    expect(restoredContract.isDeleted, isFalse);
    expect(restoredContract.albumIds, [clients]);
    expect(File(restoredContract.localPath!).readAsStringSync(), 'Contrato');
    expect(
      snapshot.documents.singleWhere((d) => d.id == invoice.id).title,
      invoice.title,
    );
  });

  test('archived documents go to Archive, and old restore points are pruned '
      'with the removed files only they needed', () async {
    final kept = await importText('a.txt', 'A');
    final gone = await importText('b.txt', 'B');
    await store.setArchived([kept.id], true);
    await service.backupTo(storage, now: DateTime(2026, 1, 1));
    expect(filesIn('Current/Archive'), {'a.txt'});
    expect(filesIn('Current/Gallery'), {'b.txt'});

    await store.setArchived([kept.id], false);
    await store.moveToTrash([gone.id]);
    await service.backupTo(storage, now: DateTime(2026, 1, 2));
    expect(
      Directory('${storage.root.path}/Current/Archive').existsSync(),
      isFalse,
    );
    expect(filesIn('Current/Gallery'), {'a.txt'});
    expect(filesIn('Removed'), hasLength(1));

    for (var day = 3; day < 3 + BackupService.keptBackups; day++) {
      await service.backupTo(storage, now: DateTime(2026, 1, day));
    }
    final snapshots = await service.listSnapshots(storage);
    expect(snapshots, hasLength(BackupService.keptBackups));
    expect(snapshots.last.name, 'Backup 2026-01-03 00-00-00');
    expect(filesIn('Removed'), isEmpty);
  });

  test('a restore point whose files are gone restores what it can', () async {
    await importText('a.txt', 'A');
    await service.backupTo(storage, now: DateTime(2026, 2, 1));
    Directory(
      '${storage.root.path}/Current/Gallery',
    ).deleteSync(recursive: true);

    final snapshot = (await service.listSnapshots(storage)).single;
    final info = await service.restoreSnapshot(snapshot);
    expect(info.documentCount, 0);
    expect(info.missingCount, 1);
    expect((await store.loadSnapshot()).documents, isEmpty);
  });

  test('a folder named like the picked one is not nested again', () {
    expect(
      service.deviceBackupRoot('/storage/emulated/0/Download').path,
      '/storage/emulated/0/Download/AllDocs Backups',
    );
    expect(
      service.deviceBackupRoot('/storage/emulated/0/AllDocs Backups/').path,
      '/storage/emulated/0/AllDocs Backups',
    );
  });
}
