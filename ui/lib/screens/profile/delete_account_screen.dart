import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/app_constants.dart';
import '../../common/document_actions.dart' show showSnack;
import '../../services/services.dart';
import '../../theme/app_theme.dart';

/// Profile › Account › Delete account: what goes and what stays, keeping
/// the documents first (export), then an email whose link opens the web
/// page where the deletion is confirmed — the same page Google Play links
/// to for people without the app.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, required this.documentsService});

  final DocumentsService documentsService;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _sending = false;
  bool _exporting = false;
  String? _sentTo;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final result = await widget.documentsService.exportDocuments(
        dialogTitle: AppConstants.profileExportPickerTitle.tr(),
      );
      if (!mounted) return;
      showSnack(
        context,
        result.count == 0 || result.path == null
            ? AppConstants.profileExportEmpty.tr()
            : AppConstants.profileExportDone.tr(
                namedArgs: {'count': '${result.count}', 'path': result.path!},
              ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _sendEmail() async {
    setState(() => _sending = true);
    try {
      final email = await AuthService.requestAccountDeletion(
        language: context.locale.languageCode,
      );
      if (mounted) setState(() => _sentTo = email);
    } catch (_) {
      if (mounted) showSnack(context, AppConstants.profileDeleteFailed.tr());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _manageSubscription() async {
    final uri = Uri.parse(
      Platform.isIOS
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final subscribed = !PlanService.current.value.isFree;
    final spinner = const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
              child: Row(
                children: [
                  const BackButton(),
                  Expanded(
                    child: Text(
                      AppConstants.profileDeleteAccount.tr(),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Text(
                    AppConstants.profileDeleteIntro.tr(),
                    style: const TextStyle(
                      color: AppTheme.mutedText,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _ListCard(
                    title: AppConstants.profileDeleteGoes.tr(),
                    color: AppTheme.destructive,
                    icon: Icons.delete_forever_outlined,
                    items: [
                      AppConstants.profileDeleteGoesAccount.tr(),
                      AppConstants.profileDeleteGoesServer.tr(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _ListCard(
                    title: AppConstants.profileDeleteStays.tr(),
                    color: AppTheme.success,
                    icon: Icons.phone_android_rounded,
                    items: [
                      AppConstants.profileDeleteStaysPhone.tr(),
                      AppConstants.profileDeleteStaysBackups.tr(),
                    ],
                  ),
                  if (subscribed) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.warning.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppConstants.profileDeleteSubscription.tr(),
                            style: const TextStyle(
                              color: AppTheme.text,
                              height: 1.4,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _manageSubscription,
                              child: Text(
                                AppConstants.profileDeleteManageSubscription
                                    .tr(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _Step(
                    title: AppConstants.profileDeleteStepExport.tr(),
                    hint: AppConstants.profileDeleteStepExportHint.tr(),
                    child: OutlinedButton.icon(
                      onPressed: _exporting ? null : _export,
                      icon: _exporting
                          ? spinner
                          : const Icon(Icons.ios_share_rounded),
                      label: Text(AppConstants.profileExportDocuments.tr()),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _Step(
                    title: AppConstants.profileDeleteStepEmail.tr(),
                    hint: AppConstants.profileDeleteStepEmailHint.tr(),
                    child: _sentTo == null
                        ? FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.destructive,
                            ),
                            onPressed: _sending ? null : _sendEmail,
                            icon: _sending
                                ? spinner
                                : const Icon(Icons.mail_outline_rounded),
                            label: Text(AppConstants.profileDeleteSend.tr()),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.success.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.mark_email_read_outlined,
                                      color: AppTheme.success,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        AppConstants.profileDeleteSent.tr(
                                          namedArgs: {'email': _sentTo!},
                                        ),
                                        style: const TextStyle(
                                          color: AppTheme.text,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: _sending ? null : _sendEmail,
                                child: Text(
                                  AppConstants.profileDeleteResend.tr(),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.color,
    required this.icon,
    required this.items,
  });

  final String title;
  final Color color;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '•  ',
                    style: TextStyle(color: AppTheme.mutedText),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: AppTheme.text,
                        height: 1.35,
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
}

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.hint, required this.child});

  final String title;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(hint, style: const TextStyle(color: AppTheme.mutedText)),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}
