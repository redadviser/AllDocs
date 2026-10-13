import 'dart:convert';

import 'api_helpers.dart';
import 'auth_service.dart';

enum HiddenPinResetState { none, codeSent, waiting, ready }

class HiddenPinResetStatus {
  const HiddenPinResetStatus({
    required this.state,
    this.readyAt,
    this.attemptsLeft,
    this.cancelled = false,
  });

  final HiddenPinResetState state;

  /// When the new PIN may be set (waiting / ready).
  final DateTime? readyAt;
  final int? attemptsLeft;

  /// The last request was cancelled (from the warning email).
  final bool cancelled;

  factory HiddenPinResetStatus.fromJson(Map<String, dynamic> json) {
    return HiddenPinResetStatus(
      state: HiddenPinResetState.values.firstWhere(
        (state) => state.name == json['state'],
        orElse: () => HiddenPinResetState.none,
      ),
      readyAt: DateTime.tryParse(json['readyAt']?.toString() ?? '')?.toLocal(),
      attemptsLeft: (json['attemptsLeft'] as num?)?.toInt(),
      cancelled: json['cancelled'] == true,
    );
  }
}

enum HiddenPinResetProblem {
  wrongCode,
  expired,
  tooManyAttempts,
  tooManyRequests,
  notReady,
  unavailable,
}

class HiddenPinResetException implements Exception {
  const HiddenPinResetException(this.problem, {this.attemptsLeft});

  final HiddenPinResetProblem problem;
  final int? attemptsLeft;
}

/// Resetting the hidden albums' PIN, which the server allows only after a
/// code sent to the account's email and a 24-hour wait (see the backend's
/// hidden-pin module). The PIN itself stays on the phone.
class HiddenPinResetService {
  const HiddenPinResetService._();

  static const _base = '/api/security/hidden-pin-reset';

  static Future<Map<String, dynamic>> _call(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final headers = ApiHelpers.headersWithToken(
      await AuthService.tokenStore.read(),
    );
    final res =
        await (body == null && path.isEmpty
                ? ApiHelpers.get(_base, headers: headers)
                : ApiHelpers.post(
                    '$_base$path',
                    headers: headers,
                    body: jsonEncode(body ?? const {}),
                  ))
            .catchError(
              (_) => throw const HiddenPinResetException(
                HiddenPinResetProblem.unavailable,
              ),
            );
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      data = const {};
    }
    if (res.statusCode == 200) return data;
    throw HiddenPinResetException(switch (data['code']) {
      'wrongCode' => HiddenPinResetProblem.wrongCode,
      'expired' || 'noCode' => HiddenPinResetProblem.expired,
      'tooManyAttempts' => HiddenPinResetProblem.tooManyAttempts,
      'tooManyRequests' => HiddenPinResetProblem.tooManyRequests,
      'notReady' => HiddenPinResetProblem.notReady,
      _ => HiddenPinResetProblem.unavailable,
    }, attemptsLeft: (data['attemptsLeft'] as num?)?.toInt());
  }

  static Future<HiddenPinResetStatus> status() async =>
      HiddenPinResetStatus.fromJson(await _call(''));

  static Future<HiddenPinResetStatus> requestCode({
    required String language,
  }) async => HiddenPinResetStatus.fromJson(
    await _call('/request', body: {'language': language}),
  );

  static Future<HiddenPinResetStatus> verify(
    String code, {
    required String language,
  }) async => HiddenPinResetStatus.fromJson(
    await _call('/verify', body: {'code': code, 'language': language}),
  );

  /// The server lets the new PIN be set (once).
  static Future<void> complete() => _call('/complete', body: const {});

  static Future<void> cancel() => _call('/cancel', body: const {});
}
