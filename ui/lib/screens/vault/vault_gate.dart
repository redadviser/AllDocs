import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/album_dialog.dart' show showConfirmDialog;
import '../../common/app_constants.dart';
import '../../services/auth_service.dart';
import '../../services/local_documents_store.dart';
import '../auth/auth_gate.dart';
import '../../services/local_mode_config.dart';
import '../../services/thumbnail_cache.dart';
import '../../services/vault/vault_migration.dart';
import '../../services/vault/vault_unlocker.dart';
import '../../theme/app_theme.dart';

enum _Phase {
  checking,
  localWarning,
  migrating,
  noSpace,
  needsNetwork,
  unrecoverable,
  needsSignIn,
  failed,
  ready,
}

/// Opens the library's encryption before the app shows it: finds the key,
/// encrypts an older library once (with its progress), or explains why it
/// can't be opened. Sits below StoragePermissionGate, which decides which
/// folder the library lives in.
class VaultGate extends StatefulWidget {
  const VaultGate({
    super.key,
    required this.child,
    this.unlocker,
    this.migrate,
    this.localOnly = LocalModeConfig.isLocalOnly,
    this.signOut,
  });

  /// Tests: stand-in for signing out.
  final Future<void> Function()? signOut;

  final Widget child;

  /// Tests: stand-ins for the real unlock and migration.
  final VaultUnlocker? unlocker;
  final Future<MigrationResult> Function(
    void Function(MigrationProgress) onProgress,
  )?
  migrate;

  final bool localOnly;

  @override
  State<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<VaultGate> {
  static const _localWarningSeen = 'vault.local_warning_seen.v1';

  _Phase _phase = _Phase.checking;
  MigrationProgress? _progress;
  int _missingBytes = 0;

  late final VaultUnlocker _unlocker =
      widget.unlocker ??
      VaultUnlocker(
        store: const LocalDocumentsStore(),
        localOnly: widget.localOnly,
      );

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    _set(_Phase.checking);
    try {
      if (widget.localOnly && !await _localWarningAccepted()) {
        _set(_Phase.localWarning);
        return;
      }
      switch (await _unlocker.unlock()) {
        case VaultState.open || VaultState.notEncrypted:
          _set(_Phase.ready);
        case VaultState.needsMigration:
          await _migrate();
        case VaultState.needsNetwork:
          _set(_Phase.needsNetwork);
        case VaultState.unrecoverable:
          _set(_Phase.unrecoverable);
        case VaultState.needsSignIn:
          _set(_Phase.needsSignIn);
      }
    } catch (_) {
      _set(_Phase.failed);
    }
  }

  Future<void> _migrate() async {
    _set(_Phase.migrating);
    void onProgress(MigrationProgress progress) {
      if (mounted) setState(() => _progress = progress);
    }

    final result =
        await (widget.migrate?.call(onProgress) ??
            VaultMigration(
              const LocalDocumentsStore(),
            ).run(onProgress: onProgress));
    LocalDocumentsStore.reload();
    await ThumbnailCache.instance.purgePlain();
    if (result.outcome == MigrationOutcome.noSpace) {
      _missingBytes = result.missingBytes;
      _set(_Phase.noSpace);
      return;
    }
    // Documents that didn't verify stay as they were and are retried on
    // the next start; the settings row says how many.
    _set(_Phase.ready);
  }

  Future<bool> _localWarningAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_localWarningSeen) ?? false;
  }

  Future<void> _acceptLocalWarning() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localWarningSeen, true);
    await _open();
  }

  Future<void> _startNewLibrary() async {
    final confirmed = await showConfirmDialog(
      context,
      title: AppConstants.vaultLostConfirmTitle.tr(),
      message: AppConstants.vaultLostConfirmMessage.tr(),
      actionLabel: AppConstants.vaultLostConfirmAction.tr(),
    );
    if (!confirmed) return;
    try {
      await _unlocker.setAsideLockedLibrary();
    } catch (_) {
      _set(_Phase.failed);
      return;
    }
    await _open();
  }

  /// The key copy is only handed out right after signing in: sign out and
  /// back to the sign-in screen; the library stays as it is.
  Future<void> _signInAgain() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    await (widget.signOut ?? AuthService.logout)();
    await navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  void _set(_Phase phase) {
    if (mounted) setState(() => _phase = phase);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.ready => widget.child,
      _Phase.checking => const _VaultFrame(
        child: Center(child: CircularProgressIndicator()),
      ),
      _Phase.migrating => _migrating(context),
      _Phase.localWarning => _VaultMessage(
        icon: Icons.phone_android_rounded,
        title: AppConstants.vaultLocalTitle.tr(),
        message: AppConstants.vaultLocalMessage.tr(),
        primary: (AppConstants.vaultLocalOk.tr(), _acceptLocalWarning),
      ),
      _Phase.noSpace => _VaultMessage(
        icon: Icons.sd_storage_outlined,
        title: AppConstants.vaultNoSpaceTitle.tr(),
        message: _missingBytes > 0
            ? AppConstants.vaultNoSpaceMessage.tr(
                namedArgs: {'size': _sizeLabel(context, _missingBytes)},
              )
            : AppConstants.vaultNoSpaceMidway.tr(),
        primary: (AppConstants.vaultRetry.tr(), _open),
        secondary: (
          AppConstants.vaultContinuePlain.tr(),
          () async => _set(_Phase.ready),
        ),
      ),
      _Phase.needsNetwork => _VaultMessage(
        icon: Icons.wifi_off_rounded,
        title: AppConstants.vaultNetworkTitle.tr(),
        message: AppConstants.vaultNetworkMessage.tr(),
        primary: (AppConstants.vaultRetry.tr(), _open),
      ),
      _Phase.unrecoverable => _VaultMessage(
        icon: Icons.lock_outline_rounded,
        title: AppConstants.vaultLostTitle.tr(),
        message: AppConstants.vaultLostMessage.tr(),
        primary: (AppConstants.vaultLostNew.tr(), _startNewLibrary),
        secondary: (AppConstants.vaultRetry.tr(), _open),
      ),
      _Phase.needsSignIn => _VaultMessage(
        icon: Icons.login_rounded,
        title: AppConstants.vaultSignInTitle.tr(),
        message: AppConstants.vaultSignInMessage.tr(),
        primary: (AppConstants.vaultSignInAction.tr(), _signInAgain),
      ),
      _Phase.failed => _VaultMessage(
        icon: Icons.error_outline_rounded,
        title: AppConstants.vaultFailedTitle.tr(),
        message: AppConstants.vaultFailedMessage.tr(),
        primary: (AppConstants.vaultRetry.tr(), _open),
      ),
    };
  }

  Widget _migrating(BuildContext context) {
    final progress = _progress;
    return _VaultFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _VaultIcon(icon: Icons.lock_rounded),
          const SizedBox(height: 18),
          _Title(AppConstants.vaultMigratingTitle.tr()),
          const SizedBox(height: 10),
          _Message(AppConstants.vaultMigratingMessage.tr()),
          const SizedBox(height: 24),
          Semantics(
            label: AppConstants.vaultMigratingTitle.tr(),
            value: progress == null
                ? null
                : '${(progress.fraction * 100).round()} %',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress?.fraction,
                minHeight: 10,
                backgroundColor: AppTheme.surfaceStrong,
              ),
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            _Message(
              AppConstants.vaultMigratingCount.tr(
                namedArgs: {
                  'done': _count(context, progress.done),
                  'total': _count(context, progress.total),
                },
              ),
            ),
            const SizedBox(height: 2),
            _Message(
              AppConstants.vaultMigratingBytes.tr(
                namedArgs: {
                  'done': _sizeLabel(context, progress.bytesDone),
                  'total': _sizeLabel(context, progress.bytesTotal),
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Plain `pt` formats numbers the Brazilian way ("1.240"); the app is pt-PT.
String _numberLocale(BuildContext context) =>
    context.locale.languageCode == 'pt' ? 'pt_PT' : context.locale.toString();

String _count(BuildContext context, int value) =>
    NumberFormat.decimalPattern(_numberLocale(context)).format(value);

/// "640 MB", "2,1 GB" in the app's language.
String _sizeLabel(BuildContext context, int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  final locale = _numberLocale(context);
  if (bytes >= gb) {
    return '${NumberFormat('#,##0.#', locale).format(bytes / gb)} GB';
  }
  return '${NumberFormat.decimalPattern(locale).format((bytes / mb).ceil())} MB';
}

class _VaultFrame extends StatelessWidget {
  const _VaultFrame({required this.child});

  final Widget child;

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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultMessage extends StatelessWidget {
  const _VaultMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.primary,
    this.secondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final (String, Future<void> Function()) primary;
  final (String, Future<void> Function())? secondary;

  @override
  Widget build(BuildContext context) {
    final secondary = this.secondary;
    return _VaultFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _VaultIcon(icon: icon)),
          const SizedBox(height: 18),
          _Title(title),
          const SizedBox(height: 10),
          _Message(message),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => primary.$2(), child: Text(primary.$1)),
          if (secondary != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => secondary.$2(),
              child: Text(secondary.$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _VaultIcon extends StatelessWidget {
  const _VaultIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
      ),
      child: Icon(icon, color: AppTheme.primarySoft, size: 36),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppTheme.text,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppTheme.mutedText,
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
