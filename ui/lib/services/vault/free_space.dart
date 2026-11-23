import 'package:flutter/services.dart';

/// Free space on the phone, from the platform (StatFs on Android, the
/// volume's "important usage" capacity on iOS).
class FreeSpace {
  const FreeSpace._();

  static const _channel = MethodChannel('alldocs/storage');

  /// Bytes free on the volume holding [path]; null when it can't be told
  /// (callers then go ahead and let a full disk fail the write instead).
  static Future<int?> at(String path) async {
    try {
      return await _channel.invokeMethod<int>('freeBytes', {'path': path});
    } catch (_) {
      // No platform side (tests, background isolate) or it failed.
      return null;
    }
  }
}
