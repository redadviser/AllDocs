import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../local_documents_store.dart';
import 'document_vault.dart';
import 'vault_format.dart';
import 'vault_keyring.dart';

enum VaultState {
  /// Unlocked and fully encrypted.
  open,

  /// Unlocked; older plain files still have to be encrypted.
  needsMigration,

  /// Not encrypted yet and couldn't be set up now (no network for the key
  /// backup): the library works as before and it's tried on the next start.
  notEncrypted,

  /// Encrypted, its key isn't on this phone and the account copy can't be
  /// fetched right now.
  needsNetwork,

  /// Encrypted, and no key that opens it exists anywhere.
  unrecoverable,

  /// The account's key copy is only handed out right after a sign-in: the
  /// session is too old to fetch it.
  needsSignIn,
}

/// Opens the signed-in account's library: finds its key (this phone, then
/// the account), or encrypts a library that isn't yet. Nothing here deletes
/// or overwrites a file; a library without its key stays as it is on disk.
class VaultUnlocker {
  VaultUnlocker({
    required this.store,
    required this.localOnly,
    VaultKeyring? keyring,
  }) : keyring = keyring ?? VaultKeyring();

  final LocalDocumentsStore store;
  final VaultKeyring keyring;

  /// No account server: the key only ever lives on this phone.
  final bool localOnly;

  Future<VaultState> unlock() async {
    final libraryId = LocalDocumentsStore.libraryId;
    final library = await store.appDirectory();
    final meta = await VaultMeta.read(library);
    if (meta == null) return _setUp(libraryId, library);

    var key = await keyring.localKey(libraryId, meta.keyCheck);
    if (key == null && libraryId != 'root') {
      // A library kept without an account, taken over by this one.
      final rootKey = await keyring.localKey('root', meta.keyCheck);
      if (rootKey != null) {
        await keyring.saveKey(libraryId, rootKey);
        key = rootKey;
        if (!localOnly) unawaited(keyring.backUp(libraryId, rootKey));
      }
    }
    if (key == null) {
      if (localOnly) return VaultState.unrecoverable;
      final (outcome, recovered) = await keyring.recover(
        libraryId,
        meta.keyCheck,
      );
      switch (outcome) {
        case KeyRecovery.recovered:
          key = recovered;
        case KeyRecovery.unavailable:
          return VaultState.needsNetwork;
        case KeyRecovery.needsSignIn:
          return VaultState.needsSignIn;
        case KeyRecovery.notStored || KeyRecovery.otherKey:
          return VaultState.unrecoverable;
      }
    }

    _activate(libraryId, key!);
    if (meta.owner == 'account') unawaited(keyring.retryPending(libraryId));
    return meta.migrated ? VaultState.open : VaultState.needsMigration;
  }

  /// A library that isn't encrypted yet. With an account it uses the
  /// account's key (the same on all its phones), making and backing one up
  /// when there's none; it only starts once the server confirmed it has
  /// the copy.
  Future<VaultState> _setUp(String libraryId, Directory library) async {
    final sealedState = File(
      '${library.path}/${LocalDocumentsStore.sealedStateFileName}',
    );
    if (await sealedState.exists()) {
      return _rebuildMeta(libraryId, library, sealedState);
    }
    Uint8List? key;
    if (localOnly) {
      key =
          await keyring.storedKey(libraryId) ??
          await keyring.createKey(libraryId);
    } else {
      for (var attempt = 0; attempt < 2 && key == null; attempt++) {
        final (outcome, accountKey) = await keyring.fetchAccountKey();
        if (outcome == KeyRecovery.needsSignIn) return VaultState.needsSignIn;
        if (outcome == KeyRecovery.recovered) {
          await keyring.saveKey(libraryId, accountKey!);
          key = accountKey;
        } else if (outcome == KeyRecovery.notStored) {
          final made =
              await keyring.storedKey(libraryId) ??
              await keyring.createKey(libraryId);
          final backup = await keyring.backUp(libraryId, made);
          if (backup == KeyBackupResult.stored) key = made;
          // conflict: another phone stored one meanwhile; fetch it.
          if (backup != KeyBackupResult.stored &&
              backup != KeyBackupResult.conflict) {
            return VaultState.notEncrypted;
          }
        } else {
          return VaultState.notEncrypted;
        }
      }
      if (key == null) return VaultState.notEncrypted;
    }

    await VaultMeta(
      keyCheck: VaultFormat(key).keyCheck,
      owner: localOnly ? 'local' : 'account',
      migration: 'pending',
    ).write(library);
    _activate(libraryId, key);
    return VaultState.needsMigration;
  }

  /// Encrypted files but no vault.json (lost or deleted): the key is the
  /// one that opens the sealed state, never a new one.
  Future<VaultState> _rebuildMeta(
    String libraryId,
    Directory library,
    File sealedState,
  ) async {
    final bytes = await sealedState.readAsBytes();
    var accountUnavailable = false;
    final candidates = <Uint8List?>[
      await keyring.storedKey(libraryId),
      await keyring.storedKey('root'),
    ];
    if (!localOnly) {
      final (outcome, accountKey) = await keyring.fetchAccountKey();
      if (outcome == KeyRecovery.needsSignIn) return VaultState.needsSignIn;
      accountUnavailable = outcome == KeyRecovery.unavailable;
      candidates.add(accountKey);
    }
    for (final key in candidates) {
      if (key == null) continue;
      try {
        await VaultFormat(key).openBytes(bytes);
      } on VaultFormatException {
        continue;
      }
      await keyring.saveKey(libraryId, key);
      await VaultMeta(
        keyCheck: VaultFormat(key).keyCheck,
        owner: localOnly ? 'local' : 'account',
        migration: 'running',
      ).write(library);
      _activate(libraryId, key);
      return VaultState.needsMigration;
    }
    return accountUnavailable
        ? VaultState.needsNetwork
        : VaultState.unrecoverable;
  }

  void _activate(String libraryId, Uint8List key) {
    DocumentVault.activate(libraryId, key);
    LocalDocumentsStore.reload();
  }

  /// "Start a new library" when the old one can't be opened: its files are
  /// moved into a `locked-<time>` folder beside it, never deleted.
  Future<void> setAsideLockedLibrary() async {
    final library = await store.appDirectory();
    final aside = Directory(
      '${library.path}/locked-${DateTime.now().millisecondsSinceEpoch}',
    );
    await aside.create(recursive: true);
    for (final name in [
      LocalDocumentsStore.sealedStateFileName,
      LocalDocumentsStore.stateFileName,
      VaultMeta.fileName,
      LocalDocumentsStore.documentsFolderName,
    ]) {
      final type = await FileSystemEntity.type('${library.path}/$name');
      if (type == FileSystemEntityType.notFound) continue;
      final entity = type == FileSystemEntityType.directory
          ? Directory('${library.path}/$name')
          : File('${library.path}/$name');
      await entity.rename('${aside.path}/$name');
    }
    DocumentVault.deactivate();
    LocalDocumentsStore.reload();
  }
}
