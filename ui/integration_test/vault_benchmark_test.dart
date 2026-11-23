import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:all_docs/models/models.dart';
import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/vault/document_vault.dart';
import 'package:all_docs/services/vault/vault_format.dart';
import 'package:all_docs/services/vault/vault_migration.dart';

/// Run on a real phone (plan section 10, task F1):
///   `flutter test integration_test/vault_benchmark_test.dart -d <device>`
/// Targets: a 200 MB file opens in under 5 s on a mid-range Android and
/// under 3 s on a recent iPhone.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final key = List.generate(32, (i) => Random.secure().nextInt(256));

  late Directory dir;
  setUp(() async {
    dir = await (await getTemporaryDirectory()).createTemp('vault_bench_');
    DocumentVault.debugTempDirectory = dir;
    DocumentVault.activate('root', key);
  });
  tearDown(() async {
    DocumentVault.deactivate();
    DocumentVault.debugTempDirectory = null;
    await dir.delete(recursive: true);
  });

  test('AES-GCM is the platform one, not pure Dart', () {
    final aes = AesGcm.with256bits();
    debugPrint('[vault] AesGcm implementation: ${aes.runtimeType}');
    expect(aes.runtimeType.toString(), isNot('DartAesGcm'));
  });

  test('a 200 MB document: seal, then open (materialize)', () async {
    const size = 200 * 1024 * 1024;
    final plain = File('${dir.path}/big.pdf');
    final sink = plain.openWrite();
    final chunk = Uint8List(1024 * 1024);
    for (var i = 0; i < 200; i++) {
      chunk[0] = i;
      sink.add(chunk);
    }
    await sink.close();

    final sealWatch = Stopwatch()..start();
    final sealed = await DocumentVault.sealTo(
      plain.openRead(),
      File('${dir.path}/doc.adv'),
    );
    sealWatch.stop();

    final document = DocumentFile(
      id: 'doc',
      title: 'big',
      fileName: 'big.pdf',
      type: DocumentType.pdf,
      dateLabel: '',
      timeLabel: '',
      sizeLabel: '',
      localPath: '${dir.path}/doc.adv',
      sealed: true,
    );
    final openWatch = Stopwatch()..start();
    final opened = await DocumentVault.materialize(document);
    openWatch.stop();

    debugPrint(
      '[vault] seal 200 MB: ${sealWatch.elapsedMilliseconds} ms; '
      'open 200 MB: ${openWatch.elapsedMilliseconds} ms',
    );
    expect(await opened.file.length(), size);
    expect(sealed.size, size);
    await opened.release();
    expect(
      openWatch.elapsed,
      lessThan(
        Platform.isIOS
            ? const Duration(seconds: 3)
            : const Duration(seconds: 5),
      ),
    );
  });

  test('migrating 50 documents (200 MB)', () async {
    final library = Directory('${dir.path}/library');
    await library.create();
    LocalDocumentsStore.debugDirectory = library;
    addTearDown(() => LocalDocumentsStore.debugDirectory = null);
    DocumentVault.deactivate();
    const store = LocalDocumentsStore();
    for (var i = 0; i < 50; i++) {
      await store.importBytes(
        'doc_$i.pdf',
        Uint8List(4 * 1024 * 1024)..[0] = i,
      );
    }
    LocalDocumentsStore.reload();
    DocumentVault.activate('root', key);
    await VaultMeta(
      keyCheck: VaultFormat(key).keyCheck,
      owner: 'local',
      migration: 'pending',
    ).write(library);

    final watch = Stopwatch()..start();
    final result = await VaultMigration(store).run();
    watch.stop();
    debugPrint(
      '[vault] migrate 50 docs / 200 MB: ${watch.elapsedMilliseconds} ms',
    );
    expect(result.outcome, MigrationOutcome.done);
  });
}
