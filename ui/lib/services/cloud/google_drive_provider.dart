import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../auth_service.dart';
import '../backup_storage.dart';
import '../current_user.dart';
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
  // Per account (see CurrentUser).
  static const _sharedConnectedKey = 'cloud.googleDrive.account';
  static String get _connectedKey => CurrentUser.scoped(_sharedConnectedKey);
  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3';
  static const _fields =
      'id,name,mimeType,size,modifiedTime,version,md5Checksum';
  // Only scopes Google doesn't need to verify the app for. Reading the
  // user's own Drive (drive.readonly) is a "restricted" scope — it shows
  // the "unverified app" warning until Google audits the app — so Drive is
  // a backup destination only; Drive files are imported through the
  // system file picker, which already lists Google Drive.
  static const _scopes = [
    // Backups: the "AllDocs Backups" folder AllDocs creates in My Drive.
    'https://www.googleapis.com/auth/drive.file',
    // Only to read the zip backups older versions put in the hidden
    // app-data folder.
    'https://www.googleapis.com/auth/drive.appdata',
  ];
  static const backupFolderName = 'AllDocs Backups';
  static const _folderMime = 'application/vnd.google-apps.folder';

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

  /// drive.file only sees what AllDocs itself created.
  @override
  bool get canBrowseFiles => false;

  @override
  Future<bool> isConnected() async => (await accountLabel()) != null;

  @override
  Future<String?> accountLabel() async {
    await claimSharedSecureValue(_storage, _sharedConnectedKey, _connectedKey);
    return _storage.read(key: _connectedKey);
  }

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

  Future<List<CloudItem>> _list(
    String query, {
    String spaces = 'drive',
    int maxPages = 10,
  }) async {
    final items = <CloudItem>[];
    String? pageToken;
    for (var page = 0; page < maxPages; page++) {
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
      isFolder: mimeType == _folderMime,
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

  /// Resumable upload: one request for the metadata, one for the bytes —
  /// streamed from disk, never held in memory whole.
  Future<CloudItem> _uploadFile(
    File file, {
    required String method,
    required String url,
    required Map<String, dynamic> metadata,
    String contentType = 'application/octet-stream',
  }) async {
    final length = await file.length();
    final start = await _send(
      (token) => http.Request(method, Uri.parse(url))
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Content-Type'] = 'application/json; charset=UTF-8'
        ..headers['X-Upload-Content-Type'] = contentType
        ..headers['X-Upload-Content-Length'] = '$length'
        ..body = jsonEncode(metadata),
    );
    final location = start.headers['location'];
    if (location == null) {
      throw const CloudRequestException(500, 'No upload location');
    }
    final response = await _send((token) {
      final request = http.StreamedRequest('PUT', Uri.parse(location))
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Content-Type'] = contentType
        ..contentLength = length;
      file.openRead().listen(
        request.sink.add,
        onError: request.sink.addError,
        onDone: request.sink.close,
        cancelOnError: true,
      );
      return request;
    });
    return _item(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  Future<CloudItem> _sendJsonForItem(
    String method,
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final response = await _send(
      (token) => http.Request(method, uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Content-Type'] = 'application/json; charset=UTF-8'
        ..body = jsonEncode(body),
    );
    return _item(Map<String, dynamic>.from(jsonDecode(response.body) as Map));
  }

  @override
  BackupStorage backupStorage() => _DriveBackupStorage(this);

  @override
  Future<List<CloudItem>> listLegacyBackups() {
    return _list('trashed = false', spaces: 'appDataFolder');
  }
}

/// The "AllDocs Backups" folder in My Drive. Drive addresses everything by
/// id, so paths are resolved folder by folder and cached for the run (one
/// storage object is used per backup / restore).
class _DriveBackupStorage extends BackupStorage {
  _DriveBackupStorage(this._drive);

  final GoogleDriveProvider _drive;

  /// Found by this marker rather than by name: the user can rename or move
  /// the folder in Drive without AllDocs building a second one beside it.
  static const _rootProperty = 'alldocs_backups_root';

  final _folderIds = <String, String>{};
  final _children = <String, Map<String, CloudItem>>{};

  @override
  String get label => 'Google Drive · ${GoogleDriveProvider.backupFolderName}';

  Uri _files([String suffix = '', Map<String, String>? query]) =>
      Uri.parse('${GoogleDriveProvider._api}/files$suffix').replace(
        queryParameters: {'fields': GoogleDriveProvider._fields, ...?query},
      );

  Future<String> _rootId() async {
    final cached = _folderIds[''];
    if (cached != null) return cached;
    final found = await _drive._list(
      "appProperties has { key='$_rootProperty' and value='true' } "
      "and mimeType = '${GoogleDriveProvider._folderMime}' "
      'and trashed = false',
    );
    final root = found.isNotEmpty
        ? found.first
        : await _drive._sendJsonForItem('POST', _files(), {
            'name': GoogleDriveProvider.backupFolderName,
            'mimeType': GoogleDriveProvider._folderMime,
            'parents': ['root'],
            'appProperties': {_rootProperty: 'true'},
          });
    return _folderIds[''] = root.id;
  }

  Future<Map<String, CloudItem>> _childrenOf(String folder) async {
    final cached = _children[folder];
    if (cached != null) return cached;
    final id = await _folderId(folder, create: false);
    final children = <String, CloudItem>{};
    if (id != null) {
      // No page cap here: a folder listed short would have its missing
      // files uploaded again, and Drive happily keeps two of the same name.
      for (final item in await _drive._list(
        "'$id' in parents and trashed = false",
        maxPages: 1 << 20,
      )) {
        children[item.name] = item;
      }
    }
    return _children[folder] = children;
  }

  Future<String?> _folderId(String folder, {required bool create}) async {
    if (folder.isEmpty) return _rootId();
    final cached = _folderIds[folder];
    if (cached != null) return cached;
    final split = splitBackupPath(folder);
    final parentId = await _folderId(split.parent, create: create);
    if (parentId == null) return null;
    final existing = (await _childrenOf(split.parent))[split.name];
    if (existing != null && existing.isFolder) {
      return _folderIds[folder] = existing.id;
    }
    if (!create) return null;
    final created = await _drive._sendJsonForItem('POST', _files(), {
      'name': split.name,
      'mimeType': GoogleDriveProvider._folderMime,
      'parents': [parentId],
    });
    (_children[split.parent] ??= {})[split.name] = created;
    _children[folder] = {};
    return _folderIds[folder] = created.id;
  }

  Future<CloudItem?> _itemAt(String path) async {
    final split = splitBackupPath(path);
    return (await _childrenOf(split.parent))[split.name];
  }

  @override
  Future<List<BackupEntry>> list(String folder) async {
    return [
      for (final item in (await _childrenOf(folder)).values)
        BackupEntry(
          name: item.name,
          isFolder: item.isFolder,
          sizeBytes: item.sizeBytes,
        ),
    ];
  }

  @override
  Future<void> ensureFolder(String folder) async {
    await _folderId(folder, create: true);
  }

  @override
  Future<void> upload(String path, File file) async {
    final split = splitBackupPath(path);
    final parentId = (await _folderId(split.parent, create: true))!;
    final existing = await _itemAt(path);
    final uploaded = existing == null
        ? await _drive._uploadFile(
            file,
            method: 'POST',
            url:
                '${GoogleDriveProvider._upload}/files?uploadType=resumable'
                '&fields=${GoogleDriveProvider._fields}',
            metadata: {
              'name': split.name,
              'parents': [parentId],
            },
          )
        : await _drive._uploadFile(
            file,
            method: 'PATCH',
            url:
                '${GoogleDriveProvider._upload}/files/${existing.id}'
                '?uploadType=resumable&fields=${GoogleDriveProvider._fields}',
            metadata: const {},
          );
    (await _childrenOf(split.parent))[split.name] = uploaded;
  }

  @override
  Future<void> download(String path, File destination) async {
    final item = await _itemAt(path);
    if (item == null || item.isFolder) throw BackupNotFoundException(path);
    final downloaded = await _drive.download(item);
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(downloaded.bytes, flush: true);
  }

  @override
  Future<void> copy(String from, String to) async {
    final source = await _itemAt(from);
    if (source == null) throw BackupNotFoundException(from);
    final split = splitBackupPath(to);
    final parentId = (await _folderId(split.parent, create: true))!;
    final copied = await _drive._sendJsonForItem(
      'POST',
      _files('/${source.id}/copy'),
      {
        'name': split.name,
        'parents': [parentId],
      },
    );
    (await _childrenOf(split.parent))[split.name] = copied;
  }

  @override
  Future<void> move(String from, String to) async {
    final source = await _itemAt(from);
    if (source == null) throw BackupNotFoundException(from);
    final fromSplit = splitBackupPath(from);
    final toSplit = splitBackupPath(to);
    final oldParentId = (await _folderId(fromSplit.parent, create: false))!;
    final newParentId = (await _folderId(toSplit.parent, create: true))!;
    final moved = await _drive._sendJsonForItem(
      'PATCH',
      _files('/${source.id}', {
        if (oldParentId != newParentId) ...{
          'addParents': newParentId,
          'removeParents': oldParentId,
        },
      }),
      {'name': toSplit.name},
    );
    (await _childrenOf(fromSplit.parent)).remove(fromSplit.name);
    (await _childrenOf(toSplit.parent))[toSplit.name] = moved;
  }

  @override
  Future<void> delete(String path) async {
    final item = await _itemAt(path);
    if (item == null) return;
    try {
      await _drive._send(
        (token) => http.Request(
          'DELETE',
          Uri.parse('${GoogleDriveProvider._api}/files/${item.id}'),
        )..headers['Authorization'] = 'Bearer $token',
      );
    } on CloudRequestException catch (error) {
      if (error.statusCode != 404) rethrow;
    }
    final split = splitBackupPath(path);
    _children[split.parent]?.remove(split.name);
    if (item.isFolder) {
      bool inside(String key) => key == path || key.startsWith('$path/');
      _folderIds.removeWhere((key, _) => inside(key));
      _children.removeWhere((key, _) => inside(key));
    }
  }
}
