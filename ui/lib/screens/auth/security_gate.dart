import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/app_constants.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';

class SecurityGate extends StatefulWidget {
  const SecurityGate({super.key, required this.userName, required this.child});

  final String userName;
  final Widget child;

  @override
  State<SecurityGate> createState() => _SecurityGateState();
}

class _SecurityGateState extends State<SecurityGate> {
  final SecurityLockService _securityLockService = SecurityLockService();
  bool _loading = true;
  bool _unlocked = false;
  bool _hasPin = false;
  bool _biometricEnabled = false;
  bool _canUseBiometrics = false;
  bool _promptedBiometrics = false;

  @override
  void initState() {
    super.initState();
    _loadSecurityState();
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;

    if (_loading) {
      return const _SecurityShell(
        greeting: '',
        title: '',
        subtitle: '',
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final greeting = _securityGreeting(context, widget.userName);
    if (!_hasPin) {
      return PinSetupScreen(
        greeting: greeting,
        canUseBiometrics: _canUseBiometrics,
        onCreated: _createPin,
      );
    }

    return PinUnlockScreen(
      greeting: greeting,
      biometricEnabled: _biometricEnabled,
      canUseBiometrics: _canUseBiometrics,
      onUnlockWithPin: _unlockWithPin,
      onUnlockWithBiometrics: _unlockWithBiometrics,
    );
  }

  Future<void> _loadSecurityState() async {
    final hasPin = await _securityLockService.hasPin();
    final biometricEnabled = await _securityLockService.isBiometricEnabled();
    final canUseBiometrics = await _securityLockService.canUseBiometrics();
    if (!mounted) return;

    setState(() {
      _hasPin = hasPin;
      _biometricEnabled = biometricEnabled;
      _canUseBiometrics = canUseBiometrics;
      _loading = false;
    });

    if (hasPin && biometricEnabled && canUseBiometrics) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_promptedBiometrics) _unlockWithBiometrics();
      });
    }
  }

  Future<void> _createPin(String pin, bool enableBiometrics) async {
    await _securityLockService.setPin(pin);
    if (enableBiometrics) {
      await _securityLockService.setBiometricEnabled(true);
    }
    if (!mounted) return;
    setState(() {
      _hasPin = true;
      _biometricEnabled = enableBiometrics;
      _unlocked = true;
    });
  }

  Future<bool> _unlockWithPin(String pin) async {
    final valid = await _securityLockService.verifyPin(pin);
    if (valid && mounted) setState(() => _unlocked = true);
    return valid;
  }

  Future<bool> _unlockWithBiometrics() async {
    _promptedBiometrics = true;
    final ok = await _securityLockService.authenticateWithBiometrics(
      reason: AppConstants.securityBiometricReason.tr(),
    );
    if (ok && mounted) setState(() => _unlocked = true);
    return ok;
  }
}

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({
    super.key,
    required this.greeting,
    required this.canUseBiometrics,
    required this.onCreated,
  });

  final String greeting;
  final bool canUseBiometrics;
  final Future<void> Function(String pin, bool enableBiometrics) onCreated;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  bool _enableBiometrics = false;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SecurityShell(
      greeting: widget.greeting,
      title: AppConstants.securityCreatePinTitle.tr(),
      subtitle: AppConstants.securityCreatePinSubtitle.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinField(
            controller: _pinController,
            label: AppConstants.securityPin.tr(),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          _PinField(
            controller: _confirmPinController,
            label: AppConstants.securityConfirmPin.tr(),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.canUseBiometrics) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enableBiometrics,
              onChanged: (value) => setState(() => _enableBiometrics = value),
              title: Text(AppConstants.securityEnableBiometrics.tr()),
              secondary: const Icon(Icons.fingerprint_rounded),
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorText!,
              style: const TextStyle(
                color: AppTheme.destructive,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(AppConstants.securitySavePin.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    if (pin.length < 4 || confirmPin.length < 4) {
      setState(() => _errorText = AppConstants.securityPinLength.tr());
      return;
    }
    if (pin != confirmPin) {
      setState(() => _errorText = AppConstants.securityPinMismatch.tr());
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });
    await widget.onCreated(pin, _enableBiometrics && widget.canUseBiometrics);
    if (!mounted) return;
    setState(() => _submitting = false);
  }
}

class PinUnlockScreen extends StatefulWidget {
  const PinUnlockScreen({
    super.key,
    required this.greeting,
    required this.biometricEnabled,
    required this.canUseBiometrics,
    required this.onUnlockWithPin,
    required this.onUnlockWithBiometrics,
  });

  final String greeting;
  final bool biometricEnabled;
  final bool canUseBiometrics;
  final Future<bool> Function(String pin) onUnlockWithPin;
  final Future<bool> Function() onUnlockWithBiometrics;

  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<PinUnlockScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _submitting = false;
  String? _errorText;

  bool get _showBiometrics =>
      widget.biometricEnabled && widget.canUseBiometrics;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SecurityShell(
      greeting: widget.greeting,
      title: AppConstants.securityUnlockTitle.tr(),
      subtitle: AppConstants.securityUnlockSubtitle.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinField(
            controller: _pinController,
            label: AppConstants.securityPin.tr(),
            onSubmitted: (_) => _submitPin(),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorText!,
              style: const TextStyle(
                color: AppTheme.destructive,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _submitting ? null : _submitPin,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(AppConstants.securityUnlock.tr()),
          ),
          if (_showBiometrics) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _submitBiometrics,
              icon: const Icon(Icons.fingerprint_rounded),
              label: Text(AppConstants.securityUseBiometrics.tr()),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submitPin() async {
    if (_pinController.text.trim().length < 4) {
      setState(() => _errorText = AppConstants.securityPinLength.tr());
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final ok = await widget.onUnlockWithPin(_pinController.text.trim());
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _errorText = ok ? null : AppConstants.securityInvalidPin.tr();
    });
  }

  Future<void> _submitBiometrics() async {
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final ok = await widget.onUnlockWithBiometrics();
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _errorText = ok ? null : AppConstants.securityBiometricUnavailable.tr();
    });
  }
}

class _SecurityShell extends StatelessWidget {
  const _SecurityShell({
    required this.greeting,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String greeting;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final showText = greeting.isNotEmpty || title.isNotEmpty;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.background, AppTheme.backgroundBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      child: Container(
                        width: 76,
                        height: 76,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: const Icon(
                          Icons.lock_rounded,
                          color: AppTheme.primarySoft,
                          size: 38,
                        ),
                      ),
                    ),
                    if (showText) ...[
                      Text(
                        greeting,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.primarySoft,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppTheme.border.withValues(alpha: 0.75),
                        ),
                      ),
                      child: child,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    required this.label,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      maxLength: 4,
      onSubmitted: onSubmitted,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        prefixIcon: const Icon(Icons.pin_rounded),
      ),
    );
  }
}

String _securityGreeting(BuildContext context, String name) {
  final hour = DateTime.now().hour;
  final key = hour < 12
      ? AppConstants.securityGreetingMorning
      : hour < 20
      ? AppConstants.securityGreetingAfternoon
      : AppConstants.securityGreetingEvening;
  return key.tr(namedArgs: {'name': name});
}
