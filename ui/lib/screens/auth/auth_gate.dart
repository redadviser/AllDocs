import 'package:flutter/material.dart';

import '../../common/app_scaffold.dart';
import '../../common/storage_permission_gate.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import 'auth_screen.dart';
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
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final signedIn = await AuthService.isSignedIn();
    final name = await AuthService.displayName();
    final avatarUrl = await AuthService.avatarUrl();
    await _useAccount(signedIn ? await AuthService.email() : null);
    if (signedIn) await PlanService.onSignedIn();
    if (!mounted) return;

    setState(() {
      _signedIn = signedIn;
      _userName = name ?? _fallbackUserName;
      _avatarUrl = avatarUrl;
      _loadingSession = false;
    });
  }

  Future<void> _completeAuth(Future<String> Function() action) async {
    final name = await action();
    final avatarUrl = await AuthService.avatarUrl();
    await _useAccount(await AuthService.email());
    await PlanService.onSignedIn();
    if (!mounted) return;
    setState(() {
      _userName = name;
      _avatarUrl = avatarUrl;
      _signedIn = true;
    });
  }

  /// Everything kept per account on this phone (documents, PIN, cloud
  /// connections, backup settings) switches to [email]'s account before
  /// the PIN screen or the app is shown.
  Future<void> _useAccount(String? email) async {
    CurrentUser.setEmail(email);
    await AppSettings.loadAccountSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSession) {
      return const _AuthLoadingScreen();
    }

    if (_signedIn) {
      return SecurityGate(
        userName: _userName,
        avatarUrl: _avatarUrl,
        child: const StoragePermissionGate(child: MainNavScreen()),
      );
    }

    // Primeiro acesso: pede a conta (login/signup/Google). Depois o
    // SecurityGate trata da criação do PIN e biometria, como já está
    // implementado.
    return AuthScreen(
      onLogin: (email, password) =>
          _completeAuth(() => AuthService.login(email, password)),
      onSignup: (email, password, displayName) => _completeAuth(
        () => AuthService.signup(email, password, displayName: displayName),
      ),
      onGoogleSignIn: () => _completeAuth(AuthService.loginWithGoogle),
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.background, AppTheme.backgroundBottom],
          ),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
