import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/profile/plans_screen.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'document_actions.dart';

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
  final free = summary.freeDocuments ?? 0;
  final message = free > 0
      ? AppConstants.plansStorageFullMessage.tr(
          namedArgs: {
            'needed': '${error.neededDocuments}',
            'free': '$free',
            'limit': '${summary.limitDocuments}',
          },
        )
      : AppConstants.plansStorageFullMessageUnknown.tr(
          namedArgs: {'limit': '${summary.limitDocuments}'},
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

/// Files left out of an import for being bigger than the plan allows per
/// document. The top plan has nothing to upgrade to, so it only gets a note.
Future<void> showTooLargeNotice(BuildContext context, int count) {
  final plan = PlanService.current.value;
  final message = AppConstants.plansDocumentTooLargeMessage.tr(
    namedArgs: {
      'count': '$count',
      'plan': plan.name,
      'limit': megabytes(plan.maxDocumentBytes),
    },
  );
  if (plan.id == AppPlan.pro) {
    showSnack(context, message);
    return Future.value();
  }
  return showPlansPrompt(
    context,
    title: AppConstants.plansStorageFullTitle.tr(
      namedArgs: {'plan': plan.name},
    ),
    message: message,
  );
}

String megabytes(int bytes) => '${(bytes / (1024 * 1024)).ceil()} MB';
