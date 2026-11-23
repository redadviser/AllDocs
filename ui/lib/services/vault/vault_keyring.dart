import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api_helpers.dart';
import '../auth_service.dart';
import 'chunked_aead.dart';
import 'vault_format.dart';

/// Where a library key lives on this phone.
abstract interface class VaultKeyStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
  Future<void> delete(String name);
}

/// The account's copy of the key on the server (/api/security/vault-key).
abstract interface class VaultKeyBackup {
  /// HTTP status and, on 200, `{key, keyCheck}`.
  Future<(int, Map<String, dynamic>?)> fetch();

  /// HTTP status of storing it (201 new, 200 same, 409 another one).
  Future<int> store(String key, String keyCheck);
}

class VaultKeyStoreException implements Exception {
  const VaultKeyStoreException();
}

enum KeyBackupResult { stored, conflict, notSignedIn, unavailable }

enum KeyRecovery {
  recovered,
  notStored,
  otherKey,
  unavailable,

  /// The server wants a fresh sign-in before handing out the key.
  needsSignIn,
}

/// One 256-bit key per library (account), in the Keystore/Keychain, with a
/// copy on the account so a reinstall can open the library again.
///
/// Nothing here ever replaces or deletes a key: a read that fails is "no
/// key", never a reason to make a new one, and the server never overwrites
/// its copy.
class VaultKeyring {
  VaultKeyring({VaultKeyStore? store, VaultKeyBackup? backup})
    : _store = store ?? const _SecureKeyStore(),
      _backup = backup ?? const _ServerKeyBackup();

  final VaultKeyStore _store;
  final VaultKeyBackup _backup;

  static String _keyName(String libraryId) => 'vault.key.v1.$libraryId';
  static String _pendingName(String libraryId) =>
      'vault.key.pending.v1.$libraryId';

  /// This phone's key for [libraryId], when it opens files whose key check
  /// is [keyCheck].
  Future<Uint8List?> localKey(String libraryId, String keyCheck) async {
    final key = await _readKey(libraryId);
    if (key == null || VaultFormat(key).keyCheck != keyCheck) return null;
    return key;
  }

  /// Whatever key this phone holds for [libraryId], unchecked: only for a
  /// library that isn't encrypted yet (a key made by an earlier attempt
  /// whose backup didn't go through).
  Future<Uint8List?> storedKey(String libraryId) => _readKey(libraryId);

  /// Stores [key] as [libraryId]'s. Only for a library that isn't
  /// encrypted yet (no vault.json), where no file was sealed with whatever
  /// key was there before, or to move a key over (root library adopted).
  /// A different key already there is kept aside first, never just lost.
  Future<void> saveKey(String libraryId, Uint8List key) async {
    final previous = await _readKey(libraryId);
    if (previous != null && base64Encode(previous) != base64Encode(key)) {
      await _store.write(
        'vault.key.old.v1.$libraryId.${DateTime.now().millisecondsSinceEpoch}',
        base64Encode(previous),
      );
    }
    await _writeKey(libraryId, key);
  }

  /// The account's key, whatever it is (to encrypt a new library with the
  /// same key as the account's other phones).
  Future<(KeyRecovery, Uint8List?)> fetchAccountKey() async {
    final int status;
    final Map<String, dynamic>? body;
    try {
      (status, body) = await _backup.fetch();
    } catch (_) {
      return (KeyRecovery.unavailable, null);
    }
    if (status == 404) return (KeyRecovery.notStored, null);
    if (status == 403) return (KeyRecovery.needsSignIn, null);
    if (status != 200 || body == null) return (KeyRecovery.unavailable, null);
    try {
      final key = base64Decode(body['key'] as String);
      if (key.length == 32) return (KeyRecovery.recovered, key);
    } catch (_) {}
    return (KeyRecovery.unavailable, null);
  }

  /// A key for a library that has none yet, stored and read back before
  /// anything is encrypted with it.
  Future<Uint8List> createKey(String libraryId) async {
    final key = Uint8List.fromList(ChunkedAead.randomBytes(32));
    await _writeKey(libraryId, key);
    return key;
  }

  /// The account's copy, saved on this phone when it matches [keyCheck].
  Future<(KeyRecovery, Uint8List?)> recover(
    String libraryId,
    String keyCheck,
  ) async {
    final int status;
    final Map<String, dynamic>? body;
    try {
      (status, body) = await _backup.fetch();
    } catch (_) {
      return (KeyRecovery.unavailable, null);
    }
    if (status == 404) return (KeyRecovery.notStored, null);
    if (status == 403) return (KeyRecovery.needsSignIn, null);
    if (status != 200 || body == null) return (KeyRecovery.unavailable, null);
    final Uint8List key;
    try {
      key = base64Decode(body['key'] as String);
    } catch (_) {
      return (KeyRecovery.unavailable, null);
    }
    if (key.length != 32 || VaultFormat(key).keyCheck != keyCheck) {
      return (KeyRecovery.otherKey, null);
    }
    await _writeKey(libraryId, key);
    return (KeyRecovery.recovered, key);
  }

  /// Sends [key] to the account. Anything but a definite answer leaves it
  /// pending for [retryPending].
  Future<KeyBackupResult> backUp(String libraryId, Uint8List key) async {
    final int status;
    try {
      status = await _backup.store(
        base64Encode(key),
        VaultFormat(key).keyCheck,
      );
    } catch (_) {
      return _pending(libraryId, KeyBackupResult.unavailable);
    }
    switch (status) {
      case 200 || 201:
        await _store.delete(_pendingName(libraryId));
        return KeyBackupResult.stored;
      case 409:
        // Another key is on the account: this phone's key stays as it is.
        await _store.delete(_pendingName(libraryId));
        return KeyBackupResult.conflict;
      case 401:
        return _pending(libraryId, KeyBackupResult.notSignedIn);
      default:
        return _pending(libraryId, KeyBackupResult.unavailable);
    }
  }

  Future<bool> hasPendingBackup(String libraryId) async {
    try {
      return await _store.read(_pendingName(libraryId)) != null;
    } catch (_) {
      return false;
    }
  }

  /// Tries again to send a key [backUp] couldn't; null if none is waiting.
  Future<KeyBackupResult?> retryPending(String libraryId) async {
    if (!await hasPendingBackup(libraryId)) return null;
    final key = await _readKey(libraryId);
    if (key == null) return null;
    return backUp(libraryId, key);
  }

  Future<KeyBackupResult> _pending(
    String libraryId,
    KeyBackupResult result,
  ) async {
    await _store.write(_pendingName(libraryId), '1');
    return result;
  }

  Future<Uint8List?> _readKey(String libraryId) async {
    try {
      final raw = await _store.read(_keyName(libraryId));
      if (raw == null) return null;
      final key = base64Decode(raw);
      return key.length == 32 ? key : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeKey(String libraryId, Uint8List key) async {
    final encoded = base64Encode(key);
    try {
      await _store.write(_keyName(libraryId), encoded);
      if (await _store.read(_keyName(libraryId)) != encoded) {
        throw const VaultKeyStoreException();
      }
    } on VaultKeyStoreException {
      rethrow;
    } catch (_) {
      throw const VaultKeyStoreException();
    }
  }
}

class _SecureKeyStore implements VaultKeyStore {
  const _SecureKeyStore();

  // iOS: readable in the background after the first unlock (OCR, backups),
  // and kept out of iCloud Keychain.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<String?> read(String name) => _storage.read(key: name);

  @override
  Future<void> write(String name, String value) =>
      _storage.write(key: name, value: value);

  @override
  Future<void> delete(String name) => _storage.delete(key: name);
}

class _ServerKeyBackup implements VaultKeyBackup {
  const _ServerKeyBackup();

  static const _path = '/api/security/vault-key';

  Future<Map<String, String>> _headers() async =>
      ApiHelpers.headersWithToken(await AuthService.tokenStore.read());

  @override
  Future<(int, Map<String, dynamic>?)> fetch() async {
    final res = await ApiHelpers.get(_path, headers: await _headers());
    if (res.statusCode != 200) return (res.statusCode, null);
    return (200, jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<int> store(String key, String keyCheck) async {
    final res = await ApiHelpers.put(
      _path,
      headers: await _headers(),
      body: jsonEncode({'key': key, 'keyCheck': keyCheck}),
    );
    return res.statusCode;
  }
}
