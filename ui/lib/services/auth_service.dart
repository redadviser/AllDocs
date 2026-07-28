import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_helpers.dart';
import 'google_auth_config.dart';
import 'local_mode_config.dart';

class _GoogleIdToken {
  const _GoogleIdToken({required this.token, required this.email});
  final String token;
  final String email;
}

/// Storage seam for the session token, so tests can swap in an in-memory
/// fake instead of exercising flutter_secure_storage's platform channel
/// (see test/auth_service_test.dart).
abstract class AuthTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class _SecureAuthTokenStore implements AuthTokenStore {
  const _SecureAuthTokenStore();

  static const _storage = FlutterSecureStorage();
  static const _key = 'auth.session_token.v1';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Account-level sign-in, kept separate from [SecurityLockService]'s device
/// PIN/biometric lock. While [LocalModeConfig.isLocalOnly] is true this
/// never leaves the device. Once flipped, login calls the AllDocs backend,
/// which authenticates against the `users` table shared with AllPhotos (see
/// docs/architecture.md) — same account, same password, across both apps.
class AuthService {
  // Swappable in tests; production code should never need to touch this.
  static AuthTokenStore tokenStore = const _SecureAuthTokenStore();

  static const _signedInKey = 'auth.signed_in.v1';
  static const _displayNameKey = 'auth.display_name.v1';
  static const _deviceIdKey = 'auth.device_id.v1';

  static Future<bool> isSignedIn() async {
    if (LocalModeConfig.isLocalOnly) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_signedInKey) ?? false;
    }
    return await tokenStore.read() != null;
  }

  static Future<String?> displayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_displayNameKey);
  }

  static Future<String> login(String email, String password) async {
    final name = _displayNameFromEmail(email);

    if (LocalModeConfig.isLocalOnly) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_signedInKey, true);
      await prefs.setString(_displayNameKey, name);
      return name;
    }

    final res = await ApiHelpers.post(
      '/api/auth/login',
      headers: ApiHelpers.headersWithToken(),
      body: jsonEncode({
        'email': email,
        'password': password,
        'device': await _deviceInfo(),
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(ApiHelpers.errorMessage(res, 'Login failed'));
    }

    await _persistSession(res, name);
    return name;
  }

  static Future<String> signup(String email, String password) async {
    final name = _displayNameFromEmail(email);

    if (LocalModeConfig.isLocalOnly) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_signedInKey, true);
      await prefs.setString(_displayNameKey, name);
      return name;
    }

    final res = await ApiHelpers.post(
      '/api/auth/signup',
      headers: ApiHelpers.headersWithToken(),
      body: jsonEncode({
        'email': email,
        'password': password,
        'device': await _deviceInfo(),
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(ApiHelpers.errorMessage(res, 'Sign up failed'));
    }

    await _persistSession(res, name);
    return name;
  }

  static bool _googleSignInInitialized = false;

  static Future<String> loginWithGoogle() async {
    final googleToken = await _obtainGoogleIdToken();
    final name = _displayNameFromEmail(googleToken.email);

    if (LocalModeConfig.isLocalOnly) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_signedInKey, true);
      await prefs.setString(_displayNameKey, name);
      return name;
    }

    final res = await ApiHelpers.post(
      '/api/auth/google/signin',
      headers: ApiHelpers.headersWithToken(),
      body: jsonEncode({
        'idToken': googleToken.token,
        'device': await _deviceInfo(),
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(ApiHelpers.errorMessage(res, 'Google sign-in failed'));
    }

    await _persistSession(res, name);
    return name;
  }

  static Future<_GoogleIdToken> _obtainGoogleIdToken() async {
    final googleSignIn = GoogleSignIn.instance;
    if (!_googleSignInInitialized) {
      await googleSignIn.initialize(
        serverClientId: GoogleAuthConfig.serverClientId,
      );
      _googleSignInInitialized = true;
    }

    if (!googleSignIn.supportsAuthenticate()) {
      throw Exception('Google sign-in is not supported on this device');
    }

    final account = await googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw Exception('Google did not return an ID token');
    }
    return _GoogleIdToken(token: idToken, email: account.email);
  }

  static Future<void> logout() async {
    if (_googleSignInInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Best effort; local sign-out must still work if this fails.
      }
    }

    if (!LocalModeConfig.isLocalOnly) {
      final token = await tokenStore.read();
      try {
        await ApiHelpers.post(
          '/api/auth/logout',
          headers: ApiHelpers.headersWithToken(token),
        );
      } catch (_) {
        // Best effort on server logout; local sign-out must still work offline.
      }
      await tokenStore.delete();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_signedInKey);
    await prefs.remove(_displayNameKey);
  }

  static Future<void> _persistSession(http.Response res, String name) async {
    final setCookie = res.headers['set-cookie'] ?? '';
    final match = RegExp(r'session_token=([^;]+)').firstMatch(setCookie);
    if (match != null) await tokenStore.write(match.group(1)!);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name);
  }

  static Future<Map<String, String>> _deviceInfo() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = _randomId();
      await prefs.setString(_deviceIdKey, id);
    }

    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
        ? 'ios'
        : 'other';
    return {'id': id, 'platform': platform};
  }

  static String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
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
