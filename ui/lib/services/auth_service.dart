import 'package:shared_preferences/shared_preferences.dart';

import 'local_mode_config.dart';

/// Account-level sign-in, kept separate from [SecurityLockService]'s
/// device PIN/biometric lock. While [LocalModeConfig.isLocalOnly] is true
/// this never leaves the device; once the AllDocs backend exists, only the
/// body of this class needs to change to call it, with no changes required
/// in AuthGate/SecurityGate/MainNavScreen.
class AuthService {
  static const _signedInKey = 'auth.signed_in.v1';
  static const _displayNameKey = 'auth.display_name.v1';

  static Future<bool> isSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_signedInKey) ?? false;
  }

  static Future<String?> displayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_displayNameKey);
  }

  static Future<String> login(String email, String password) async {
    if (LocalModeConfig.isLocalOnly) {
      final name = _displayNameFromEmail(email);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_signedInKey, true);
      await prefs.setString(_displayNameKey, name);
      return name;
    }

    throw UnimplementedError(
      'Remote AuthService is not wired up yet. Flip LocalModeConfig.isLocalOnly '
      'off only once the AllDocs backend login endpoint exists.',
    );
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_signedInKey);
    await prefs.remove(_displayNameKey);
  }

  static String _displayNameFromEmail(String email) {
    final local = email.trim().split('@').first.trim();
    if (local.isEmpty) return 'AllDocs';

    final words = local
        .split(RegExp(r'[._-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1));
    return words.isEmpty ? local : words.join(' ');
  }
}
