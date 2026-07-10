import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityLockService {
  SecurityLockService({LocalAuthentication? localAuthentication})
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  static const _legacyPinKey = 'security.pin.v1';
  static const _pinHashKey = 'security.pin_hash.v1';
  static const _pinSaltKey = 'security.pin_salt.v1';
  static const _biometricEnabledKey = 'security.biometric_enabled.v1';
  static const _biometricProbeTimeout = Duration(seconds: 2);

  final LocalAuthentication _localAuthentication;

  Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    final pinHash = prefs.getString(_pinHashKey);
    if (pinHash != null && pinHash.isNotEmpty) return true;
    final legacyPin = prefs.getString(_legacyPinKey);
    return legacyPin != null && legacyPin.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _newSalt();
    await prefs.setString(_pinSaltKey, salt);
    await prefs.setString(_pinHashKey, _hashPin(pin, salt));
    await prefs.remove(_legacyPinKey);
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
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
      return _localAuthentication.authenticate(
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
