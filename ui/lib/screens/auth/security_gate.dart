import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/app_constants.dart';
import '../../common/user_initials.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';

class SecurityGate extends StatefulWidget {
  /// True while the user is past the PIN / biometrics. Work that must not
  /// happen behind the lock screen (importing a file opened with AllDocs)
  /// waits on this.
  static final unlocked = ValueNotifier<bool>(false);

  /// Completes as soon as [unlocked] is true.
  static Future<void> whenUnlocked() {
    if (unlocked.value) return Future.value();
    final completer = Completer<void>();
    void listener() {
      if (!unlocked.value) return;
      unlocked.removeListener(listener);
      completer.complete();
    }

    unlocked.addListener(listener);
    return completer.future;
  }

  const SecurityGate({
    super.key,
    required this.userName,
    this.avatarUrl,
    required this.child,
  });

  final String userName;
  final String? avatarUrl;
  final Widget child;

  @override
  State<SecurityGate> createState() => _SecurityGateState();
}

class _SecurityGateState extends State<SecurityGate>
    with WidgetsBindingObserver {
  final SecurityLockService _securityLockService = SecurityLockService();
  bool _loading = true;
  bool _unlocked = false;
  // Once the app has been unlocked, later locks cover the app instead of
  // replacing it, so tabs, scroll positions and open sheets survive.
  bool _everUnlocked = false;
  DateTime? _backgroundedAt;
  bool _hasPin = false;
  bool _biometricEnabled = false;
  bool _canUseBiometrics = false;
  bool _promptedBiometrics = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSecurityState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SecurityGate.unlocked.value = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_unlocked || !_hasPin) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!SecurityLockService.autoLockSuspended) {
        _backgroundedAt ??= DateTime.now();
      }
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final leftAt = _backgroundedAt;
    _backgroundedAt = null;
    if (leftAt == null || SecurityLockService.autoLockSuspended) return;
    final minutes = AppSettings.autoLockMinutes.value;
    if (minutes < 0) return;
    if (DateTime.now().difference(leftAt) >= Duration(minutes: minutes)) {
      // Pages, sheets and dialogs opened on top of the app live above this
      // gate in the navigator; close them so nothing shows past the lock.
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() {
        _unlocked = false;
        _promptedBiometrics = false;
      });
      if (_biometricEnabled && _canUseBiometrics) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_unlocked) _unlockWithBiometrics();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build-time sync is enough here: every lock/unlock goes through
    // setState, and listeners only react after the frame.
    if (SecurityGate.unlocked.value != _unlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SecurityGate.unlocked.value = _unlocked;
      });
    }
    if (!_unlocked && !_everUnlocked) return _buildLockScreen(context);
    // Same structure locked or unlocked, so the app below keeps its state.
    return Stack(
      children: [
        Offstage(
          offstage: !_unlocked,
          child: TickerMode(enabled: _unlocked, child: widget.child),
        ),
        if (!_unlocked) Positioned.fill(child: _buildLockScreen(context)),
      ],
    );
  }

  Widget _buildLockScreen(BuildContext context) {
    if (_loading) {
      return _SecurityShell(
        greeting: '',
        title: '',
        subtitle: '',
        userName: widget.userName,
        avatarUrl: widget.avatarUrl,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final greeting = _securityGreeting(context, widget.userName);
    if (!_hasPin) {
      return PinSetupScreen(
        greeting: greeting,
        userName: widget.userName,
        avatarUrl: widget.avatarUrl,
        canUseBiometrics: _canUseBiometrics,
        onCreated: _createPin,
      );
    }

    return PinUnlockScreen(
      greeting: greeting,
      userName: widget.userName,
      avatarUrl: widget.avatarUrl,
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
      _unlocked = _everUnlocked = true;
    });
  }

  Future<bool> _unlockWithPin(String pin) async {
    final valid = await _securityLockService.verifyPin(pin);
    if (valid && mounted) setState(() => _unlocked = _everUnlocked = true);
    return valid;
  }

  Future<bool> _unlockWithBiometrics() async {
    _promptedBiometrics = true;
    final ok = await _securityLockService.authenticateWithBiometrics(
      reason: AppConstants.securityBiometricReason.tr(),
    );
    if (ok && mounted) setState(() => _unlocked = _everUnlocked = true);
    return ok;
  }
}

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({
    super.key,
    required this.greeting,
    required this.userName,
    this.avatarUrl,
    required this.canUseBiometrics,
    required this.onCreated,
  });

  final String greeting;
  final String userName;
  final String? avatarUrl;
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
  int _errorCount = 0;

  @override
  Widget build(BuildContext context) {
    return _SecurityShell(
      greeting: widget.greeting,
      title: _confirming
          ? AppConstants.securityConfirmPin.tr()
          : AppConstants.securityCreatePinTitle.tr(),
      subtitle: AppConstants.securityCreatePinSubtitle.tr(),
      userName: widget.userName,
      avatarUrl: widget.avatarUrl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinDots(
            length: _pin.length,
            hasError: _errorText != null,
            errorCount: _errorCount,
          ),
          _PinMessage(text: _errorText),
          if (widget.canUseBiometrics)
            _BiometricChoice(
              value: _enableBiometrics,
              onChanged: (value) => setState(() => _enableBiometrics = value),
            ),
          const SizedBox(height: 8),
          _PinKeyboard(
            enabled: !_submitting,
            canDelete: _pin.isNotEmpty,
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
        _errorCount++;
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
    required this.userName,
    this.avatarUrl,
    required this.biometricEnabled,
    required this.canUseBiometrics,
    required this.onUnlockWithPin,
    required this.onUnlockWithBiometrics,
  });

  final String greeting;
  final String userName;
  final String? avatarUrl;
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
  int _errorCount = 0;

  bool get _showBiometrics =>
      widget.biometricEnabled && widget.canUseBiometrics;

  @override
  Widget build(BuildContext context) {
    return _SecurityShell(
      greeting: widget.greeting,
      title: '',
      subtitle: AppConstants.securityUnlockSubtitle.tr(),
      userName: widget.userName,
      avatarUrl: widget.avatarUrl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinDots(
            length: _pin.length,
            hasError: _errorText != null,
            errorCount: _errorCount,
          ),
          _PinMessage(text: _errorText),
          const SizedBox(height: 8),
          _PinKeyboard(
            enabled: !_submitting,
            canDelete: _pin.isNotEmpty,
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
      if (!ok) {
        _pin = '';
        _errorCount++;
      }
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

enum _PinChangeStep { current, fresh, confirm }

/// Settings → Security → Change PIN: the current PIN first, then the new
/// one twice. Pops with true once the new PIN is saved.
class PinChangeScreen extends StatefulWidget {
  const PinChangeScreen({super.key, required this.userName, this.avatarUrl});

  final String userName;
  final String? avatarUrl;

  @override
  State<PinChangeScreen> createState() => _PinChangeScreenState();
}

class _PinChangeScreenState extends State<PinChangeScreen> {
  final SecurityLockService _securityLockService = SecurityLockService();
  _PinChangeStep _step = _PinChangeStep.current;
  String _pin = '';
  String _newPin = '';
  bool _submitting = false;
  String? _errorText;
  int _errorCount = 0;

  String get _title => switch (_step) {
    _PinChangeStep.current => AppConstants.securityChangePinCurrent.tr(),
    _PinChangeStep.fresh => AppConstants.securityChangePinNew.tr(),
    _PinChangeStep.confirm => AppConstants.securityChangePinConfirm.tr(),
  };

  @override
  Widget build(BuildContext context) {
    return _SecurityShell(
      greeting: '',
      title: _title,
      subtitle: _step == _PinChangeStep.current
          ? ''
          : AppConstants.securityChangePinSubtitle.tr(),
      userName: widget.userName,
      avatarUrl: widget.avatarUrl,
      onBack: () => Navigator.of(context).pop(false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinDots(
            length: _pin.length,
            hasError: _errorText != null,
            errorCount: _errorCount,
          ),
          _PinMessage(text: _errorText),
          const SizedBox(height: 8),
          _PinKeyboard(
            enabled: !_submitting,
            canDelete: _pin.isNotEmpty,
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
      Future<void>.delayed(const Duration(milliseconds: 120), _advance);
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

  void _fail(String message, {_PinChangeStep? step}) {
    HapticFeedback.mediumImpact();
    setState(() {
      _pin = '';
      _errorText = message;
      _errorCount++;
      _submitting = false;
      if (step != null) _step = step;
    });
  }

  Future<void> _advance() async {
    if (!mounted || _pin.length != 4) return;
    switch (_step) {
      case _PinChangeStep.current:
        setState(() => _submitting = true);
        final valid = await _securityLockService.verifyPin(_pin);
        if (!mounted) return;
        if (!valid) return _fail(AppConstants.securityInvalidPin.tr());
        setState(() {
          _submitting = false;
          _pin = '';
          _step = _PinChangeStep.fresh;
        });
      case _PinChangeStep.fresh:
        setState(() {
          _newPin = _pin;
          _pin = '';
          _step = _PinChangeStep.confirm;
        });
      case _PinChangeStep.confirm:
        // A mismatch starts the new PIN over, so it's chosen again in full.
        if (_pin != _newPin) {
          return _fail(
            AppConstants.securityPinMismatch.tr(),
            step: _PinChangeStep.fresh,
          );
        }
        setState(() => _submitting = true);
        await _securityLockService.setPin(_newPin);
        if (mounted) Navigator.of(context).pop(true);
    }
  }
}

enum _HiddenPinStep { enter, create, confirm }

/// The hidden albums' own PIN: asked before they open, or chosen (twice)
/// the first time an album is hidden. Pops with true once it's right.
class HiddenAlbumsPinScreen extends StatefulWidget {
  const HiddenAlbumsPinScreen({super.key, required this.create});

  /// Choose a new PIN instead of entering the existing one.
  final bool create;

  @override
  State<HiddenAlbumsPinScreen> createState() => _HiddenAlbumsPinScreenState();
}

class _HiddenAlbumsPinScreenState extends State<HiddenAlbumsPinScreen> {
  late _HiddenPinStep _step = widget.create
      ? _HiddenPinStep.create
      : _HiddenPinStep.enter;
  String _pin = '';
  String _newPin = '';
  bool _submitting = false;
  String? _errorText;
  int _errorCount = 0;

  String get _title => switch (_step) {
    _HiddenPinStep.enter => AppConstants.hiddenEnterPin.tr(),
    _HiddenPinStep.create => AppConstants.hiddenCreatePinTitle.tr(),
    _HiddenPinStep.confirm => AppConstants.hiddenConfirmPin.tr(),
  };

  @override
  Widget build(BuildContext context) {
    return _SecurityShell(
      greeting: '',
      title: _title,
      subtitle: _step == _HiddenPinStep.enter
          ? ''
          : AppConstants.hiddenCreatePinSubtitle.tr(),
      userName: '',
      onBack: () => Navigator.of(context).pop(false),
      leading: Align(
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.premium.withValues(alpha: 0.18),
            border: Border.all(color: AppTheme.premium.withValues(alpha: 0.4)),
          ),
          child: const Icon(
            Icons.visibility_off_rounded,
            color: AppTheme.premium,
            size: 32,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinDots(
            length: _pin.length,
            hasError: _errorText != null,
            errorCount: _errorCount,
          ),
          _PinMessage(text: _errorText),
          const SizedBox(height: 8),
          _PinKeyboard(
            enabled: !_submitting,
            canDelete: _pin.isNotEmpty,
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
      Future<void>.delayed(const Duration(milliseconds: 120), _advance);
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

  void _fail(String message, {_HiddenPinStep? step}) {
    HapticFeedback.mediumImpact();
    setState(() {
      _pin = '';
      _errorText = message;
      _errorCount++;
      _submitting = false;
      if (step != null) _step = step;
    });
  }

  Future<void> _advance() async {
    if (!mounted || _pin.length != 4) return;
    setState(() => _submitting = true);
    switch (_step) {
      case _HiddenPinStep.enter:
        final valid = await HiddenAlbumsLock.verifyPin(_pin);
        if (!mounted) return;
        if (!valid) return _fail(AppConstants.securityInvalidPin.tr());
        Navigator.of(context).pop(true);
      case _HiddenPinStep.create:
        // The app PIN would defeat the point of a second lock.
        if (await SecurityLockService().verifyPin(_pin)) {
          return _fail(AppConstants.hiddenSameAsApp.tr());
        }
        if (!mounted) return;
        setState(() {
          _newPin = _pin;
          _pin = '';
          _submitting = false;
          _step = _HiddenPinStep.confirm;
        });
      case _HiddenPinStep.confirm:
        if (_pin != _newPin) {
          return _fail(
            AppConstants.securityPinMismatch.tr(),
            step: _HiddenPinStep.create,
          );
        }
        await HiddenAlbumsLock.setPin(_newPin);
        if (mounted) Navigator.of(context).pop(true);
    }
  }
}

/// The lock screens' layout: who is unlocking at the top, the PIN and its
/// keypad at the bottom, within reach of the thumb. Nothing boxed in, like
/// the phone's own lock screen and most banking apps.
class _SecurityShell extends StatelessWidget {
  const _SecurityShell({
    required this.greeting,
    required this.title,
    required this.subtitle,
    required this.userName,
    this.avatarUrl,
    this.onBack,
    this.leading,
    required this.child,
  });

  /// Shows a back arrow (screens opened from settings, not the lock).
  final VoidCallback? onBack;

  /// Shown instead of the user's photo.
  final Widget? leading;

  final String greeting;
  final String title;
  final String subtitle;
  final String userName;
  final String? avatarUrl;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final showText = greeting.isNotEmpty || title.isNotEmpty;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.background, AppTheme.backgroundBottom],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The width is fixed outside IntrinsicHeight so text is
              // measured at the width it will really have.
              const horizontal = 28.0;
              const vertical = 20.0;
              final width = math.min(
                400.0,
                constraints.maxWidth - horizontal * 2,
              );
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: vertical),
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - vertical * 2,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (onBack == null)
                              const _SecurityBrand()
                            else
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  const _SecurityBrand(),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: IconButton(
                                      onPressed: onBack,
                                      tooltip: MaterialLocalizations.of(
                                        context,
                                      ).backButtonTooltip,
                                      icon: const Icon(
                                        Icons.arrow_back_rounded,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 28),
                            leading ??
                                _SecurityAvatar(
                                  userName: userName,
                                  avatarUrl: avatarUrl,
                                ),
                            const SizedBox(height: 18),
                            if (showText) ..._texts(),
                            const Spacer(),
                            const SizedBox(height: 24),
                            child,
                            if (LocalModeConfig.isLocalOnly) ...[
                              const SizedBox(height: 12),
                              const _SecurityFootnote(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _texts() {
    return [
      if (title.isEmpty)
        Text(
          greeting,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        )
      else ...[
        if (greeting.isNotEmpty) ...[
          Text(
            greeting,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.primarySoft,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
      if (subtitle.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.mutedText,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    ];
  }
}

class _SecurityBrand extends StatelessWidget {
  const _SecurityBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.asset(
            'assets/images/docs_icon.png',
            width: 30,
            height: 30,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 9),
        Text(
          AppConstants.appTitle.tr(),
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SecurityAvatar extends StatelessWidget {
  const _SecurityAvatar({required this.userName, this.avatarUrl});

  final String userName;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final photoUrl = avatarUrl;
    final isNetworkPhoto = photoUrl != null && photoUrl.startsWith('http');
    final isLocalPhoto = photoUrl != null && !isNetworkPhoto;

    return Align(
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: photoUrl == null
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4F9DFF), Color(0xFF12306A)],
                )
              : null,
          image: isNetworkPhoto
              ? DecorationImage(
                  image: NetworkImage(photoUrl),
                  fit: BoxFit.cover,
                )
              : isLocalPhoto
              ? DecorationImage(
                  image: FileImage(File(photoUrl)),
                  fit: BoxFit.cover,
                )
              : null,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: photoUrl == null
            ? Center(
                child: Text(
                  initialsFromName(userName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Four dots that fill as the PIN is typed, and shake when it's wrong.
class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.length,
    required this.hasError,
    required this.errorCount,
  });

  final int length;
  final bool hasError;

  /// Grows with every wrong PIN; each new value plays the shake once.
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    final filledColor = hasError ? AppTheme.destructive : AppTheme.text;
    final dots = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < 4; index++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: AnimatedScale(
              scale: index < length ? 1 : 0.86,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutBack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index < length
                      ? filledColor
                      : AppTheme.text.withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
      ],
    );

    if (errorCount == 0 || MediaQuery.disableAnimationsOf(context)) {
      return dots;
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey(errorCount),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      builder: (context, t, child) => Transform.translate(
        offset: Offset(math.sin(t * math.pi * 5) * 10 * (1 - t), 0),
        child: child,
      ),
      child: dots,
    );
  }
}

/// The line under the dots: empty, or why the PIN wasn't accepted. Keeps
/// its height either way so the keypad doesn't jump.
class _PinMessage extends StatelessWidget {
  const _PinMessage({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Text(
            text ?? '',
            key: ValueKey(text),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.destructive,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
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
      borderRadius: BorderRadius.circular(14),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.fingerprint_rounded, color: AppTheme.primarySoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppConstants.securityEnableBiometrics.tr(),
                style: const TextStyle(color: AppTheme.text, fontSize: 14),
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// A phone-style keypad: plain digits, a soft circle where a key is
/// pressed, biometrics bottom-left and delete bottom-right.
class _PinKeyboard extends StatelessWidget {
  const _PinKeyboard({
    required this.enabled,
    required this.canDelete,
    required this.onDigit,
    required this.onDelete,
    this.biometricEnabled = false,
    this.onBiometric,
  });

  final bool enabled;
  final bool canDelete;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final bool biometricEnabled;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    final keySize = (MediaQuery.sizeOf(context).height * 0.095).clamp(
      60.0,
      78.0,
    );
    Widget digit(String value) => _KeypadButton(
      size: keySize,
      label: value,
      enabled: enabled,
      onTap: () => onDigit(value),
    );

    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [for (final value in row) digit(value)],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            biometricEnabled
                ? _KeypadButton(
                    size: keySize,
                    icon: Icons.fingerprint_rounded,
                    semanticLabel: AppConstants.securityUseBiometrics.tr(),
                    enabled: enabled,
                    onTap: onBiometric,
                  )
                : SizedBox.square(dimension: keySize),
            digit('0'),
            // Only there once there is something to delete.
            AnimatedOpacity(
              opacity: canDelete ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: _KeypadButton(
                size: keySize,
                icon: Icons.backspace_outlined,
                semanticLabel: MaterialLocalizations.of(
                  context,
                ).deleteButtonTooltip,
                enabled: enabled && canDelete,
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
    required this.size,
    this.label,
    this.icon,
    this.semanticLabel,
    required this.enabled,
    required this.onTap,
  });

  final double size;
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
            style: TextStyle(
              color: AppTheme.text,
              fontSize: size * 0.4,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          )
        : Icon(icon, color: AppTheme.primarySoft, size: size * 0.36);

    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: SizedBox.square(
        dimension: size,
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            customBorder: const CircleBorder(),
            splashColor: AppTheme.text.withValues(alpha: 0.12),
            highlightColor: AppTheme.text.withValues(alpha: 0.08),
            child: Center(child: child),
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
            fontWeight: FontWeight.w600,
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
