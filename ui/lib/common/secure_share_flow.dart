import 'dart:io';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../services/watermark_overlay.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'app_sheet.dart';
import 'document_actions.dart' show showSnack;
import 'pdf_tools_flow.dart' show isPdfDocument;
import 'plan_prompts.dart';

/// Shares [document] behind a secure link (Vault): asks how (validity,
/// code, number of opens, watermark), uploads it and offers the link.
/// Returns whether a link was made.
Future<bool> shareWithSecureLink(
  BuildContext context,
  DocumentsService documentsService,
  DocumentFile document,
) async {
  if (!PlanService.current.value.has(PlanFeature.secureSharing)) {
    await showPlansPrompt(
      context,
      title: AppConstants.sharesTitle.tr(),
      message: AppConstants.sharesLocked.tr(),
    );
    return false;
  }
  final created = await showOptionsSheet<({SecureShare share, String? code})>(
    context: context,
    builder: (_) => _SecureShareSheet(
      documentsService: documentsService,
      document: document,
    ),
  );
  if (created == null || !context.mounted) return false;
  await showOptionsSheet<void>(
    context: context,
    builder: (_) => _ShareReadySheet(share: created.share, code: created.code),
  );
  return true;
}

/// Opens the system share sheet with [share]'s link and a line about it.
Future<void> shareSecureLink(BuildContext context, SecureShare share) async {
  final url = share.url;
  if (url == null) {
    showSnack(context, AppConstants.sharesLinkUnknown.tr());
    return;
  }
  final date = DateFormat.yMMMd(
    context.locale.toString(),
  ).format(share.expiresAt);
  await SecurityLockService.withoutAutoLock(
    () => SharePlus.instance.share(
      ShareParams(
        text: AppConstants.sharesShareText.tr(
          namedArgs: {'title': share.title, 'date': date, 'url': url},
        ),
      ),
    ),
  );
}

class _SecureShareSheet extends StatefulWidget {
  const _SecureShareSheet({
    required this.documentsService,
    required this.document,
  });

  final DocumentsService documentsService;
  final DocumentFile document;

  @override
  State<_SecureShareSheet> createState() => _SecureShareSheetState();
}

class _SecureShareSheetState extends State<_SecureShareSheet> {
  static const _dayChoices = [1, 7, 30];
  static const _viewChoices = <int?>[null, 1, 5];
  static const _presets = [
    AppConstants.pdfPresetRent,
    AppConstants.pdfPresetBank,
    AppConstants.pdfPresetJob,
    AppConstants.pdfPresetInsurance,
  ];

  final _purpose = TextEditingController();
  int _days = 7;
  int? _maxViews;
  bool _withCode = true;
  bool _watermark = false;
  bool _working = false;

  bool get _canWatermark =>
      isPdfDocument(widget.document) ||
      widget.document.type == DocumentType.image;

  @override
  void dispose() {
    _purpose.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _working = true);
    final document = widget.document;
    final language = context.locale.languageCode;
    File? temporary;
    try {
      var file = File(document.localPath!);
      var fileName = document.fileName;
      if (_watermark) {
        final text = AppConstants.pdfWatermarkText.tr(
          namedArgs: {
            'purpose': _purpose.text.trim(),
            'date': DateFormat('MM/yyyy').format(DateTime.now()),
          },
        );
        fileName =
            '${document.title} (${AppConstants.pdfWatermarkTitle.tr()}).pdf'
                .replaceAll('/', '-');
        file = temporary = await widget.documentsService.watermarkedCopy(
          document,
          overlay: (width, height) => renderWatermarkOverlay(
            text,
            pageWidth: width,
            pageHeight: height,
          ),
          fileName: fileName,
        );
      }
      final random = Random.secure();
      final code = _withCode
          ? List.generate(6, (_) => random.nextInt(10)).join()
          : null;
      final share = await SecureSharesService.create(
        file: file,
        title: document.title,
        fileName: fileName,
        days: _days,
        code: code,
        maxViews: _maxViews,
        language: language,
      );
      if (mounted) Navigator.of(context).pop((share: share, code: code));
    } on SecureShareException catch (error) {
      if (!mounted) return;
      setState(() => _working = false);
      showSnack(context, switch (error.problem) {
        SecureShareProblem.notIncluded => AppConstants.sharesLocked.tr(),
        SecureShareProblem.tooBig => AppConstants.sharesTooBig.tr(),
        SecureShareProblem.badType => AppConstants.sharesBadType.tr(),
        SecureShareProblem.unavailable => AppConstants.sharesFailed.tr(),
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
      showSnack(context, AppConstants.sharesFailed.tr());
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_watermark || _purpose.text.trim().isNotEmpty;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(color: AppTheme.mutedText)),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppConstants.sharesTitle.tr(),
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.document.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppConstants.sharesIntro.tr(),
              style: const TextStyle(color: AppTheme.mutedText, height: 1.4),
            ),
            const SizedBox(height: 18),
            label(AppConstants.sharesValidFor.tr()),
            Wrap(
              spacing: 8,
              children: [
                for (final days in _dayChoices)
                  ChoiceChip(
                    label: Text(
                      days == 1
                          ? AppConstants.sharesOneDay.tr()
                          : AppConstants.sharesDays.tr(
                              namedArgs: {'count': '$days'},
                            ),
                    ),
                    selected: _days == days,
                    onSelected: (_) => setState(() => _days = days),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            label(AppConstants.sharesViews.tr()),
            Wrap(
              spacing: 8,
              children: [
                for (final views in _viewChoices)
                  ChoiceChip(
                    label: Text(switch (views) {
                      null => AppConstants.sharesViewsUnlimited.tr(),
                      1 => AppConstants.sharesViewsOnce.tr(),
                      _ => AppConstants.sharesViewsCount.tr(
                        namedArgs: {'count': '$views'},
                      ),
                    }),
                    selected: _maxViews == views,
                    onSelected: (_) => setState(() => _maxViews = views),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _withCode,
              onChanged: (value) => setState(() => _withCode = value),
              title: Text(AppConstants.sharesCode.tr()),
              subtitle: Text(
                AppConstants.sharesCodeHint.tr(),
                style: const TextStyle(color: AppTheme.mutedText),
              ),
            ),
            if (_canWatermark) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _watermark,
                onChanged: (value) => setState(() => _watermark = value),
                title: Text(AppConstants.sharesWatermark.tr()),
              ),
              if (_watermark) ...[
                TextField(
                  controller: _purpose,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: AppConstants.sharesWatermarkHint.tr(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final preset in _presets)
                      ActionChip(
                        label: Text(preset.tr()),
                        onPressed: () =>
                            setState(() => _purpose.text = preset.tr()),
                      ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: ready && !_working ? _create : null,
              icon: _working
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_rounded),
              label: Text(AppConstants.sharesCreate.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareReadySheet extends StatelessWidget {
  const _ShareReadySheet({required this.share, this.code});

  final SecureShare share;
  final String? code;

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showSnack(context, AppConstants.sharesCopied.tr());
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.yMMMd(
      context.locale.toString(),
    ).format(share.expiresAt);
    final code = this.code;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.success.withValues(alpha: 0.15),
                  ),
                  child: const Icon(
                    Icons.link_rounded,
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppConstants.sharesCreatedTitle.tr(),
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        AppConstants.sharesCreatedBody.tr(
                          namedArgs: {'date': date},
                        ),
                        style: const TextStyle(color: AppTheme.mutedText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Material(
              color: AppTheme.surfaceStrong,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _copy(context, share.url ?? ''),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          share.url ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.text),
                        ),
                      ),
                      const Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: AppTheme.mutedText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (code != null) ...[
              const SizedBox(height: 14),
              Text(
                AppConstants.sharesCodeLabel.tr(),
                style: const TextStyle(color: AppTheme.mutedText),
              ),
              const SizedBox(height: 6),
              Material(
                color: AppTheme.surfaceStrong,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _copy(context, code),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${code.substring(0, 3)} ${code.substring(3)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppTheme.text,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: AppTheme.mutedText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      AppConstants.sharesCodeSeparately.tr(),
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => shareSecureLink(context, share),
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(AppConstants.sharesShareLink.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
