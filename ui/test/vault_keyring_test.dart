import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/vault/vault_format.dart';
import 'package:all_docs/services/vault/vault_keyring.dart';

class FakeStore implements VaultKeyStore {
  final values = <String, String>{};
  bool failReads = false;
  bool failWrites = false;

  @override
  Future<String?> read(String name) async {
    if (failReads) throw Exception('keystore unavailable');
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    if (failWrites) throw Exception('keystore unavailable');
    values[name] = value;
  }

  @override
  Future<void> delete(String name) async => values.remove(name);
}

class FakeBackup implements VaultKeyBackup {
  Map<String, String>? stored;
  bool offline = false;
  int? forcedStatus;
  int puts = 0;

  @override
  Future<(int, Map<String, dynamic>?)> fetch() async {
    if (offline) throw Exception('no network');
    if (forcedStatus != null) return (forcedStatus!, null);
    final value = stored;
    return value == null ? (404, null) : (200, value);
  }

  @override
  Future<int> store(String key, String keyCheck) async {
    puts++;
    if (offline) throw Exception('no network');
    if (forcedStatus != null) return forcedStatus!;
    final current = stored;
    if (current == null) {
      stored = {'key': key, 'keyCheck': keyCheck};
      return 201;
    }
    return current['key'] == key ? 200 : 409;
  }
}

void main() {
  const lib = 'acc1';
  late FakeStore store;
  late FakeBackup backup;
  late VaultKeyring keyring;

  setUp(() {
    store = FakeStore();
    backup = FakeBackup();
    keyring = VaultKeyring(store: store, backup: backup);
  });

  String check(Uint8List key) => VaultFormat(key).keyCheck;

  test('a new key is stored and found again by its check', () async {
    final key = await keyring.createKey(lib);
    expect(key, hasLength(32));
    expect(await keyring.localKey(lib, check(key)), key);
  });

  test(
    'a keystore read that fails is "no key", and nothing is written',
    () async {
      final key = await keyring.createKey(lib);
      final before = Map.of(store.values);
      store.failReads = true;
      expect(await keyring.localKey(lib, check(key)), isNull);
      expect(store.values, before);
    },
  );

  test('a key with a different check counts as missing', () async {
    await keyring.createKey(lib);
    expect(await keyring.localKey(lib, 'a' * 64), isNull);
  });

  test('a write that fails is an error, not a silent key', () async {
    store.failWrites = true;
    await expectLater(
      keyring.createKey(lib),
      throwsA(isA<VaultKeyStoreException>()),
    );
  });

  test(
    'backed up once; a second phone\'s key gets 409 and keeps its own',
    () async {
      final first = await keyring.createKey(lib);
      expect(await keyring.backUp(lib, first), KeyBackupResult.stored);
      expect(await keyring.backUp(lib, first), KeyBackupResult.stored);

      final other = VaultKeyring(store: FakeStore(), backup: backup);
      final second = await other.createKey(lib);
      expect(await other.backUp(lib, second), KeyBackupResult.conflict);
      expect(backup.stored!['key'], base64Encode(first));
      expect(await other.localKey(lib, check(second)), second);
    },
  );

  test('offline: the backup waits and is sent on retry', () async {
    final key = await keyring.createKey(lib);
    backup.offline = true;
    expect(await keyring.backUp(lib, key), KeyBackupResult.unavailable);
    expect(await keyring.hasPendingBackup(lib), isTrue);

    backup.offline = false;
    expect(await keyring.retryPending(lib), KeyBackupResult.stored);
    expect(await keyring.hasPendingBackup(lib), isFalse);
    expect(await keyring.retryPending(lib), isNull);
  });

  test('signed out (401): still pending', () async {
    final key = await keyring.createKey(lib);
    backup.forcedStatus = 401;
    expect(await keyring.backUp(lib, key), KeyBackupResult.notSignedIn);
    expect(await keyring.hasPendingBackup(lib), isTrue);
  });

  test('after a reinstall the account copy opens the library again', () async {
    final key = await keyring.createKey(lib);
    await keyring.backUp(lib, key);

    final reinstalled = VaultKeyring(store: FakeStore(), backup: backup);
    expect(await reinstalled.localKey(lib, check(key)), isNull);
    final (outcome, recovered) = await reinstalled.recover(lib, check(key));
    expect(outcome, KeyRecovery.recovered);
    expect(recovered, key);
    expect(await reinstalled.localKey(lib, check(key)), key);
  });

  test('recovery tells none, another key and offline apart', () async {
    final fresh = VaultKeyring(store: FakeStore(), backup: backup);
    expect((await fresh.recover(lib, 'a' * 64)).$1, KeyRecovery.notStored);

    await keyring.backUp(lib, await keyring.createKey(lib));
    expect((await fresh.recover(lib, 'a' * 64)).$1, KeyRecovery.otherKey);

    backup.offline = true;
    expect((await fresh.recover(lib, 'a' * 64)).$1, KeyRecovery.unavailable);
  });

  test('saving over a different key keeps the old one aside', () async {
    final old = await keyring.createKey(lib);
    final replacement = Uint8List.fromList(List.filled(32, 9));
    await keyring.saveKey(lib, replacement);
    expect(await keyring.storedKey(lib), replacement);
    final kept = store.values.entries.where(
      (e) => e.key.startsWith('vault.key.old.v1.$lib.'),
    );
    expect(kept.single.value, base64Encode(old));
  });

  test('a session too old to fetch the key asks to sign in again', () async {
    backup.forcedStatus = 403;
    backup.stored = {'key': base64Encode(List.filled(32, 1)), 'keyCheck': 'x'};
    expect((await keyring.fetchAccountKey()).$1, KeyRecovery.needsSignIn);
  });
}
