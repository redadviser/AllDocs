import 'dart:io';

import 'package:flutter/services.dart';

import '../backup_storage.dart';
import 'cloud_provider.dart';

/// iCloud Drive on iPhone: backup-only, into the app's iCloud container,
/// which the Files app shows as iCloud Drive > AllDocs. There's no sign-in:
/// it uses the Apple ID of the phone, so it counts as connected whenever
/// iCloud Drive is on, unless the person disconnected it in AllDocs.
class ICloudProvider extends CloudProvider {
  ICloudProvider({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('alldocs/icloud');

  final MethodChannel _channel;
  final _optOut = const CloudTokenStore(CloudProviderId.icloud);

  static const backupFolderName = 'AllDocs Backups';

  @override
  CloudProviderId get id => CloudProviderId.icloud;

  @override
  String get displayName => 'iCloud Drive';

  @override
  bool get isConfigured => Platform.isIOS;

  @override
  bool get canBrowseFiles => false;

  /// The container's Documents folder; null when iCloud Drive is off.
  Future<String?> _documentsPath() async {
    if (!isConfigured) return null;
    return _channel.invokeMethod<String>('documentsPath');
  }

  @override
  Future<bool> isConnected() async {
    if (await _optOut.read() != null) return false;
    return await _documentsPath() != null;
  }

  @override
  Future<String?> accountLabel() async => null;

  @override
  Future<void> connect() async {
    if (await _documentsPath() == null) {
      throw const CloudAuthException('iCloud Drive is off on this iPhone');
    }
    await _optOut.clear();
  }

  @override
  Future<void> disconnect() => _optOut.write({'disconnected': true});

  @override
  BackupStorage backupStorage() => ICloudBackupStorage(() async {
    final documents = await _documentsPath();
    if (documents == null) {
      throw const CloudAuthException('iCloud Drive is off on this iPhone');
    }
    return Directory('$documents/$backupFolderName');
  }, (path) => _channel.invokeMethod<bool>('download', {'path': path}));

  @override
  Future<List<CloudItem>> listFolder(String? folderId) async => const [];

  @override
  Future<List<CloudItem>> search(String query) async => const [];

  @override
  Future<CloudItem?> metadata(String fileId) async => null;

  @override
  Future<({String fileName, Uint8List bytes})> download(CloudItem item) {
    throw UnsupportedError('iCloud Drive is backup-only');
  }

  @override
  Future<List<CloudItem>> listLegacyBackups() async => const [];
}

/// A [DeviceBackupStorage] inside the iCloud container. iOS may evict a
/// synced file to free space, leaving a hidden ".name.icloud" placeholder:
/// listings report the real name, and reads download the file first.
class ICloudBackupStorage extends DeviceBackupStorage {
  ICloudBackupStorage(this._resolveRoot, this._downloadNative)
    : super(Directory(''));

  final Future<Directory> Function() _resolveRoot;
  final Future<bool?> Function(String absolutePath) _downloadNative;
  Directory? _root;

  @override
  Directory get root => _root ?? Directory('');

  @override
  String get label => 'iCloud Drive · AllDocs';

  Future<void> _ready() async => _root ??= await _resolveRoot();

  String _abs(String path) => path.isEmpty ? root.path : '${root.path}/$path';

  String _placeholder(String path) {
    final (:parent, :name) = splitBackupPath(path);
    return _abs(parent.isEmpty ? '.$name.icloud' : '$parent/.$name.icloud');
  }

  /// Downloads [path] when iOS evicted it. Throws rather than pretend the
  /// file is missing: callers delete what they think is gone.
  Future<void> _ensureLocal(String path) async {
    await _ready();
    if (!await File(_placeholder(path)).exists()) return;
    if (await _downloadNative(_abs(path)) != true) {
      throw FileSystemException('iCloud download did not finish', path);
    }
  }

  @override
  Future<List<BackupEntry>> list(String folder) async {
    await _ready();
    return [
      for (final entry in await super.list(folder))
        if (iCloudPlaceholderName(entry.name) case final real?)
          BackupEntry(name: real, isFolder: false)
        else
          entry,
    ];
  }

  @override
  Future<void> ensureFolder(String folder) async {
    await _ready();
    await super.ensureFolder(folder);
  }

  @override
  Future<void> upload(String path, File file) async {
    await _ready();
    final placeholder = File(_placeholder(path));
    if (await placeholder.exists()) await placeholder.delete();
    await super.upload(path, file);
  }

  @override
  Future<void> download(String path, File destination) async {
    await _ensureLocal(path);
    await super.download(path, destination);
  }

  @override
  Future<void> copy(String from, String to) async {
    await _ensureLocal(from);
    await super.copy(from, to);
  }

  @override
  Future<void> move(String from, String to) async {
    await _ensureLocal(from);
    await super.move(from, to);
  }

  @override
  Future<void> delete(String path) async {
    await _ready();
    await super.delete(path);
    final placeholder = File(_placeholder(path));
    if (await placeholder.exists()) await placeholder.delete();
  }

  @override
  Future<String?> readText(String path) async {
    await _ensureLocal(path);
    return super.readText(path);
  }

  @override
  Future<void> writeText(String path, String text) async {
    await _ready();
    await super.writeText(path, text);
  }
}

/// ".Invoice.pdf.icloud" -> "Invoice.pdf"; null for any other name.
String? iCloudPlaceholderName(String name) {
  if (name.length > 8 && name.startsWith('.') && name.endsWith('.icloud')) {
    return name.substring(1, name.length - '.icloud'.length);
  }
  return null;
}
