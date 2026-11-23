import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/vault/free_space.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('alldocs/storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('asks the platform for the path\'s volume', () async {
    MethodCall? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return 5368709120;
    });
    expect(await FreeSpace.at('/data/library'), 5368709120);
    expect(seen?.method, 'freeBytes');
    expect(seen?.arguments, {'path': '/data/library'});
  });

  test('unknown when the platform fails or has no channel', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'stat_failed'),
    );
    expect(await FreeSpace.at('/x'), isNull);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await FreeSpace.at('/x'), isNull);
  });
}
