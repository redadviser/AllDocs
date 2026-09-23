import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_helpers.dart';

/// OAuth client ids for Google (sign-in + Drive), OneDrive and Dropbox.
///
/// The backend is the source of truth (its .env, served by
/// `GET /api/config/cloud`), so a key can be added or rotated without a new
/// app build. The last answer is cached so the app works offline, and a
/// `--dart-define` of the same name (e.g. from cloud_keys.json) wins, for
/// pointing a dev build at other registrations.
class CloudKeys {
  CloudKeys._();

  static const _cacheKey = 'cloud.keys.v1';
  static Map<String, String> _values = const {};

  static String? get googleWebClientId => _value(
    'GOOGLE_SERVER_CLIENT_ID',
    const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
  );
  static String? get googleIosClientId => _value(
    'GOOGLE_IOS_CLIENT_ID',
    const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
  );
  static String? get oneDriveClientId => _value(
    'ONEDRIVE_CLIENT_ID',
    const String.fromEnvironment('ONEDRIVE_CLIENT_ID'),
  );
  static String? get dropboxAppKey => _value(
    'DROPBOX_APP_KEY',
    const String.fromEnvironment('DROPBOX_APP_KEY'),
  );

  static String? _value(String name, String buildTime) {
    if (buildTime.isNotEmpty) return buildTime;
    final value = _values[name];
    return value == null || value.isEmpty ? null : value;
  }

  /// Reads the cached keys, then refreshes them from the backend. On the
  /// very first launch (nothing cached) it waits briefly for the backend —
  /// Google Sign-In can only be set up once per run, so it needs the ids
  /// before the login screen — otherwise it refreshes in the background.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        _values = Map<String, String>.from(jsonDecode(cached) as Map);
        unawaited(refresh());
        return;
      }
    } catch (_) {}
    await refresh().timeout(const Duration(seconds: 4), onTimeout: () {});
  }

  static Future<void> refresh() async {
    try {
      final res = await ApiHelpers.get('/api/config/cloud');
      if (res.statusCode != 200) return;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      Map<String, dynamic> section(String name) =>
          (json[name] as Map?)?.cast<String, dynamic>() ?? const {};
      final values = <String, String>{
        'GOOGLE_SERVER_CLIENT_ID': ?section('google')['webClientId'] as String?,
        'GOOGLE_IOS_CLIENT_ID': ?section('google')['iosClientId'] as String?,
        'ONEDRIVE_CLIENT_ID': ?section('oneDrive')['clientId'] as String?,
        'DROPBOX_APP_KEY': ?section('dropbox')['appKey'] as String?,
      };
      _values = values;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(values));
    } catch (_) {
      // Offline or server unreachable: keep the cached keys.
    }
  }
}
