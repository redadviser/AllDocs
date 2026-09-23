import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_appauth/flutter_appauth.dart';

import 'cloud_config.dart';
import 'cloud_provider.dart';
import 'oauth_cloud_provider.dart';

/// Microsoft OneDrive (personal and work/school) through Microsoft Graph.
/// SharePoint document libraries are also Graph "drives", so this is the
/// base for a SharePoint integration later.
class OneDriveProvider extends OAuthCloudProvider {
  OneDriveProvider({super.client});

  static const _graph = 'https://graph.microsoft.com/v1.0';
  static const _select =
      r'$select=id,name,size,folder,file,lastModifiedDateTime,eTag';
  // Upload-session chunks must be a multiple of 320 KiB.
  static const _chunkSize = 320 * 1024 * 16;

  @override
  CloudProviderId get id => CloudProviderId.oneDrive;

  @override
  String get displayName => 'Microsoft OneDrive';

  @override
  String get clientId => CloudConfig.oneDriveClientId;

  @override
  AuthorizationServiceConfiguration get serviceConfiguration =>
      const AuthorizationServiceConfiguration(
        authorizationEndpoint:
            'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
        tokenEndpoint:
            'https://login.microsoftonline.com/common/oauth2/v2.0/token',
      );

  @override
  List<String> get scopes => const [
    'Files.ReadWrite',
    'User.Read',
    'offline_access',
  ];

  @override
  Future<String?> fetchAccountLabel() async {
    final me = await sendJson(
      (token) => request('GET', Uri.parse('$_graph/me'), token),
    );
    return (me['mail'] ?? me['userPrincipalName'] ?? me['displayName'])
        ?.toString();
  }

  @override
  Future<List<CloudItem>> listFolder(String? folderId) async {
    final path = folderId == null
        ? '/me/drive/root/children'
        : '/me/drive/items/$folderId/children';
    return _collect(Uri.parse('$_graph$path?$_select&\$top=200'));
  }

  @override
  Future<List<CloudItem>> search(String query) {
    final escaped = query.replaceAll("'", "''");
    return _collect(
      Uri.parse(
        "$_graph/me/drive/root/search(q='${Uri.encodeComponent(escaped)}')?$_select",
      ),
    );
  }

  Future<List<CloudItem>> _collect(Uri first) async {
    final items = <CloudItem>[];
    Uri? next = first;
    // Follow @odata.nextLink, capped so a huge folder can't loop forever.
    for (var page = 0; next != null && page < 10; page++) {
      final uri = next;
      final json = await sendJson((token) => request('GET', uri, token));
      for (final raw in (json['value'] as List? ?? const [])) {
        items.add(_item(Map<String, dynamic>.from(raw as Map)));
      }
      final link = json['@odata.nextLink']?.toString();
      next = link == null ? null : Uri.parse(link);
    }
    return items;
  }

  CloudItem _item(Map<String, dynamic> json) {
    final file = json['file'];
    return CloudItem(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      isFolder: json['folder'] != null,
      sizeBytes: (json['size'] as num?)?.toInt(),
      modifiedAt: DateTime.tryParse(
        json['lastModifiedDateTime']?.toString() ?? '',
      ),
      version: json['eTag']?.toString(),
      mimeType: file is Map ? file['mimeType']?.toString() : null,
    );
  }

  @override
  Future<CloudItem?> metadata(String fileId) async {
    try {
      final json = await sendJson(
        (token) => request(
          'GET',
          Uri.parse('$_graph/me/drive/items/$fileId?$_select'),
          token,
        ),
      );
      return _item(json);
    } on CloudRequestException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<({String fileName, Uint8List bytes})> download(CloudItem item) async {
    final response = await send(
      (token) => request(
        'GET',
        Uri.parse('$_graph/me/drive/items/${item.id}/content'),
        token,
      ),
    );
    return (fileName: item.name, bytes: response.bodyBytes);
  }

  @override
  Future<CloudItem> uploadBackup(String fileName, File file) async {
    final session = await sendJson(
      (token) => request(
        'POST',
        Uri.parse(
          '$_graph/me/drive/special/approot:/${Uri.encodeComponent(fileName)}:/createUploadSession',
        ),
        token,
        jsonBody: {
          'item': {'@microsoft.graph.conflictBehavior': 'replace'},
        },
      ),
    );
    final uploadUrl = Uri.parse(session['uploadUrl'].toString());
    final length = await file.length();
    final handle = await file.open();
    try {
      var offset = 0;
      Map<String, dynamic> last = const {};
      while (offset < length) {
        final size = math.min(_chunkSize, length - offset);
        await handle.setPosition(offset);
        final chunk = await handle.read(size);
        final end = offset + chunk.length - 1;
        // The upload URL is pre-authorized: no bearer token on these PUTs.
        final response = await send(
          (_) => request(
            'PUT',
            uploadUrl,
            '',
            headers: {'Content-Range': 'bytes $offset-$end/$length'},
            bodyBytes: chunk,
          )..headers.remove('Authorization'),
        );
        // 202 = more chunks expected; 200/201 = done, body is the item.
        if (response.statusCode != 202 && response.body.isNotEmpty) {
          last = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
        }
        offset += chunk.length;
      }
      return last.isEmpty
          ? CloudItem(
              id: '',
              name: fileName,
              isFolder: false,
              sizeBytes: length,
            )
          : _item(last);
    } finally {
      await handle.close();
    }
  }

  @override
  Future<List<CloudItem>> listBackups() async {
    final items = await _collect(
      Uri.parse('$_graph/me/drive/special/approot/children?$_select'),
    );
    return items.where((item) => !item.isFolder).toList();
  }
}
