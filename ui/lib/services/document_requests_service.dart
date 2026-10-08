import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_helpers.dart';
import 'auth_service.dart';
import 'current_user.dart';
import 'documents_service.dart';

enum DocumentRequestStatus { open, expired, closed }

class DocumentRequestFile {
  const DocumentRequestFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.uploadedAt,
    this.receivedAt,
  });

  final String id;
  final String name;
  final int sizeBytes;
  final DateTime uploadedAt;

  /// When this phone collected it (and the server deleted its copy).
  final DateTime? receivedAt;

  factory DocumentRequestFile.fromJson(Map<String, dynamic> json) {
    return DocumentRequestFile(
      id: json['id'] as String,
      name: json['name']?.toString() ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      uploadedAt: DateTime.parse(json['uploadedAt'] as String).toLocal(),
      receivedAt: DateTime.tryParse(json['receivedAt']?.toString() ?? ''),
    );
  }
}

/// "Send me X": a link someone else uses to upload files into this
/// account's library (Vault).
class DocumentRequest {
  const DocumentRequest({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.files,
    this.message,
    this.albumId,
    this.url,
  });

  final String id;
  final String title;
  final String? message;
  final String? albumId;
  final DocumentRequestStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<DocumentRequestFile> files;

  /// The link to share again; only known on the phone that created it.
  final String? url;

  factory DocumentRequest.fromJson(Map<String, dynamic> json, String? url) {
    return DocumentRequest(
      id: json['id'] as String,
      title: json['title']?.toString() ?? '',
      message: json['message'] as String?,
      albumId: json['albumId'] as String?,
      status: switch (json['status']) {
        'expired' => DocumentRequestStatus.expired,
        'closed' => DocumentRequestStatus.closed,
        _ => DocumentRequestStatus.open,
      },
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
      files: [
        for (final file in (json['files'] as List? ?? const []))
          DocumentRequestFile.fromJson(file as Map<String, dynamic>),
      ],
      url: url,
    );
  }
}

class DocumentRequestsException implements Exception {
  const DocumentRequestsException({this.notIncluded = false});

  /// The account isn't on Vault (creating needs it).
  final bool notIncluded;
}

class DocumentRequestsService {
  const DocumentRequestsService._();

  static String get _linksKey => CurrentUser.scoped('requests.links.v1');

  static Future<Map<String, String>> _links() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_linksKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).cast<String, String>();
  }

  static Future<void> _saveLinks(Map<String, String> links) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_linksKey, jsonEncode(links));
  }

  static Future<Map<String, String>> _headers() async =>
      ApiHelpers.headersWithToken(await AuthService.tokenStore.read());

  static Future<DocumentRequest> create({
    required String title,
    String? message,
    required int days,
    String? albumId,
    required String language,
  }) async {
    final res = await ApiHelpers.post(
      '/api/requests',
      headers: await _headers(),
      body: jsonEncode({
        'title': title,
        'message': message,
        'days': days,
        'albumId': albumId,
        'language': language,
      }),
    ).catchError((_) => throw const DocumentRequestsException());
    if (res.statusCode == 403) {
      throw const DocumentRequestsException(notIncluded: true);
    }
    if (res.statusCode != 200) throw const DocumentRequestsException();
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final id = data['id'] as String;
    final url = data['url'] as String;
    final links = await _links();
    links[id] = url;
    await _saveLinks(links);
    return DocumentRequest(
      id: id,
      title: title,
      message: message,
      albumId: albumId,
      status: DocumentRequestStatus.open,
      createdAt: DateTime.now(),
      expiresAt: DateTime.parse(data['expiresAt'] as String).toLocal(),
      files: const [],
      url: url,
    );
  }

  static Future<List<DocumentRequest>> list() async {
    final res = await ApiHelpers.get(
      '/api/requests',
      headers: await _headers(),
    ).catchError((_) => throw const DocumentRequestsException());
    if (res.statusCode != 200) throw const DocumentRequestsException();
    final links = await _links();
    return [
      for (final raw
          in (jsonDecode(res.body) as Map<String, dynamic>)['requests'] as List)
        DocumentRequest.fromJson(
          raw as Map<String, dynamic>,
          links[(raw)['id']],
        ),
    ];
  }

  /// No more files through this link.
  static Future<void> close(String id) async {
    final res = await ApiHelpers.post(
      '/api/requests/$id/close',
      headers: await _headers(),
    ).catchError((_) => throw const DocumentRequestsException());
    if (res.statusCode != 200) throw const DocumentRequestsException();
  }

  static Future<void> delete(String id) async {
    final res = await ApiHelpers.delete(
      '/api/requests/$id',
      headers: await _headers(),
    ).catchError((_) => throw const DocumentRequestsException());
    if (res.statusCode != 200 && res.statusCode != 404) {
      throw const DocumentRequestsException();
    }
    final links = await _links()
      ..remove(id);
    await _saveLinks(links);
  }

  /// Brings every file that arrived and isn't on this phone yet into the
  /// library (into the request's album when it still exists), then lets the
  /// server delete its copy. Returns how many documents were added. A full
  /// library stops it (StorageFullException); the rest wait on the server.
  static Future<int> collect(DocumentsService documentsService) async {
    final requests = await list();
    final pending = [
      for (final request in requests)
        for (final file in request.files)
          if (file.receivedAt == null) (request, file),
    ];
    if (pending.isEmpty) return 0;

    final snapshot = await documentsService.loadSnapshot();
    final temp = await getTemporaryDirectory();
    final headers = await _headers();
    var added = 0;
    for (final (request, file) in pending) {
      final res = await ApiHelpers.get(
        '/api/requests/${request.id}/files/${file.id}',
        headers: headers,
        timeout: const Duration(minutes: 2),
      );
      if (res.statusCode != 200) continue;
      final folder = await Directory(
        '${temp.path}/request_${file.id}',
      ).create(recursive: true);
      final local = File('${folder.path}/${file.name.replaceAll('/', '-')}');
      await local.writeAsBytes(res.bodyBytes, flush: true);
      try {
        final albumId = request.albumId;
        final result = await documentsService.importFilePaths(
          [local.path],
          albumId: albumId != null && snapshot.albumById(albumId) != null
              ? albumId
              : null,
          source: DocumentSource.shared,
        );
        added += result.count;
        // Imported, or already in the library: either way it's here now.
        await ApiHelpers.post(
          '/api/requests/${request.id}/files/${file.id}/received',
          headers: headers,
        );
      } finally {
        await folder.delete(recursive: true);
      }
    }
    return added;
  }
}
