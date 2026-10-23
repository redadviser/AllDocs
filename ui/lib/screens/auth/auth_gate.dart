import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/app_constants.dart';

import '../../common/app_scaffold.dart';
import '../../common/storage_permission_gate.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import 'auth_screen.dart';
import 'security_gate.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.notice});

  /// Shown once over the sign-in screen (why the user is back there).
  final String? notice;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  static const _fallbackUserName = 'AllDocs';
  static const _sessionCheckInterval = Duration(minutes: 1);

  bool _loadingSession = true;
  bool _signedIn = false;
  String _userName = _fallbackUserName;
  String? _avatarUrl;

  Timer? _sessionTimer;
  bool _endingSession = false;

  Future<bool>? _checking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SecurityGate.sessionCheck = _checkSession;
    _loadSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (SecurityGate.sessionCheck == _checkSession) {
      SecurityGate.sessionCheck = null;
    }
    _sessionTimer?.cancel();
    super.dispose();
  }

  /// Whether the session is still valid; signs this phone out (to the
  /// sign-in screen) when it isn't. One check at a time.
  Future<bool> _checkSession() {
    return _checking ??= _runSessionCheck().whenComplete(
      () => _checking = null,
    );
  }

  Future<bool> _runSessionCheck() async {
    if (!_signedIn || _endingSession) return !_endingSession;
    final state = await AuthService.checkSession();
    if (!mounted) return true;
    if (state != SessionState.ended && state != SessionState.accountDeleted) {
      return true;
    }
    _endingSession = true;
    _sessionTimer?.cancel();
    final notice =
        (state == SessionState.accountDeleted
                ? AppConstants.authAccountDeleted
                : AppConstants.authSessionEnded)
            .tr();
    await AuthService.logout();
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AuthGate(notice: notice)),
        (route) => false,
      );
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _verifySession();
  }

  /// The library works without the server, so a session ended on another
  /// device (Security → Devices) would otherwise go unnoticed here: the app
  /// asks on start, when it comes back, and every minute while open.
  void _watchSession() {
    _sessionTimer?.cancel();
    if (!_signedIn) return;
    _sessionTimer = Timer.periodic(
      _sessionCheckInterval,
      (_) => _verifySession(),
    );
    _verifySession();
  }

  Future<void> _verifySession() => _checkSession();

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
    _watchSession();
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
    _watchSession();
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
      notice: widget.notice,
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
