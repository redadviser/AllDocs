import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/app_constants.dart';
import '../../common/document_actions.dart' show showSnack;
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import '../auth/security_gate.dart';

/// "Forgot the hidden albums PIN": a code sent to the account's email, a
/// 24-hour wait (with a warning email that can cancel it), then a new PIN.
/// Pops with true once the new PIN is set.
class HiddenPinResetScreen extends StatefulWidget {
  const HiddenPinResetScreen({super.key});

  @override
  State<HiddenPinResetScreen> createState() => _HiddenPinResetScreenState();
}

class _HiddenPinResetScreenState extends State<HiddenPinResetScreen> {
  final _code = TextEditingController();
  HiddenPinResetStatus? _status;
  String _email = '';
  bool _busy = false;
  bool _failed = false;
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // The countdown, and the switch to "ready" when the wait ends.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final readyAt = _status?.readyAt;
      if (_status?.state == HiddenPinResetState.waiting &&
          readyAt != null &&
          !readyAt.isAfter(DateTime.now())) {
        _load();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final email = await AuthService.email() ?? '';
    try {
      final status = await HiddenPinResetService.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _email = email;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _run(Future<HiddenPinResetStatus?> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await work();
      if (mounted && status != null) setState(() => _status = status);
    } on HiddenPinResetException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.problem) {
          HiddenPinResetProblem.wrongCode => AppConstants.hiddenResetWrong.tr(
            namedArgs: {'count': '${error.attemptsLeft ?? 0}'},
          ),
          HiddenPinResetProblem.expired => AppConstants.hiddenResetExpired.tr(),
          HiddenPinResetProblem.tooManyAttempts =>
            AppConstants.hiddenResetTooManyAttempts.tr(),
          HiddenPinResetProblem.tooManyRequests =>
            AppConstants.hiddenResetTooManyRequests.tr(),
          HiddenPinResetProblem.notReady || HiddenPinResetProblem.unavailable =>
            AppConstants.hiddenResetFailed.tr(),
        };
      });
      // An expired or locked code: back to asking for a new one.
      if (error.problem == HiddenPinResetProblem.expired ||
          error.problem == HiddenPinResetProblem.tooManyAttempts) {
        _code.clear();
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() {
    _code.clear();
    return HiddenPinResetService.requestCode(
      language: context.locale.languageCode,
    );
  });

  Future<void> _verify() => _run(
    () => HiddenPinResetService.verify(
      _code.text.trim(),
      language: context.locale.languageCode,
    ),
  );

  Future<void> _cancel() => _run(() async {
    await HiddenPinResetService.cancel();
    return HiddenPinResetService.status();
  });

  Future<void> _createPin() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HiddenAlbumsPinScreen(
          create: true,
          // The server's go-ahead, right before the new PIN is saved.
          beforeSave: () async {
            try {
              await HiddenPinResetService.complete();
              return true;
            } catch (_) {
              return false;
            }
          },
        ),
      ),
    );
    if (created != true || !mounted) return;
    showSnack(context, AppConstants.hiddenResetDone.tr());
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
              child: Row(
                children: [
                  BackButton(onPressed: () => Navigator.of(context).pop(false)),
                  Expanded(
                    child: Text(
                      AppConstants.hiddenResetTitle.tr(),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: status == null
                  ? Center(
                      child: _failed
                          ? TextButton(
                              onPressed: _load,
                              child: Text(AppConstants.hiddenResetFailed.tr()),
                            )
                          : const CircularProgressIndicator(),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                      children: [
                        const _Badge(),
                        const SizedBox(height: 20),
                        ..._body(status),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.destructive),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(HiddenPinResetStatus status) {
    final email = _maskEmail(_email);
    final spinner = const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    switch (status.state) {
      case HiddenPinResetState.none:
        return [
          if (status.cancelled) ...[
            _Note(
              icon: Icons.info_outline_rounded,
              text: AppConstants.hiddenResetCancelledNote.tr(),
            ),
            const SizedBox(height: 16),
          ],
          _Text(AppConstants.hiddenResetIntro.tr()),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _sendCode,
            icon: _busy ? spinner : const Icon(Icons.mail_outline_rounded),
            label: Text(
              AppConstants.hiddenResetSend.tr(namedArgs: {'email': email}),
            ),
          ),
        ];
      case HiddenPinResetState.codeSent:
        return [
          _Text(
            AppConstants.hiddenResetCodeHint.tr(namedArgs: {'email': email}),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 10,
            ),
            onChanged: (value) {
              setState(() {});
              if (value.length == 6 && !_busy) _verify();
            },
            decoration: InputDecoration(
              labelText: AppConstants.hiddenResetCodeLabel.tr(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || _code.text.length != 6 ? null : _verify,
            child: _busy ? spinner : Text(AppConstants.hiddenResetConfirm.tr()),
          ),
          TextButton(
            onPressed: _busy ? null : _sendCode,
            child: Text(AppConstants.hiddenResetResend.tr()),
          ),
        ];
      case HiddenPinResetState.waiting:
        final readyAt = status.readyAt ?? DateTime.now();
        final left = readyAt.difference(DateTime.now());
        final date = DateFormat.MMMd(
          context.locale.toString(),
        ).add_Hm().format(readyAt);
        return [
          Center(
            child: Text(
              AppConstants.hiddenResetWaitingTitle.tr(),
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _Text(
            AppConstants.hiddenResetWaitingBody.tr(namedArgs: {'date': date}),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppConstants.hiddenResetRemaining.tr(
                      namedArgs: {'time': _duration(left)},
                    ),
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _busy ? null : _cancel,
            icon: const Icon(Icons.close_rounded),
            label: Text(AppConstants.hiddenResetCancel.tr()),
          ),
        ];
      case HiddenPinResetState.ready:
        return [
          Center(
            child: Text(
              AppConstants.hiddenResetReadyTitle.tr(),
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _Text(AppConstants.hiddenResetReadyBody.tr()),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _createPin,
            icon: const Icon(Icons.pin_outlined),
            label: Text(AppConstants.hiddenResetCreate.tr()),
          ),
          TextButton(
            onPressed: _busy ? null : _cancel,
            child: Text(AppConstants.hiddenResetCancel.tr()),
          ),
        ];
    }
  }

  static String _duration(Duration left) {
    final minutes = left.isNegative ? 0 : (left.inSeconds / 60).ceil();
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return hours > 0
        ? '$hours h ${rest.toString().padLeft(2, '0')} min'
        : '$rest min';
  }

  /// a••••@gmail.com
  static String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 1) return email;
    return '${email[0]}${'•' * (at - 1).clamp(3, 6)}${email.substring(at)}';
  }
}

class _Badge extends StatelessWidget {
  const _Badge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.premium.withValues(alpha: 0.18),
          border: Border.all(color: AppTheme.premium.withValues(alpha: 0.4)),
        ),
        child: const Icon(
          Icons.lock_reset_rounded,
          color: AppTheme.premium,
          size: 32,
        ),
      ),
    );
  }
}

class _Text extends StatelessWidget {
  const _Text(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppTheme.mutedText, height: 1.5),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
  }
}
