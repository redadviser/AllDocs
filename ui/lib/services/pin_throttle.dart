import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wrong-PIN back-off. A four-digit PIN has 10 000 values, so after
/// [_freeAttempts] misses each further one makes the next try wait longer
/// (30 s, 1 min, 2 min... up to [_maxWait]). Stored, so closing the app
/// doesn't reset it.
// shortcut: uses the phone's clock; setting it forward skips the wait. Move to
// a monotonic or server-backed check if that becomes a concern.
class PinThrottle {
  const PinThrottle(this._key);

  final String _key;

  static const _freeAttempts = 5;
  static const _maxWait = Duration(hours: 1);

  String get _failuresKey => '$_key.failures';
  String get _untilKey => '$_key.locked_until';

  /// Time left before another PIN may be tried; zero when it may.
  Future<Duration> remaining() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_untilKey);
    if (until == null) return Duration.zero;
    final left = DateTime.fromMillisecondsSinceEpoch(
      until,
    ).difference(DateTime.now());
    if (left.isNegative) return Duration.zero;
    // A clock set backwards must not lock the owner out for longer.
    return left > _maxWait ? _maxWait : left;
  }

  Future<void> recordFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final failures = (prefs.getInt(_failuresKey) ?? 0) + 1;
    await prefs.setInt(_failuresKey, failures);
    final wait = waitAfter(failures);
    if (wait > Duration.zero) {
      await prefs.setInt(
        _untilKey,
        DateTime.now().add(wait).millisecondsSinceEpoch,
      );
    }
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_failuresKey);
    await prefs.remove(_untilKey);
  }

  @visibleForTesting
  static Duration waitAfter(int failures) {
    if (failures < _freeAttempts) return Duration.zero;
    final doublings = min(failures - _freeAttempts, 7);
    final wait = Duration(seconds: 30 * (1 << doublings));
    return wait > _maxWait ? _maxWait : wait;
  }
}

/// "Try again in ..." for [wait], rounded up to whole seconds or minutes.
String pinWaitLabel(Duration wait) {
  final seconds = (wait.inMilliseconds / 1000).ceil();
  if (seconds < 60) return '$seconds s';
  return '${(seconds / 60).ceil()} min';
}
