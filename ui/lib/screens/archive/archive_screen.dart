import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/app_constants.dart';
import '../../common/document_tile.dart';
import '../../common/glass_panel.dart';
import '../../common/snapshot_builder.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, required this.documentsService});

  final DocumentsService documentsService;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  DocumentType? _selectedType;

  @override
  Widget build(BuildContext context) {
    return SnapshotBuilder(
      documentsService: widget.documentsService,
      builder: (context, snapshot) {
        final unorganizedDocuments = _filterDocuments(
          snapshot.unorganizedDocuments,
        );
        final recentImports = _filterDocuments(snapshot.recentImports);
        final allHistory = _filterDocuments(snapshot.documents);

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: CustomScrollView(
            key: const PageStorageKey('archive'),
            slivers: [
              SliverToBoxAdapter(
                child: _ArchiveTitle(
                  onAdd: () => widget.documentsService.importDocuments(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              SliverToBoxAdapter(
                child: _AddDocumentPanel(
                  onSelectFiles: () =>
                      widget.documentsService.importDocuments(),
                  onScanDocument: () => _scanDocument(context),
                  onUnavailable: () => _showSoon(context),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: _TypeFilters(
                  selectedType: _selectedType,
                  onSelected: (type) => setState(() => _selectedType = type),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: GlassPanel(
                  child: Column(
                    children: [
                      SectionTitle(
                        icon: Icons.inventory_2_outlined,
                        title: AppConstants.archiveUnorganized.tr(),
                        count: unorganizedDocuments.length,
                        trailing: SectionAction(
                          label: AppConstants.commonViewAll.tr(),
                          onTap: () => _showDocumentsSheet(
                            context,
                            title: AppConstants.archiveUnorganized.tr(),
                            documents: unorganizedDocuments,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (unorganizedDocuments.isEmpty)
                        _ArchiveEmptyState(filtered: _selectedType != null)
                      else
                        for (final document in unorganizedDocuments) ...[
                          DocumentTile(
                            document: document,
                            onTap: () =>
                                widget.documentsService.openDocument(document),
                            trailing: _ArchiveActions(
                              document: document,
                              snapshot: snapshot,
                              documentsService: widget.documentsService,
                            ),
                          ),
                          if (document != unorganizedDocuments.last)
                            const Divider(height: 1),
                        ],
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: GlassPanel(
                  child: Column(
                    children: [
                      SectionTitle(
                        icon: Icons.folder_outlined,
                        title: AppConstants.archiveDeviceFolders.tr(),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 108,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: snapshot.deviceFolders.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            return _DeviceFolderCard(
                              folder: snapshot.deviceFolders[index],
                              onTap: () => _openDeviceFolder(
                                context,
                                snapshot.deviceFolders[index],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: GlassPanel(
                  child: Column(
                    children: [
                      SectionTitle(
                        icon: Icons.history_rounded,
                        title: AppConstants.archiveRecentlyImported.tr(),
                        trailing: SectionAction(
                          label: AppConstants.archiveViewHistory.tr(),
                          onTap: () => _showDocumentsSheet(
                            context,
                            title: AppConstants.archiveRecentlyImported.tr(),
                            documents: allHistory,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 320) {
                            return Column(
                              children: [
                                for (final document in recentImports)
                                  DocumentTile(
                                    document: document,
                                    showImportedStatus: true,
                                    onTap: () => widget.documentsService
                                        .openDocument(document),
                                  ),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              for (final document in recentImports) ...[
                                Expanded(
                                  child: _ImportedMiniCard(document: document),
                                ),
                                if (document != recentImports.last)
                                  const SizedBox(width: 10),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _scanDocument(BuildContext context) async {
    final imported = await widget.documentsService.scanDocumentWithCamera();
    if (!context.mounted || imported == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppConstants.archiveDocumentImported.tr())),
    );
  }

  Future<void> _openDeviceFolder(
    BuildContext context,
    DeviceFolder folder,
  ) async {
    try {
      final scan = await widget.documentsService.openDeviceFolder(
        folder,
        folderTitle: _deviceFolderTitle(folder),
        dialogTitle: AppConstants.archiveSelectFolder.tr(),
      );
      if (!context.mounted || scan == null) return;
      _showDeviceFolderSheet(context, scan);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppConstants.archiveFolderOpenFailed.tr())),
      );
    }
  }

  List<DocumentFile> _filterDocuments(List<DocumentFile> documents) {
    final type = _selectedType;
    if (type == null) return documents;
    return documents.where((document) => document.type == type).toList();
  }

  void _showDocumentsSheet(
    BuildContext context, {
    required String title,
    required List<DocumentFile> documents,
  }) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.42,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, controller) {
            return Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: AppConstants.commonClose.tr(),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: documents.isEmpty
                        ? Center(
                            child: Text(
                              AppConstants.archiveNoFilterResults.tr(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.mutedText),
                            ),
                          )
                        : ListView.separated(
                            controller: controller,
                            itemCount: documents.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final document = documents[index];
                              return DocumentTile(
                                document: document,
                                onTap: () => widget.documentsService
                                    .openDocument(document),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showDeviceFolderSheet(BuildContext context, DeviceFolderScan scan) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.76,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, controller) {
            return Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.folder_open_rounded,
                        color: AppTheme.primarySoft,
                        size: 36,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              scan.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              AppConstants.archiveDeviceFolderFound.tr(
                                namedArgs: {
                                  'count': '${scan.documents.length}',
                                },
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.mutedText),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: scan.documents.isEmpty
                            ? null
                            : () async {
                                final imported = await widget.documentsService
                                    .importScannedDocuments(scan.documents);
                                if (!context.mounted) return;
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      AppConstants.archiveImportedCount.tr(
                                        namedArgs: {'count': '$imported'},
                                      ),
                                    ),
                                  ),
                                );
                              },
                        child: Text(AppConstants.commonImportAll.tr()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: scan.documents.isEmpty
                        ? Center(
                            child: Text(
                              AppConstants.archiveNoSupportedDocuments.tr(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.mutedText),
                            ),
                          )
                        : ListView.separated(
                            controller: controller,
                            itemCount: scan.documents.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final document = scan.documents[index];
                              return DocumentTile(
                                document: document,
                                onTap: () => widget.documentsService
                                    .openDocument(document),
                                trailing: TextButton(
                                  onPressed: () async {
                                    final imported = await widget
                                        .documentsService
                                        .importScannedDocuments([document]);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          imported > 0
                                              ? AppConstants
                                                    .archiveDocumentImported
                                                    .tr()
                                              : AppConstants.archiveImportFailed
                                                    .tr(),
                                        ),
                                      ),
                                    );
                                  },
                                  child: Text(AppConstants.commonImport.tr()),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

void _showSoon(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(AppConstants.archiveFeatureSoon.tr())));
}

class _ArchiveTitle extends StatelessWidget {
  const _ArchiveTitle({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            AppConstants.archiveTitle.tr(),
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.surfaceStrong,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(14),
          ),
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 30),
        ),
      ],
    );
  }
}

class _AddDocumentPanel extends StatelessWidget {
  const _AddDocumentPanel({
    required this.onSelectFiles,
    required this.onScanDocument,
    required this.onUnavailable,
  });

  final VoidCallback onSelectFiles;
  final VoidCallback onScanDocument;
  final VoidCallback onUnavailable;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppConstants.archiveAddDocument.tr().toUpperCase(),
            style: TextStyle(
              color: AppTheme.primarySoft,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AddActionCard(
                  icon: Icons.phone_android_rounded,
                  title: AppConstants.archiveSelectFromPhoneTitle.tr(),
                  subtitle: AppConstants.archiveSelectFromPhoneSubtitle.tr(),
                  gradient: const [Color(0xFF1D65DB), Color(0xFF0C3280)],
                  onTap: onSelectFiles,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AddActionCard(
                  icon: Icons.document_scanner_rounded,
                  title: AppConstants.archiveScanDocumentTitle.tr(),
                  subtitle: AppConstants.archiveScanDocumentSubtitle.tr(),
                  gradient: const [Color(0xFF7647D8), Color(0xFF253A91)],
                  onTap: onScanDocument,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AddActionCard(
                  icon: Icons.cloud_outlined,
                  title: AppConstants.archiveImportCloudTitle.tr(),
                  subtitle: AppConstants.archiveImportCloudSubtitle.tr(),
                  gradient: const [Color(0xFF0A94A9), Color(0xFF07546E)],
                  onTap: onUnavailable,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddActionCard extends StatelessWidget {
  const _AddActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 26),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 10,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeFilters extends StatelessWidget {
  const _TypeFilters({required this.selectedType, required this.onSelected});

  final DocumentType? selectedType;
  final ValueChanged<DocumentType?> onSelected;

  @override
  Widget build(BuildContext context) {
    final filters = const [
      _FilterSpec(Icons.layers_rounded, AppConstants.archiveAll, null),
      _FilterSpec(Icons.picture_as_pdf_rounded, 'PDF', DocumentType.pdf),
      _FilterSpec(Icons.description_rounded, 'Word', DocumentType.word),
      _FilterSpec(Icons.table_chart_rounded, 'Excel', DocumentType.excel),
      _FilterSpec(
        Icons.image_rounded,
        AppConstants.archiveImage,
        DocumentType.image,
      ),
    ];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = filter.type == selectedType;

          return ChoiceChip(
            selected: selected,
            onSelected: (_) => onSelected(filter.type),
            avatar: Icon(
              filter.icon,
              color: selected ? Colors.white : AppTheme.primarySoft,
              size: 18,
            ),
            label: Text(filter.translatedLabel),
            labelStyle: TextStyle(
              color: selected ? Colors.white : AppTheme.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            side: BorderSide(
              color: selected ? AppTheme.primary : AppTheme.border,
            ),
            backgroundColor: AppTheme.surface,
            selectedColor: AppTheme.primary.withValues(alpha: 0.22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          );
        },
      ),
    );
  }
}

class _ArchiveActions extends StatelessWidget {
  const _ArchiveActions({
    required this.document,
    required this.snapshot,
    required this.documentsService,
  });

  final DocumentFile document;
  final DocumentsSnapshot snapshot;
  final DocumentsService documentsService;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        if (document.isNew)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(
              AppConstants.archiveNew.tr(),
              style: const TextStyle(
                color: AppTheme.primarySoft,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        OutlinedButton(
          onPressed: () => _showArchiveTargets(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primarySoft,
            side: const BorderSide(color: AppTheme.border),
            minimumSize: const Size(96, 38),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(AppConstants.archiveArchive.tr()),
        ),
        IconButton(
          tooltip: AppConstants.commonFavorite.tr(),
          onPressed: () => documentsService.toggleFavorite(document.id),
          icon: Icon(
            document.isFavorite
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
          ),
          color: AppTheme.primarySoft,
        ),
      ],
    );
  }

  void _showArchiveTargets(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      showDragHandle: true,
      builder: (context) {
        final albums = [
          for (final shelf in snapshot.shelves)
            for (final album in shelf.albums) (shelf: shelf, album: album),
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.archiveArchiveIn.tr(),
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                if (albums.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      AppConstants.archiveNoAlbums.tr(),
                      style: const TextStyle(color: AppTheme.mutedText),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: albums.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final target = albums[index];
                        return ListTile(
                          leading: Icon(
                            Icons.folder_rounded,
                            color: Color(target.album.colorValue),
                          ),
                          title: Text(target.album.name),
                          subtitle: Text(target.shelf.name),
                          onTap: () async {
                            await documentsService.moveDocumentToAlbum(
                              document.id,
                              target.album.id,
                            );
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ArchiveEmptyState extends StatelessWidget {
  const _ArchiveEmptyState({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Text(
        filtered
            ? AppConstants.archiveNoFilterResults.tr()
            : AppConstants.archiveUnorganizedEmpty.tr(),
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.mutedText),
      ),
    );
  }
}

class _DeviceFolderCard extends StatelessWidget {
  const _DeviceFolderCard({required this.folder, required this.onTap});

  final DeviceFolder folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 108,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceStrong.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.75)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.folder_rounded, color: AppTheme.primary, size: 30),
                Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
            const Spacer(),
            Text(
              _deviceFolderTitle(folder),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              folder.isLinked
                  ? AppConstants.archiveDeviceFolderCount.tr(
                      namedArgs: {'count': '${folder.itemCount}'},
                    )
                  : AppConstants.archiveOpenFolder.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.mutedText, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

String _deviceFolderTitle(DeviceFolder folder) {
  return switch (folder.id) {
    'downloads' => AppConstants.archiveDeviceFolderDownloads.tr(),
    'documents' => AppConstants.archiveDeviceFolderDocuments.tr(),
    'whatsapp' => AppConstants.archiveDeviceFolderWhatsapp.tr(),
    'scans' => AppConstants.archiveDeviceFolderScans.tr(),
    'drive' => AppConstants.archiveDeviceFolderDrive.tr(),
    _ => folder.title,
  };
}

class _ImportedMiniCard extends StatelessWidget {
  const _ImportedMiniCard({required this.document});

  final DocumentFile document;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceStrong.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(
            document.type == DocumentType.image
                ? Icons.image_rounded
                : Icons.picture_as_pdf_rounded,
            color: document.type == DocumentType.image
                ? const Color(0xFF9B6DFF)
                : const Color(0xFFFF6868),
            size: 34,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${document.dateLabel}, ${document.timeLabel}  •  ${document.sizeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.check_circle_rounded, color: AppTheme.success),
        ],
      ),
    );
  }
}

class _FilterSpec {
  const _FilterSpec(this.icon, this.label, this.type);

  final IconData icon;
  final String label;
  final DocumentType? type;

  String get translatedLabel {
    return label.contains('.') ? label.tr() : label;
  }
}
