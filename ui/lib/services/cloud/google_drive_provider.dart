import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../auth_service.dart';
import 'cloud_config.dart';
import 'cloud_provider.dart';

/// Google Drive through the Drive API v3. Authorization reuses the Google
/// Sign-In plugin (same OAuth clients as "Continue with Google"), asking
/// for the Drive scopes on top; access tokens come from the plugin, which
/// handles their refresh.
class GoogleDriveProvider extends CloudProvider {
  GoogleDriveProvider({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  static const _storage = FlutterSecureStorage();
  static const _connectedKey = 'cloud.googleDrive.account';
  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3';
  static const _fields =
      'id,name,mimeType,size,modifiedTime,version,md5Checksum';
  static const _scopes = [
    'https://www.googleapis.com/auth/drive.readonly',
    // Backups go to the hidden per-app folder, not the user's Drive.
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  /// Google-native formats have no bytes of their own; export them.
  static const _exports = {
    'application/vnd.google-apps.document': (
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'docx',
    ),
    'application/vnd.google-apps.spreadsheet': (
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'xlsx',
    ),
    'application/vnd.google-apps.presentation': (
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'pptx',
    ),
  };

  GoogleSignInAccount? _account;

  @override
  CloudProviderId get id => CloudProviderId.googleDrive;

  @override
  String get displayName => 'Google Drive';

  @override
  bool get isConfigured => CloudConfig.googleDriveEnabled;

  @override
  Future<bool> isConnected() async {
    return (await _storage.read(key: _connectedKey)) != null;
  }

  @override
  Future<String?> accountLabel() => _storage.read(key: _connectedKey);

  @override
  Future<void> connect() async {
    final signIn = await AuthService.googleSignIn();
    final account =
        await signIn.attemptLightweightAuthentication() ??
        await signIn.authenticate();
    await account.authorizationClient.authorizeScopes(_scopes);
    _account = account;
    await _storage.write(key: _connectedKey, value: account.email);
  }

  @override
  Future<void> disconnect() async {
    _account = null;
    await _storage.delete(key: _connectedKey);
  }

  /// Silent token first; only prompts again if Google needs consent.
  Future<String> _token() async {
    final signIn = await AuthService.googleSignIn();
    _account ??= await signIn.attemptLightweightAuthentication();
    final account = _account;
    if (account == null) throw const CloudAuthException('Not connected');
    final client = account.authorizationClient;
    final existing = await client.authorizationForScopes(_scopes);
    if (existing != null) return existing.accessToken;
    return (await client.authorizeScopes(_scopes)).accessToken;
  }

  Future<http.Response> _send(
    http.BaseRequest Function(String token) build,
  ) async {
    var token = await _token();
    var response = await http.Response.fromStream(
      await _client.send(build(token)),
    );
    if (response.statusCode == 401) {
      final signIn = await AuthService.googleSignIn();
      await signIn.authorizationClient.clearAuthorizationToken(
        accessToken: token,
      );
      token = await _token();
      response = await http.Response.fromStream(
        await _client.send(build(token)),
      );
    }
    if (response.statusCode >= 300) {
      throw CloudRequestException(response.statusCode, response.body);
    }
    return response;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _send(
      (token) =>
          http.Request('GET', uri)..headers['Authorization'] = 'Bearer $token',
    );
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<List<CloudItem>> _list(String query, {String spaces = 'drive'}) async {
    final items = <CloudItem>[];
    String? pageToken;
    for (var page = 0; page < 10; page++) {
      final json = await _getJson(
        Uri.parse('$_api/files').replace(
          queryParameters: {
            'q': query,
            'spaces': spaces,
            'pageSize': '200',
            'orderBy': 'folder,name',
            'fields': 'nextPageToken,files($_fields)',
            'pageToken': ?pageToken,
          },
        ),
      );
      for (final raw in (json['files'] as List? ?? const [])) {
        items.add(_item(Map<String, dynamic>.from(raw as Map)));
      }
      pageToken = json['nextPageToken']?.toString();
      if (pageToken == null) break;
    }
    return items;
  }

  CloudItem _item(Map<String, dynamic> json) {
    final mimeType = json['mimeType']?.toString();
    return CloudItem(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      isFolder: mimeType == 'application/vnd.google-apps.folder',
      sizeBytes: int.tryParse(json['size']?.toString() ?? ''),
      modifiedAt: DateTime.tryParse(json['modifiedTime']?.toString() ?? ''),
      version: (json['md5Checksum'] ?? json['version'])?.toString(),
      mimeType: mimeType,
    );
  }

  String _escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  @override
  Future<List<CloudItem>> listFolder(String? folderId) {
    return _list("'${folderId ?? 'root'}' in parents and trashed = false");
  }

  @override
  Future<List<CloudItem>> search(String query) {
    final escaped = _escape(query);
    return _list(
      "(name contains '$escaped' or fullText contains '$escaped') "
      'and trashed = false',
    );
  }

  @override
  Future<CloudItem?> metadata(String fileId) async {
    try {
      return _item(
        await _getJson(
          Uri.parse(
            '$_api/files/$fileId',
          ).replace(queryParameters: {'fields': _fields}),
        ),
      );
    } on CloudRequestException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<({String fileName, Uint8List bytes})> download(CloudItem item) async {
    final export = _exports[item.mimeType];
    final uri = export == null
        ? Uri.parse('$_api/files/${item.id}?alt=media')
        : Uri.parse(
            '$_api/files/${item.id}/export',
          ).replace(queryParameters: {'mimeType': export.$1});
    final response = await _send(
      (token) =>
          http.Request('GET', uri)..headers['Authorization'] = 'Bearer $token',
    );
    final fileName =
        export == null || item.name.toLowerCase().endsWith('.${export.$2}')
        ? item.name
        : '${item.name}.${export.$2}';
    return (fileName: fileName, bytes: response.bodyBytes);
  }

  @override
  Future<CloudItem> uploadBackup(String fileName, File file) async {
    final length = await file.length();
    // Resumable upload: one request for the metadata, one for the bytes.
    final start = await _send(
      (token) =>
          http.Request(
              'POST',
              Uri.parse('$_upload/files?uploadType=resumable&fields=$_fields'),
            )
            ..headers['Authorization'] = 'Bearer $token'
            ..headers['Content-Type'] = 'application/json; charset=UTF-8'
            ..headers['X-Upload-Content-Type'] = 'application/zip'
            ..headers['X-Upload-Content-Length'] = '$length'
            ..body = jsonEncode({
              'name': fileName,
              'parents': ['appDataFolder'],
            }),
    );
    final location = start.headers['location'];
    if (location == null) {
      throw const CloudRequestException(500, 'No upload location');
    }
    final bytes = await file.readAsBytes();
    final response = await _send(
      (token) => http.Request('PUT', Uri.parse(location))
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Content-Type'] = 'application/zip'
        ..bodyBytes = bytes,
    );
    return _item(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  @override
  Future<List<CloudItem>> listBackups() {
    return _list('trashed = false', spaces: 'appDataFolder');
  }
}
