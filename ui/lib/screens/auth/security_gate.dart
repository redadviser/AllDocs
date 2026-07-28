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
  String _pin = '';
  String _firstPin = '';
  bool _confirming = false;
  bool _enableBiometrics = false;
  bool _submitting = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    return _SecurityShell(
      greeting: widget.greeting,
      title: _confirming
          ? AppConstants.securityConfirmPin.tr()
          : AppConstants.securityCreatePinTitle.tr(),
      subtitle: AppConstants.securityCreatePinSubtitle.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinDots(length: _pin.length, hasError: _errorText != null),
          const SizedBox(height: 18),
          Text(
            _confirming
                ? AppConstants.securityConfirmPin.tr()
                : AppConstants.securityPin.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (widget.canUseBiometrics) ...[
            const SizedBox(height: 16),
            _BiometricChoice(
              value: _enableBiometrics,
              onChanged: (value) => setState(() => _enableBiometrics = value),
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 14),
            Text(
              _errorText!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.destructive,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _PinKeyboard(
            enabled: !_submitting,
            onDigit: _addDigit,
            onDelete: _deleteDigit,
          ),
        ],
      ),
    );
  }

  void _addDigit(String digit) {
    if (_submitting || _pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += digit;
      _errorText = null;
    });

    if (_pin.length == 4) {
      Future<void>.delayed(const Duration(milliseconds: 140), _advance);
    }
  }

  void _deleteDigit() {
    if (_submitting || _pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _errorText = null;
    });
  }

  Future<void> _advance() async {
    if (!mounted || _pin.length != 4) return;
    if (!_confirming) {
      setState(() {
        _firstPin = _pin;
        _pin = '';
        _confirming = true;
      });
      return;
    }

    if (_pin != _firstPin) {
      HapticFeedback.mediumImpact();
      setState(() {
        _pin = '';
        _errorText = AppConstants.securityPinMismatch.tr();
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });
    await widget.onCreated(_pin, _enableBiometrics && widget.canUseBiometrics);
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
  String _pin = '';
  bool _submitting = false;
  String? _errorText;

  bool get _showBiometrics =>
      widget.biometricEnabled && widget.canUseBiometrics;

  @override
  Widget build(BuildContext context) {
    return _SecurityShell(
      greeting: widget.greeting,
      title: AppConstants.securityUnlockTitle.tr(),
      subtitle: AppConstants.securityUnlockSubtitle.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinDots(length: _pin.length, hasError: _errorText != null),
          if (_errorText != null) ...[
            const SizedBox(height: 14),
            Text(
              _errorText!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.destructive,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 22),
          _PinKeyboard(
            enabled: !_submitting,
            biometricEnabled: _showBiometrics,
            onDigit: _addDigit,
            onDelete: _deleteDigit,
            onBiometric: _submitBiometrics,
          ),
        ],
      ),
    );
  }

  void _addDigit(String digit) {
    if (_submitting || _pin.length >= 4) return;
    HapticFeedback.selectionClick();
    final candidate = '$_pin$digit';
    setState(() {
      _pin = candidate;
      _errorText = null;
    });

    if (candidate.length == 4) {
      Future<void>.delayed(
        const Duration(milliseconds: 120),
        () => _submitPin(candidate),
      );
    }
  }

  void _deleteDigit() {
    if (_submitting || _pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _errorText = null;
    });
  }

  Future<void> _submitPin(String pin) async {
    if (pin.length < 4) return;

    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final ok = await widget.onUnlockWithPin(pin);
    if (!mounted) return;
    if (!ok) HapticFeedback.mediumImpact();
    setState(() {
      _submitting = false;
      _errorText = ok ? null : AppConstants.securityInvalidPin.tr();
      if (!ok) _pin = '';
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: const Icon(
                            Icons.folder_copy_rounded,
                            color: AppTheme.primarySoft,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          AppConstants.appTitle.tr(),
                          style: const TextStyle(
                            color: AppTheme.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const _SecurityAvatar(),
                    const SizedBox(height: 18),
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
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: AppTheme.border.withValues(alpha: 0.75),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 28,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: child,
                    ),
                    const SizedBox(height: 16),
                    const _SecurityFootnote(),
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

class _SecurityAvatar extends StatelessWidget {
  const _SecurityAvatar();

  @override
  Widget build(BuildContext context) {
    return Align(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4F9DFF), Color(0xFF12306A)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.26),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'PC',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: 2,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.success,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.background, width: 3),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.length, required this.hasError});

  final int length;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < 4; index++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: index < length ? 18 : 14,
            height: index < length ? 18 : 14,
            decoration: BoxDecoration(
              color: index < length
                  ? (hasError ? AppTheme.destructive : AppTheme.primary)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: hasError ? AppTheme.destructive : AppTheme.primarySoft,
                width: 1.7,
              ),
              boxShadow: index < length
                  ? [
                      BoxShadow(
                        color:
                            (hasError ? AppTheme.destructive : AppTheme.primary)
                                .withValues(alpha: 0.28),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
          ),
          if (index != 3) const SizedBox(width: 16),
        ],
      ],
    );
  }
}

class _BiometricChoice extends StatelessWidget {
  const _BiometricChoice({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: value
              ? AppTheme.primary.withValues(alpha: 0.16)
              : AppTheme.surfaceStrong.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: value ? AppTheme.primary : AppTheme.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.fingerprint_rounded, color: AppTheme.primarySoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppConstants.securityEnableBiometrics.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _PinKeyboard extends StatelessWidget {
  const _PinKeyboard({
    required this.enabled,
    required this.onDigit,
    required this.onDelete,
    this.biometricEnabled = false,
    this.onBiometric,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final bool biometricEnabled;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ]) ...[
          Row(
            children: [
              for (final digit in row) ...[
                Expanded(
                  child: _KeypadButton(
                    label: digit,
                    enabled: enabled,
                    onTap: () => onDigit(digit),
                  ),
                ),
                if (digit != row.last) const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: biometricEnabled
                  ? _KeypadButton(
                      icon: Icons.fingerprint_rounded,
                      semanticLabel: AppConstants.securityUseBiometrics.tr(),
                      enabled: enabled,
                      onTap: onBiometric,
                    )
                  : const SizedBox(height: 58),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KeypadButton(
                label: '0',
                enabled: enabled,
                onTap: () => onDigit('0'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KeypadButton(
                icon: Icons.backspace_outlined,
                semanticLabel: MaterialLocalizations.of(
                  context,
                ).deleteButtonTooltip,
                enabled: enabled,
                onTap: onDelete,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    this.label,
    this.icon,
    this.semanticLabel,
    required this.enabled,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(
            label ?? '',
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          )
        : Icon(icon, color: AppTheme.primarySoft, size: 25);

    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 160),
          child: Container(
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.surfaceStrong.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border.withValues(alpha: 0.7)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SecurityFootnote extends StatelessWidget {
  const _SecurityFootnote();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.offline_bolt_rounded,
          color: AppTheme.success,
          size: 16,
        ),
        const SizedBox(width: 6),
        Text(
          AppConstants.authOffline.tr(),
          style: const TextStyle(
            color: AppTheme.success,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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
