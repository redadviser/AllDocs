import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;

import 'chunked_aead.dart';

class VaultFormatException implements Exception {
  const VaultFormatException(this.reason);

  final String reason;

  @override
  String toString() => 'VaultFormatException($reason)';
}

/// The encrypted library's file format (ADV1), for documents, the library
/// state and backup manifests:
///
/// | offset | bytes | field                                   |
/// |--------|-------|-----------------------------------------|
/// | 0      | 4     | magic `ADV1`                            |
/// | 4      | 1     | version = 1                             |
/// | 5      | 1     | log2 of the chunk size (16..24; 20 = 1 MiB) |
/// | 6      | 2     | reserved = 0                            |
/// | 8      | 8     | nonce prefix, random per file           |
/// | 16     | ...   | chunks ([ChunkedAead]), AAD = header · last |
///
/// The whole header is in every chunk's associated data, so changing any
/// of it makes opening fail.
class VaultFormat {
  VaultFormat(List<int> key)
    : assert(key.length == 32),
      _key = Uint8List.fromList(key),
      _chunks = ChunkedAead(key);

  static const headerLength = 16;
  static const _magic = [0x41, 0x44, 0x56, 0x31]; // "ADV1"
  static const _version = 1;
  static const defaultChunkLog2 = 20;

  final Uint8List _key;
  final ChunkedAead _chunks;

  /// Tells a wrong key apart from a damaged file, without revealing it.
  String get keyCheck => hmac('alldocs-vault-check');

  /// A name derived from [message] that means nothing without the key.
  String hmac(String message) =>
      hashes.Hmac(hashes.sha256, _key).convert(utf8.encode(message)).toString();

  /// Size of [plainLength] bytes once sealed with 2^[chunkLog2] chunks.
  static int sealedLength(int plainLength, {int chunkLog2 = defaultChunkLog2}) {
    final chunkSize = 1 << chunkLog2;
    final chunks = plainLength == 0
        ? 1
        : (plainLength + chunkSize - 1) ~/ chunkSize;
    return headerLength + plainLength + chunks * ChunkedAead.macLength;
  }

  /// Plain length of a sealed file of [sealedLength] bytes whose chunks are
  /// 2^[chunkLog2] (byte 5 of its header).
  static int plainLength(int sealedLength, {int chunkLog2 = defaultChunkLog2}) {
    final body = sealedLength - headerLength;
    final sealedChunk = (1 << chunkLog2) + ChunkedAead.macLength;
    final chunks = (body + sealedChunk - 1) ~/ sealedChunk;
    return body - chunks * ChunkedAead.macLength;
  }

  Stream<List<int>> seal(
    Stream<List<int>> plain, {
    int chunkLog2 = defaultChunkLog2,
  }) async* {
    assert(chunkLog2 >= 16 && chunkLog2 <= 24);
    final header = Uint8List.fromList([
      ..._magic,
      _version,
      chunkLog2,
      0,
      0,
      ...ChunkedAead.randomBytes(8),
    ]);
    yield header;
    yield* _chunks.seal(
      plain,
      prefix: header.sublist(8),
      aadPrefix: header,
      chunkSize: 1 << chunkLog2,
    );
  }

  /// [sealed] decrypted. Throws [VaultFormatException] for anything that
  /// isn't an intact ADV1 file sealed with this key.
  Stream<List<int>> open(Stream<List<int>> sealed) async* {
    final input = StreamIterator(sealed);
    try {
      final head = BytesBuilder(copy: false);
      while (head.length < headerLength) {
        if (!await input.moveNext()) {
          throw const VaultFormatException('too short');
        }
        head.add(input.current);
      }
      final first = head.takeBytes();
      final header = Uint8List.sublistView(first, 0, headerLength);
      for (var i = 0; i < _magic.length; i++) {
        if (header[i] != _magic[i]) {
          throw const VaultFormatException('not ADV1');
        }
      }
      if (header[4] != _version) {
        throw VaultFormatException('version ${header[4]}');
      }
      final chunkLog2 = header[5];
      if (chunkLog2 < 16 ||
          chunkLog2 > 24 ||
          header[6] != 0 ||
          header[7] != 0) {
        throw const VaultFormatException('bad header');
      }

      Stream<List<int>> body() async* {
        if (first.length > headerLength) {
          yield Uint8List.sublistView(first, headerLength);
        }
        while (await input.moveNext()) {
          yield input.current;
        }
      }

      yield* _chunks
          .open(
            body(),
            prefix: header.sublist(8),
            aadPrefix: header,
            chunkSize: 1 << chunkLog2,
          )
          // yield* forwards stream errors instead of throwing them here.
          .handleError(
            (Object _) =>
                throw const VaultFormatException('authentication failed'),
            test: (error) => error is ChunkedAeadException,
          );
    } finally {
      await input.cancel();
    }
  }

  Future<Uint8List> sealBytes(List<int> plain) =>
      _collect(seal(Stream.value(plain)));

  Future<Uint8List> openBytes(List<int> sealed) =>
      _collect(open(Stream.value(sealed)));

  static Future<Uint8List> _collect(Stream<List<int>> stream) async {
    final out = BytesBuilder(copy: false);
    await for (final data in stream) {
      out.add(data);
    }
    return out.takeBytes();
  }
}
