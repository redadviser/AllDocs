import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/document_file.dart';
import 'vault_format.dart';

/// The library is encrypted but its key isn't loaded (not unlocked yet, or
/// lost): nothing may be read, and nothing may be written over.
class VaultLockedException implements Exception {
  const VaultLockedException();
}

/// A file too large to read into memory; use [DocumentVault.materialize].
class DocumentTooLargeForMemory implements Exception {
  const DocumentTooLargeForMemory();
}

/// A sealed copy didn't decrypt back to what was sealed; it was discarded.
class SealVerificationException implements Exception {
  const SealVerificationException();
}

/// A document file decrypted to the private temp folder for something that
/// needs a path (PDF viewer, another app, the share sheet). [release] deletes
/// it; for files that aren't sealed it's the stored file and does nothing.
class Materialized {
  const Materialized(this.file, this._release);

  final File file;
  final Future<void> Function() _release;

  Future<void> release() => _release();
}

/// The only place that reads and writes the library's document files.
/// Sealed documents (ADV1, see [VaultFormat]) are opened with the key of
/// the library that is unlocked; documents that aren't sealed (device
/// folders, or not migrated yet) pass through as plain files, so callers
/// have a single code path.
class DocumentVault {
  DocumentVault._();

  static VaultFormat? _format;
  static String? _libraryId;

  /// Tests: where [materialize] writes instead of the app's temp folder.
  static Directory? debugTempDirectory;

  /// Largest file [readBytes] reads into memory.
  static const memoryLimit = 20 * 1024 * 1024;

  static const _openFolder = 'alldocs_open';

  /// The library that is unlocked, if any.
  static String? get libraryId => _format == null ? null : _libraryId;

  static bool isActiveFor(String libraryId) =>
      _format != null && _libraryId == libraryId;

  static void activate(String libraryId, List<int> key) {
    _format = VaultFormat(key);
    _libraryId = libraryId;
  }

  static void deactivate() {
    _format = null;
    _libraryId = null;
  }

  static VaultFormat get format =>
      _format ?? (throw const VaultLockedException());

  /// Seals [plain] into [target]: written as `<target>.part`, then renamed,
  /// so [target] is either absent or complete. Returns the SHA-256 and size
  /// of the plain bytes. With [verify], the `.part` is decrypted and its
  /// SHA-256 compared before the rename ([SealVerificationException]).
  static Future<({String checksum, int size})> sealTo(
    Stream<List<int>> plain,
    File target, {
    VaultFormat? using,
    bool verify = false,
  }) async {
    final vault = using ?? format;
    final part = File('${target.path}.${_randomName().substring(0, 8)}.part');
    final digest = _DigestSink();
    final hashing = sha256.startChunkedConversion(digest);
    var size = 0;
    try {
      await vault
          .seal(
            plain.map((data) {
              size += data.length;
              hashing.add(data);
              return data;
            }),
          )
          .pipe(part.openWrite());
      hashing.close();
      // On disk before the rename: the migration deletes the original next.
      final handle = await part.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      if (verify &&
          await checksumOf(openSealed(part.path, using: vault)) !=
              digest.value.toString()) {
        throw const SealVerificationException();
      }
      await part.rename(target.path);
    } catch (_) {
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      rethrow;
    }
    return (checksum: digest.value.toString(), size: size);
  }

  /// SHA-256 of what [stream] carries.
  static Future<String> checksumOf(Stream<List<int>> stream) async =>
      (await sha256.bind(stream).first).toString();

  /// The plain content of a sealed file at [path].
  static Stream<List<int>> openSealed(String path, {VaultFormat? using}) =>
      (using ?? format).open(File(path).openRead());

  static Stream<List<int>> openRead(DocumentFile document) {
    final path = _pathOf(document);
    return document.sealed ? openSealed(path) : File(path).openRead();
  }

  /// The whole file in memory; only for files up to [memoryLimit].
  static Future<Uint8List> readBytes(DocumentFile document) async {
    final path = _pathOf(document);
    if (await File(path).length() > memoryLimit + 64 * 1024) {
      throw const DocumentTooLargeForMemory();
    }
    if (!document.sealed) return File(path).readAsBytes();
    final out = BytesBuilder(copy: false);
    await for (final data in openSealed(path)) {
      out.add(data);
    }
    return out.takeBytes();
  }

  /// [document] as a plain file. Sealed ones are decrypted to
  /// `<temp>/alldocs_open/<random>/<original name>` (the receiving app shows
  /// that name). With [handoff] (another app or the share sheet still reads
  /// it after we're done), [Materialized.release] leaves it for
  /// [purgeTemp].
  static Future<Materialized> materialize(
    DocumentFile document, {
    bool handoff = false,
  }) async {
    final path = _pathOf(document);
    if (!document.sealed) return Materialized(File(path), () async {});
    unawaited(_purgeOldHandoffs());
    final folder = await scratch(handoff: handoff);
    final file = File('${folder.path}/${_safeName(document.fileName)}');
    try {
      await openSealed(path).pipe(file.openWrite());
    } catch (_) {
      await _deleteQuietly(folder);
      rethrow;
    }
    return Materialized(file, () async {
      if (!handoff) await _deleteQuietly(folder);
    });
  }

  /// A new folder for plain files that only exist for a moment (an import
  /// being read, a watermarked copy, a download being checked). Everything
  /// in it goes with [purgeTemp]. [handoff] marks one another app reads
  /// after we're done: it's also removed once it's older than
  /// [_handoffLifetime].
  static Future<Directory> scratch({bool handoff = false}) async {
    final folder = Directory(
      '${(await _tempRoot()).path}/$_openFolder/'
      '${handoff ? _handoffPrefix : ''}${_randomName()}',
    );
    await folder.create(recursive: true);
    return folder;
  }

  static const _handoffPrefix = 'h_';
  static const _handoffLifetime = Duration(minutes: 10);

  // With auto-lock off, a copy handed to another app would otherwise stay
  // until the next start or sign-out.
  static Future<void> _purgeOldHandoffs() async {
    try {
      final root = Directory('${(await _tempRoot()).path}/$_openFolder');
      if (!await root.exists()) return;
      final cutoff = DateTime.now().subtract(_handoffLifetime);
      await for (final entity in root.list()) {
        if (entity is! Directory ||
            !entity.uri.pathSegments.reversed
                .firstWhere((s) => s.isNotEmpty)
                .startsWith(_handoffPrefix)) {
          continue;
        }
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await _deleteQuietly(entity);
        }
      }
    } catch (_) {}
  }

  /// Whether [path] is one of AllDocs' own working files (decrypted copies,
  /// staged imports, thumbnails, the library itself). Another app handing
  /// such a path back ("open with AllDocs") is refused: it must never make
  /// AllDocs copy its own private files around.
  static bool isPrivatePath(String path) {
    final normalized = File(path).absolute.path.replaceAll('\\', '/');
    if (normalized.split('/').contains('..')) return true;
    return const [
      '/$_openFolder/',
      '/alldocs_import/',
      '/alldocs_thumbnails/',
      '/.AllDocs/',
      // The private libraries: Android's app_flutter, iOS's Documents.
      '/app_flutter/users/',
      '/Documents/users/',
    ].any(normalized.contains);
  }

  /// Deletes every decrypted or staged copy and the thumbnails of plain
  /// documents: on start, when the app locks, on sign out and when the
  /// account changes.
  static Future<void> purgeTemp() async {
    try {
      final root = (await _tempRoot()).path;
      for (final name in [_openFolder, 'alldocs_import']) {
        await _deleteQuietly(Directory('$root/$name'));
      }
    } catch (_) {}
  }

  static String _pathOf(DocumentFile document) {
    final path = document.localPath;
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Document has no stored file');
    }
    return path;
  }

  static Future<Directory> _tempRoot() async {
    final debug = debugTempDirectory;
    if (debug != null) return debug;
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      // No platform side (unit tests): the system's temp folder.
      return Directory.systemTemp;
    }
  }

  static String _randomName() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static String _safeName(String fileName) {
    final cleaned = fileName
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .trim();
    return cleaned.isEmpty ? 'documento' : cleaned;
  }

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } catch (_) {}
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// `vault.json` beside the library: in plain text, no secrets. Says the
/// library is encrypted, with which key (its check) and how far the
/// migration of older, unencrypted files got.
class VaultMeta {
  const VaultMeta({
    required this.keyCheck,
    required this.owner,
    required this.migration,
  });

  static const fileName = 'vault.json';

  final String keyCheck;

  /// `account` (a copy of the key is on the server) or `local`.
  final String owner;

  /// `pending`, `running` or `done`.
  final String migration;

  bool get migrated => migration == 'done';

  VaultMeta copyWith({String? owner, String? migration}) => VaultMeta(
    keyCheck: keyCheck,
    owner: owner ?? this.owner,
    migration: migration ?? this.migration,
  );

  static Future<VaultMeta?> read(Directory library) async {
    final file = File('${library.path}/$fileName');
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return VaultMeta(
      keyCheck: json['keyCheck'] as String,
      owner: json['owner'] as String? ?? 'account',
      migration: json['migration'] as String? ?? 'pending',
    );
  }

  Future<void> write(Directory library) async {
    final file = File('${library.path}/$fileName');
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temp.writeAsString(
      jsonEncode({
        'v': 1,
        'keyCheck': keyCheck,
        'owner': owner,
        'migration': migration,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await temp.rename(file.path);
  }
}
