import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/sync/sync_crypto.dart';

/// SyncCrypto's file sealing exactly as it was before ChunkedAead (ADS1),
/// kept here so files other devices already uploaded keep opening.
Stream<List<int>> legacySealFile(List<int> key, File file) async* {
  final aes = AesGcm.with256bits();
  final secretKey = SecretKey(key);
  const chunkSize = 1024 * 1024;
  final length = await file.length();
  final random = Random.secure();
  final prefix = [for (var i = 0; i < 8; i++) random.nextInt(256)];
  yield [0x41, 0x44, 0x53, 0x31, ...prefix];
  final chunks = length == 0 ? 1 : (length + chunkSize - 1) ~/ chunkSize;
  final reader = await file.open();
  try {
    for (var index = 0; index < chunks; index++) {
      final plain = await reader.read(chunkSize);
      final last = index == chunks - 1;
      final box = await aes.encrypt(
        plain,
        secretKey: secretKey,
        nonce: [
          ...prefix,
          (index >> 24) & 0xff,
          (index >> 16) & 0xff,
          (index >> 8) & 0xff,
          index & 0xff,
        ],
        aad: [last ? 1 : 0],
      );
      yield [...box.cipherText, ...box.mac.bytes];
    }
  } finally {
    await reader.close();
  }
}

void main() {
  late Directory dir;
  final key = SyncCrypto.newKey();
  final crypto = SyncCrypto(key);

  setUp(() => dir = Directory.systemTemp.createTempSync('sync_crypto_test_'));
  tearDown(() => dir.deleteSync(recursive: true));

  File plainFile(int length) {
    final file = File('${dir.path}/plain_$length');
    file.writeAsBytesSync(
      Uint8List.fromList([for (var i = 0; i < length; i++) i % 251]),
    );
    return file;
  }

  Future<File> collect(Stream<List<int>> stream, String name) async {
    final file = File('${dir.path}/$name');
    final sink = file.openWrite();
    await sink.addStream(stream);
    await sink.close();
    return file;
  }

  for (final length in [0, 1, 1024 * 1024, 1024 * 1024 + 1, 2621440]) {
    test('ADS1 from the old code opens with the new ($length bytes)', () async {
      final plain = plainFile(length);
      final sealed = await collect(legacySealFile(key, plain), 'old.ads');
      final out = File('${dir.path}/out');
      await crypto.openFile(sealed, out);
      expect(out.readAsBytesSync(), plain.readAsBytesSync());
    });

    test('ADS1 from the new code is byte-compatible ($length bytes)', () async {
      final plain = plainFile(length);
      final sealed = await collect(crypto.sealFile(plain), 'new.ads');
      expect(sealed.lengthSync(), SyncCrypto.sealedLength(length));
      final out = File('${dir.path}/out');
      await crypto.openFile(sealed, out);
      expect(out.readAsBytesSync(), plain.readAsBytesSync());
    });
  }

  test('a cut file fails as SyncDecryptException', () async {
    final sealed = await collect(
      legacySealFile(key, plainFile(1024 * 1024 + 5)),
      'cut.ads',
    );
    final bytes = sealed.readAsBytesSync();
    // Drop the last chunk: the one before it wasn't sealed as the last.
    sealed.writeAsBytesSync(bytes.sublist(0, 12 + 1024 * 1024 + 16));
    await expectLater(
      crypto.openFile(sealed, File('${dir.path}/out')),
      throwsA(isA<SyncDecryptException>()),
    );
  });
}
