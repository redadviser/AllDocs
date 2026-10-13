import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../api_base_url.dart';
import '../auth_service.dart';

/// Why a sync call failed, in the terms the app reacts to.
enum SyncProblem {
  /// Not on Vault (any more).
  notIncluded,

  /// Removed from sync (from another device), or sync was turned off.
  deviceRemoved,

  /// Another device pushed first: pull, then push again.
  behind,

  /// Joining: the pairing code expired or was already used.
  badCode,

  /// Joining: the QR is from another sync (an older key).
  wrongKey,

  /// Joining: the plan's device limit is reached.
  tooMany,

  /// Starting: another device already started sync for this account.
  needsPairing,

  /// The server holds too many files waiting already; try later.
  quota,

  /// Not on the server (a blob nobody sent yet, a snapshot not ready).
  missing,

  /// No network, server down, anything else.
  unavailable,
}

class SyncApiException implements Exception {
  const SyncApiException(this.problem, [this.status]);

  final SyncProblem problem;
  final int? status;

  @override
  String toString() => 'SyncApiException($problem, $status)';
}

class SyncPull {
  const SyncPull({
    required this.changes,
    required this.hasMore,
    required this.latest,
    required this.needsSnapshot,
    required this.snapshotReady,
    required this.requestedBlobs,
    required this.snapshotFor,
    required this.otherDevices,
  });

  final List<({int seq, String deviceId, Uint8List payload})> changes;
  final bool hasMore;
  final int latest;
  final bool needsSnapshot;
  final bool snapshotReady;
  final List<String> requestedBlobs;
  final List<String> snapshotFor;
  final int otherDevices;
}

class SyncDeviceInfo {
  const SyncDeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastSeenAt,
    required this.waitingForLibrary,
  });

  final String id;
  final String name;
  final String? platform;
  final DateTime lastSeenAt;
  final bool waitingForLibrary;
}

class SyncAccountStatus {
  const SyncAccountStatus({
    required this.enabled,
    required this.keyCheck,
    required this.maxDevices,
    required this.devices,
  });

  final bool enabled;
  final String? keyCheck;
  final int maxDevices;
  final List<SyncDeviceInfo> devices;
}

/// The AllDocs server's /api/sync, as this phone's device ([deviceId]).
class SyncApi {
  SyncApi({this.deviceId, http.Client? client})
    : _client = client ?? http.Client();

  String? deviceId;
  final http.Client _client;

  static const _timeout = Duration(seconds: 30);
  static const _transferTimeout = Duration(minutes: 30);

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await AuthService.tokenStore.read();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Cookie': 'session_token=$token',
      'X-Sync-Device': ?deviceId,
    };
  }

  Uri _uri(String path) => Uri.parse('${ApiBaseUrl.baseUrl}/api/sync$path');

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      throw const SyncApiException(SyncProblem.unavailable);
    } on SocketException {
      throw const SyncApiException(SyncProblem.unavailable);
    } on http.ClientException {
      throw const SyncApiException(SyncProblem.unavailable);
    } on HandshakeException {
      throw const SyncApiException(SyncProblem.unavailable);
    }
    _check(response.statusCode, response.body);
    return response;
  }

  static void _check(int status, String body) {
    if (status >= 200 && status < 300) return;
    String? code;
    try {
      code = (jsonDecode(body) as Map)['code']?.toString();
    } catch (_) {}
    final problem = switch (code) {
      'notIncluded' => SyncProblem.notIncluded,
      'deviceRemoved' => SyncProblem.deviceRemoved,
      'behind' => SyncProblem.behind,
      'badCode' || 'noCircle' => SyncProblem.badCode,
      'wrongKey' => SyncProblem.wrongKey,
      'tooMany' => SyncProblem.tooMany,
      'needsPairing' => SyncProblem.needsPairing,
      'quota' => SyncProblem.quota,
      'missing' => SyncProblem.missing,
      _ when status == 403 => SyncProblem.notIncluded,
      _ when status == 404 => SyncProblem.missing,
      _ => SyncProblem.unavailable,
    };
    throw SyncApiException(problem, status);
  }

  Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;

  // ---- Account & devices ----

  Future<SyncAccountStatus> status() async {
    final data = _json(
      await _send(
        () async => _client.get(_uri('/'), headers: await _headers()),
      ),
    );
    return SyncAccountStatus(
      enabled: data['enabled'] == true,
      keyCheck: data['keyCheck'] as String?,
      maxDevices: (data['maxDevices'] as num?)?.toInt() ?? 3,
      devices: [
        for (final raw in (data['devices'] as List? ?? const []))
          SyncDeviceInfo(
            id: raw['id'] as String,
            name: raw['name']?.toString() ?? '',
            platform: raw['platform'] as String?,
            lastSeenAt: DateTime.parse(raw['lastSeenAt'] as String).toLocal(),
            waitingForLibrary: raw['waitingForLibrary'] == true,
          ),
      ],
    );
  }

  /// Returns the new device's id.
  Future<String> register({
    required String name,
    required String platform,
    required String keyCheck,
    String? pairingCode,
  }) async {
    final data = _json(
      await _send(
        () async => _client.post(
          _uri('/devices'),
          headers: await _headers(),
          body: jsonEncode({
            'name': name,
            'platform': platform,
            'keyCheck': keyCheck,
            'pairingCode': ?pairingCode,
          }),
        ),
      ),
    );
    return data['deviceId'] as String;
  }

  Future<void> removeDevice(String id) async {
    await _send(
      () async =>
          _client.delete(_uri('/devices/$id'), headers: await _headers()),
    );
  }

  Future<({String code, DateTime expiresAt})> createPairing() async {
    final data = _json(
      await _send(
        () async => _client.post(_uri('/pairings'), headers: await _headers()),
      ),
    );
    return (
      code: data['code'] as String,
      expiresAt: DateTime.parse(data['expiresAt'] as String).toLocal(),
    );
  }

  Future<({bool joined, String? deviceName, bool expired})> pairingStatus(
    String code,
  ) async {
    final data = _json(
      await _send(
        () async => _client.post(
          _uri('/pairings/status'),
          headers: await _headers(),
          body: jsonEncode({'code': code}),
        ),
      ),
    );
    return (
      joined: data['joined'] == true,
      deviceName: data['deviceName'] as String?,
      expired: data['expired'] == true,
    );
  }

  // ---- Changes ----

  Future<SyncPull> pull(int after) async {
    final data = _json(
      await _send(
        () async => _client.get(
          _uri('/changes?after=$after'),
          headers: await _headers(),
        ),
      ),
    );
    return SyncPull(
      changes: [
        for (final raw in (data['changes'] as List? ?? const []))
          (
            seq: (raw['seq'] as num).toInt(),
            deviceId: raw['deviceId'] as String,
            payload: base64Decode(raw['payload'] as String),
          ),
      ],
      hasMore: data['hasMore'] == true,
      latest: (data['latest'] as num?)?.toInt() ?? 0,
      needsSnapshot: data['needsSnapshot'] == true,
      snapshotReady: data['snapshotReady'] == true,
      requestedBlobs: (data['requestedBlobs'] as List? ?? const [])
          .cast<String>(),
      snapshotFor: (data['snapshotFor'] as List? ?? const []).cast<String>(),
      otherDevices: (data['otherDevices'] as num?)?.toInt() ?? 0,
    );
  }

  /// Returns the batch's sequence number.
  Future<int> push(int base, Uint8List sealed) async {
    final data = _json(
      await _send(
        () async => _client.post(
          _uri('/changes?base=$base'),
          headers: {
            ...await _headers(json: false),
            'Content-Type': 'application/octet-stream',
          },
          body: sealed,
        ),
      ),
    );
    return (data['seq'] as num).toInt();
  }

  // ---- Blobs ----

  Future<Set<String>> existingBlobs(List<String> ids) async {
    if (ids.isEmpty) return {};
    final data = _json(
      await _send(
        () async => _client.post(
          _uri('/blobs/existing'),
          headers: await _headers(),
          body: jsonEncode({'ids': ids}),
        ),
      ),
    );
    return (data['existing'] as List).cast<String>().toSet();
  }

  Future<Set<String>> requestBlobs(List<String> ids) async {
    if (ids.isEmpty) return {};
    final data = _json(
      await _send(
        () async => _client.post(
          _uri('/blobs/requests'),
          headers: await _headers(),
          body: jsonEncode({'ids': ids}),
        ),
      ),
    );
    return (data['available'] as List).cast<String>().toSet();
  }

  Future<void> putBlob(
    String blobId,
    Stream<List<int>> body,
    int length, {
    required bool forEveryone,
  }) => _upload(
    _uri('/blobs/$blobId${forEveryone ? '?for=all' : ''}'),
    body,
    length,
  );

  /// Downloads a blob into [target].
  Future<void> getBlob(String blobId, File target) =>
      _download(_uri('/blobs/$blobId'), target);

  Future<void> ackBlob(String blobId) async {
    await _send(
      () async =>
          _client.post(_uri('/blobs/$blobId/ack'), headers: await _headers()),
    );
  }

  // ---- Snapshots ----

  Future<void> putSnapshot(String deviceId, int upto, Uint8List sealed) =>
      _upload(
        _uri('/snapshots/$deviceId?upto=$upto'),
        Stream.value(sealed),
        sealed.length,
      );

  /// The snapshot sent for this device, and the change it goes up to.
  Future<({Uint8List sealed, int upto})> getSnapshot() async {
    final response = await _send(
      () async => _client.get(_uri('/snapshot'), headers: await _headers()),
    );
    return (
      sealed: response.bodyBytes,
      upto: int.tryParse(response.headers['x-upto-seq'] ?? '') ?? 0,
    );
  }

  Future<void> ackSnapshot() async {
    await _send(
      () async =>
          _client.post(_uri('/snapshot/ack'), headers: await _headers()),
    );
  }

  // ---- Streaming ----

  Future<void> _upload(Uri uri, Stream<List<int>> body, int length) async {
    final request = http.StreamedRequest('PUT', uri)
      ..headers.addAll({
        ...await _headers(json: false),
        'Content-Type': 'application/octet-stream',
      })
      ..contentLength = length;
    unawaited(
      request.sink
          .addStream(body)
          .catchError(request.sink.addError)
          .whenComplete(request.sink.close),
    );
    try {
      final response = await _client.send(request).timeout(_transferTimeout);
      final text = await response.stream.bytesToString();
      _check(response.statusCode, text);
    } on TimeoutException {
      throw const SyncApiException(SyncProblem.unavailable);
    } on SocketException {
      throw const SyncApiException(SyncProblem.unavailable);
    } on http.ClientException {
      throw const SyncApiException(SyncProblem.unavailable);
    }
  }

  Future<void> _download(Uri uri, File target) async {
    final request = http.Request('GET', uri)
      ..headers.addAll(await _headers(json: false));
    try {
      final response = await _client.send(request).timeout(_transferTimeout);
      if (response.statusCode != 200) {
        _check(response.statusCode, await response.stream.bytesToString());
      }
      final sink = target.openWrite();
      try {
        await response.stream.pipe(sink);
      } finally {
        await sink.close().catchError((_) {});
      }
    } on TimeoutException {
      throw const SyncApiException(SyncProblem.unavailable);
    } on SocketException {
      throw const SyncApiException(SyncProblem.unavailable);
    } on http.ClientException {
      throw const SyncApiException(SyncProblem.unavailable);
    }
  }
}
