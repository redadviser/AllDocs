import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'current_user.dart';
import 'pin_throttle.dart';

/// The hidden albums' own PIN — separate from the app PIN, so someone
/// handed the unlocked phone still can't open them. Per account, stored
/// as a salted hash like the app PIN.
class HiddenAlbumsLock {
  const HiddenAlbumsLock._();

  static String get _hashKey => CurrentUser.scoped('hidden_albums.pin_hash.v1');
  static String get _saltKey => CurrentUser.scoped('hidden_albums.pin_salt.v1');
  static PinThrottle get _throttle =>
      PinThrottle(CurrentUser.scoped('hidden_albums.pin_throttle.v1'));

  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_hashKey) ?? '').isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final random = Random.secure();
    final salt = base64UrlEncode([
      for (var i = 0; i < 16; i++) random.nextInt(256),
    ]);
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, _hash(pin, salt));
    await _throttle.reset();
  }

  /// Wrong attempts count towards [lockRemaining]; while that runs, every
  /// attempt fails without being checked.
  static Future<bool> verifyPin(String pin) async {
    if (await _throttle.remaining() > Duration.zero) return false;
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_hashKey);
    final salt = prefs.getString(_saltKey);
    if (hash == null || salt == null) return false;
    final ok = hash == _hash(pin, salt);
    ok ? await _throttle.reset() : await _throttle.recordFailure();
    return ok;
  }

  static Future<Duration> lockRemaining() => _throttle.remaining();

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:hidden:$pin')).toString();
}
