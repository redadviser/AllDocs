import 'package:flutter/material.dart';

import '../../common/app_scaffold.dart';
import '../../common/storage_permission_gate.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import 'all_id_screen.dart';
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
    if (!mounted) return;
    setState(() {
      _userName = name;
      _avatarUrl = avatarUrl;
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
        avatarUrl: _avatarUrl,
        child: const StoragePermissionGate(child: MainNavScreen()),
      );
    }

    // Primeiro acesso: pede AllID (login/signup/Google). Depois o
    // SecurityGate trata da criação do PIN e biometria, como já está
    // implementado.
    return AllIdScreen(
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
