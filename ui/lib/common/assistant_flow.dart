import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'app_sheet.dart';
import 'document_actions.dart' show showSnack;
import 'plan_prompts.dart';

/// Vault includes the assistant, and the first time the user agrees to
/// what it sends. False when either isn't the case (and it was explained).
Future<bool> ensureAssistantAllowed(BuildContext context) async {
  if (!PlanService.current.value.has(PlanFeature.aiAssistant)) {
    await showPlansPrompt(
      context,
      title: AppConstants.assistantTitle.tr(),
      message: AppConstants.assistantLocked.tr(),
    );
    return false;
  }
  if (await AssistantService.hasConsent()) return true;
  if (!context.mounted) return false;
  final agreed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppTheme.surface,
      icon: Icon(Icons.auto_awesome_rounded, color: AppTheme.accent, size: 30),
      title: Text(AppConstants.assistantConsentTitle.tr()),
      content: Text(
        AppConstants.assistantConsentMessage.tr(),
        style: const TextStyle(color: AppTheme.mutedText, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(AppConstants.commonCancel.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(AppConstants.assistantConsentAccept.tr()),
        ),
      ],
    ),
  );
  if (agreed != true) return false;
  await AssistantService.giveConsent();
  return true;
}

String assistantProblemMessage(AssistantProblem problem) => switch (problem) {
  AssistantProblem.notIncluded => AppConstants.assistantLocked,
  AssistantProblem.allowanceUsed => AppConstants.assistantAllowanceUsed,
  AssistantProblem.declined => AppConstants.assistantDeclined,
  AssistantProblem.unavailable => AppConstants.assistantUnavailable,
}.tr();

/// Runs [work] behind a "Reading your documents…" dialog; problems are
/// explained and come back as null.
Future<T?> _withProgress<T>(
  BuildContext context,
  Future<T> Function() work,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppTheme.surface,
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(AppConstants.assistantThinking.tr())),
          ],
        ),
      ),
    ),
  );
  try {
    final result = await work();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return result;
  } on AssistantException catch (error) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showSnack(context, assistantProblemMessage(error.problem));
    }
  } catch (_) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showSnack(context, AppConstants.assistantUnavailable.tr());
    }
  }
  return null;
}

Future<bool> _readyFor(BuildContext context, DocumentFile document) async {
  if (!await ensureAssistantAllowed(context) || !context.mounted) return false;
  if (!AssistantService.canRead(document)) {
    showSnack(context, AppConstants.assistantNoText.tr());
    return false;
  }
  return true;
}

/// A contract or official document in plain words: what it is, what
/// matters, what can catch you out, and its dates.
Future<void> summarizeWithAssistant(
  BuildContext context,
  DocumentFile document,
) async {
  if (!await _readyFor(context, document) || !context.mounted) return;
  final language = context.locale.languageCode;
  final summary = await _withProgress(
    context,
    () => AssistantService.summarize(document, language: language),
  );
  if (summary == null || !context.mounted) return;
  await showOptionsSheet<void>(
    context: context,
    builder: (_) => _SummarySheet(document: document, summary: summary),
  );
}

/// The details worth keeping from a document; name, tags and expiry date
/// can be saved on it (the date sets its reminder).
Future<void> extractWithAssistant(
  BuildContext context,
  DocumentsService documentsService,
  DocumentFile document,
) async {
  if (!await _readyFor(context, document) || !context.mounted) return;
  final language = context.locale.languageCode;
  final fields = await _withProgress(
    context,
    () => AssistantService.extract(document, language: language),
  );
  if (fields == null || !context.mounted) return;
  await showOptionsSheet<void>(
    context: context,
    builder: (_) => _FieldsSheet(
      documentsService: documentsService,
      document: document,
      fields: fields,
    ),
  );
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.auto_awesome_rounded, color: AppTheme.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.mutedText),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummarySheet extends StatelessWidget {
  const _SummarySheet({required this.document, required this.summary});

  final DocumentFile document;
  final AssistantSummary summary;

  @override
  Widget build(BuildContext context) {
    Widget section(String title, List<String> items, {Color? color}) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                color: color ?? AppTheme.mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 10),
                      child: Icon(
                        Icons.circle,
                        size: 6,
                        color: color ?? AppTheme.primarySoft,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: AppTheme.text,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    final dateFormat = DateFormat.yMMMd(context.locale.toString());
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetTitle(
              title: AppConstants.assistantSummaryTitle.tr(),
              subtitle: document.title,
            ),
            const SizedBox(height: 14),
            Text(
              summary.summary,
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 15,
                height: 1.45,
              ),
            ),
            section(AppConstants.assistantKeyPoints.tr(), summary.keyPoints),
            section(
              AppConstants.assistantWatchOut.tr(),
              summary.watchOut,
              color: AppTheme.warning,
            ),
            section(AppConstants.assistantDates.tr(), [
              for (final item in summary.dates)
                '${dateFormat.format(item.date)} — ${item.label}',
            ]),
          ],
        ),
      ),
    );
  }
}

class _FieldsSheet extends StatefulWidget {
  const _FieldsSheet({
    required this.documentsService,
    required this.document,
    required this.fields,
  });

  final DocumentsService documentsService;
  final DocumentFile document;
  final AssistantFields fields;

  @override
  State<_FieldsSheet> createState() => _FieldsSheetState();
}

class _FieldsSheetState extends State<_FieldsSheet> {
  late bool _title =
      widget.fields.suggestedTitle.isNotEmpty &&
      widget.fields.suggestedTitle != widget.document.title;
  late bool _tags = widget.fields.suggestedTags.any(
    (tag) => !widget.document.tags.contains(tag),
  );
  late bool _expiry =
      widget.fields.expiryDate != null &&
      widget.fields.expiryDate != widget.document.validityDate;
  bool _saving = false;

  Future<void> _apply() async {
    setState(() => _saving = true);
    final fields = widget.fields;
    await widget.documentsService.updateDocument(
      widget.document.id,
      title: _title ? fields.suggestedTitle : null,
      tags: _tags
          ? {...widget.document.tags, ...fields.suggestedTags}.toList()
          : null,
      validityDate: _expiry ? fields.expiryDate : null,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    showSnack(context, AppConstants.assistantApplied.tr());
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.fields;
    final dateFormat = DateFormat.yMMMd(context.locale.toString());
    final details = <(String, String)>[
      if (fields.holderName case final value?)
        (AppConstants.assistantFieldHolder.tr(), value),
      if (fields.documentNumber case final value?)
        (AppConstants.assistantFieldNumber.tr(), value),
      if (fields.nif case final value?)
        (AppConstants.assistantFieldNif.tr(), value),
      if (fields.iban case final value?)
        (AppConstants.assistantFieldIban.tr(), value),
      if (fields.policyNumber case final value?)
        (AppConstants.assistantFieldPolicy.tr(), value),
      if (fields.issueDate case final value?)
        (AppConstants.assistantFieldIssue.tr(), dateFormat.format(value)),
      if (fields.amount case final value?)
        (
          AppConstants.assistantFieldAmount.tr(),
          NumberFormat.simpleCurrency(
            locale: context.locale.toString(),
            name: fields.currency ?? 'EUR',
          ).format(value),
        ),
    ];
    final canSave = _title || _tags || _expiry;
    final offers =
        fields.suggestedTitle.isNotEmpty ||
        fields.suggestedTags.isNotEmpty ||
        fields.expiryDate != null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _SheetTitle(
                title: AppConstants.assistantFieldsTitle.tr(),
                subtitle: widget.document.title,
              ),
            ),
            const SizedBox(height: 10),
            if (!offers && details.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  AppConstants.assistantNothingFound.tr(),
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              ),
            if (offers) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                child: Text(
                  AppConstants.assistantApplyHint.tr(),
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              ),
              if (fields.suggestedTitle.isNotEmpty)
                CheckboxListTile(
                  value: _title,
                  onChanged: (value) => setState(() => _title = value!),
                  title: Text(AppConstants.assistantFieldTitle.tr()),
                  subtitle: Text(fields.suggestedTitle),
                ),
              if (fields.suggestedTags.isNotEmpty)
                CheckboxListTile(
                  value: _tags,
                  onChanged: (value) => setState(() => _tags = value!),
                  title: Text(AppConstants.assistantFieldTags.tr()),
                  subtitle: Text(
                    fields.suggestedTags.map((tag) => '#$tag').join('  '),
                  ),
                ),
              if (fields.expiryDate case final expiry?)
                CheckboxListTile(
                  value: _expiry,
                  onChanged: (value) => setState(() => _expiry = value!),
                  title: Text(AppConstants.assistantFieldExpiry.tr()),
                  subtitle: Text(dateFormat.format(expiry)),
                ),
            ],
            if (details.isNotEmpty) ...[
              const Divider(height: 20),
              for (final (label, value) in details)
                ListTile(
                  dense: true,
                  title: Text(
                    label,
                    style: const TextStyle(color: AppTheme.mutedText),
                  ),
                  subtitle: Text(
                    value,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(Icons.copy_rounded, size: 18),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    showSnack(context, AppConstants.assistantCopied.tr());
                  },
                ),
            ],
            if (offers) ...[
              const SizedBox(height: 10),
              FilledButton(
                onPressed: canSave && !_saving ? _apply : null,
                child: Text(AppConstants.assistantApply.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
