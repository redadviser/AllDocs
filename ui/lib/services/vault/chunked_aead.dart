import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class ChunkedAeadException implements Exception {
  const ChunkedAeadException();
}

/// AES-256-GCM over a stream cut into fixed-size chunks, shared by device
/// sync (ADS1) and the encrypted library (ADV1). Chunk *i* is sealed under
/// nonce `prefix (8) · i (uint32, big-endian)`, with `aadPrefix · last`
/// (1 on the final chunk, 0 before) as associated data, so chunks can't be
/// reordered, dropped, added or the stream cut short without opening
/// failing. Streamed both ways: a large file never sits in memory.
///
/// An empty input is one empty chunk; an input that is an exact multiple
/// of the chunk size ends with a full chunk.
class ChunkedAead {
  ChunkedAead(List<int> key) : _key = SecretKey(Uint8List.fromList(key));

  static const macLength = 16;
  static final _aes = AesGcm.with256bits();

  final SecretKey _key;

  Stream<List<int>> seal(
    Stream<List<int>> plain, {
    required List<int> prefix,
    List<int> aadPrefix = const [],
    int chunkSize = 1024 * 1024,
  }) async* {
    var index = 0;
    await for (final (chunk, last) in _units(plain, chunkSize)) {
      final box = await _aes.encrypt(
        chunk,
        secretKey: _key,
        nonce: _nonce(prefix, index++),
        aad: [...aadPrefix, last ? 1 : 0],
      );
      yield [...box.cipherText, ...box.mac.bytes];
    }
  }

  Stream<List<int>> open(
    Stream<List<int>> sealed, {
    required List<int> prefix,
    List<int> aadPrefix = const [],
    int chunkSize = 1024 * 1024,
  }) async* {
    var index = 0;
    await for (final (chunk, last) in _units(sealed, chunkSize + macLength)) {
      if (chunk.length < macLength) throw const ChunkedAeadException();
      final split = chunk.length - macLength;
      final box = SecretBox(
        Uint8List.sublistView(chunk, 0, split),
        nonce: _nonce(prefix, index++),
        mac: Mac(Uint8List.sublistView(chunk, split)),
      );
      try {
        yield await _aes.decrypt(
          box,
          secretKey: _key,
          aad: [...aadPrefix, last ? 1 : 0],
        );
      } on SecretBoxAuthenticationError {
        throw const ChunkedAeadException();
      }
    }
  }

  /// [input] regrouped into [size]-byte units, each flagged when it's the
  /// last. Looks one byte ahead, so a stream that ends exactly on a unit
  /// boundary still marks that full unit as the last.
  static Stream<(Uint8List, bool)> _units(
    Stream<List<int>> input,
    int size,
  ) async* {
    final pending = BytesBuilder(copy: false);
    await for (final data in input) {
      pending.add(data);
      while (pending.length > size) {
        final bytes = pending.takeBytes();
        yield (Uint8List.sublistView(bytes, 0, size), false);
        pending.add(Uint8List.sublistView(bytes, size));
      }
    }
    yield (pending.takeBytes(), true);
  }

  static List<int> _nonce(List<int> prefix, int index) {
    // A nonce must never repeat; 2^32 chunks is far past any real file.
    if (index > 0xFFFFFFFF) throw const ChunkedAeadException();
    return _nonceBytes(prefix, index);
  }

  static List<int> _nonceBytes(List<int> prefix, int index) => [
    ...prefix,
    (index >> 24) & 0xff,
    (index >> 16) & 0xff,
    (index >> 8) & 0xff,
    index & 0xff,
  ];

  static List<int> randomBytes(int length) {
    final random = Random.secure();
    return [for (var i = 0; i < length; i++) random.nextInt(256)];
  }
}
