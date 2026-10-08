import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'current_user.dart';

class SecurityLockService {
  SecurityLockService({LocalAuthentication? localAuthentication})
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  // Each account on the phone has its own PIN/biometrics setting (see
  // CurrentUser), so a second account never needs the first one's PIN.
  static const _baseKeys = [
    'security.pin.v1',
    'security.pin_hash.v1',
    'security.pin_salt.v1',
    'security.biometric_enabled.v1',
  ];
  static String get _legacyPinKey => CurrentUser.scoped(_baseKeys[0]);
  static String get _pinHashKey => CurrentUser.scoped(_baseKeys[1]);
  static String get _pinSaltKey => CurrentUser.scoped(_baseKeys[2]);
  static String get _biometricEnabledKey => CurrentUser.scoped(_baseKeys[3]);
  static const _biometricProbeTimeout = Duration(seconds: 2);

  final LocalAuthentication _localAuthentication;

  /// Preferences, after handing the PIN set before PINs were per account to
  /// the first account that signs in (the one that set it).
  static Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (CurrentUser.key == null) return prefs;
    final shared = [for (final key in _baseKeys) prefs.get(key)];
    if (shared.every((value) => value == null)) return prefs;
    final ownHash = prefs.getString(CurrentUser.scoped(_baseKeys[1]));
    final ownLegacy = prefs.getString(CurrentUser.scoped(_baseKeys[0]));
    if (ownHash == null && ownLegacy == null) {
      for (var i = 0; i < _baseKeys.length; i++) {
        final value = shared[i];
        final key = CurrentUser.scoped(_baseKeys[i]);
        if (value is String) await prefs.setString(key, value);
        if (value is bool) await prefs.setBool(key, value);
      }
    }
    for (final key in _baseKeys) {
      await prefs.remove(key);
    }
    return prefs;
  }

  static int _autoLockSuspensions = 0;

  /// True while AllDocs itself sent the user to another screen (file
  /// picker, scanner, share sheet, OAuth login...). Leaving the app for
  /// those must not trigger the auto-lock.
  static bool get autoLockSuspended => _autoLockSuspensions > 0;

  static Future<T> withoutAutoLock<T>(Future<T> Function() action) async {
    _autoLockSuspensions++;
    try {
      return await action();
    } finally {
      // Resume events arrive slightly after the awaited call returns.
      Future<void>.delayed(const Duration(seconds: 2), () {
        _autoLockSuspensions--;
      });
    }
  }

  Future<bool> hasPin() async {
    final prefs = await _prefs();
    final pinHash = prefs.getString(_pinHashKey);
    if (pinHash != null && pinHash.isNotEmpty) return true;
    final legacyPin = prefs.getString(_legacyPinKey);
    return legacyPin != null && legacyPin.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    final prefs = await _prefs();
    final salt = _newSalt();
    await prefs.setString(_pinSaltKey, salt);
    await prefs.setString(_pinHashKey, _hashPin(pin, salt));
    await prefs.remove(_legacyPinKey);
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await _prefs();
    final pinHash = prefs.getString(_pinHashKey);
    if (pinHash != null && pinHash.isNotEmpty) {
      final salt = prefs.getString(_pinSaltKey);
      if (salt != null && salt.isNotEmpty) {
        return pinHash == _hashPin(pin, salt);
      }

      final validLegacyHash = pinHash == _legacyHashPin(pin);
      if (validLegacyHash) await setPin(pin);
      return validLegacyHash;
    }

    final legacyPin = prefs.getString(_legacyPinKey);
    final validLegacyPin = legacyPin == pin;
    if (validLegacyPin) await setPin(pin);
    return validLegacyPin;
  }

  Future<bool> isBiometricEnabled() async {
    final prefs = await _prefs();
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await _prefs();
    await prefs.setBool(_biometricEnabledKey, enabled);
  }

  Future<bool> canUseBiometrics() async {
    try {
      final supported = await _localAuthentication.isDeviceSupported().timeout(
        _biometricProbeTimeout,
        onTimeout: () => false,
      );
      if (!supported) return false;
      final canCheck = await _localAuthentication.canCheckBiometrics.timeout(
        _biometricProbeTimeout,
        onTimeout: () => false,
      );
      if (canCheck) return true;
      final enrolled = await _localAuthentication
          .getAvailableBiometrics()
          .timeout(
            _biometricProbeTimeout,
            onTimeout: () => const <BiometricType>[],
          );
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics({required String reason}) async {
    try {
      return await _localAuthentication.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  String _legacyHashPin(String pin) {
    final bytes = utf8.encode('AllDocs.local.pin.v1:$pin');
    return sha256.convert(bytes).toString();
  }

  String _newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
