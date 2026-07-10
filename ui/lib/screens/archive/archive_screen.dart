import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

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
        final visibleUnorganizedDocuments = unorganizedDocuments
            .take(6)
            .toList();

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
                            snapshot: snapshot,
                            showArchiveActions: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (unorganizedDocuments.isEmpty)
                        _ArchiveEmptyState(filtered: _selectedType != null)
                      else
                        _UnorganizedDocumentsGrid(
                          documents: visibleUnorganizedDocuments,
                          snapshot: snapshot,
                          documentsService: widget.documentsService,
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
    DocumentsSnapshot? snapshot,
    bool showArchiveActions = false,
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
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final spacing = constraints.maxWidth < 360
                                  ? 10.0
                                  : 12.0;

                              final childAspectRatio = showArchiveActions
                                  ? (constraints.maxWidth < 360 ? 0.56 : 0.60)
                                  : (constraints.maxWidth < 360 ? 0.64 : 0.70);

                              return GridView.builder(
                                controller: controller,
                                padding: const EdgeInsets.only(bottom: 12),
                                itemCount: documents.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: spacing,
                                      mainAxisSpacing: spacing,
                                      childAspectRatio: childAspectRatio,
                                    ),
                                itemBuilder: (context, index) {
                                  final document = documents[index];

                                  return _UnorganizedDocumentCard(
                                    document: document,
                                    snapshot: snapshot,
                                    documentsService: widget.documentsService,
                                    showArchiveActions:
                                        showArchiveActions && snapshot != null,
                                  );
                                },
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

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in filters)
          Builder(
            builder: (context) {
              final selected = filter.type == selectedType;
              return ChoiceChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
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
      ],
    );
  }
}

class _UnorganizedDocumentsGrid extends StatelessWidget {
  const _UnorganizedDocumentsGrid({
    required this.documents,
    required this.snapshot,
    required this.documentsService,
  });

  final List<DocumentFile> documents;
  final DocumentsSnapshot snapshot;
  final DocumentsService documentsService;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = constraints.maxWidth < 360 ? 10.0 : 12.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: documents.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: constraints.maxWidth < 360 ? 0.56 : 0.60,
          ),
          itemBuilder: (context, index) {
            final document = documents[index];

            return _UnorganizedDocumentCard(
              document: document,
              snapshot: snapshot,
              documentsService: documentsService,
            );
          },
        );
      },
    );
  }
}

class _UnorganizedDocumentCard extends StatelessWidget {
  const _UnorganizedDocumentCard({
    required this.document,
    required this.snapshot,
    required this.documentsService,
    this.showArchiveActions = true,
  });

  final DocumentFile document;
  final DocumentsSnapshot? snapshot;
  final DocumentsService documentsService;
  final bool showArchiveActions;

  @override
  Widget build(BuildContext context) {
    final color = _documentColor(document.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => documentsService.openDocument(document),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.surfaceStrong.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border.withValues(alpha: 0.72)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _DocumentPreview(
                  document: document,
                  color: color,
                  icon: _documentIcon(document.type),
                  extension: _documentExtension(document.type),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: Text(
                  document.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 12.5,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${document.dateLabel} • ${document.sizeLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showArchiveActions && snapshot != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: _ArchiveActions(
                    document: document,
                    snapshot: snapshot!,
                    documentsService: documentsService,
                    compact: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _documentIcon(DocumentType type) {
    switch (type) {
      case DocumentType.pdf:
        return Icons.picture_as_pdf_rounded;
      case DocumentType.word:
        return Icons.description_rounded;
      case DocumentType.excel:
        return Icons.table_chart_rounded;
      case DocumentType.image:
        return Icons.image_rounded;
    }
  }

  Color _documentColor(DocumentType type) {
    switch (type) {
      case DocumentType.pdf:
        return const Color(0xFFFF6868);
      case DocumentType.word:
        return const Color(0xFF5C8DFF);
      case DocumentType.excel:
        return const Color(0xFF4CC58A);
      case DocumentType.image:
        return const Color(0xFF9B6DFF);
    }
  }

  String _documentExtension(DocumentType type) {
    switch (type) {
      case DocumentType.pdf:
        return 'PDF';
      case DocumentType.word:
        return 'DOC';
      case DocumentType.excel:
        return 'XLS';
      case DocumentType.image:
        return AppConstants.archiveImage.tr().toUpperCase();
    }
  }
}

class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({
    required this.document,
    required this.color,
    required this.icon,
    required this.extension,
  });

  final DocumentFile document;
  final Color color;
  final IconData icon;
  final String extension;

  @override
  Widget build(BuildContext context) {
    final thumbnailSource = _previewSource(_documentThumbnailPath(document));
    final filePath = _existingLocalPath(_documentFilePath(document));
    final imagePreviewSource = document.type == DocumentType.image
        ? _previewSource(_documentFilePath(document))
        : null;
    final previewSource = thumbnailSource ?? imagePreviewSource;

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.22)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (previewSource != null)
              _ImagePreviewSource(
                source: previewSource,
                fallback: _FallbackDocumentPreview(
                  color: color,
                  icon: icon,
                  extension: extension,
                  type: document.type,
                ),
              )
            else if (document.type == DocumentType.pdf && filePath != null)
              _PdfFirstPagePreview(
                filePath: filePath,
                fallback: _FallbackDocumentPreview(
                  color: color,
                  icon: icon,
                  extension: extension,
                  type: document.type,
                ),
              )
            else
              _FallbackDocumentPreview(
                color: color,
                icon: icon,
                extension: extension,
                type: document.type,
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: _ExtensionBadge(extension: extension, color: color),
            ),
            if (document.isNew)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Text(
                    AppConstants.archiveNew.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImagePreviewSource extends StatelessWidget {
  const _ImagePreviewSource({required this.source, required this.fallback});

  final String source;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return Image.network(
        source,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    return Image.file(
      File(source),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

class _PdfFirstPagePreview extends StatefulWidget {
  const _PdfFirstPagePreview({required this.filePath, required this.fallback});

  final String filePath;
  final Widget fallback;

  @override
  State<_PdfFirstPagePreview> createState() => _PdfFirstPagePreviewState();
}

class _PdfFirstPagePreviewState extends State<_PdfFirstPagePreview> {
  late PdfController _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = PdfController(
      document: PdfDocument.openFile(widget.filePath),
      initialPage: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _PdfFirstPagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _controller.dispose();
      _hasError = false;
      _controller = PdfController(
        document: PdfDocument.openFile(widget.filePath),
        initialPage: 1,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) return widget.fallback;

    return IgnorePointer(
      child: PdfView(
        controller: _controller,
        scrollDirection: Axis.vertical,
        physics: const NeverScrollableScrollPhysics(),
        onDocumentError: (_) => setState(() => _hasError = true),
        onPageChanged: (page) {
          if (page > 1) {
            _controller.jumpToPage(1);
          }
        },
      ),
    );
  }
}

class _FallbackDocumentPreview extends StatelessWidget {
  const _FallbackDocumentPreview({
    required this.color,
    required this.icon,
    required this.extension,
    required this.type,
  });

  final Color color;
  final IconData icon;
  final String extension;
  final DocumentType type;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Center(
        child: AspectRatio(
          aspectRatio: 0.72,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.26)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const Spacer(),
                    Text(
                      extension,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (type == DocumentType.excel)
                  Expanded(child: _ExcelSkeleton(color: color))
                else
                  Expanded(child: _TextSkeleton(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextSkeleton extends StatelessWidget {
  const _TextSkeleton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 10,
          width: 54,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(height: 12),
        for (final widthFactor in const [1.0, 0.78, 0.92, 0.55]) ...[
          FractionallySizedBox(
            widthFactor: widthFactor,
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: AppTheme.surfaceStrong.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 7),
        ],
      ],
    );
  }
}

class _ExcelSkeleton extends StatelessWidget {
  const _ExcelSkeleton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1.7,
      ),
      itemCount: 15,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: index < 3
                ? color.withValues(alpha: 0.22)
                : AppTheme.surfaceStrong.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      },
    );
  }
}

class _ExtensionBadge extends StatelessWidget {
  const _ExtensionBadge({required this.extension, required this.color});

  final String extension;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        extension,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String? _documentThumbnailPath(DocumentFile document) {
  final dynamic value = document;

  String? valid(dynamic candidate) {
    if (candidate is String && candidate.trim().isNotEmpty) {
      return candidate.trim();
    }
    return null;
  }

  try {
    final path = valid(value.thumbnailPath);
    if (path != null) return path;
  } catch (_) {}

  try {
    final path = valid(value.previewPath);
    if (path != null) return path;
  } catch (_) {}

  try {
    final path = valid(value.coverPath);
    if (path != null) return path;
  } catch (_) {}

  try {
    final path = valid(value.thumbnailUrl);
    if (path != null) return path;
  } catch (_) {}

  return null;
}

String? _documentFilePath(DocumentFile document) {
  final dynamic value = document;

  String? valid(dynamic candidate) {
    if (candidate is String && candidate.trim().isNotEmpty) {
      return candidate.trim();
    }
    return null;
  }

  try {
    final path = valid(value.path);
    if (path != null) return path;
  } catch (_) {}

  try {
    final path = valid(value.filePath);
    if (path != null) return path;
  } catch (_) {}

  try {
    final path = valid(value.localPath);
    if (path != null) return path;
  } catch (_) {}

  try {
    final path = valid(value.uri);
    if (path != null) return Uri.tryParse(path)?.toFilePath() ?? path;
  } catch (_) {}

  return null;
}

String? _previewSource(String? source) {
  if (source == null || source.isEmpty) return null;
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return source;
  }

  return _existingLocalPath(source);
}

String? _existingLocalPath(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('file://')) {
    path = Uri.tryParse(path)?.toFilePath() ?? path;
  }

  try {
    return File(path).existsSync() ? path : null;
  } catch (_) {
    return null;
  }
}

class _ArchiveActions extends StatelessWidget {
  const _ArchiveActions({
    required this.document,
    required this.snapshot,
    required this.documentsService,
    this.compact = false,
  });

  final DocumentFile document;
  final DocumentsSnapshot snapshot;
  final DocumentsService documentsService;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showArchiveTargets(context),
              icon: const Icon(Icons.archive_outlined, size: 16),
              label: Text(
                AppConstants.archiveArchive.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primarySoft,
                side: const BorderSide(color: AppTheme.border),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              tooltip: AppConstants.commonFavorite.tr(),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                foregroundColor: AppTheme.primarySoft,
                backgroundColor: AppTheme.surface.withValues(alpha: 0.54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppTheme.border),
                ),
              ),
              onPressed: () => documentsService.toggleFavorite(document.id),
              icon: Icon(
                document.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 20,
              ),
            ),
          ),
        ],
      );
    }

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
