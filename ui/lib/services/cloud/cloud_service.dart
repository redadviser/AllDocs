import '../../models/models.dart';
import '../local_documents_store.dart';
import 'cloud_provider.dart';
import 'dropbox_provider.dart';
import 'google_drive_provider.dart';
import 'onedrive_provider.dart';

/// A cloud document whose remote copy changed since it was imported.
class CloudUpdate {
  const CloudUpdate({
    required this.document,
    required this.provider,
    required this.remote,
  });

  final DocumentFile document;
  final CloudProvider provider;
  final CloudItem remote;
}

/// Registry of cloud providers plus the import / "is there a newer
/// version?" logic on top of them. Importing always stores a local copy —
/// documents stay available offline and don't depend on the cloud account.
class CloudService {
  CloudService({List<CloudProvider>? providers, LocalDocumentsStore? store})
    : providers =
          providers ??
          [OneDriveProvider(), GoogleDriveProvider(), DropboxProvider()],
      _store = store ?? const LocalDocumentsStore();

  final List<CloudProvider> providers;
  final LocalDocumentsStore _store;

  CloudProvider? provider(CloudProviderId id) {
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  CloudProvider? providerNamed(String name) {
    final id = cloudProviderIdFromName(name);
    return id == null ? null : provider(id);
  }

  Future<List<CloudProvider>> connectedProviders() async {
    final connected = <CloudProvider>[];
    for (final provider in providers) {
      if (provider.isConfigured && await provider.isConnected()) {
        connected.add(provider);
      }
    }
    return connected;
  }

  /// Downloads and imports [items]. Folders and unsupported files are
  /// skipped. [onProgress] reports (done, total).
  Future<ImportResult> importItems(
    CloudProvider provider,
    List<CloudItem> items, {
    String? albumId,
    void Function(int done, int total)? onProgress,
  }) async {
    final files = items
        .where((item) => !item.isFolder && isImportableCloudItem(item))
        .toList();
    var result = ImportResult.empty;
    for (var index = 0; index < files.length; index++) {
      final item = files[index];
      final downloaded = await provider.download(item);
      result =
          result +
          await _store.importBytes(
            downloaded.fileName,
            downloaded.bytes,
            albumId: albumId,
            source: provider.id.documentSource,
            cloudFileId: item.id,
            cloudVersion: item.version,
          );
      onProgress?.call(index + 1, files.length);
    }
    return result;
  }

  /// Checks every document imported from a connected provider for a newer
  /// remote version.
  Future<List<CloudUpdate>> checkForUpdates(
    List<DocumentFile> documents,
  ) async {
    final updates = <CloudUpdate>[];
    final connected = {
      for (final provider in await connectedProviders()) provider.id: provider,
    };
    for (final document in documents) {
      if (!document.isFromCloud) continue;
      final providerId = cloudProviderIdForSource(document.source);
      final provider = providerId == null ? null : connected[providerId];
      if (provider == null) continue;
      try {
        final remote = await provider.metadata(document.cloudFileId!);
        if (remote == null || remote.version == null) continue;
        if (remote.version != document.cloudVersion) {
          updates.add(
            CloudUpdate(document: document, provider: provider, remote: remote),
          );
        }
      } catch (_) {
        // One unreachable file shouldn't hide the other updates.
      }
    }
    return updates;
  }

  Future<void> applyUpdate(CloudUpdate update) async {
    final downloaded = await update.provider.download(update.remote);
    await _store.replaceDocumentContent(
      update.document.id,
      downloaded.bytes,
      cloudVersion: update.remote.version,
    );
  }
}
