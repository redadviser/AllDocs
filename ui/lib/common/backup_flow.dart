import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'app_sheet.dart';
import 'document_actions.dart';

/// Connects [provider] (OAuth in the browser / Google account picker),
/// telling the user how it went. Returns whether it's connected now.
Future<bool> connectCloudProvider(
  BuildContext context,
  CloudProvider provider,
) async {
  if (!provider.isConfigured) {
    showSnack(context, AppConstants.cloudNotConfigured.tr());
    return false;
  }
  try {
    await SecurityLockService.withoutAutoLock(provider.connect);
    if (context.mounted) {
      showSnack(
        context,
        AppConstants.cloudConnected.tr(
          namedArgs: {'provider': provider.displayName},
        ),
      );
    }
    return true;
  } on CloudNotConfiguredException {
    if (context.mounted) {
      showSnack(context, AppConstants.cloudNotConfigured.tr());
    }
  } catch (_) {
    if (context.mounted) {
      showSnack(context, AppConstants.cloudConnectFailed.tr());
    }
  }
  return false;
}

/// "Back up now": asks where (this phone or any cloud, connecting it on the
/// spot if needed), runs the backup and remembers the choice as the
/// default destination (also used by the daily auto-backup).
Future<void> showBackupSheet(
  BuildContext context,
  DocumentsService documentsService,
) async {
  final cloud = documentsService.cloud;
  final connected = {
    for (final provider in await cloud.connectedProviders())
      provider.id: await provider.accountLabel(),
  };
  if (!context.mounted) return;

  final current = AppSettings.backupProvider.value;
  // Wrapped so "this phone" (null) is distinguishable from a dismissed
  // sheet.
  final choice = await showOptionsSheet<({CloudProvider? provider})>(
    context: context,
    builder: (context) {
      Widget tile({
        required IconData icon,
        required String title,
        String? subtitle,
        required bool selected,
        VoidCallback? onTap,
      }) {
        return ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 12.5,
                  ),
                ),
          trailing: selected
              ? Icon(Icons.check_rounded, color: AppTheme.accent)
              : null,
          enabled: onTap != null,
          onTap: onTap,
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                AppConstants.backupSheetTitle.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            tile(
              icon: Icons.phone_android_outlined,
              title: AppConstants.backupThisDevice.tr(),
              selected: current == null,
              onTap: () => Navigator.of(context).pop((provider: null)),
            ),
            for (final provider in cloud.providers)
              tile(
                icon: cloudProviderIcon(provider.id),
                title: provider.displayName,
                subtitle: !provider.isConfigured
                    ? AppConstants.cloudNotConfiguredShort.tr()
                    : connected.containsKey(provider.id)
                    ? (connected[provider.id] ??
                          AppConstants.cloudConnectedShort.tr())
                    : AppConstants.cloudTapToConnect.tr(),
                selected: current == provider.id.name,
                onTap: provider.isConfigured
                    ? () => Navigator.of(context).pop((provider: provider))
                    : null,
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;

  final provider = choice.provider;
  if (provider == null) {
    await AppSettings.setBackupProvider(null);
    if (!context.mounted) return;
    await saveBackupToDevice(context, documentsService);
    return;
  }
  if (!connected.containsKey(provider.id) &&
      !await connectCloudProvider(context, provider)) {
    return;
  }
  await AppSettings.setBackupProvider(provider.id.name);
  if (!context.mounted) return;
  await backupToCloud(context, documentsService, provider);
}

Future<void> backupToCloud(
  BuildContext context,
  DocumentsService documentsService,
  CloudProvider provider,
) async {
  final ok = await _withProgress(
    context,
    AppConstants.backupRunning.tr(),
    () => documentsService.backup.backupToCloud(provider),
  );
  if (!context.mounted) return;
  showSnack(
    context,
    ok
        ? AppConstants.backupDoneTo.tr(
            namedArgs: {'provider': provider.displayName},
          )
        : AppConstants.backupFailed.tr(),
  );
}

Future<void> saveBackupToDevice(
  BuildContext context,
  DocumentsService documentsService,
) async {
  try {
    final path = await SecurityLockService.withoutAutoLock(
      () => documentsService.backup.saveBackupToDevice(
        dialogTitle: AppConstants.backupPickFolder.tr(),
      ),
    );
    if (path != null && context.mounted) {
      showSnack(
        context,
        AppConstants.backupSavedTo.tr(namedArgs: {'path': path}),
      );
    }
  } catch (_) {
    if (context.mounted) showSnack(context, AppConstants.backupFailed.tr());
  }
}

/// Blocks the screen with a spinner while [task] runs — a backup zips and
/// uploads every document, which can take a while.
Future<bool> _withProgress(
  BuildContext context,
  String message,
  Future<void> Function() task,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppTheme.surface,
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    await task();
    return true;
  } catch (_) {
    return false;
  } finally {
    navigator.pop();
  }
}

IconData cloudProviderIcon(CloudProviderId id) => switch (id) {
  CloudProviderId.oneDrive => Icons.cloud_outlined,
  CloudProviderId.googleDrive => Icons.add_to_drive_outlined,
  CloudProviderId.dropbox => Icons.cloud_queue_outlined,
};
