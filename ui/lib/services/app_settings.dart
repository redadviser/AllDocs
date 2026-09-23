import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local preferences for security and backup. Kept in
/// SharedPreferences: none of these are secrets.
class AppSettings {
  AppSettings._();

  static const _autoLockKey = 'security.auto_lock_minutes';
  static const _hidePreviewsKey = 'security.hide_previews';
  static const _backupProviderKey = 'backup.provider';
  static const _autoBackupKey = 'backup.auto';
  static const _lastBackupKey = 'backup.last_at';

  /// Minutes in the background before PIN/biometrics are asked again.
  /// 0 = every time the app is left; -1 = never.
  static final autoLockMinutes = ValueNotifier<int>(5);
  static final hidePreviews = ValueNotifier<bool>(false);
  static final backupProvider = ValueNotifier<String?>(null);
  static final autoBackup = ValueNotifier<bool>(false);
  static final lastBackupAt = ValueNotifier<DateTime?>(null);

  static const autoLockChoices = [0, 1, 5, 15, -1];
  static const _secureChannel = MethodChannel('alldocs/secure_screen');

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    autoLockMinutes.value = prefs.getInt(_autoLockKey) ?? 5;
    hidePreviews.value = prefs.getBool(_hidePreviewsKey) ?? false;
    backupProvider.value = prefs.getString(_backupProviderKey);
    autoBackup.value = prefs.getBool(_autoBackupKey) ?? false;
    lastBackupAt.value = DateTime.tryParse(
      prefs.getString(_lastBackupKey) ?? '',
    );
    await _applySecureScreen(hidePreviews.value);
  }

  static Future<void> setAutoLockMinutes(int minutes) async {
    autoLockMinutes.value = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoLockKey, minutes);
  }

  static Future<void> setHidePreviews(bool enabled) async {
    hidePreviews.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hidePreviewsKey, enabled);
    await _applySecureScreen(enabled);
  }

  static Future<void> setBackupProvider(String? provider) async {
    backupProvider.value = provider;
    final prefs = await SharedPreferences.getInstance();
    if (provider == null) {
      await prefs.remove(_backupProviderKey);
    } else {
      await prefs.setString(_backupProviderKey, provider);
    }
  }

  static Future<void> setAutoBackup(bool enabled) async {
    autoBackup.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupKey, enabled);
  }

  static Future<void> setLastBackupAt(DateTime value) async {
    lastBackupAt.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupKey, value.toIso8601String());
  }

  /// Android FLAG_SECURE: blank thumbnail in recent apps, no screenshots.
  static Future<void> _applySecureScreen(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _secureChannel.invokeMethod('setSecure', {'enabled': enabled});
    } catch (_) {
      // Not available (tests / other platforms).
    }
  }
}
