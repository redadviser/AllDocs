import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/app_constants.dart';
import '../../common/app_scaffold.dart';
import '../../common/storage_permission_gate.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import 'security_gate.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _fallbackUserName = 'AllDocs';

  bool _loadingSession = true;
  bool _signedIn = false;
  String _userName = _fallbackUserName;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final signedIn = await AuthService.isSignedIn();
    final name = await AuthService.displayName();
    if (!mounted) return;

    setState(() {
      _signedIn = signedIn;
      _userName = name ?? _fallbackUserName;
      _loadingSession = false;
    });
  }

  Future<void> _handleLogin(String email, String password) async {
    final name = await AuthService.login(email, password);
    if (!mounted) return;
    setState(() {
      _userName = name;
      _signedIn = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSession) {
      return const _AuthLoadingScreen();
    }

    if (_signedIn) {
      return SecurityGate(
        userName: _userName,
        child: const StoragePermissionGate(child: MainNavScreen()),
      );
    }

    // Primeiro acesso: pede login. Depois o SecurityGate trata da criação do PIN
    // e biometria, como já está implementado.
    return LoginScreen(onLogin: _handleLogin);
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.background, AppTheme.backgroundBottom],
          ),
        ),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLogin});

  final Future<void> Function(String email, String password) onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController(
    text: 'paulo.cunha@email.com',
  );
  final TextEditingController _passwordController = TextEditingController(
    text: 'alldocs',
  );
  bool _remember = true;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onLogin(_emailController.text, _passwordController.text);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppConstants.authLoginError.tr())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
                    _LoginHero(),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
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
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Checkbox(
                                value: _remember,
                                onChanged: (value) {
                                  setState(() => _remember = value ?? true);
                                },
                              ),
                              Expanded(
                                child: Text(
                                  AppConstants.authRemember.tr(),
                                  style: const TextStyle(
                                    color: AppTheme.mutedText,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppConstants.authMockHint.tr(),
                                      ),
                                    ),
                                  );
                                },
                                child: Text(AppConstants.authForgot.tr()),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: _submitting ? null : _submit,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(AppConstants.authLogin.tr()),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            AppConstants.authMockHint.tr(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppTheme.mutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
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
      ),
    );
  }
}

class _LoginHero extends StatelessWidget {
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
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppTheme.success.withValues(alpha: 0.32)),
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
    );
  }
}
