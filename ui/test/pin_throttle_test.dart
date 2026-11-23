import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:all_docs/services/hidden_albums_lock.dart';
import 'package:all_docs/services/pin_throttle.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the wait starts at the fifth miss and doubles up to an hour', () {
    expect(PinThrottle.waitAfter(4), Duration.zero);
    expect(PinThrottle.waitAfter(5), const Duration(seconds: 30));
    expect(PinThrottle.waitAfter(6), const Duration(minutes: 1));
    expect(PinThrottle.waitAfter(7), const Duration(minutes: 2));
    expect(PinThrottle.waitAfter(50), const Duration(hours: 1));
  });

  test(
    'a locked PIN is refused even when right, and a right one resets',
    () async {
      await HiddenAlbumsLock.setPin('1234');
      for (var i = 0; i < 5; i++) {
        expect(await HiddenAlbumsLock.verifyPin('0000'), isFalse);
      }
      expect(
        await HiddenAlbumsLock.lockRemaining(),
        greaterThan(Duration.zero),
      );
      expect(await HiddenAlbumsLock.verifyPin('1234'), isFalse);

      // Once the wait is over (cleared here), the right PIN works and resets.
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where(
        (k) => k.endsWith('locked_until'),
      )) {
        await prefs.remove(key);
      }
      expect(await HiddenAlbumsLock.verifyPin('1234'), isTrue);
      expect(await HiddenAlbumsLock.verifyPin('0000'), isFalse);
      expect(await HiddenAlbumsLock.lockRemaining(), Duration.zero);
    },
  );

  test('labels round up', () {
    expect(pinWaitLabel(const Duration(milliseconds: 29100)), '30 s');
    expect(pinWaitLabel(const Duration(seconds: 61)), '2 min');
  });
}
