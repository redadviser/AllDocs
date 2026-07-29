import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/app_constants.dart';
import '../../common/glass_panel.dart';
import '../../models/device_session.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late Future<List<DeviceSession>> _future;

  @override
  void initState() {
    super.initState();
    _future = AuthService.listDevices();
  }

  void _reload() {
    setState(() => _future = AuthService.listDevices());
  }

  Future<void> _revoke(DeviceSession device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(AppConstants.securityDevicesRevokeConfirmTitle.tr()),
        content: Text(AppConstants.securityDevicesRevokeConfirmMessage.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppConstants.commonCancel.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: Text(AppConstants.securityDevicesRevoke.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await AuthService.revokeDevice(device.id);
      if (!mounted) return;
      _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppConstants.securityDevicesRevokeError.tr())),
      );
    }
  }

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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        AppConstants.securityDevicesTitle.tr(),
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<DeviceSession>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _DevicesMessage(
                        text: AppConstants.securityDevicesLoadError.tr(),
                        actionLabel: AppConstants.securityDevicesRetry.tr(),
                        onAction: _reload,
                      );
                    }

                    final devices = snapshot.data ?? const [];
                    if (devices.isEmpty) {
                      return _DevicesMessage(
                        text: AppConstants.securityDevicesEmpty.tr(),
                      );
                    }

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        Text(
                          AppConstants.securityDevicesSubtitle.tr(),
                          style: const TextStyle(
                            color: AppTheme.mutedText,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final device in devices) ...[
                          _DeviceTile(
                            device: device,
                            onRevoke: () => _revoke(device),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DevicesMessage extends StatelessWidget {
  const _DevicesMessage({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.mutedText, fontSize: 14),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onRevoke});

  final DeviceSession device;
  final VoidCallback onRevoke;

  IconData get _icon => switch (device.platform) {
    'android' => Icons.android_rounded,
    'ios' => Icons.phone_iphone_rounded,
    _ => Icons.devices_other_rounded,
  };

  String get _platformLabel => switch (device.platform) {
    'android' => AppConstants.securityDevicesPlatformAndroid.tr(),
    'ios' => AppConstants.securityDevicesPlatformIos.tr(),
    _ => AppConstants.securityDevicesPlatformOther.tr(),
  };

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_icon, color: AppTheme.primarySoft, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _platformLabel,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (device.isCurrentDevice) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          AppConstants.securityDevicesCurrent.tr(),
                          style: const TextStyle(
                            color: AppTheme.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  AppConstants.securityDevicesLastSeen.tr(
                    namedArgs: {'date': _formatDate(device.lastSeenAt)},
                  ),
                  style: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (!device.isCurrentDevice)
            IconButton(
              onPressed: onRevoke,
              icon: const Icon(Icons.delete_outline_rounded),
              color: AppTheme.destructive,
              tooltip: AppConstants.securityDevicesRevoke.tr(),
            ),
        ],
      ),
    );
  }
}
