import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_base_url.dart';
import 'api_helpers.dart';
import 'auth_service.dart';
import 'current_user.dart';
import 'package:http/http.dart' as http;

enum SecureShareStatus { active, expired, revoked, locked, used }

/// One of the user's documents behind a link (Vault): it expires, can need
/// a code, can open a set number of times, and can be revoked.
class SecureShare {
  const SecureShare({
    required this.id,
    required this.title,
    required this.fileName,
    required this.status,
    required this.hasCode,
    required this.viewCount,
    required this.createdAt,
    required this.expiresAt,
    this.maxViews,
    this.lastViewedAt,
    this.url,
  });

  final String id;
  final String title;
  final String fileName;
  final SecureShareStatus status;
  final bool hasCode;
  final int viewCount;
  final int? maxViews;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? lastViewedAt;

  /// The link to share again; only known on the phone that created it.
  final String? url;

  factory SecureShare.fromJson(Map<String, dynamic> json, String? url) {
    return SecureShare(
      id: json['id'] as String,
      title: json['title']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      status: SecureShareStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => SecureShareStatus.expired,
      ),
      hasCode: json['hasCode'] == true,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      maxViews: (json['maxViews'] as num?)?.toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
      lastViewedAt: DateTime.tryParse(
        json['lastViewedAt']?.toString() ?? '',
      )?.toLocal(),
      url: url,
    );
  }
}

enum SecureShareProblem { notIncluded, tooBig, badType, unavailable }

class SecureShareException implements Exception {
  const SecureShareException(this.problem);

  final SecureShareProblem problem;
}

class SecureSharesService {
  const SecureSharesService._();

  /// The server's limit for one shared file.
  static const maxBytes = 50 * 1024 * 1024;

  static String get _linksKey => CurrentUser.scoped('shares.links.v1');

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

  /// Uploads [file] as [fileName] behind a new link.
  static Future<SecureShare> create({
    required File file,
    required String title,
    required String fileName,
    required int days,
    String? code,
    int? maxViews,
    required String language,
  }) async {
    final length = await file.length();
    if (length > maxBytes) {
      throw const SecureShareException(SecureShareProblem.tooBig);
    }
    final meta = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'title': title,
          'fileName': fileName,
          'days': days,
          'code': ?code,
          'maxViews': ?maxViews,
          'language': language,
        }),
      ),
    );
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${ApiBaseUrl.baseUrl}/api/shares'),
            headers: {
              ...await _headers(),
              'Content-Type': 'application/octet-stream',
              'X-Share-Meta': meta,
            },
            body: await file.readAsBytes(),
          )
          .timeout(const Duration(minutes: 3));
    } catch (_) {
      throw const SecureShareException(SecureShareProblem.unavailable);
    }
    switch (res.statusCode) {
      case 200:
        break;
      case 403:
        throw const SecureShareException(SecureShareProblem.notIncluded);
      case 413:
        throw const SecureShareException(SecureShareProblem.tooBig);
      case 415:
        throw const SecureShareException(SecureShareProblem.badType);
      default:
        throw const SecureShareException(SecureShareProblem.unavailable);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final id = data['id'] as String;
    final url = data['url'] as String;
    final links = await _links();
    links[id] = url;
    await _saveLinks(links);
    return SecureShare(
      id: id,
      title: title,
      fileName: fileName,
      status: SecureShareStatus.active,
      hasCode: code != null,
      viewCount: 0,
      maxViews: maxViews,
      createdAt: DateTime.now(),
      expiresAt: DateTime.parse(data['expiresAt'] as String).toLocal(),
      url: url,
    );
  }

  static Future<List<SecureShare>> list() async {
    final res = await ApiHelpers.get('/api/shares', headers: await _headers())
        .catchError(
          (_) =>
              throw const SecureShareException(SecureShareProblem.unavailable),
        );
    if (res.statusCode != 200) {
      throw const SecureShareException(SecureShareProblem.unavailable);
    }
    final links = await _links();
    return [
      for (final raw
          in (jsonDecode(res.body) as Map<String, dynamic>)['shares'] as List)
        SecureShare.fromJson(raw as Map<String, dynamic>, links[raw['id']]),
    ];
  }

  /// The link stops working now (and the server deletes the file).
  static Future<void> revoke(String id) async {
    final res =
        await ApiHelpers.post(
          '/api/shares/$id/revoke',
          headers: await _headers(),
        ).catchError(
          (_) =>
              throw const SecureShareException(SecureShareProblem.unavailable),
        );
    if (res.statusCode != 200) {
      throw const SecureShareException(SecureShareProblem.unavailable);
    }
  }

  static Future<void> delete(String id) async {
    final res =
        await ApiHelpers.delete(
          '/api/shares/$id',
          headers: await _headers(),
        ).catchError(
          (_) =>
              throw const SecureShareException(SecureShareProblem.unavailable),
        );
    if (res.statusCode != 200 && res.statusCode != 404) {
      throw const SecureShareException(SecureShareProblem.unavailable);
    }
    final links = await _links()
      ..remove(id);
    await _saveLinks(links);
  }
}
