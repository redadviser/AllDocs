import 'dart:io';

import '../local_documents_store.dart';
import 'document_vault.dart';
import 'free_space.dart';
import 'vault_format.dart';

/// How far a migration got, for the progress screen.
class MigrationProgress {
  const MigrationProgress({
    required this.done,
    required this.total,
    required this.bytesDone,
    required this.bytesTotal,
  });

  final int done;
  final int total;
  final int bytesDone;
  final int bytesTotal;

  double get fraction => bytesTotal == 0 ? 1 : bytesDone / bytesTotal;
}

enum MigrationOutcome {
  /// Every document is sealed.
  done,

  /// Not enough room (before starting, or the disk filled up mid-way). The
  /// library is consistent and the rest is retried on the next start.
  noSpace,

  /// Some documents didn't verify after sealing and stay as they were;
  /// retried on the next start.
  incomplete,
}

class MigrationResult {
  const MigrationResult(this.outcome, {this.failed = 0, this.missingBytes = 0});

  final MigrationOutcome outcome;
  final int failed;

  /// For [MigrationOutcome.noSpace] before starting: how much more is needed.
  final int missingBytes;
}

/// Encrypts a library that was kept in plain files (or moves one to a new
/// key, with [previous]). Safe to stop at any point and run again:
///
/// 1. the state is written sealed and read back before the plain one goes;
/// 2. each document is sealed to `<id>.adv.part`, decrypted and compared
///    (SHA-256), and only then renamed to `<id>.adv`;
/// 3. every batch (100 MB or 20 documents) the state is saved, and only
///    after that are the batch's originals deleted.
///
/// Until the state that points at `<id>.adv` is saved, the original is what
/// the library uses; if the app stops in between, the next run seals it
/// again.
class VaultMigration {
  VaultMigration(
    this._store, {
    this.previous,
    Future<int?> Function(String path)? freeSpace,
    this.debugFailAt,
  }) : _freeSpace = freeSpace ?? FreeSpace.at;

  final LocalDocumentsStore _store;
  final Future<int?> Function(String path) _freeSpace;

  /// The key the library is moving away from, when re-sealing.
  final VaultFormat? previous;

  /// Tests: throws at the named step to stand in for the app being killed.
  final void Function(String step)? debugFailAt;

  static const _batchBytes = 100 * 1024 * 1024;
  static const _batchDocuments = 20;
  static const _margin = 100 * 1024 * 1024;

  // ENOSPC on Linux/Android and on Darwin.
  static const _noSpaceErrno = 28;

  Future<MigrationResult> run({
    void Function(MigrationProgress progress)? onProgress,
  }) async {
    final library = await _store.appDirectory();
    final meta = await VaultMeta.read(library);
    if (meta == null) throw const VaultLockedException();
    final documentsDir = await _store.documentsDirectory();
    final state = await _store.readStateForVault(previous: previous);
    final documents = _documents(state);

    final pending = [
      for (final raw in documents)
        if (await _needsSealing(raw, documentsDir)) raw,
    ];
    final sizes = {
      for (final raw in pending)
        raw: await _sizeOf(raw['local_path'] as String),
    };
    final bytesTotal = sizes.values.fold(0, (a, b) => a + b);

    final missing = await _missingSpace(library, sizes.values, state);
    if (missing > 0) {
      return MigrationResult(MigrationOutcome.noSpace, missingBytes: missing);
    }

    await meta.copyWith(migration: 'running').write(library);
    // The state first: from here on it's only ever written sealed.
    await _store.writeStateForVault(state);
    debugFailAt?.call('state');

    var done = 0;
    var bytesDone = 0;
    var failed = 0;
    var batch = <File>[];
    var batchBytes = 0;

    Future<void> closeBatch() async {
      debugFailAt?.call('before-save');
      await _store.writeStateForVault(state);
      debugFailAt?.call('after-save');
      for (final original in batch) {
        await _deleteQuietly(original);
      }
      batch = [];
      batchBytes = 0;
    }

    void report() => onProgress?.call(
      MigrationProgress(
        done: done,
        total: pending.length,
        bytesDone: bytesDone,
        bytesTotal: bytesTotal,
      ),
    );
    report();

    for (final raw in pending) {
      final original = File(raw['local_path'] as String);
      final id = raw['id'].toString();
      final target = File('${documentsDir.path}/$id.adv');
      final resealing = raw['sealed'] == true;
      try {
        final plain = resealing
            ? DocumentVault.openSealed(original.path, using: previous)
            : original.openRead();
        final sealed = await DocumentVault.sealTo(
          plain,
          resealing ? File('${target.path}.new') : target,
          verify: true,
        );
        debugFailAt?.call('part');
        if (resealing) {
          // Same file name: replaced only once the new copy verified.
          await File('${target.path}.new').rename(target.path);
        }
        debugFailAt?.call('rename');
        raw['checksum'] ??= sealed.checksum;
        raw['local_path'] = target.path;
        raw['sealed'] = true;
        if (!resealing) batch.add(original);
      } on SealVerificationException {
        failed++;
        continue;
      } on VaultFormatException {
        // An unreadable sealed file (re-sealing): left as it is, the rest
        // goes on.
        failed++;
        continue;
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode == _noSpaceErrno) {
          await closeBatch();
          return MigrationResult(MigrationOutcome.noSpace, failed: failed);
        }
        failed++;
        continue;
      }
      done++;
      bytesDone += sizes[raw]!;
      batchBytes += sizes[raw]!;
      report();
      if (batch.length >= _batchDocuments || batchBytes >= _batchBytes) {
        await closeBatch();
      }
    }
    await closeBatch();
    await _removeLeftovers(documentsDir, documents);

    if (failed > 0) {
      return MigrationResult(MigrationOutcome.incomplete, failed: failed);
    }
    await meta.copyWith(migration: 'done').write(library);
    return const MigrationResult(MigrationOutcome.done);
  }

  /// Plain documents stored in the library, or (re-sealing) sealed ones
  /// still on the previous key. Device-folder documents are only
  /// referenced, never copied in, so they're left alone.
  Future<bool> _needsSealing(
    Map<String, dynamic> raw,
    Directory documentsDir,
  ) async {
    final path = raw['local_path']?.toString();
    if (path == null || !path.startsWith('${documentsDir.path}/')) return false;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(raw['id']?.toString() ?? '')) {
      return false;
    }
    if (!await File(path).exists()) return false;
    if (raw['sealed'] == true) {
      return previous != null && !await _opensWithCurrentKey(path);
    }
    return true;
  }

  /// Re-sealing resumed: whether [path] is already on the current key
  /// (its first chunk authenticates with it).
  static Future<bool> _opensWithCurrentKey(String path) async {
    try {
      await DocumentVault.openSealed(path).first;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> _missingSpace(
    Directory library,
    Iterable<int> sizes,
    Map<String, dynamic> state,
  ) async {
    final free = await _freeSpace(library.path);
    if (free == null) return 0;
    final largest = sizes.fold(0, (a, b) => a > b ? a : b);
    final stateSize = await _stateSize(library);
    final needed =
        (largest > _margin ? largest : _margin) + 2 * stateSize + _margin;
    return needed > free ? needed - free : 0;
  }

  Future<int> _stateSize(Directory library) async {
    for (final name in [
      LocalDocumentsStore.sealedStateFileName,
      LocalDocumentsStore.stateFileName,
    ]) {
      final file = File('${library.path}/$name');
      if (await file.exists()) return file.length();
    }
    return 0;
  }

  /// Plain originals whose sealed copy is what the state points at (left
  /// when the app stopped between saving the state and deleting them), and
  /// unfinished `.part`, `.new` and `.tmp` files.
  Future<void> _removeLeftovers(
    Directory documentsDir,
    List<Map<String, dynamic>> documents,
  ) async {
    final sealedIds = {
      for (final raw in documents)
        if (raw['sealed'] == true) raw['id'].toString(),
    };
    final referenced = {
      for (final raw in documents) raw['local_path']?.toString(),
    };
    await for (final entity in documentsDir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final unfinished =
          name.endsWith('.part') ||
          name.endsWith('.new') ||
          name.endsWith('.tmp');
      final orphan =
          !referenced.contains(entity.path) &&
          sealedIds.any((id) => name.startsWith('${id}_'));
      if (unfinished || orphan) await _deleteQuietly(entity);
    }
  }

  static List<Map<String, dynamic>> _documents(Map<String, dynamic> state) => [
    for (final raw in (state['documents'] as List? ?? const []))
      if (raw is Map<String, dynamic>) raw,
  ];

  static Future<int> _sizeOf(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
