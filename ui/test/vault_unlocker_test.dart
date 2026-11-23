import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/local_documents_store.dart';
import 'package:all_docs/services/vault/document_vault.dart';
import 'package:all_docs/services/vault/vault_format.dart';
import 'package:all_docs/services/vault/vault_keyring.dart';
import 'package:all_docs/services/vault/vault_unlocker.dart';

class MemoryStore implements VaultKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String name) async => values[name];
  @override
  Future<void> write(String name, String value) async => values[name] = value;
  @override
  Future<void> delete(String name) async => values.remove(name);
}

class Server implements VaultKeyBackup {
  Map<String, String>? stored;
  bool offline = false;

  @override
  Future<(int, Map<String, dynamic>?)> fetch() async {
    if (offline) throw const SocketException('offline');
    return stored == null ? (404, null) : (200, stored);
  }

  @override
  Future<int> store(String key, String keyCheck) async {
    if (offline) throw const SocketException('offline');
    if (stored == null) {
      stored = {'key': key, 'keyCheck': keyCheck};
      return 201;
    }
    return stored!['key'] == key ? 200 : 409;
  }
}

void main() {
  const store = LocalDocumentsStore();
  late Directory library;
  late MemoryStore phone;
  late Server server;

  VaultUnlocker unlocker({bool localOnly = false, MemoryStore? keys}) =>
      VaultUnlocker(
        store: store,
        localOnly: localOnly,
        keyring: VaultKeyring(store: keys ?? phone, backup: server),
      );

  setUp(() async {
    library = Directory.systemTemp.createTempSync('unlocker_test_');
    LocalDocumentsStore.debugDirectory = library;
    DocumentVault.debugTempDirectory = library;
    phone = MemoryStore();
    server = Server();
    await store.importBytes('a.txt', Uint8List.fromList(utf8.encode('olá')));
  });

  tearDown(() {
    DocumentVault.deactivate();
    DocumentVault.debugTempDirectory = null;
    LocalDocumentsStore.debugDirectory = null;
    library.deleteSync(recursive: true);
  });

  test(
    'first start with an account: key made, backed up, then encrypt',
    () async {
      expect(await unlocker().unlock(), VaultState.needsMigration);
      expect(server.stored, isNotNull);
      final meta = (await VaultMeta.read(library))!;
      expect(meta.owner, 'account');
      expect(meta.keyCheck, server.stored!['keyCheck']);
      expect(DocumentVault.isActiveFor('root'), isTrue);
    },
  );

  test("a new phone of the account uses the account's key", () async {
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    server.stored = {
      'key': base64Encode(key),
      'keyCheck': VaultFormat(key).keyCheck,
    };
    expect(await unlocker().unlock(), VaultState.needsMigration);
    expect(
      (await VaultMeta.read(library))!.keyCheck,
      VaultFormat(key).keyCheck,
    );
  });

  test('offline on first start: stays as it is, nothing written', () async {
    server.offline = true;
    expect(await unlocker().unlock(), VaultState.notEncrypted);
    expect(await VaultMeta.read(library), isNull);
    expect(DocumentVault.libraryId, isNull);
  });

  test('encrypted, key on the phone: opens', () async {
    await unlocker().unlock();
    await VaultMeta.read(
      library,
    ).then((m) => m!.copyWith(migration: 'done').write(library));
    DocumentVault.deactivate();
    expect(await unlocker().unlock(), VaultState.open);
  });

  test(
    'reinstalled: the account copy opens it; offline asks for network',
    () async {
      await unlocker().unlock();
      DocumentVault.deactivate();
      final reinstalled = MemoryStore();

      server.offline = true;
      expect(
        await unlocker(keys: reinstalled).unlock(),
        VaultState.needsNetwork,
      );
      expect(DocumentVault.libraryId, isNull);

      server.offline = false;
      expect(
        await unlocker(keys: reinstalled).unlock(),
        VaultState.needsMigration,
      );
      expect(DocumentVault.isActiveFor('root'), isTrue);
    },
  );

  test('no key anywhere: unrecoverable, and nothing is touched', () async {
    await unlocker().unlock();
    DocumentVault.deactivate();
    server.stored = {'key': base64Encode(List.filled(32, 7)), 'keyCheck': 'x'};
    final before = library.listSync(recursive: true).map((e) => e.path).toSet();
    expect(
      await unlocker(keys: MemoryStore()).unlock(),
      VaultState.unrecoverable,
    );
    expect(
      library.listSync(recursive: true).map((e) => e.path).toSet(),
      before,
    );

    expect(
      await unlocker(localOnly: true, keys: MemoryStore()).unlock(),
      VaultState.unrecoverable,
    );
  });

  test('a new library keeps the old one aside, never deletes it', () async {
    await unlocker().unlock();
    DocumentVault.deactivate();
    final lost = unlocker(keys: MemoryStore());
    await lost.setAsideLockedLibrary();
    final aside = library.listSync().whereType<Directory>().singleWhere(
      (d) => d.path.contains('locked-'),
    );
    expect(File('${aside.path}/vault.json').existsSync(), isTrue);
    expect(Directory('${aside.path}/documents').listSync(), isNotEmpty);
    expect(File('${library.path}/vault.json').existsSync(), isFalse);
  });

  test(
    'vault.json lost: the key that opens the state is found, never a new one',
    () async {
      await unlocker().unlock();
      await store.importBytes('b.txt', Uint8List.fromList(utf8.encode('x')));
      final keyCheck = (await VaultMeta.read(library))!.keyCheck;
      DocumentVault.deactivate();
      File('${library.path}/vault.json').deleteSync();

      expect(await unlocker().unlock(), VaultState.needsMigration);
      expect((await VaultMeta.read(library))!.keyCheck, keyCheck);
      expect(File('${library.path}/alldocs_state.adv').existsSync(), isTrue);
    },
  );
}
