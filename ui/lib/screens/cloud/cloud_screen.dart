import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/app_constants.dart';
import '../../common/album_dialog.dart';
import '../../common/document_actions.dart';
import '../../common/document_import_flow.dart';
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
    if (!mounted) return;
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
    try {
      await SecurityLockService.withoutAutoLock(provider.connect);
      await _refreshStatus();
      if (mounted) {
        showSnack(
          context,
          AppConstants.cloudConnected.tr(
            namedArgs: {'provider': provider.displayName},
          ),
        );
      }
      return true;
    } on CloudNotConfiguredException {
      if (mounted) showSnack(context, AppConstants.cloudNotConfigured.tr());
    } catch (_) {
      if (mounted) showSnack(context, AppConstants.cloudConnectFailed.tr());
    }
    return false;
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

    return ListView(
      key: const PageStorageKey('cloud'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
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
        const SizedBox(height: 18),
        _Card(
          children: [
            for (final provider in _cloud.providers) ...[
              _ProviderTile(
                provider: provider,
                status: _status[provider.id],
                onConnect: () => _connect(provider),
                onOpen: () => openProvider(provider.id),
                onDisconnect: () => _disconnect(provider),
              ),
              if (provider != _cloud.providers.last) const Divider(indent: 64),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          children: [
            ListTile(
              leading: const Icon(Icons.bolt_outlined),
              title: Text(AppConstants.cloudQuickImport.tr()),
              subtitle: Text(
                AppConstants.cloudQuickImportHint.tr(),
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 12.5,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () =>
                  pickAndImportDocuments(context, widget.documentsService),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SectionTitle(AppConstants.cloudUpdatesTitle.tr()),
        const SizedBox(height: 8),
        _Card(
          children: [
            ListTile(
              leading: _checkingUpdates
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              title: Text(AppConstants.cloudCheckUpdates.tr()),
              subtitle: Text(
                _updates == null
                    ? AppConstants.cloudUpdatesHint.tr()
                    : _updates!.isEmpty
                    ? AppConstants.cloudUpToDate.tr()
                    : AppConstants.cloudUpdatesFound.tr(
                        namedArgs: {'count': '${_updates!.length}'},
                      ),
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 12.5,
                ),
              ),
              onTap: connected.isEmpty || _checkingUpdates
                  ? null
                  : _checkUpdates,
            ),
            for (final update in _updates ?? const <CloudUpdate>[]) ...[
              const Divider(indent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
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
                          onPressed: () => _resolveUpdate(update, apply: false),
                          child: Text(AppConstants.cloudKeepCurrent.tr()),
                        ),
                        TextButton(
                          onPressed: () => _resolveUpdate(update, apply: true),
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
        const SizedBox(height: 24),
        _SectionTitle(AppConstants.backupTitle.tr()),
        const SizedBox(height: 8),
        _BackupCard(
          connected: connected,
          busy: _backingUp,
          onBackupNow: _backupNow,
          onSaveToDevice: _saveToDevice,
          onRestore: () => _restore(connected),
        ),
      ],
    );
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

  Future<void> _backupNow() async {
    final providerId = AppSettings.backupProvider.value;
    final provider = providerId == null
        ? null
        : _cloud.providerNamed(providerId);
    if (provider == null) {
      await _saveToDevice();
      return;
    }
    setState(() => _backingUp = true);
    try {
      await widget.documentsService.backup.backupToCloud(provider);
      if (mounted) showSnack(context, AppConstants.backupDone.tr());
    } catch (_) {
      if (mounted) showSnack(context, AppConstants.backupFailed.tr());
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _saveToDevice() async {
    setState(() => _backingUp = true);
    try {
      final path = await SecurityLockService.withoutAutoLock(
        () => widget.documentsService.backup.saveBackupToDevice(
          dialogTitle: AppConstants.backupPickFolder.tr(),
        ),
      );
      if (path != null && mounted) {
        showSnack(
          context,
          AppConstants.backupSavedTo.tr(namedArgs: {'path': path}),
        );
      }
    } catch (_) {
      if (mounted) showSnack(context, AppConstants.backupFailed.tr());
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _restore(List<CloudProvider> connected) async {
    final source = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone_android_outlined),
              title: Text(AppConstants.backupFromDevice.tr()),
              onTap: () => Navigator.of(context).pop('device'),
            ),
            for (final provider in connected)
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: Text(provider.displayName),
                onTap: () => Navigator.of(context).pop(provider),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    Future<BackupInfo?> Function()? restore;
    if (source == 'device') {
      restore = () => SecurityLockService.withoutAutoLock(
        widget.documentsService.backup.pickAndRestoreFromDevice,
      );
    } else if (source is CloudProvider) {
      final backups = await source.listBackups();
      if (!mounted) return;
      if (backups.isEmpty) {
        showSnack(context, AppConstants.backupNoneFound.tr());
        return;
      }
      backups.sort(
        (a, b) => (b.modifiedAt ?? DateTime(1970)).compareTo(
          a.modifiedAt ?? DateTime(1970),
        ),
      );
      final chosen = await showModalBottomSheet<CloudItem>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final backup in backups)
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(backup.name),
                  subtitle: backup.modifiedAt == null
                      ? null
                      : Text(
                          DateFormat.yMMMd().add_Hm().format(
                            backup.modifiedAt!.toLocal(),
                          ),
                        ),
                  onTap: () => Navigator.of(context).pop(backup),
                ),
            ],
          ),
        ),
      );
      if (chosen == null) return;
      restore = () =>
          widget.documentsService.backup.restoreFromCloud(source, chosen);
    }
    if (restore == null || !mounted) return;

    final confirmed = await showConfirmDialog(
      context,
      title: AppConstants.backupRestoreTitle.tr(),
      message: AppConstants.backupRestoreMessage.tr(),
      actionLabel: AppConstants.backupRestore.tr(),
    );
    if (!confirmed || !mounted) return;

    setState(() => _backingUp = true);
    try {
      final info = await widget.documentsService.restoreBackup(restore());
      if (info != null && mounted) {
        showSnack(
          context,
          AppConstants.backupRestored.tr(
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

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.status,
    required this.onConnect,
    required this.onOpen,
    required this.onDisconnect,
  });

  final CloudProvider provider;
  final _ProviderStatus? status;
  final VoidCallback onConnect;
  final VoidCallback onOpen;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final connected = status?.connected == true;
    final subtitle = !provider.isConfigured
        ? AppConstants.cloudNotConfiguredShort.tr()
        : connected
        ? (status?.account ?? AppConstants.cloudConnectedShort.tr())
        : AppConstants.cloudNotConnected.tr();

    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      leading: CircleAvatar(
        backgroundColor: _color(provider.id).withValues(alpha: 0.14),
        child: Icon(_icon(provider.id), color: _color(provider.id), size: 22),
      ),
      title: Text(provider.displayName),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppTheme.mutedText, fontSize: 12.5),
      ),
      onTap: connected ? onOpen : null,
      trailing: connected
          ? PopupMenuButton<String>(
              onSelected: (value) =>
                  value == 'open' ? onOpen() : onDisconnect(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'open',
                  child: Text(AppConstants.cloudBrowse.tr()),
                ),
                PopupMenuItem(
                  value: 'disconnect',
                  child: Text(AppConstants.cloudDisconnect.tr()),
                ),
              ],
            )
          : OutlinedButton(
              onPressed: provider.isConfigured ? onConnect : null,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
              child: Text(AppConstants.cloudConnect.tr()),
            ),
    );
  }

  IconData _icon(CloudProviderId id) => switch (id) {
    CloudProviderId.oneDrive => Icons.cloud_outlined,
    CloudProviderId.googleDrive => Icons.add_to_drive_outlined,
    CloudProviderId.dropbox => Icons.cloud_queue_outlined,
  };

  Color _color(CloudProviderId id) => switch (id) {
    CloudProviderId.oneDrive => const Color(0xFF4A90D9),
    CloudProviderId.googleDrive => const Color(0xFF5DB37E),
    CloudProviderId.dropbox => const Color(0xFF5B7FE0),
  };
}

class _BackupCard extends StatelessWidget {
  const _BackupCard({
    required this.connected,
    required this.busy,
    required this.onBackupNow,
    required this.onSaveToDevice,
    required this.onRestore,
  });

  final List<CloudProvider> connected;
  final bool busy;
  final VoidCallback onBackupNow;
  final VoidCallback onSaveToDevice;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppSettings.backupProvider,
        AppSettings.autoBackup,
        AppSettings.lastBackupAt,
      ]),
      builder: (context, _) {
        final selected = connected
            .where((p) => p.id.name == AppSettings.backupProvider.value)
            .firstOrNull;
        final last = AppSettings.lastBackupAt.value;
        return _Card(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                AppConstants.backupHint.tr(),
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: Text(AppConstants.backupDestination.tr()),
              trailing: DropdownButton<String?>(
                value: selected?.id.name,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(AppConstants.backupThisDevice.tr()),
                  ),
                  for (final provider in connected)
                    DropdownMenuItem<String?>(
                      value: provider.id.name,
                      child: Text(provider.displayName),
                    ),
                ],
                onChanged: AppSettings.setBackupProvider,
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.schedule_outlined),
              title: Text(AppConstants.backupAuto.tr()),
              subtitle: Text(
                selected == null
                    ? AppConstants.backupAutoNeedsCloud.tr()
                    : AppConstants.backupAutoHint.tr(),
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 12.5,
                ),
              ),
              value: AppSettings.autoBackup.value && selected != null,
              onChanged: selected == null ? null : AppSettings.setAutoBackup,
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text(AppConstants.backupLast.tr()),
              trailing: Text(
                last == null
                    ? AppConstants.backupNever.tr()
                    : DateFormat.yMMMd().add_Hm().format(last),
                style: const TextStyle(color: AppTheme.mutedText),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: busy ? null : onBackupNow,
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.backup_outlined),
                      label: Text(AppConstants.backupNow.tr()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (selected != null) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy ? null : onSaveToDevice,
                            child: Text(
                              AppConstants.backupSaveDevice.tr(),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy ? null : onRestore,
                          child: Text(AppConstants.backupRestore.tr()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.text,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
