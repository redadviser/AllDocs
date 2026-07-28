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
  const _GoogleIdToken({required this.token, required this.email, this.name});
  final String token;
  final String email;
  final String? name;
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
  static const _emailKey = 'auth.email.v1';
  static const _planKey = 'auth.plan.v1';
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

  static Future<String?> email() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  /// The shared "All" subscription plan (free/premium/pro), read from the
  /// profiles row shared with AllPhotos — a purchase in either app unlocks
  /// premium in both. Null until a real login/signup response has reported
  /// one (always the case in local-only mode).
  static Future<String?> plan() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_planKey);
  }

  static Future<String> login(String email, String password) async {
    if (LocalModeConfig.isLocalOnly) {
      return _persistLocalSession(email: email);
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

    return _persistSession(res, fallbackEmail: email);
  }

  static Future<String> signup(
    String email,
    String password, {
    String? displayName,
  }) async {
    if (LocalModeConfig.isLocalOnly) {
      return _persistLocalSession(email: email, displayName: displayName);
    }

    final res = await ApiHelpers.post(
      '/api/auth/signup',
      headers: ApiHelpers.headersWithToken(),
      body: jsonEncode({
        'email': email,
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'displayName': displayName.trim(),
        'device': await _deviceInfo(),
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(ApiHelpers.errorMessage(res, 'Sign up failed'));
    }

    return _persistSession(res, fallbackEmail: email, fallbackName: displayName);
  }

  static bool _googleSignInInitialized = false;

  static Future<String> loginWithGoogle() async {
    final googleToken = await _obtainGoogleIdToken();

    if (LocalModeConfig.isLocalOnly) {
      return _persistLocalSession(
        email: googleToken.email,
        displayName: googleToken.name,
      );
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

    return _persistSession(
      res,
      fallbackEmail: googleToken.email,
      fallbackName: googleToken.name,
    );
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
    return _GoogleIdToken(
      token: idToken,
      email: account.email,
      name: account.displayName,
    );
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
    await prefs.remove(_emailKey);
    await prefs.remove(_planKey);
  }

  static Future<String> _persistLocalSession({
    required String email,
    String? displayName,
  }) async {
    final name = _resolveName(email, displayName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_signedInKey, true);
    await prefs.setString(_displayNameKey, name);
    await prefs.setString(_emailKey, email);
    await prefs.setString(_planKey, 'free');
    return name;
  }

  /// Persists the session cookie plus whatever profile info the server
  /// returned (email/displayName/plan, shared with AllPhotos via the
  /// `profiles` table), falling back to locally-known values if the
  /// response doesn't include them.
  static Future<String> _persistSession(
    http.Response res, {
    required String fallbackEmail,
    String? fallbackName,
  }) async {
    final setCookie = res.headers['set-cookie'] ?? '';
    final match = RegExp(r'session_token=([^;]+)').firstMatch(setCookie);
    if (match != null) await tokenStore.write(match.group(1)!);

    var email = fallbackEmail;
    var name = _resolveName(fallbackEmail, fallbackName);
    String? plan;

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>?;
      if (user != null) {
        email = user['email']?.toString() ?? email;
        final serverName = user['displayName']?.toString();
        if (serverName != null && serverName.trim().isNotEmpty) {
          name = serverName.trim();
        }
        plan = user['plan']?.toString();
      }
    } catch (_) {
      // Unexpected response shape; keep the locally-known email/name.
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name);
    await prefs.setString(_emailKey, email);
    if (plan != null) await prefs.setString(_planKey, plan);

    return name;
  }

  static String _resolveName(String email, String? requested) {
    final trimmed = requested?.trim();
    return trimmed != null && trimmed.isNotEmpty
        ? trimmed
        : _displayNameFromEmail(email);
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
