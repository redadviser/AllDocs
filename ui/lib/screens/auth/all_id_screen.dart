import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/app_constants.dart';
import '../../services/local_mode_config.dart';
import '../../theme/app_theme.dart';

enum _AuthMode { login, signup }

/// AllID: the shared account screen for the AllPhotos/AllDocs suite. Signing
/// in or creating an account here works on both apps, since they
/// authenticate against the same shared `users`/`profiles` tables (see
/// docs/architecture.md). Starts as a two-button landing (AllID / Google);
/// tapping AllID expands the card into the email/password (+ display name
/// for signup) form.
class AllIdScreen extends StatefulWidget {
  const AllIdScreen({
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
  State<AllIdScreen> createState() => _AllIdScreenState();
}

class _AllIdScreenState extends State<AllIdScreen> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _showForm = false;
  bool _submitting = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppConstants.authLoginError.tr())));
    } finally {
      if (mounted) setState(() => _submitting = false);
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

  Future<void> _submitGoogle() => _run(widget.onGoogleSignIn);

  void _toggleMode() {
    setState(() {
      _mode = _mode == _AuthMode.login ? _AuthMode.signup : _AuthMode.login;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                    const _AllIdHero(),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppTheme.border.withValues(alpha: 0.75),
                        ),
                      ),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _showForm ? _buildForm() : _buildLanding(),
                        ),
                      ),
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

  Widget _buildLanding() {
    return Column(
      key: const ValueKey('landing'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => setState(() => _showForm = true),
          icon: const Icon(Icons.badge_outlined),
          label: Text(AppConstants.authContinueWithAllId.tr()),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _submitting ? null : _submitGoogle,
          icon: const Icon(Icons.g_mobiledata_rounded),
          label: Text(AppConstants.authContinueWithGoogle.tr()),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    final isLogin = _mode == _AuthMode.login;

    return Column(
      key: const ValueKey('form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() => _showForm = false),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Text(
                AppConstants.authTitle.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 8),
        if (!isLogin) ...[
          TextField(
            controller: _displayNameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: AppConstants.authDisplayName.tr(),
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: AppConstants.authEmail.tr(),
            prefixIcon: const Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: AppConstants.authPassword.tr(),
            prefixIcon: const Icon(Icons.lock_outline),
          ),
        ),
        if (isLogin) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppConstants.authForgotHint.tr())),
                );
              },
              child: Text(AppConstants.authForgot.tr()),
            ),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(
            (isLogin ? AppConstants.authLogin : AppConstants.authSignup).tr(),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _submitting ? null : _toggleMode,
            child: Text(
              (isLogin
                      ? AppConstants.authToggleToSignup
                      : AppConstants.authToggleToLogin)
                  .tr(),
            ),
          ),
        ),
      ],
    );
  }
}

class _AllIdHero extends StatelessWidget {
  const _AllIdHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.border),
          ),
          child: const Icon(
            Icons.folder_copy_rounded,
            color: AppTheme.primarySoft,
            size: 42,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          AppConstants.authTitle.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppConstants.authSubtitle.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.mutedText,
            fontSize: 13,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (LocalModeConfig.isLocalOnly) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: AppTheme.success.withValues(alpha: 0.32),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.offline_bolt_rounded,
                  color: AppTheme.success,
                  size: 17,
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
            ),
          ),
        ],
      ],
    );
  }
}
