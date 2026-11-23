import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/vault/vault_format.dart';

void main() {
  final random = Random(7);
  List<int> newKey() => [for (var i = 0; i < 32; i++) random.nextInt(256)];
  final vault = VaultFormat(newKey());
  const mib = 1024 * 1024;

  Uint8List data(int length) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) (i * 31) % 256]);

  // Fed in uneven pieces, as a file read would be.
  Stream<List<int>> pieces(List<int> bytes, {int size = 7777}) async* {
    for (var i = 0; i < bytes.length; i += size) {
      yield bytes.sublist(i, min(i + size, bytes.length));
    }
  }

  Future<Uint8List> collect(Stream<List<int>> stream) async {
    final out = BytesBuilder();
    await for (final d in stream) {
      out.add(d);
    }
    return out.takeBytes();
  }

  for (final length in [0, 1, mib - 1, mib, mib + 1, 5 * mib]) {
    test('round trip, $length bytes', () async {
      final plain = data(length);
      final sealed = await collect(vault.seal(pieces(plain)));
      expect(sealed.length, VaultFormat.sealedLength(length));
      expect(await collect(vault.open(pieces(sealed, size: 4096))), plain);
    });
  }

  test('the same input seals differently each time', () async {
    final plain = data(100);
    expect(await vault.sealBytes(plain), isNot(await vault.sealBytes(plain)));
  });

  group('refuses', () {
    // Small chunks: 3 of 64 KiB (+ a partial one) keep these quick.
    const log2 = 16;
    const chunk = 1 << log2;
    const sealedChunk = chunk + 16;
    late Uint8List plain;
    late Uint8List sealed;

    setUp(() async {
      plain = data(3 * chunk + 100);
      sealed = await collect(vault.seal(Stream.value(plain), chunkLog2: log2));
    });

    Future<void> expectRefused(List<int> bytes, [VaultFormat? with_]) =>
        expectLater(
          collect((with_ ?? vault).open(Stream.value(bytes))),
          throwsA(isA<VaultFormatException>()),
        );

    Uint8List flipped(int at) => Uint8List.fromList(sealed)..[at] ^= 0x01;

    test('a changed byte in each header field', () async {
      for (final at in [0, 4, 5, 6, 8, 15]) {
        await expectRefused(flipped(at));
      }
    });

    test('a changed byte in a chunk or its tag', () async {
      await expectRefused(flipped(16));
      await expectRefused(flipped(16 + chunk + 3)); // first chunk's tag
      await expectRefused(flipped(sealed.length - 1)); // last tag
    });

    test('chunks swapped', () async {
      final a = sealed.sublist(16, 16 + sealedChunk);
      final b = sealed.sublist(16 + sealedChunk, 16 + 2 * sealedChunk);
      await expectRefused([
        ...sealed.sublist(0, 16),
        ...b,
        ...a,
        ...sealed.sublist(16 + 2 * sealedChunk),
      ]);
    });

    test('the last chunk cut off, or cut short', () async {
      await expectRefused(sealed.sublist(0, 16 + 3 * sealedChunk));
      await expectRefused(sealed.sublist(0, sealed.length - 1));
      await expectRefused(sealed.sublist(0, 16));
      await expectRefused(sealed.sublist(0, 10));
    });

    test('a chunk added', () async {
      await expectRefused([...sealed, ...sealed.sublist(16, 16 + sealedChunk)]);
    });

    test('the wrong key', () async {
      await expectRefused(sealed, VaultFormat(newKey()));
    });

    test('wrong magic, version 2, chunk size out of range', () async {
      await expectRefused(Uint8List.fromList(sealed)..[0] = 0x58);
      await expectRefused(Uint8List.fromList(sealed)..[4] = 2);
      await expectRefused(Uint8List.fromList(sealed)..[5] = 25);
      await expectRefused(Uint8List.fromList(sealed)..[5] = 15);
    });

    test('and still opens when intact', () async {
      expect(await vault.openBytes(sealed), plain);
    });
  });

  test('keyCheck depends on the key only', () {
    final key = newKey();
    expect(VaultFormat(key).keyCheck, VaultFormat(key).keyCheck);
    expect(VaultFormat(key).keyCheck, isNot(VaultFormat(newKey()).keyCheck));
    expect(VaultFormat(key).keyCheck, matches(RegExp(r'^[0-9a-f]{64}$')));
  });
}
