import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../common/album_dialog.dart' show showConfirmDialog;
import '../../common/app_constants.dart';
import '../../common/app_sheet.dart';
import '../../common/document_actions.dart' show showSnack;
import '../../common/plan_prompts.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';

Future<void> openSyncScreen(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SyncScreen()));
}

/// What a sync problem means for the person.
String syncProblemMessage(SyncProblem problem, {int maxDevices = 3}) =>
    switch (problem) {
      SyncProblem.notIncluded => AppConstants.syncLocked.tr(),
      SyncProblem.deviceRemoved => AppConstants.syncRemoved.tr(),
      SyncProblem.badCode => AppConstants.syncBadCode.tr(),
      SyncProblem.wrongKey => AppConstants.syncWrongKey.tr(),
      SyncProblem.tooMany => AppConstants.syncTooMany.tr(
        namedArgs: {'max': '$maxDevices'},
      ),
      SyncProblem.needsPairing => AppConstants.syncAlreadyOn.tr(),
      SyncProblem.unavailable ||
      SyncProblem.behind ||
      SyncProblem.quota ||
      SyncProblem.missing => AppConstants.syncStatusOffline.tr(),
    };

/// Device sync (Vault): turn it on, bring in another device with a QR
/// code, see and remove devices.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _sync = SyncService.instance;
  SyncAccountStatus? _account;
  bool _enabledHere = false;
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _sync.status.addListener(_onStatus);
    _refresh();
  }

  @override
  void dispose() {
    _sync.status.removeListener(_onStatus);
    super.dispose();
  }

  void _onStatus() {
    if (!mounted) return;
    final enabled = _sync.status.value.enabled;
    if (enabled != _enabledHere) _refresh();
    setState(() {});
  }

  Future<void> _refresh() async {
    final enabled = await _sync.isEnabled();
    SyncAccountStatus? account;
    var failed = false;
    if (PlanService.current.value.has(PlanFeature.deviceSync)) {
      try {
        account = await _sync.accountStatus();
      } catch (_) {
        failed = true;
      }
    }
    if (!mounted) return;
    setState(() {
      _enabledHere = enabled;
      _account = account;
      _failed = failed;
      _loading = false;
    });
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } on SyncApiException catch (error) {
      if (mounted) {
        showSnack(
          context,
          syncProblemMessage(error.problem, maxDevices: _maxDevices),
        );
      }
    } on SyncJoinException catch (error) {
      if (mounted) {
        showSnack(
          context,
          error.error == SyncJoinError.otherAccount
              ? AppConstants.syncOtherAccount.tr()
              : AppConstants.syncNotInvite.tr(),
        );
      }
    } catch (_) {
      if (mounted) showSnack(context, AppConstants.syncFailed.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  int get _maxDevices =>
      _account?.maxDevices ?? PlanService.current.value.maxDevices;

  Future<void> _turnOn() => _run(() async {
    await _sync.turnOn();
    if (mounted) showSnack(context, AppConstants.syncTurnedOn.tr());
  });

  Future<void> _join() async {
    final payload = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _ScanScreen()));
    if (payload == null || !mounted) return;
    await _run(() async {
      await _sync.join(payload);
      if (mounted) showSnack(context, AppConstants.syncJoinedSelf.tr());
    });
  }

  Future<void> _addDevice() async {
    await showOptionsSheet<void>(
      context: context,
      builder: (_) => const _InviteSheet(),
    );
    await _refresh();
  }

  Future<void> _remove(SyncDeviceInfo device) async {
    final thisOne = device.id == _sync.thisDeviceId;
    final confirmed = await showConfirmDialog(
      context,
      title: thisOne
          ? AppConstants.syncLeave.tr()
          : AppConstants.syncRemoveTitle.tr(namedArgs: {'name': device.name}),
      message: thisOne
          ? AppConstants.syncLeaveMessage.tr()
          : AppConstants.syncRemoveMessage.tr(),
      actionLabel: AppConstants.syncRemove.tr(),
    );
    if (!confirmed) return;
    await _run(() => thisOne ? _sync.leave() : _sync.removeDevice(device.id));
  }

  @override
  Widget build(BuildContext context) {
    final included = PlanService.current.value.has(PlanFeature.deviceSync);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
              child: Row(
                children: [
                  const BackButton(),
                  Expanded(
                    child: Text(
                      AppConstants.syncTitle.tr(),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          _Intro(maxDevices: _maxDevices),
                          const SizedBox(height: 20),
                          if (!included)
                            FilledButton.icon(
                              onPressed: () => showPlansPrompt(
                                context,
                                title: AppConstants.syncTitle.tr(),
                                message: AppConstants.syncLocked.tr(),
                              ),
                              icon: const Icon(
                                Icons.workspace_premium_outlined,
                              ),
                              label: Text(AppConstants.syncLocked.tr()),
                            )
                          else if (_failed && !_enabledHere)
                            Text(
                              AppConstants.syncStatusOffline.tr(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.mutedText),
                            )
                          else if (!_enabledHere)
                            ..._notEnabled()
                          else
                            ..._enabled(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _notEnabled() {
    final startedElsewhere = _account?.enabled ?? false;
    return [
      if (startedElsewhere) ...[
        Text(
          AppConstants.syncJoinHint.tr(),
          style: const TextStyle(color: AppTheme.mutedText, height: 1.45),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _join,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: Text(AppConstants.syncJoin.tr()),
        ),
      ] else ...[
        FilledButton.icon(
          onPressed: _busy ? null : _turnOn,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync_rounded),
          label: Text(AppConstants.syncTurnOn.tr()),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _busy ? null : _join,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: Text(AppConstants.syncJoin.tr()),
        ),
      ],
    ];
  }

  List<Widget> _enabled() {
    final status = _sync.status.value;
    final devices = _account?.devices ?? const <SyncDeviceInfo>[];
    final locale = context.locale.toString();
    final String line;
    if (status.running) {
      line = AppConstants.syncStatusSyncing.tr();
    } else if (status.waitingForLibrary) {
      line = AppConstants.syncStatusWaiting.tr();
    } else if (status.problem != null) {
      line = syncProblemMessage(status.problem!, maxDevices: _maxDevices);
    } else if (status.toReceive > 0) {
      line = AppConstants.syncStatusReceiving.tr(
        namedArgs: {'count': '${status.toReceive}'},
      );
    } else if (status.lastSyncAt != null) {
      line = AppConstants.syncStatusSynced.tr(
        namedArgs: {
          'date': DateFormat.yMMMd(locale).add_Hm().format(status.lastSyncAt!),
        },
      );
    } else {
      line = AppConstants.syncStatusNever.tr();
    }
    return [
      Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Icon(
                status.problem != null
                    ? Icons.sync_problem_rounded
                    : status.running
                    ? Icons.sync_rounded
                    : Icons.cloud_done_outlined,
                color: status.problem != null
                    ? AppTheme.warning
                    : AppTheme.success,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  line,
                  style: const TextStyle(color: AppTheme.text, height: 1.35),
                ),
              ),
              IconButton(
                tooltip: AppConstants.syncSyncNow.tr(),
                onPressed: status.running ? null : _sync.syncNow,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      Row(
        children: [
          Expanded(
            child: Text(
              AppConstants.syncDevices.tr(),
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            AppConstants.syncDevicesCount.tr(
              namedArgs: {'count': '${devices.length}', 'max': '$_maxDevices'},
            ),
            style: const TextStyle(color: AppTheme.mutedText),
          ),
        ],
      ),
      const SizedBox(height: 10),
      for (final device in devices) ...[
        _DeviceTile(
          device: device,
          thisDevice: device.id == _sync.thisDeviceId,
          onRemove: _busy ? null : () => _remove(device),
        ),
        const SizedBox(height: 8),
      ],
      if (_failed)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            AppConstants.syncStatusOffline.tr(),
            style: const TextStyle(color: AppTheme.mutedText),
          ),
        ),
      const SizedBox(height: 12),
      if (devices.length < _maxDevices)
        FilledButton.icon(
          onPressed: _busy ? null : _addDevice,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: Text(AppConstants.syncAddDevice.tr()),
        ),
    ];
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.maxDevices});

  final int maxDevices;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accent.withValues(alpha: 0.14),
          ),
          child: Icon(Icons.devices_rounded, color: AppTheme.accent, size: 30),
        ),
        const SizedBox(height: 14),
        Text(
          AppConstants.syncIntro.tr(namedArgs: {'max': '$maxDevices'}),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.mutedText, height: 1.45),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: AppTheme.success,
            ),
            const SizedBox(width: 6),
            Text(
              AppConstants.syncEncrypted.tr(),
              style: const TextStyle(
                color: AppTheme.success,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.thisDevice,
    required this.onRemove,
  });

  final SyncDeviceInfo device;
  final bool thisDevice;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final seen = DateFormat.yMMMd(
      context.locale.toString(),
    ).add_Hm().format(device.lastSeenAt);
    final subtitle = thisDevice
        ? AppConstants.syncThisDevice.tr()
        : device.waitingForLibrary
        ? AppConstants.syncWaitingLibrary.tr()
        : AppConstants.syncLastSeen.tr(namedArgs: {'date': seen});
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        leading: Icon(
          device.platform == 'ios'
              ? Icons.phone_iphone_rounded
              : Icons.phone_android_rounded,
          color: thisDevice ? AppTheme.accent : AppTheme.mutedText,
        ),
        title: Text(
          device.name,
          style: const TextStyle(
            color: AppTheme.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: thisDevice ? AppTheme.accent : AppTheme.mutedText,
          ),
        ),
        trailing: IconButton(
          tooltip: thisDevice
              ? AppConstants.syncLeave.tr()
              : AppConstants.syncRemove.tr(),
          onPressed: onRemove,
          icon: Icon(
            thisDevice ? Icons.logout_rounded : Icons.close_rounded,
            color: AppTheme.mutedText,
          ),
        ),
      ),
    );
  }
}

/// Shows the QR code another device scans to join, and waits for it.
class _InviteSheet extends StatefulWidget {
  const _InviteSheet();

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _sync = SyncService.instance;
  ({String payload, DateTime expiresAt, String code})? _invite;
  String? _joinedName;
  String? _error;
  Timer? _poll;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _create();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _invite = null;
      _error = null;
    });
    try {
      final invite = await _sync.createInvite();
      if (!mounted) return;
      setState(() => _invite = invite);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    } on SyncApiException catch (error) {
      if (mounted) setState(() => _error = syncProblemMessage(error.problem));
    } catch (_) {
      if (mounted) setState(() => _error = AppConstants.syncFailed.tr());
    }
  }

  Future<void> _check() async {
    final invite = _invite;
    if (invite == null || _joinedName != null) return;
    try {
      final state = await _sync.invitationStatus(invite.code);
      if (!state.joined || !mounted) return;
      _poll?.cancel();
      setState(() => _joinedName = state.deviceName ?? '');
      // The new device waits for the library: send it right away.
      await _sync.syncNow();
      await Future<void>.delayed(const Duration(seconds: 2));
      await _sync.syncNow();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // Keep waiting; the next poll tries again.
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    final left = invite?.expiresAt.difference(DateTime.now());
    final expired = left != null && left.isNegative;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppConstants.syncAddDevice.tr(),
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppConstants.syncAddHint.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.mutedText, height: 1.4),
            ),
            const SizedBox(height: 18),
            SizedBox.square(
              dimension: 232,
              child: _joinedName != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppTheme.success,
                          size: 56,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          AppConstants.syncJoined.tr(
                            namedArgs: {'name': _joinedName!},
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.text),
                        ),
                      ],
                    )
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.mutedText),
                      ),
                    )
                  : invite == null
                  ? const Center(child: CircularProgressIndicator())
                  : Opacity(
                      opacity: expired ? 0.15 : 1,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: QrImageView(
                          data: invite.payload,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            if (invite != null && _joinedName == null)
              expired
                  ? FilledButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(AppConstants.syncNewCode.tr()),
                    )
                  : Text(
                      AppConstants.syncQrExpires.tr(
                        namedArgs: {'minutes': '${left!.inMinutes + 1}'},
                      ),
                      style: const TextStyle(color: AppTheme.mutedText),
                    ),
          ],
        ),
      ),
    );
  }
}

/// The camera, until it reads an AllDocs sync code.
class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final _controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _done = false;
  bool _warned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      if (SyncService.looksLikeInvite(value)) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
      if (!_warned) {
        _warned = true;
        showSnack(context, AppConstants.syncNotInvite.tr());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? AppConstants.syncCameraDenied.tr()
                      : AppConstants.syncFailed.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                  child: Text(
                    AppConstants.syncScanHint.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
