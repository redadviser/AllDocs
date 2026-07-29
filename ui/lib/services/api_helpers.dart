import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io' show HttpException, SocketException;

import 'package:http/http.dart' as http;

import 'api_base_url.dart';

class ApiHelpers {
  const ApiHelpers._();

  static Map<String, String> headersWithToken([String? token]) {
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Cookie': 'session_token=$token',
    };
  }

  static Future<http.Response> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _guardRequest(
      () => http
          .post(Uri.parse('${ApiBaseUrl.baseUrl}$path'), headers: headers, body: body)
          .timeout(ApiBaseUrl.requestTimeout),
      path,
    );
  }

  static Future<http.Response> get(String path, {Map<String, String>? headers}) {
    return _guardRequest(
      () => http
          .get(Uri.parse('${ApiBaseUrl.baseUrl}$path'), headers: headers)
          .timeout(ApiBaseUrl.requestTimeout),
      path,
    );
  }

  static Future<http.Response> delete(
    String path, {
    Map<String, String>? headers,
  }) {
    return _guardRequest(
      () => http
          .delete(Uri.parse('${ApiBaseUrl.baseUrl}$path'), headers: headers)
          .timeout(ApiBaseUrl.requestTimeout),
      path,
    );
  }

  static Future<T> _guardRequest<T>(Future<T> Function() run, String path) async {
    try {
      return await run();
    } on SocketException {
      throw Exception('Could not reach the AllDocs server ($path).');
    } on HttpException {
      throw Exception('The AllDocs server returned an invalid response ($path).');
    } on FormatException {
      throw Exception('The AllDocs server returned an unreadable response ($path).');
    } on TimeoutException {
      throw Exception('The AllDocs server took too long to respond ($path).');
    }
  }

  static String errorMessage(http.Response res, String fallback) {
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['error']?.toString() ?? fallback;
    } catch (_) {
      return fallback;
    }
  }
}
