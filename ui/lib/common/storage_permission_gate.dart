import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';

class StoragePermissionGate extends StatefulWidget {
  const StoragePermissionGate({super.key, required this.child});

  final Widget child;

  @override
  State<StoragePermissionGate> createState() => _StoragePermissionGateState();
}

class _StoragePermissionGateState extends State<StoragePermissionGate>
    with WidgetsBindingObserver {
  final StoragePermissionService _permissionService =
      const StoragePermissionService();

  bool _checking = true;
  bool _allowed = false;
  bool _requestedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensurePermission(requestIfNeeded: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ensurePermission(requestIfNeeded: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed) return widget.child;

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
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Icon(
                        Icons.folder_open_rounded,
                        color: AppTheme.primarySoft,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      AppConstants.permissionStorageTitle.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      AppConstants.permissionStorageMessage.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _checking
                          ? null
                          : () => _ensurePermission(requestIfNeeded: true),
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open_rounded),
                      label: Text(
                        _requestedOnce
                            ? AppConstants.permissionStorageRetry.tr()
                            : AppConstants.permissionStorageButton.tr(),
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

  Future<void> _ensurePermission({required bool requestIfNeeded}) async {
    if (!mounted) return;
    setState(() => _checking = true);

    var allowed = await _permissionService.hasAllFilesAccess();
    if (!allowed && requestIfNeeded) {
      _requestedOnce = true;
      allowed = await _permissionService.requestAllFilesAccess();
    }

    if (!mounted) return;
    setState(() {
      _allowed = allowed;
      _checking = false;
    });
  }
}
