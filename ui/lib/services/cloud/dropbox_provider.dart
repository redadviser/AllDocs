import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_appauth/flutter_appauth.dart';

import 'cloud_config.dart';
import 'cloud_provider.dart';
import 'oauth_cloud_provider.dart';

/// Dropbox through the HTTP API v2 (OAuth PKCE, offline refresh tokens).
class DropboxProvider extends OAuthCloudProvider {
  DropboxProvider({super.client});

  static const _api = 'https://api.dropboxapi.com/2';
  static const _content = 'https://content.dropboxapi.com/2';
  static const backupFolder = '/AllDocs Backups';
  // /files/upload accepts up to 150 MB; bigger files use an upload session.
  static const _singleUploadLimit = 140 * 1024 * 1024;
  static const _chunkSize = 8 * 1024 * 1024;

  @override
  CloudProviderId get id => CloudProviderId.dropbox;

  @override
  String get displayName => 'Dropbox';

  @override
  String get clientId => CloudConfig.dropboxAppKey;

  @override
  AuthorizationServiceConfiguration get serviceConfiguration =>
      const AuthorizationServiceConfiguration(
        authorizationEndpoint: 'https://www.dropbox.com/oauth2/authorize',
        tokenEndpoint: 'https://api.dropboxapi.com/oauth2/token',
      );

  @override
  List<String> get scopes => const [
    'account_info.read',
    'files.metadata.read',
    'files.content.read',
    'files.content.write',
  ];

  @override
  Map<String, String>? get additionalAuthParameters => const {
    'token_access_type': 'offline',
  };

  Future<Map<String, dynamic>> _rpc(String path, Object? body) {
    return sendJson(
      (token) => request(
        'POST',
        Uri.parse('$_api$path'),
        token,
        headers: {'Content-Type': 'application/json'},
        bodyBytes: utf8.encode(jsonEncode(body)),
      ),
    );
  }

  @override
  Future<String?> fetchAccountLabel() async {
    final account = await _rpc('/users/get_current_account', null);
    return (account['email'] ?? (account['name'] as Map?)?['display_name'])
        ?.toString();
  }

  @override
  Future<List<CloudItem>> listFolder(String? folderId) async {
    final items = <CloudItem>[];
    var json = await _rpc('/files/list_folder', {
      'path': folderId ?? '',
      'limit': 500,
    });
    for (var page = 0; page < 10; page++) {
      for (final raw in (json['entries'] as List? ?? const [])) {
        final item = _item(Map<String, dynamic>.from(raw as Map));
        if (item != null) items.add(item);
      }
      if (json['has_more'] != true) break;
      json = await _rpc('/files/list_folder/continue', {
        'cursor': json['cursor'],
      });
    }
    return items;
  }

  CloudItem? _item(Map<String, dynamic> json) {
    final tag = json['.tag']?.toString();
    if (tag != 'file' && tag != 'folder') return null;
    return CloudItem(
      id: json['id']?.toString() ?? json['path_lower'].toString(),
      name: json['name']?.toString() ?? '',
      isFolder: tag == 'folder',
      sizeBytes: (json['size'] as num?)?.toInt(),
      modifiedAt: DateTime.tryParse(json['server_modified']?.toString() ?? ''),
      version: json['rev']?.toString(),
    );
  }

  @override
  Future<List<CloudItem>> search(String query) async {
    final json = await _rpc('/files/search_v2', {
      'query': query,
      'options': {'max_results': 100, 'file_status': 'active'},
    });
    return [
      for (final match in (json['matches'] as List? ?? const []))
        ?_item(
          Map<String, dynamic>.from(
            ((match as Map)['metadata'] as Map)['metadata'] as Map,
          ),
        ),
    ];
  }

  @override
  Future<CloudItem?> metadata(String fileId) async {
    try {
      return _item(await _rpc('/files/get_metadata', {'path': fileId}));
    } on CloudRequestException catch (error) {
      if (error.statusCode == 409) return null; // path/not_found
      rethrow;
    }
  }

  @override
  Future<({String fileName, Uint8List bytes})> download(CloudItem item) async {
    final response = await send(
      (token) => request(
        'POST',
        Uri.parse('$_content/files/download'),
        token,
        headers: {
          'Dropbox-API-Arg': asciiJson({'path': item.id}),
        },
      ),
    );
    return (fileName: item.name, bytes: response.bodyBytes);
  }

  @override
  Future<CloudItem> uploadBackup(String fileName, File file) async {
    final path = '$backupFolder/$fileName';
    final length = await file.length();
    final commit = {'path': path, 'mode': 'overwrite', 'mute': true};

    if (length <= _singleUploadLimit) {
      final bytes = await file.readAsBytes();
      final json = await sendJson(
        (token) => request(
          'POST',
          Uri.parse('$_content/files/upload'),
          token,
          headers: {
            'Dropbox-API-Arg': asciiJson(commit),
            'Content-Type': 'application/octet-stream',
          },
          bodyBytes: bytes,
        ),
      );
      return _item({...json, '.tag': 'file'})!;
    }

    final handle = await file.open();
    try {
      final first = await handle.read(math.min(_chunkSize, length));
      final start = await sendJson(
        (token) => request(
          'POST',
          Uri.parse('$_content/files/upload_session/start'),
          token,
          headers: {
            'Dropbox-API-Arg': asciiJson({'close': false}),
            'Content-Type': 'application/octet-stream',
          },
          bodyBytes: first,
        ),
      );
      final sessionId = start['session_id'];
      var offset = first.length;
      while (length - offset > _chunkSize) {
        final chunk = await handle.read(_chunkSize);
        final chunkOffset = offset;
        await send(
          (token) => request(
            'POST',
            Uri.parse('$_content/files/upload_session/append_v2'),
            token,
            headers: {
              'Dropbox-API-Arg': asciiJson({
                'cursor': {'session_id': sessionId, 'offset': chunkOffset},
              }),
              'Content-Type': 'application/octet-stream',
            },
            bodyBytes: chunk,
          ),
        );
        offset += chunk.length;
      }
      final last = await handle.read(length - offset);
      final json = await sendJson(
        (token) => request(
          'POST',
          Uri.parse('$_content/files/upload_session/finish'),
          token,
          headers: {
            'Dropbox-API-Arg': asciiJson({
              'cursor': {'session_id': sessionId, 'offset': offset},
              'commit': commit,
            }),
            'Content-Type': 'application/octet-stream',
          },
          bodyBytes: last,
        ),
      );
      return _item({...json, '.tag': 'file'})!;
    } finally {
      await handle.close();
    }
  }

  @override
  Future<List<CloudItem>> listBackups() async {
    try {
      final items = await listFolder(backupFolder);
      return items.where((item) => !item.isFolder).toList();
    } on CloudRequestException catch (error) {
      if (error.statusCode == 409) return const []; // folder doesn't exist yet
      rethrow;
    }
  }
}
