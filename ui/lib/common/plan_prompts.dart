import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/profile/plans_screen.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'zip_preview_sheet.dart' show formatBytes;

/// Runs an import; one that doesn't fit in the plan's space explains why
/// and offers the plans instead of failing silently.
Future<ImportResult> guardStorage(
  BuildContext context,
  Future<ImportResult> Function() import,
) async {
  try {
    return await import();
  } on StorageFullException catch (error) {
    if (context.mounted) await showStorageFullDialog(context, error);
    return ImportResult.empty;
  }
}

Future<void> showStorageFullDialog(
  BuildContext context,
  StorageFullException error,
) {
  final summary = error.summary;
  final plan = PlanService.current.value;
  final message = error.neededBytes > 0
      ? AppConstants.plansStorageFullMessage.tr(
          namedArgs: {
            'needed': formatBytes(error.neededBytes),
            'free': formatBytes(summary.freeBytes),
            'limit': formatBytes(summary.limitBytes),
          },
        )
      : AppConstants.plansStorageFullMessageUnknown.tr(
          namedArgs: {'limit': formatBytes(summary.limitBytes)},
        );
  return showPlansPrompt(
    context,
    title: AppConstants.plansStorageFullTitle.tr(
      namedArgs: {'plan': plan.name},
    ),
    message: message,
    summary: summary,
  );
}

/// "This needs another plan": a short reason, then the plans on request.
Future<void> showPlansPrompt(
  BuildContext context, {
  required String title,
  required String message,
  StorageSummary? summary,
}) async {
  final seePlans = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppTheme.surface,
      icon: const Icon(
        Icons.workspace_premium_rounded,
        color: AppTheme.premium,
        size: 32,
      ),
      title: Text(title),
      content: Text(
        message,
        style: const TextStyle(color: AppTheme.mutedText, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(AppConstants.plansNotNow.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(AppConstants.plansSeePlans.tr()),
        ),
      ],
    ),
  );
  if (seePlans == true && context.mounted) {
    await openPlansScreen(context, summary: summary);
  }
}
