import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'document_actions.dart';
import 'device_scan_sheet.dart';
import 'document_import_flow.dart';

/// The "+ Add" menu: every way a document can get into AllDocs.
Future<void> showAddDocumentSheet(
  BuildContext context,
  DocumentsService documentsService, {
  String? albumId,
  void Function(CloudProviderId? provider)? onOpenCloud,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      void run(Future<void> Function() action) {
        Navigator.of(sheetContext).pop();
        action();
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                AppConstants.archiveAddDocument.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _Option(
              icon: Icons.insert_drive_file_outlined,
              title: AppConstants.addFile.tr(),
              onTap: () => run(
                () => pickAndImportDocuments(
                  context,
                  documentsService,
                  albumId: albumId,
                  allowMultiple: false,
                ),
              ),
            ),
            _Option(
              icon: Icons.file_copy_outlined,
              title: AppConstants.addManyFiles.tr(),
              onTap: () => run(
                () => pickAndImportDocuments(
                  context,
                  documentsService,
                  albumId: albumId,
                ),
              ),
            ),
            _Option(
              icon: Icons.folder_zip_outlined,
              title: AppConstants.addZip.tr(),
              subtitle: AppConstants.addZipHint.tr(),
              onTap: () => run(
                () => pickAndImportDocuments(
                  context,
                  documentsService,
                  albumId: albumId,
                  kind: ImportPickKind.zip,
                  allowMultiple: false,
                ),
              ),
            ),
            const Divider(indent: 20, endIndent: 20),
            _Option(
              icon: Icons.document_scanner_outlined,
              title: AppConstants.archiveScanDocumentTitle.tr(),
              subtitle: AppConstants.addScanHint.tr(),
              onTap: () => run(
                () =>
                    scanAndImport(context, documentsService, albumId: albumId),
              ),
            ),
            _Option(
              icon: Icons.image_outlined,
              title: AppConstants.addImage.tr(),
              onTap: () => run(
                () => pickAndImportDocuments(
                  context,
                  documentsService,
                  albumId: albumId,
                  kind: ImportPickKind.images,
                ),
              ),
            ),
            _Option(
              icon: Icons.phone_android_outlined,
              title: AppConstants.addFromDevice.tr(),
              subtitle: AppConstants.addFromDeviceHint.tr(),
              onTap: () => run(
                () => showDeviceFoldersSheet(
                  context,
                  documentsService,
                  albumId: albumId,
                ),
              ),
            ),
            if (onOpenCloud != null) ...[
              const Divider(indent: 20, endIndent: 20),
              _Option(
                icon: Icons.cloud_outlined,
                title: 'OneDrive',
                onTap: () =>
                    run(() async => onOpenCloud(CloudProviderId.oneDrive)),
              ),
              _Option(
                icon: Icons.add_to_drive_outlined,
                title: 'Google Drive',
                onTap: () =>
                    run(() async => onOpenCloud(CloudProviderId.googleDrive)),
              ),
              _Option(
                icon: Icons.cloud_queue_outlined,
                title: 'Dropbox',
                onTap: () =>
                    run(() async => onOpenCloud(CloudProviderId.dropbox)),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Linked device folders (Downloads, WhatsApp, ...) plus "search the whole
/// device".
Future<void> showDeviceFoldersSheet(
  BuildContext context,
  DocumentsService documentsService, {
  String? albumId,
}) async {
  final snapshot = await documentsService.loadSnapshot();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      Future<void> open(Future<DeviceFolderScan?> Function() load) async {
        Navigator.of(sheetContext).pop();
        showSnack(context, AppConstants.archiveSearchingDevice.tr());
        try {
          final scan = await load();
          if (!context.mounted || scan == null) return;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          await showDeviceScanSheet(
            context,
            documentsService,
            scan,
            albumId: albumId,
          );
        } catch (_) {
          if (context.mounted) {
            showSnack(context, AppConstants.archiveFolderOpenFailed.tr());
          }
        }
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                AppConstants.archiveDeviceFolders.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _Option(
              icon: Icons.manage_search_rounded,
              title: AppConstants.archiveSearchDevice.tr(),
              subtitle: AppConstants.archiveSearchDeviceSubtitle.tr(),
              onTap: () => open(
                () => documentsService.scanAllDeviceDocuments(
                  title: AppConstants.archiveAllDeviceDocuments.tr(),
                ),
              ),
            ),
            const Divider(indent: 20, endIndent: 20),
            for (final folder in snapshot.deviceFolders)
              _Option(
                icon: _folderIcon(folder.id),
                title: deviceFolderTitle(folder),
                subtitle: folder.isLinked
                    ? AppConstants.archiveDeviceFolderCount.tr(
                        namedArgs: {'count': '${folder.itemCount}'},
                      )
                    : AppConstants.archiveSelectFolder.tr(),
                onTap: () => open(
                  () => documentsService.openDeviceFolder(
                    folder,
                    folderTitle: deviceFolderTitle(folder),
                    dialogTitle: AppConstants.archiveSelectFolder.tr(),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

String deviceFolderTitle(DeviceFolder folder) {
  return switch (folder.id) {
    'downloads' => AppConstants.archiveDeviceFolderDownloads.tr(),
    'documents' => AppConstants.archiveDeviceFolderDocuments.tr(),
    'whatsapp' => AppConstants.archiveDeviceFolderWhatsapp.tr(),
    'scans' => AppConstants.archiveDeviceFolderScans.tr(),
    'drive' => AppConstants.archiveDeviceFolderDrive.tr(),
    'screenshots' => AppConstants.archiveDeviceFolderScreenshots.tr(),
    _ => folder.title,
  };
}

IconData _folderIcon(String id) {
  return switch (id) {
    'downloads' => Icons.download_outlined,
    'whatsapp' => Icons.chat_outlined,
    'scans' => Icons.document_scanner_outlined,
    'drive' => Icons.cloud_outlined,
    'screenshots' => Icons.screenshot_outlined,
    _ => Icons.folder_outlined,
  };
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: AppTheme.mutedText, fontSize: 12.5),
            ),
      onTap: onTap,
    );
  }
}
