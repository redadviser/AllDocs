import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/app_constants.dart';
import '../../common/language_picker.dart';
import '../../services/auth_service.dart';
import '../../services/local_mode_config.dart';
import '../../theme/app_theme.dart';

enum _AuthMode { login, signup }

/// AllDocs account screen: the email/password form (+ display name when
/// creating an account) straight away, with "Continue with Google" below.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.onLogin,
    required this.onSignup,
    required this.onGoogleSignIn,
  });

  final Future<void> Function(String email, String password) onLogin;
  final Future<void> Function(String email, String password, String displayName)
  onSignup;
  final Future<void> Function() onGoogleSignIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _submitting = false;
  bool _googleInFlight = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool google = false,
  }) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _googleInFlight = google;
    });
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppConstants.authLoginError.tr())));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _googleInFlight = false;
        });
      }
    }
  }

  Future<void> _submit() {
    return _run(() {
      final email = _emailController.text;
      final password = _passwordController.text;
      return _mode == _AuthMode.login
          ? widget.onLogin(email, password)
          : widget.onSignup(email, password, _displayNameController.text);
    });
  }

  Future<void> _submitGoogle() => _run(widget.onGoogleSignIn, google: true);

  /// "Forgot": asks for the email (pre-filled with what's typed) and has the
  /// backend email a link to a page where a new password is set.
  Future<void> _showForgotPassword() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _ForgotPasswordDialog(initialEmail: _emailController.text.trim()),
    );
    if (sent == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (sent ? AppConstants.authForgotSent : AppConstants.authForgotFailed)
              .tr(),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _setMode(_AuthMode mode) {
    if (_submitting || mode == _mode) return;
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final isLogin = _mode == _AuthMode.login;
    // Sized so the whole sign-in form, Google included, fits without
    // scrolling on common phones.
    final heroHeight = (MediaQuery.sizeOf(context).height * 0.33).clamp(
      240.0,
      330.0,
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      // The page fills the screen: room left under the photo is shared
      // above and below the form, so it sits centred there instead of
      // right under the photo; with no room left, it simply scrolls.
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AuthHero(imageHeight: heroHeight),
                  const Spacer(),
                  SafeArea(
                    top: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        // A fixed width (not just a maximum) so
                        // IntrinsicHeight measures text at its real width.
                        child: SizedBox(
                          width: math.min(430.0, constraints.maxWidth - 32),
                          child: _FadeSlideIn(
                            delay: const Duration(milliseconds: 120),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                16,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.surface.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: AppTheme.border.withValues(
                                    alpha: 0.75,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.28),
                                    blurRadius: 30,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: AnimatedSize(
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _ModeSwitch(
                                      isLogin: isLogin,
                                      enabled: !_submitting,
                                      onChanged: _setMode,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      (isLogin
                                              ? AppConstants.authSubtitle
                                              : AppConstants.authSubtitleSignup)
                                          .tr(),
                                      style: const TextStyle(
                                        color: AppTheme.mutedText,
                                        fontSize: 13,
                                        height: 1.35,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    _buildForm(),
                                    _buildGoogle(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Divider(color: AppTheme.border.withValues(alpha: 0.6)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                AppConstants.authOrDivider.tr(),
                style: const TextStyle(
                  color: AppTheme.dimText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Divider(color: AppTheme.border.withValues(alpha: 0.6)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _GoogleButton(
          busy: _googleInFlight,
          onPressed: _submitting ? null : _submitGoogle,
        ),
      ],
    );
  }

  Widget _buildForm() {
    final isLogin = _mode == _AuthMode.login;

    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isLogin) ...[
            TextField(
              controller: _displayNameController,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: InputDecoration(
                isDense: true,
                labelText: AppConstants.authDisplayName.tr(),
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              isDense: true,
              labelText: AppConstants.authEmail.tr(),
              prefixIcon: const Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: [
              isLogin ? AutofillHints.password : AutofillHints.newPassword,
            ],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              isDense: true,
              labelText: AppConstants.authPassword.tr(),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip:
                    (_obscurePassword
                            ? AppConstants.authShowPassword
                            : AppConstants.authHidePassword)
                        .tr(),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          if (isLogin) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _submitting ? null : _showForgotPassword,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(AppConstants.authForgot.tr()),
              ),
            ),
          ],
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _submitting && !_googleInFlight
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      (isLogin
                              ? AppConstants.authLogin
                              : AppConstants.authSignup)
                          .tr(),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Entrar | Criar conta" pill at the top of the form card.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.isLogin,
    required this.enabled,
    required this.onChanged,
  });

  final bool isLogin;
  final bool enabled;
  final ValueChanged<_AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceStrong,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.7)),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: isLogin ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _tab(AppConstants.authLogin, _AuthMode.login, isLogin),
              _tab(AppConstants.authSignup, _AuthMode.signup, !isLogin),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tab(String labelKey, _AuthMode mode, bool selected) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: enabled ? () => onChanged(mode) : null,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: selected ? AppTheme.text : AppTheme.mutedText,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
              child: Text(labelKey.tr()),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and slides its child up a little the first time it is shown.
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final total = const Duration(milliseconds: 650) + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail,
  );
  bool _sending = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _valid => _email.text.trim().contains('@');

  Future<void> _send() async {
    if (!_valid || _sending) return;
    setState(() => _sending = true);
    var sent = true;
    try {
      await AuthService.requestPasswordReset(
        _email.text,
        languageCode: context.locale.languageCode,
      );
    } catch (_) {
      sent = false;
    }
    if (mounted) Navigator.of(context).pop(sent);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(AppConstants.authForgotTitle.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppConstants.authForgotMessage.tr(),
            style: const TextStyle(color: AppTheme.mutedText, height: 1.35),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            autofocus: widget.initialEmail.isEmpty,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              labelText: AppConstants.authEmail.tr(),
              prefixIcon: const Icon(Icons.email_outlined),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(AppConstants.commonCancel.tr()),
        ),
        FilledButton(
          onPressed: _valid && !_sending ? _send : null,
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(AppConstants.authForgotSend.tr()),
        ),
      ],
    );
  }
}

/// "Continue with Google" as Google's branding guidelines draw it for dark
/// themes: #131314 fill, #8E918F outline, #E3E3E3 label and the official
/// "G" (cut from Google's own sign-in button assets, signin-assets.zip).
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  static const _fill = Color(0xFF131314);
  static const _outline = Color(0xFF8E918F);
  static const _label = Color(0xFFE3E3E3);

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null && !busy ? 0.6 : 1,
      child: Material(
        color: _fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: busy
                      ? const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _label,
                        )
                      : Image.asset(
                          'assets/images/google_g.png',
                          filterQuality: FilterQuality.medium,
                        ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    AppConstants.authContinueWithGoogle.tr(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _label,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One photo of the login slideshow. [alignment] keeps its subject in
/// frame when the photo is cropped to the header.
class _Slide {
  const _Slide(this.asset, this.alignment);

  final String asset;
  final Alignment alignment;
}

/// Photo header: a slow slideshow of document photos (Unsplash License:
/// Kelly Sikkema, Jakub Żerdzicki, Scott Graham) under the logo, fading
/// into the app background. The words sit on the faded edge only, so the
/// photos stay clear.
class _AuthHero extends StatefulWidget {
  const _AuthHero({required this.imageHeight});

  final double imageHeight;

  @override
  State<_AuthHero> createState() => _AuthHeroState();
}

class _AuthHeroState extends State<_AuthHero> {
  static const _slides = [
    _Slide('assets/images/auth_passport.jpg', Alignment(-0.4, 0)),
    _Slide('assets/images/auth_signing.jpg', Alignment(0, -0.35)),
    _Slide('assets/images/auth_forms.jpg', Alignment.center),
    _Slide('assets/images/auth_contract.jpg', Alignment(-0.2, 0)),
  ];
  static const _interval = Duration(seconds: 6);

  int _index = 0;
  Timer? _timer;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_interval, (_) {
      if (mounted) setState(() => _index = (_index + 1) % _slides.length);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decoded up front, so each crossfade starts on a ready photo.
    if (_precached) return;
    _precached = true;
    for (final slide in _slides) {
      precacheImage(AssetImage(slide.asset), context);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = AppTheme.background;
    final topInset = MediaQuery.paddingOf(context).top;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SizedBox(
      height: widget.imageHeight,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          ClipRect(
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 1400),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              child: _KenBurnsPhoto(
                key: ValueKey(_index),
                slide: _slides[_index],
                animate: !reduceMotion,
                duration: _interval + const Duration(milliseconds: 1400),
              ),
            ),
          ),
          // Shade under the status bar and the logo; clear in the middle;
          // the bottom fades into the page, where the words sit. One pixel
          // taller than the photo so its last row never shows as a line.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: -1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.22, 0.6, 0.86, 1],
                  colors: [
                    background.withValues(alpha: 0.62),
                    background.withValues(alpha: 0),
                    background.withValues(alpha: 0),
                    background.withValues(alpha: 0.82),
                    background,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: topInset + 14,
            left: 20,
            right: 20,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/images/docs_icon.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  AppConstants.authTitle.tr(),
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 10)],
                  ),
                ),
                const Spacer(),
                const LanguageButton(),
              ],
            ),
          ),
          Positioned(
            top: topInset + 58,
            right: 20,
            child: _SlideDots(count: _slides.length, index: _index),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 4,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: _FadeSlideIn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppConstants.authTagline.tr(),
                        maxLines: 2,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 14.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 10),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // One row, shrunk if a language's labels run long, so
                      // the words keep to the faded edge of the photo.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          spacing: 6,
                          children: [
                            const _FeaturePill(
                              icon: Icons.manage_search_rounded,
                              labelKey: AppConstants.authFeatureSearch,
                            ),
                            const _FeaturePill(
                              icon: Icons.notifications_active_outlined,
                              labelKey: AppConstants.authFeatureReminders,
                            ),
                            if (LocalModeConfig.isLocalOnly)
                              const _FeaturePill(
                                icon: Icons.offline_bolt_rounded,
                                labelKey: AppConstants.authOffline,
                                color: AppTheme.success,
                              )
                            else
                              const _FeaturePill(
                                icon: Icons.cloud_done_outlined,
                                labelKey: AppConstants.authFeatureBackup,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A photo that drifts in slowly while it's on screen.
class _KenBurnsPhoto extends StatelessWidget {
  const _KenBurnsPhoto({
    super.key,
    required this.slide,
    required this.animate,
    required this.duration,
  });

  final _Slide slide;
  final bool animate;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final photo = Image.asset(
      slide.asset,
      fit: BoxFit.cover,
      alignment: slide.alignment,
      excludeFromSemantics: true,
      gaplessPlayback: true,
    );
    if (!animate) return photo;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 1.07),
      duration: duration,
      curve: Curves.easeOut,
      child: photo,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: slide.alignment,
        child: child,
      ),
    );
  }
}

class _SlideDots extends StatelessWidget {
  const _SlideDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(left: 5),
            width: i == index ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i == index ? 0.9 : 0.4),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.labelKey, this.color});

  final IconData icon;
  final String labelKey;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppTheme.primarySoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceStrong.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: tint),
          const SizedBox(width: 6),
          Text(
            labelKey.tr(),
            style: TextStyle(
              color: color ?? AppTheme.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
