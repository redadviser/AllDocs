import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';

import '../vault/chunked_aead.dart';

class SyncDecryptException implements Exception {
  const SyncDecryptException();
}

/// End-to-end encryption of device sync. One 256-bit key per account's sync,
/// made on the first device and handed to the others in the QR code — the
/// server only ever sees what this produces.
///
/// - A change batch or snapshot: AES-256-GCM over gzip'd JSON, as
///   `nonce (12) · ciphertext · tag (16)`.
/// - A document file: `ADS1 · prefix (8)`, then 1 MiB chunks, each sealed
///   with AES-256-GCM under nonce `prefix · chunk number`, with the chunk's
///   "is last" flag as associated data — so chunks can't be reordered,
///   dropped or the file cut short without decryption failing. Streamed:
///   a large file never sits in memory.
class SyncCrypto {
  SyncCrypto(List<int> key)
    : assert(key.length == 32),
      _key = Uint8List.fromList(key),
      _secretKey = SecretKey(Uint8List.fromList(key)),
      _chunks = ChunkedAead(key);

  static const keyLength = 32;
  static const chunkSize = 1024 * 1024;
  static const _macLength = 16;
  static const _magic = [0x41, 0x44, 0x53, 0x31]; // "ADS1"
  static const _headerLength = 12;

  final Uint8List _key;
  final SecretKey _secretKey;
  final ChunkedAead _chunks;
  static final _aes = AesGcm.with256bits();

  static Uint8List newKey() {
    final random = Random.secure();
    return Uint8List.fromList([
      for (var i = 0; i < keyLength; i++) random.nextInt(256),
    ]);
  }

  /// Lets the server check a joining device has the same key without
  /// learning anything about it.
  String get keyCheck => _hmac('alldocs-sync-check');

  /// The id a file is stored under on the server: tied to its content (so
  /// the same file is sent once) but meaningless without the key.
  String blobIdFor(String fileKey) => _hmac('blob:$fileKey');

  String _hmac(String message) =>
      hashes.Hmac(hashes.sha256, _key).convert(utf8.encode(message)).toString();

  // ---- Batches and snapshots --------------------------------------------

  Future<Uint8List> sealJson(Object value) async {
    final plain = gzip.encode(utf8.encode(jsonEncode(value)));
    final box = await _aes.encrypt(plain, secretKey: _secretKey);
    return box.concatenation();
  }

  Future<Object?> openJson(List<int> sealed) async {
    if (sealed.length < 12 + _macLength) throw const SyncDecryptException();
    try {
      final box = SecretBox.fromConcatenation(
        sealed,
        nonceLength: 12,
        macLength: _macLength,
      );
      final plain = await _aes.decrypt(box, secretKey: _secretKey);
      return jsonDecode(utf8.decode(gzip.decode(plain)));
    } on SecretBoxAuthenticationError {
      throw const SyncDecryptException();
    } on FormatException {
      throw const SyncDecryptException();
    }
  }

  // ---- Files --------------------------------------------------------------

  /// Size of [plainLength] bytes once sealed.
  static int sealedLength(int plainLength) {
    final chunks = plainLength == 0
        ? 1
        : (plainLength + chunkSize - 1) ~/ chunkSize;
    return _headerLength + plainLength + chunks * _macLength;
  }

  /// [file] sealed, as a stream of bytes ([sealedLength] of them).
  Stream<List<int>> sealFile(File file) => sealStream(file.openRead());

  /// [plain] sealed (ADS1); [sealedLength] of its length.
  Stream<List<int>> sealStream(Stream<List<int>> plain) async* {
    final prefix = ChunkedAead.randomBytes(8);
    yield [..._magic, ...prefix];
    yield* _chunks.seal(plain, prefix: prefix, chunkSize: chunkSize);
  }

  /// [sealed] (as downloaded) decrypted, as a stream. Errors are
  /// [SyncDecryptException].
  Stream<List<int>> openStream(File sealed) async* {
    if (await sealed.length() < _headerLength + _macLength) {
      throw const SyncDecryptException();
    }
    final header = await sealed
        .openRead(0, _headerLength)
        .expand((d) => d)
        .toList();
    for (var i = 0; i < _magic.length; i++) {
      if (header[i] != _magic[i]) throw const SyncDecryptException();
    }
    yield* _chunks
        .open(
          sealed.openRead(_headerLength),
          prefix: header.sublist(4, _headerLength),
          chunkSize: chunkSize,
        )
        .handleError(
          (Object _) => throw const SyncDecryptException(),
          test: (error) => error is ChunkedAeadException,
        );
  }

  /// Decrypts [sealed] (as downloaded) into [target].
  Future<void> openFile(File sealed, File target) async {
    if (await sealed.length() < _headerLength + _macLength) {
      throw const SyncDecryptException();
    }
    final reader = await sealed.open();
    final List<int> header;
    try {
      header = await reader.read(_headerLength);
    } finally {
      await reader.close();
    }
    for (var i = 0; i < _magic.length; i++) {
      if (header[i] != _magic[i]) throw const SyncDecryptException();
    }
    try {
      await _chunks
          .open(
            sealed.openRead(_headerLength),
            prefix: header.sublist(4, _headerLength),
            chunkSize: chunkSize,
          )
          .pipe(target.openWrite());
    } on ChunkedAeadException {
      throw const SyncDecryptException();
    }
  }
}
