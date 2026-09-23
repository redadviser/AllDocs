import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/models.dart';

enum CloudProviderId { oneDrive, googleDrive, dropbox }

extension CloudProviderIdSource on CloudProviderId {
  DocumentSource get documentSource => switch (this) {
    CloudProviderId.oneDrive => DocumentSource.oneDrive,
    CloudProviderId.googleDrive => DocumentSource.googleDrive,
    CloudProviderId.dropbox => DocumentSource.dropbox,
  };
}

CloudProviderId? cloudProviderIdForSource(DocumentSource source) {
  return switch (source) {
    DocumentSource.oneDrive => CloudProviderId.oneDrive,
    DocumentSource.googleDrive => CloudProviderId.googleDrive,
    DocumentSource.dropbox => CloudProviderId.dropbox,
    _ => null,
  };
}

CloudProviderId? cloudProviderIdFromName(String? name) {
  for (final id in CloudProviderId.values) {
    if (id.name == name) return id;
  }
  return null;
}

/// A file or folder in a cloud account.
class CloudItem {
  const CloudItem({
    required this.id,
    required this.name,
    required this.isFolder,
    this.sizeBytes,
    this.modifiedAt,
    this.version,
    this.mimeType,
  });

  final String id;
  final String name;
  final bool isFolder;
  final int? sizeBytes;
  final DateTime? modifiedAt;

  /// eTag / rev / version — changes whenever the remote content changes.
  final String? version;
  final String? mimeType;

  DocumentType get documentType => documentTypeFromFileName(name);
}

/// Thrown when a provider has no OAuth client configured in [CloudConfig].
class CloudNotConfiguredException implements Exception {
  const CloudNotConfiguredException(this.provider);
  final CloudProviderId provider;
  @override
  String toString() => 'Cloud provider ${provider.name} is not configured';
}

class CloudAuthException implements Exception {
  const CloudAuthException([this.message = 'Cloud authorization failed']);
  final String message;
  @override
  String toString() => message;
}

class CloudRequestException implements Exception {
  const CloudRequestException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'Cloud request failed ($statusCode): $body';
}

/// Common interface for every cloud integration. Importing downloads a
/// copy into AllDocs (it does not sync); [metadata] lets the app notice a
/// newer remote version later; the backup methods write into an
/// app-private folder of the account.
abstract class CloudProvider {
  CloudProviderId get id;
  String get displayName;

  /// False when the OAuth client id hasn't been filled in [CloudConfig] yet.
  bool get isConfigured;

  Future<bool> isConnected();

  /// Email / display name of the connected account, when known.
  Future<String?> accountLabel();

  Future<void> connect();
  Future<void> disconnect();

  /// Children of [folderId]; null means the account's root.
  Future<List<CloudItem>> listFolder(String? folderId);
  Future<List<CloudItem>> search(String query);
  Future<CloudItem?> metadata(String fileId);

  /// Downloads [item]'s content. Returns the file name to store it under
  /// (Google Docs files are exported, which changes their extension).
  Future<({String fileName, Uint8List bytes})> download(CloudItem item);

  Future<CloudItem> uploadBackup(String fileName, File file);
  Future<List<CloudItem>> listBackups();
  Future<void> deleteBackup(CloudItem backup);
}

/// Tokens live in the platform keystore (flutter_secure_storage), never in
/// the documents state file.
class CloudTokenStore {
  const CloudTokenStore(this.provider);

  final CloudProviderId provider;
  static const _storage = FlutterSecureStorage();

  String get _key => 'cloud.${provider.name}';

  Future<Map<String, dynamic>?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> value) {
    return _storage.write(key: _key, value: jsonEncode(value));
  }

  Future<void> clear() => _storage.delete(key: _key);
}

/// Dropbox (and some other APIs) want JSON in an HTTP header, which must be
/// ASCII: escape everything else as \uXXXX.
String asciiJson(Object value) {
  final encoded = jsonEncode(value);
  final buffer = StringBuffer();
  for (final unit in encoded.codeUnits) {
    if (unit < 0x7f) {
      buffer.writeCharCode(unit);
    } else {
      buffer.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    }
  }
  return buffer.toString();
}

/// Only files AllDocs can store are offered for import.
bool isImportableCloudItem(CloudItem item) {
  if (item.isFolder) return true;
  const googleNative = {
    'application/vnd.google-apps.document',
    'application/vnd.google-apps.spreadsheet',
    'application/vnd.google-apps.presentation',
  };
  if (googleNative.contains(item.mimeType)) return true;
  final lower = item.name.toLowerCase();
  const extensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'rtf',
    'csv',
    'odt',
    'ods',
    'odp',
    'jpg',
    'jpeg',
    'png',
    'heic',
    'webp',
    'zip',
  ];
  return extensions.any((ext) => lower.endsWith('.$ext'));
}
