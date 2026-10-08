import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'current_user.dart';

/// Device-local preferences for security and backup. Kept in
/// SharedPreferences: none of these are secrets.
class AppSettings {
  AppSettings._();

  static const _autoLockKey = 'security.auto_lock_minutes';
  static const _hidePreviewsKey = 'security.hide_previews';
  // Backup settings belong to the signed-in account (see CurrentUser).
  static const _backupBaseKeys = [
    'backup.provider',
    'backup.auto',
    'backup.last_at',
  ];
  static String get _backupProviderKey =>
      CurrentUser.scoped(_backupBaseKeys[0]);
  static String get _autoBackupKey => CurrentUser.scoped(_backupBaseKeys[1]);
  static String get _lastBackupKey => CurrentUser.scoped(_backupBaseKeys[2]);

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
    await _applySecureScreen(hidePreviews.value);
  }

  /// Loads the signed-in account's backup settings. Called whenever the
  /// account changes; the settings saved before they were per account go to
  /// the first account that signs in.
  static Future<void> loadAccountSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (CurrentUser.key != null &&
        _backupBaseKeys.any(prefs.containsKey) &&
        !prefs.containsKey(_backupProviderKey) &&
        !prefs.containsKey(_autoBackupKey) &&
        !prefs.containsKey(_lastBackupKey)) {
      final provider = prefs.getString(_backupBaseKeys[0]);
      final auto = prefs.getBool(_backupBaseKeys[1]);
      final last = prefs.getString(_backupBaseKeys[2]);
      if (provider != null) await prefs.setString(_backupProviderKey, provider);
      if (auto != null) await prefs.setBool(_autoBackupKey, auto);
      if (last != null) await prefs.setString(_lastBackupKey, last);
    }
    if (CurrentUser.key != null) {
      for (final key in _backupBaseKeys) {
        await prefs.remove(key);
      }
    }
    backupProvider.value = prefs.getString(_backupProviderKey);
    autoBackup.value = prefs.getBool(_autoBackupKey) ?? false;
    lastBackupAt.value = DateTime.tryParse(
      prefs.getString(_lastBackupKey) ?? '',
    );
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
