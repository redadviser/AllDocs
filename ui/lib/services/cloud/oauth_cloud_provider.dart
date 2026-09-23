import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;

import 'cloud_config.dart';
import 'cloud_provider.dart';

/// Shared OAuth 2.0 (authorization code + PKCE, via flutter_appauth) token
/// handling for OneDrive and Dropbox: stores tokens in the keystore,
/// refreshes them before they expire, and retries a request once after a
/// 401.
abstract class OAuthCloudProvider extends CloudProvider {
  OAuthCloudProvider({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _appAuth = FlutterAppAuth();

  String get clientId;
  AuthorizationServiceConfiguration get serviceConfiguration;
  List<String> get scopes;
  Map<String, String>? get additionalAuthParameters => null;

  /// Reads the account's display label right after connecting.
  Future<String?> fetchAccountLabel();

  CloudTokenStore get tokenStore => CloudTokenStore(id);

  @override
  bool get isConfigured => clientId.isNotEmpty;

  @override
  Future<bool> isConnected() async {
    final tokens = await tokenStore.read();
    return tokens?['access_token'] != null;
  }

  @override
  Future<String?> accountLabel() async {
    return (await tokenStore.read())?['account']?.toString();
  }

  @override
  Future<void> connect() async {
    if (!isConfigured) throw CloudNotConfiguredException(id);
    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        clientId,
        CloudConfig.redirectUri,
        serviceConfiguration: serviceConfiguration,
        scopes: scopes,
        additionalParameters: additionalAuthParameters,
      ),
    );
    if (result.accessToken == null) throw const CloudAuthException();
    await _saveTokens(
      accessToken: result.accessToken!,
      refreshToken: result.refreshToken,
      expiresAt: result.accessTokenExpirationDateTime,
    );
    try {
      final label = await fetchAccountLabel();
      final tokens = await tokenStore.read() ?? {};
      await tokenStore.write({...tokens, 'account': label});
    } catch (_) {
      // The label is cosmetic.
    }
  }

  @override
  Future<void> disconnect() => tokenStore.clear();

  Future<void> _saveTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) async {
    final previous = await tokenStore.read() ?? {};
    await tokenStore.write({
      ...previous,
      'access_token': accessToken,
      // Refresh responses don't always repeat the refresh token.
      'refresh_token': refreshToken ?? previous['refresh_token'],
      'expires_at': expiresAt?.toIso8601String(),
    });
  }

  Future<String> accessToken({bool forceRefresh = false}) async {
    final tokens = await tokenStore.read();
    final token = tokens?['access_token']?.toString();
    if (token == null) throw const CloudAuthException('Not connected');
    final expiresAt = DateTime.tryParse(
      tokens?['expires_at']?.toString() ?? '',
    );
    final expired =
        expiresAt != null &&
        DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));
    if (!forceRefresh && !expired) return token;

    final refreshToken = tokens?['refresh_token']?.toString();
    if (refreshToken == null) {
      if (!forceRefresh) return token;
      throw const CloudAuthException('Session expired');
    }
    final refreshed = await _appAuth.token(
      TokenRequest(
        clientId,
        CloudConfig.redirectUri,
        serviceConfiguration: serviceConfiguration,
        refreshToken: refreshToken,
        scopes: scopes,
      ),
    );
    if (refreshed.accessToken == null) {
      throw const CloudAuthException('Session expired');
    }
    await _saveTokens(
      accessToken: refreshed.accessToken!,
      refreshToken: refreshed.refreshToken,
      expiresAt: refreshed.accessTokenExpirationDateTime,
    );
    return refreshed.accessToken!;
  }

  /// Sends a request built by [build] with a bearer token; on a 401 it
  /// refreshes the token and tries exactly once more.
  Future<http.Response> send(
    http.BaseRequest Function(String token) build, {
    Set<int> okStatuses = const {200, 201, 202, 204, 206},
  }) async {
    var response = await http.Response.fromStream(
      await _client.send(build(await accessToken())),
    );
    if (response.statusCode == 401) {
      response = await http.Response.fromStream(
        await _client.send(build(await accessToken(forceRefresh: true))),
      );
    }
    if (!okStatuses.contains(response.statusCode)) {
      throw CloudRequestException(response.statusCode, response.body);
    }
    return response;
  }

  Future<Map<String, dynamic>> sendJson(
    http.BaseRequest Function(String token) build,
  ) async {
    final response = await send(build);
    if (response.body.isEmpty) return const {};
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  http.Request request(
    String method,
    Uri uri,
    String token, {
    Map<String, String> headers = const {},
    Object? jsonBody,
    List<int>? bodyBytes,
  }) {
    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers.addAll(headers);
    if (jsonBody != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(jsonBody);
    } else if (bodyBytes != null) {
      request.bodyBytes = bodyBytes;
    }
    return request;
  }
}
