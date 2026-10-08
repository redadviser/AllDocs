import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/app_constants.dart';
import '../../common/album_dialog.dart';
import '../../common/app_sheet.dart';
import '../../common/backup_flow.dart';
import '../../common/document_actions.dart';
import '../../common/document_import_flow.dart';
import '../../common/plan_prompts.dart';
import '../../common/settings_grid.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import 'cloud_browser_screen.dart';

class _ProviderStatus {
  const _ProviderStatus({required this.connected, this.account});
  final bool connected;
  final String? account;
}

/// Opens "Connections" (cloud accounts + backup) as its own page, from the
/// profile or from the "+ Add" menu. With [provider], goes straight into
/// that account's file browser (connecting first if needed).
Future<void> openConnectionsPage(
  BuildContext context,
  DocumentsService documentsService, {
  CloudProviderId? provider,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: CloudScreen(
            documentsService: documentsService,
            initialProvider: provider,
          ),
        ),
      ),
    ),
  );
}

/// Cloud accounts: connect, browse and import (a local copy is kept), check
/// for newer versions of imported files, and back up the whole app.
class CloudScreen extends StatefulWidget {
  const CloudScreen({
    super.key,
    required this.documentsService,
    this.initialProvider,
  });

  final DocumentsService documentsService;
  final CloudProviderId? initialProvider;

  @override
  State<CloudScreen> createState() => CloudScreenState();
}

class CloudScreenState extends State<CloudScreen> {
  final Map<CloudProviderId, _ProviderStatus> _status = {};
  List<CloudUpdate>? _updates;
  bool _checkingUpdates = false;
  bool _backingUp = false;

  CloudService get _cloud => widget.documentsService.cloud;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    final provider = widget.initialProvider;
    if (provider != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openProvider(provider);
      });
    }
  }

  Future<void> _refreshStatus() async {
    for (final provider in _cloud.providers) {
      final connected = provider.isConfigured && await provider.isConnected();
      final account = connected ? await provider.accountLabel() : null;
      _status[provider.id] = _ProviderStatus(
        connected: connected,
        account: account,
      );
    }
    if (mounted) setState(() {});
  }

  /// Opens the file browser of [id], connecting first if needed. Used by
  /// the "+ Add" menu's cloud entries.
  Future<void> openProvider(CloudProviderId id) async {
    final provider = _cloud.provider(id);
    if (provider == null) return;
    if (!provider.isConfigured) {
      showSnack(context, AppConstants.cloudNotConfigured.tr());
      return;
    }
    if (!await provider.isConnected()) {
      final ok = await _connect(provider);
      if (!ok) return;
    }
    if (!mounted || !provider.canBrowseFiles) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudBrowserScreen(
          documentsService: widget.documentsService,
          provider: provider,
        ),
      ),
    );
  }

  Future<bool> _connect(CloudProvider provider) async {
    final ok = await connectCloudProvider(context, provider);
    await _refreshStatus();
    return ok;
  }

  Future<void> _disconnect(CloudProvider provider) async {
    final confirmed = await showConfirmDialog(
      context,
      title: AppConstants.cloudDisconnectTitle.tr(
        namedArgs: {'provider': provider.displayName},
      ),
      message: AppConstants.cloudDisconnectMessage.tr(),
      actionLabel: AppConstants.cloudDisconnect.tr(),
    );
    if (!confirmed) return;
    await provider.disconnect();
    if (AppSettings.backupProvider.value == provider.id.name) {
      await AppSettings.setBackupProvider(null);
    }
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _cloud.providers
        .where((provider) => _status[provider.id]?.connected == true)
        .toList();
    final updates = _updates;

    return ListView(
      key: const PageStorageKey('cloud'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            Transform.translate(
              offset: const Offset(-12, 0),
              child: const BackButton(),
            ),
            Text(
              AppConstants.connectionsTitle.tr(),
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            AppConstants.cloudSubtitle.tr(),
            style: const TextStyle(color: AppTheme.mutedText, height: 1.35),
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          icon: Icons.cloud_outlined,
          title: AppConstants.cloudAccountsTitle.tr(),
          child: SettingsGrid(
            children: [
              for (final provider in _cloud.providers) _providerTile(provider),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SettingsSection(
          icon: Icons.download_outlined,
          title: AppConstants.cloudImportTitle.tr(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsGrid(
                children: [
                  SettingsGridAction(
                    icon: Icons.bolt_outlined,
                    title: AppConstants.cloudQuickImport.tr(),
                    onTap: () => pickAndImportDocuments(
                      context,
                      widget.documentsService,
                    ),
                  ),
                  SettingsGridAction(
                    icon: Icons.sync_rounded,
                    title: AppConstants.cloudCheckUpdates.tr(),
                    value: updates == null
                        ? null
                        : updates.isEmpty
                        ? AppConstants.cloudUpToDate.tr()
                        : AppConstants.cloudUpdatesFound.tr(
                            namedArgs: {'count': '${updates.length}'},
                          ),
                    loading: _checkingUpdates,
                    onTap: connected.isEmpty || _checkingUpdates
                        ? null
                        : _checkUpdates,
                  ),
                ],
              ),
              for (final update in updates ?? const <CloudUpdate>[]) ...[
                const SizedBox(height: 8),
                SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppConstants.cloudUpdatedFile.tr(
                          namedArgs: {'name': update.document.fileName},
                        ),
                        style: const TextStyle(color: AppTheme.text),
                      ),
                      Text(
                        update.provider.displayName,
                        style: const TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 12,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                _resolveUpdate(update, apply: false),
                            child: Text(AppConstants.cloudKeepCurrent.tr()),
                          ),
                          TextButton(
                            onPressed: () =>
                                _resolveUpdate(update, apply: true),
                            child: Text(AppConstants.cloudUpdate.tr()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _BackupSection(
          providers: _cloud.providers,
          status: _status,
          busy: _backingUp,
          onChooseDestination: _chooseBackupDestination,
          onBackupNow: _backupNow,
          onRestore: _restore,
        ),
      ],
    );
  }

  /// An account: tap to connect it; once connected, tap for its options.
  Widget _providerTile(CloudProvider provider) {
    final status = _status[provider.id];
    final isConnected = status?.connected == true;
    return SettingsGridAction(
      icon: cloudProviderIcon(provider.id),
      iconColor: _providerColor(provider.id),
      title: provider.displayName,
      value: !provider.isConfigured
          ? AppConstants.cloudNotConfiguredShort.tr()
          : isConnected
          ? (status?.account ?? AppConstants.cloudConnectedShort.tr())
          : AppConstants.cloudConnect.tr(),
      onTap: !provider.isConfigured
          ? null
          : isConnected
          ? () => _showProviderOptions(provider)
          : () => _connect(provider),
    );
  }

  Future<void> _showProviderOptions(CloudProvider provider) async {
    final action = await showOptionsSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                provider.displayName,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (provider.canBrowseFiles)
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(AppConstants.cloudBrowse.tr()),
                onTap: () => Navigator.of(context).pop('open'),
              ),
            ListTile(
              leading: const Icon(
                Icons.link_off_rounded,
                color: AppTheme.destructive,
              ),
              title: Text(
                AppConstants.cloudDisconnect.tr(),
                style: const TextStyle(color: AppTheme.destructive),
              ),
              onTap: () => Navigator.of(context).pop('disconnect'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'open') await openProvider(provider.id);
    if (action == 'disconnect') await _disconnect(provider);
  }

  /// "Save to": this phone or one of the accounts (connected on the spot).
  Future<void> _chooseBackupDestination() async {
    final current = AppSettings.backupProvider.value;
    final choice = await showOptionsSheet<({CloudProvider? provider})>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                AppConstants.backupDestination.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _DestinationTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.surfaceStrong,
                child: Icon(
                  Icons.phone_android_outlined,
                  color: AppTheme.text,
                  size: 22,
                ),
              ),
              title: AppConstants.backupThisDevice.tr(),
              selected: _backupProvider == null,
              onTap: () => Navigator.of(context).pop((provider: null)),
            ),
            for (final provider in _cloud.providers)
              _DestinationTile(
                leading: _ProviderAvatar(provider.id),
                title: provider.displayName,
                subtitle: !provider.isConfigured
                    ? AppConstants.cloudNotConfiguredShort.tr()
                    : _status[provider.id]?.connected == true
                    ? (_status[provider.id]?.account ??
                          AppConstants.cloudConnectedShort.tr())
                    : AppConstants.cloudTapToConnect.tr(),
                selected:
                    current == provider.id.name &&
                    _status[provider.id]?.connected == true,
                onTap: provider.isConfigured
                    ? () => Navigator.of(context).pop((provider: provider))
                    : null,
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _selectBackupDestination(choice.provider);
  }

  Future<void> _checkUpdates() async {
    setState(() => _checkingUpdates = true);
    final snapshot = await widget.documentsService.loadSnapshot();
    final updates = await widget.documentsService.checkCloudUpdates([
      ...snapshot.documents,
      ...snapshot.archivedDocuments,
    ]);
    if (!mounted) return;
    setState(() {
      _updates = updates;
      _checkingUpdates = false;
    });
  }

  Future<void> _resolveUpdate(CloudUpdate update, {required bool apply}) async {
    try {
      if (apply) {
        await widget.documentsService.applyCloudUpdate(update);
      } else {
        await widget.documentsService.keepCurrentVersion(update);
      }
      if (!mounted) return;
      setState(() => _updates = [..._updates!]..remove(update));
      if (apply) showSnack(context, AppConstants.cloudUpdated.tr());
    } catch (_) {
      if (mounted) showSnack(context, AppConstants.cloudRequestFailed.tr());
    }
  }

  /// Picking a cloud that isn't connected yet connects it first; null means
  /// "this phone".
  Future<void> _selectBackupDestination(CloudProvider? provider) async {
    if (provider == null) {
      await AppSettings.setBackupProvider(null);
      return;
    }
    if (!provider.isConfigured) {
      showSnack(context, AppConstants.cloudNotConfigured.tr());
      return;
    }
    if (_status[provider.id]?.connected != true && !await _connect(provider)) {
      return;
    }
    await AppSettings.setBackupProvider(provider.id.name);
  }

  CloudProvider? get _backupProvider {
    final providerId = AppSettings.backupProvider.value;
    final provider = providerId == null
        ? null
        : _cloud.providerNamed(providerId);
    if (provider == null || _status[provider.id]?.connected != true) {
      return null;
    }
    return provider;
  }

  Future<void> _backupNow() async {
    final provider = _backupProvider;
    setState(() => _backingUp = true);
    try {
      provider == null
          ? await saveBackupToDevice(context, widget.documentsService)
          : await backupToCloud(context, widget.documentsService, provider);
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _restore() async {
    // Every configured cloud is offered, not just connected ones: after a
    // reinstall nothing is connected yet, and that's exactly when a restore
    // is needed.
    final clouds = _cloud.providers.where((p) => p.isConfigured).toList();
    final source = await showOptionsSheet<Object>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone_android_outlined),
              title: Text(AppConstants.backupFromDevice.tr()),
              onTap: () => Navigator.of(context).pop('device'),
            ),
            for (final provider in clouds)
              ListTile(
                leading: Icon(cloudProviderIcon(provider.id)),
                title: Text(provider.displayName),
                subtitle: Text(
                  _status[provider.id]?.connected == true
                      ? (_status[provider.id]?.account ??
                            AppConstants.cloudConnectedShort.tr())
                      : AppConstants.cloudTapToConnect.tr(),
                  style: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 12.5,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(provider),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    if (source is CloudProvider &&
        _status[source.id]?.connected != true &&
        !await _connect(source)) {
      return;
    }
    if (!mounted) return;

    final List<BackupSnapshot> snapshots;
    try {
      if (source is CloudProvider) {
        snapshots = await widget.documentsService.backup.listCloudSnapshots(
          source,
        );
      } else {
        final folder = await SecurityLockService.withoutAutoLock(
          () => widget.documentsService.backup.pickDeviceBackupFolder(
            dialogTitle: AppConstants.backupPickRestoreFolder.tr(),
          ),
        );
        if (folder == null) return;
        snapshots = await widget.documentsService.backup.listDeviceSnapshots(
          folder,
        );
      }
    } catch (_) {
      if (mounted) showSnack(context, AppConstants.cloudRequestFailed.tr());
      return;
    }
    if (!mounted) return;
    if (snapshots.isEmpty) {
      showSnack(context, AppConstants.backupNoneFound.tr());
      return;
    }
    final chosen = await showOptionsSheet<BackupSnapshot>(
      context: context,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  AppConstants.backupHistoryTitle.tr(),
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final snapshot in snapshots)
                      ListTile(
                        leading: Icon(
                          snapshot.isLegacy
                              ? Icons.folder_zip_outlined
                              : Icons.history_rounded,
                        ),
                        title: Text(
                          DateFormat.yMMMd().add_Hm().format(
                            snapshot.createdAt,
                          ),
                        ),
                        subtitle: snapshot.isLatest || snapshot.isLegacy
                            ? Text(
                                snapshot.isLatest
                                    ? AppConstants.backupLatest.tr()
                                    : AppConstants.backupLegacy.tr(),
                                style: const TextStyle(
                                  color: AppTheme.mutedText,
                                  fontSize: 12.5,
                                ),
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(snapshot),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    final confirmed = await showConfirmDialog(
      context,
      title: AppConstants.backupRestoreTitle.tr(),
      message: AppConstants.backupRestoreMessage.tr(),
      actionLabel: AppConstants.backupRestore.tr(),
    );
    if (!confirmed || !mounted) return;

    setState(() => _backingUp = true);
    try {
      final info = await widget.documentsService.restoreBackup(
        widget.documentsService.backup.restoreSnapshot(chosen),
      );
      if (info != null && mounted) {
        showSnack(
          context,
          info.missingCount > 0
              ? AppConstants.backupRestoredMissing.tr(
                  namedArgs: {
                    'count': '${info.documentCount}',
                    'missing': '${info.missingCount}',
                  },
                )
              : AppConstants.backupRestored.tr(
                  namedArgs: {'count': '${info.documentCount}'},
                ),
        );
      }
    } on InvalidBackupException {
      if (mounted) showSnack(context, AppConstants.backupInvalid.tr());
    } catch (_) {
      if (mounted) showSnack(context, AppConstants.backupFailed.tr());
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }
}

Color _providerColor(CloudProviderId id) => switch (id) {
  CloudProviderId.googleDrive => const Color(0xFF5DB37E),
  CloudProviderId.dropbox => const Color(0xFF5B7FE0),
};

class _ProviderAvatar extends StatelessWidget {
  const _ProviderAvatar(this.id);
  final CloudProviderId id;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: _providerColor(id).withValues(alpha: 0.14),
      child: Icon(cloudProviderIcon(id), color: _providerColor(id), size: 22),
    );
  }
}

/// Where backups go, the daily automatic backup, backing up now and
/// restoring one from the history.
class _BackupSection extends StatelessWidget {
  const _BackupSection({
    required this.providers,
    required this.status,
    required this.busy,
    required this.onChooseDestination,
    required this.onBackupNow,
    required this.onRestore,
  });

  final List<CloudProvider> providers;
  final Map<CloudProviderId, _ProviderStatus> status;
  final bool busy;
  final VoidCallback onChooseDestination;
  final VoidCallback onBackupNow;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppSettings.backupProvider,
        AppSettings.autoBackup,
        AppSettings.lastBackupAt,
        PlanService.current,
      ]),
      builder: (context, _) {
        final canAutoBackup = PlanService.current.value.has(
          PlanFeature.autoBackup,
        );
        // A saved destination whose account was disconnected falls back to
        // this phone.
        final selected = providers
            .where(
              (p) =>
                  p.id.name == AppSettings.backupProvider.value &&
                  status[p.id]?.connected == true,
            )
            .firstOrNull;
        final last = AppSettings.lastBackupAt.value;
        return SettingsSection(
          icon: Icons.backup_outlined,
          title: AppConstants.backupTitle.tr(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppConstants.backupHint.tr(),
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                '${AppConstants.backupLast.tr()}: '
                '${last == null ? AppConstants.backupNever.tr() : DateFormat.yMMMd().add_Hm().format(last)}',
                style: const TextStyle(color: AppTheme.text, fontSize: 13),
              ),
              const SizedBox(height: 10),
              SettingsGrid(
                children: [
                  SettingsGridAction(
                    icon: selected == null
                        ? Icons.phone_android_outlined
                        : cloudProviderIcon(selected.id),
                    iconColor: selected == null
                        ? null
                        : _providerColor(selected.id),
                    title: AppConstants.backupDestination.tr(),
                    value:
                        selected?.displayName ??
                        AppConstants.backupThisDevice.tr(),
                    onTap: busy ? null : onChooseDestination,
                  ),
                  SettingsGridToggle(
                    icon: Icons.schedule_outlined,
                    title: AppConstants.backupAuto.tr(),
                    value:
                        AppSettings.autoBackup.value &&
                        selected != null &&
                        canAutoBackup,
                    onChanged: selected == null
                        ? null
                        : (enabled) {
                            if (enabled && !canAutoBackup) {
                              showPlansPrompt(
                                context,
                                title: AppConstants.backupAuto.tr(),
                                message: AppConstants.plansAutoBackupLocked
                                    .tr(),
                              );
                              return;
                            }
                            AppSettings.setAutoBackup(enabled);
                          },
                  ),
                  SettingsGridAction(
                    icon: Icons.backup_outlined,
                    title: AppConstants.backupNow.tr(),
                    loading: busy,
                    onTap: busy ? null : onBackupNow,
                  ),
                  SettingsGridAction(
                    icon: Icons.settings_backup_restore_rounded,
                    title: AppConstants.backupRestore.tr(),
                    onTap: busy ? null : onRestore,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                selected == null
                    ? AppConstants.backupAutoNeedsCloud.tr()
                    : AppConstants.backupAutoHint.tr(),
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.leading,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: AppTheme.mutedText, fontSize: 12.5),
            ),
      enabled: onTap != null || selected,
      onTap: onTap,
      trailing: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: selected ? AppTheme.accent : AppTheme.mutedText,
      ),
    );
  }
}
