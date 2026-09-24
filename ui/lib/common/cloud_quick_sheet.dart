import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'app_sheet.dart';
import 'backup_flow.dart';
import 'sheet_quick_action.dart';

/// Quick access to the cloud accounts from the gallery header: one tap on
/// a provider browses its files (connecting it first if needed), plus a way
/// into the full Connections page.
Future<void> showCloudQuickSheet(
  BuildContext context,
  DocumentsService documentsService, {
  required void Function(CloudProviderId? provider) onOpenCloud,
}) async {
  final providers = documentsService.cloud.providers;
  final status = <CloudProviderId, String>{};
  for (final provider in providers) {
    status[provider.id] = !provider.isConfigured
        ? AppConstants.cloudNotConfiguredShort.tr()
        : await provider.isConnected()
        ? AppConstants.cloudConnectedShort.tr()
        : AppConstants.cloudTapToConnect.tr();
  }
  if (!context.mounted) return;

  await showOptionsSheet<void>(
    context: context,
    builder: (sheetContext) {
      void open(CloudProviderId? provider) {
        Navigator.of(sheetContext).pop();
        onOpenCloud(provider);
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                AppConstants.connectionsTitle.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final provider in providers)
                    SheetQuickAction(
                      icon: cloudProviderIcon(provider.id),
                      label: _shortName(provider.id),
                      caption: status[provider.id],
                      // Not configured: the Connections page explains it.
                      onTap: () =>
                          open(provider.isConfigured ? provider.id : null),
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.settings_outlined),
              title: Text(AppConstants.connectionsManage.tr()),
              subtitle: Text(
                AppConstants.connectionsSubtitle.tr(),
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 12.5,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => open(null),
            ),
          ],
        ),
      );
    },
  );
}

String _shortName(CloudProviderId id) => switch (id) {
  CloudProviderId.oneDrive => 'OneDrive',
  CloudProviderId.googleDrive => 'Google Drive',
  CloudProviderId.dropbox => 'Dropbox',
};
