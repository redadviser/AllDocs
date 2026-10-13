import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'backup_flow.dart';

/// The restore points of each connected cloud, newest first, each with a
/// button that brings the library back to that moment. With [limit], only
/// the newest few, and a button to the full history page.
class BackupHistory extends StatefulWidget {
  const BackupHistory({
    super.key,
    required this.documentsService,
    this.limit,
    this.initialCloud,
    this.showTitle = true,
  });

  final DocumentsService documentsService;
  final int? limit;

  /// The cloud shown first (otherwise the backup destination).
  final CloudProviderId? initialCloud;
  final bool showTitle;

  @override
  State<BackupHistory> createState() => _BackupHistoryState();
}

class _BackupHistoryState extends State<BackupHistory> {
  List<CloudProvider>? _clouds;
  CloudProvider? _selected;
  Future<List<BackupSnapshot>>? _snapshots;

  @override
  void initState() {
    super.initState();
    // A new backup adds a restore point; another destination may be a
    // cloud that wasn't connected before.
    AppSettings.lastBackupAt.addListener(_reload);
    AppSettings.backupProvider.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    AppSettings.lastBackupAt.removeListener(_reload);
    AppSettings.backupProvider.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final clouds = await widget.documentsService.cloud.connectedProviders();
    if (!mounted) return;
    final keep = clouds
        .where((c) => c.id == (_selected?.id ?? widget.initialCloud))
        .firstOrNull;
    final destination = clouds
        .where((c) => c.id.name == AppSettings.backupProvider.value)
        .firstOrNull;
    setState(() {
      _clouds = clouds;
      _selected = keep ?? destination ?? clouds.firstOrNull;
      _snapshots = _load(_selected);
    });
  }

  Future<List<BackupSnapshot>> _load(CloudProvider? cloud) async {
    if (cloud == null) return const [];
    return widget.documentsService.backup.listCloudSnapshots(cloud);
  }

  void _select(CloudProvider cloud) {
    setState(() {
      _selected = cloud;
      _snapshots = _load(cloud);
    });
  }

  @override
  Widget build(BuildContext context) {
    final clouds = _clouds;
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle) ...[
          Text(
            AppConstants.backupHistory.tr(),
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (clouds == null)
          const _Loading()
        else if (clouds.isEmpty || selected == null)
          Text(
            AppConstants.backupHistoryConnect.tr(),
            style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
          )
        else ...[
          if (clouds.length > 1) ...[
            Wrap(
              spacing: 8,
              children: [
                for (final cloud in clouds)
                  ChoiceChip(
                    avatar: Icon(cloudProviderIcon(cloud.id), size: 18),
                    label: Text(cloud.displayName),
                    selected: cloud.id == selected.id,
                    onSelected: (_) => _select(cloud),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          FutureBuilder<List<BackupSnapshot>>(
            future: _snapshots,
            builder: (context, result) {
              if (result.connectionState != ConnectionState.done) {
                return const _Loading();
              }
              if (result.hasError) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppConstants.backupHistoryFailed.tr(),
                        style: const TextStyle(color: AppTheme.mutedText),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _select(selected),
                      child: Text(AppConstants.backupRetry.tr()),
                    ),
                  ],
                );
              }
              final snapshots = result.data ?? const [];
              if (snapshots.isEmpty) {
                return Text(
                  AppConstants.backupHistoryEmpty.tr(
                    namedArgs: {'provider': selected.displayName},
                  ),
                  style: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 13,
                  ),
                );
              }
              final limit = widget.limit;
              final shown = limit == null
                  ? snapshots
                  : snapshots.take(limit).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final snapshot in shown)
                    _RestorePoint(
                      snapshot: snapshot,
                      onRestore: () => restoreBackupSnapshot(
                        context,
                        widget.documentsService,
                        snapshot,
                      ),
                    ),
                  if (shown.length < snapshots.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: TextButton.icon(
                        onPressed: () => openBackupHistory(
                          context,
                          widget.documentsService,
                          cloud: selected.id,
                        ),
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: Text(
                          AppConstants.backupSeeAll.tr(
                            namedArgs: {'count': '${snapshots.length}'},
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

/// Every restore point, on a page of its own, by cloud.
Future<void> openBackupHistory(
  BuildContext context,
  DocumentsService documentsService, {
  CloudProviderId? cloud,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
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
                        AppConstants.backupHistoryPage.tr(),
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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    BackupHistory(
                      documentsService: documentsService,
                      initialCloud: cloud,
                      showTitle: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _RestorePoint extends StatelessWidget {
  const _RestorePoint({required this.snapshot, required this.onRestore});

  final BackupSnapshot snapshot;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final locale = context.locale.toString();
    final day = DateFormat.yMMMd(locale).format(snapshot.createdAt);
    final note = [
      DateFormat.Hm(locale).format(snapshot.createdAt),
      if (snapshot.isLatest) AppConstants.backupLatest.tr(),
      if (snapshot.isLegacy) AppConstants.backupLegacy.tr(),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: AppTheme.surfaceStrong,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            children: [
              Icon(
                snapshot.isLegacy
                    ? Icons.folder_zip_outlined
                    : Icons.history_rounded,
                size: 20,
                color: snapshot.isLatest
                    ? AppTheme.success
                    : AppTheme.mutedText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      note,
                      style: TextStyle(
                        color: snapshot.isLatest
                            ? AppTheme.success
                            : AppTheme.mutedText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onRestore,
                icon: const Icon(
                  Icons.settings_backup_restore_rounded,
                  size: 18,
                ),
                label: Text(AppConstants.backupRestore.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
