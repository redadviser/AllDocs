import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class StoragePermissionService {
  const StoragePermissionService();

  Future<bool> hasAllFilesAccess() async {
    if (!_needsAllFilesAccess) return true;
    return Permission.manageExternalStorage.isGranted;
  }

  Future<bool> requestAllFilesAccess() async {
    if (!_needsAllFilesAccess) return true;
    if (await hasAllFilesAccess()) return true;

    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  Future<bool> openPermissionSettings() {
    return openAppSettings();
  }

  bool get _needsAllFilesAccess => !kIsWeb && Platform.isAndroid;
}
