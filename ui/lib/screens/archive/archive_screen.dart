import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart' as archive;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:xml/xml.dart' as xml;

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
  bool _deepSearchInProgress = false;

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
                      const SizedBox(height: 12),
                      _DeepDeviceSearchCard(
                        loading: _deepSearchInProgress,
                        onTap: () => _searchAllDeviceDocuments(context),
                      ),
                      const SizedBox(height: 12),
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(AppConstants.archiveScanStarting.tr())),
    );

    try {
      final imported = await widget.documentsService.scanDocumentWithCamera();
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      if (imported == 0) return;
      messenger.showSnackBar(
        SnackBar(content: Text(AppConstants.archiveScanDone.tr())),
      );
    } catch (_) {
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(AppConstants.archiveScanFailed.tr())),
      );
    }
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

  Future<void> _searchAllDeviceDocuments(BuildContext context) async {
    if (_deepSearchInProgress) return;
    setState(() => _deepSearchInProgress = true);

    try {
      final scan = await widget.documentsService.scanAllDeviceDocuments(
        title: AppConstants.archiveAllDeviceDocuments.tr(),
      );
      if (!context.mounted || scan == null) return;
      _showDeviceFolderSheet(context, scan);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppConstants.archiveFolderOpenFailed.tr())),
      );
    } finally {
      if (mounted) setState(() => _deepSearchInProgress = false);
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
        return _DeviceScanSheet(
          scan: scan,
          documentsService: widget.documentsService,
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

class _DeepDeviceSearchCard extends StatelessWidget {
  const _DeepDeviceSearchCard({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accent.withValues(alpha: 0.26),
              const Color(0xFF102F68).withValues(alpha: 0.9),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.32)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.manage_search_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loading
                        ? AppConstants.archiveSearchingDevice.tr()
                        : AppConstants.archiveSearchDevice.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    AppConstants.archiveSearchDeviceSubtitle.tr(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.mutedText,
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.primarySoft,
            ),
          ],
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
                  color: selected ? AppTheme.accent : AppTheme.border,
                ),
                backgroundColor: AppTheme.surface,
                selectedColor: AppTheme.accent.withValues(alpha: 0.22),
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
            else if (document.type == DocumentType.word && filePath != null)
              _WordDocumentPreview(
                filePath: filePath,
                color: color,
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
                    color: AppTheme.accent.withValues(alpha: 0.82),
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

class _WordDocumentPreview extends StatefulWidget {
  const _WordDocumentPreview({
    required this.filePath,
    required this.color,
    required this.fallback,
  });

  final String filePath;
  final Color color;
  final Widget fallback;

  @override
  State<_WordDocumentPreview> createState() => _WordDocumentPreviewState();
}

class _WordDocumentPreviewState extends State<_WordDocumentPreview> {
  late Future<String?> _previewText;

  @override
  void initState() {
    super.initState();
    _previewText = _loadPreviewText();
  }

  @override
  void didUpdateWidget(covariant _WordDocumentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _previewText = _loadPreviewText();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _previewText,
      builder: (context, snapshot) {
        final text = snapshot.data?.trim();
        if (snapshot.connectionState != ConnectionState.done) {
          return _WordPreviewLoading(color: widget.color);
        }
        if (snapshot.hasError || text == null || text.isEmpty) {
          return widget.fallback;
        }
        return _WordTextPreview(text: text, color: widget.color);
      },
    );
  }

  Future<String?> _loadPreviewText() async {
    if (!widget.filePath.toLowerCase().endsWith('.docx')) return null;
    return Isolate.run(() => _extractDocxPreviewText(widget.filePath));
  }
}

class _WordTextPreview extends StatelessWidget {
  const _WordTextPreview({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.description_rounded, color: color, size: 15),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 8,
              overflow: TextOverflow.fade,
              style: const TextStyle(
                color: Color(0xFF253247),
                fontSize: 9.8,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WordPreviewLoading extends StatelessWidget {
  const _WordPreviewLoading({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 10,
            width: 80,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 14),
          for (final width in const [1.0, 0.82, 0.92, 0.64, 0.74]) ...[
            FractionallySizedBox(
              widthFactor: width,
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7DEE9),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
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
              color: AppTheme.accent.withValues(alpha: 0.16),
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

class _DeviceScanSheet extends StatefulWidget {
  const _DeviceScanSheet({required this.scan, required this.documentsService});

  final DeviceFolderScan scan;
  final DocumentsService documentsService;

  @override
  State<_DeviceScanSheet> createState() => _DeviceScanSheetState();
}

class _DeviceScanSheetState extends State<_DeviceScanSheet> {
  final Set<String> _importedIds = {};
  DocumentType? _selectedType;
  bool _importingAll = false;

  List<DocumentFile> get _visibleDocuments {
    final selectedType = _selectedType;
    if (selectedType == null) return widget.scan.documents;
    return widget.scan.documents
        .where((document) => document.type == selectedType)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.94,
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
              _DeviceScanHeader(
                scan: widget.scan,
                importing: _importingAll,
                onImportAll: widget.scan.documents.isEmpty ? null : _importAll,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: widget.scan.documents.isEmpty
                    ? Center(
                        child: Text(
                          AppConstants.archiveNoSupportedDocuments.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.mutedText),
                        ),
                      )
                    : CustomScrollView(
                        controller: controller,
                        slivers: [
                          SliverToBoxAdapter(
                            child: _DeviceTypeSummary(
                              documents: widget.scan.documents,
                              selectedType: _selectedType,
                              onSelected: (type) {
                                setState(() => _selectedType = type);
                              },
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 16)),
                          for (final section in _sections(
                            _visibleDocuments,
                          )) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: SectionTitle(
                                  icon: _documentIconFor(section.type),
                                  title: _documentTypeLabel(section.type),
                                  count: section.documents.length,
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.only(bottom: 18),
                              sliver: SliverGrid.builder(
                                itemCount: section.documents.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                      childAspectRatio: 0.54,
                                    ),
                                itemBuilder: (context, index) {
                                  final document = section.documents[index];
                                  return _DeviceScanDocumentCard(
                                    document: document,
                                    imported: _importedIds.contains(
                                      document.id,
                                    ),
                                    documentsService: widget.documentsService,
                                    onImported: () {
                                      setState(
                                        () => _importedIds.add(document.id),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _importAll() async {
    setState(() => _importingAll = true);
    final imported = await widget.documentsService.importScannedDocuments(
      widget.scan.documents,
    );
    if (!mounted) return;
    setState(() {
      _importingAll = false;
      _importedIds.addAll(widget.scan.documents.map((document) => document.id));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppConstants.archiveImportedCount.tr(
            namedArgs: {'count': '$imported'},
          ),
        ),
      ),
    );
  }

  List<({DocumentType type, List<DocumentFile> documents})> _sections(
    List<DocumentFile> documents,
  ) {
    final order = const [
      DocumentType.pdf,
      DocumentType.word,
      DocumentType.excel,
      DocumentType.image,
    ];

    return [
      for (final type in order)
        if (documents.where((document) => document.type == type).isNotEmpty)
          (
            type: type,
            documents: documents
                .where((document) => document.type == type)
                .toList(),
          ),
    ];
  }
}

class _DeviceScanHeader extends StatelessWidget {
  const _DeviceScanHeader({
    required this.scan,
    required this.importing,
    required this.onImportAll,
  });

  final DeviceFolderScan scan;
  final bool importing;
  final VoidCallback? onImportAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(
            scan.folderId == 'device'
                ? Icons.devices_rounded
                : Icons.folder_open_rounded,
            color: AppTheme.primarySoft,
            size: 29,
          ),
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
              const SizedBox(height: 2),
              Text(
                AppConstants.archiveDeviceFolderFound.tr(
                  namedArgs: {'count': '${scan.documents.length}'},
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.mutedText),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: importing ? null : onImportAll,
          child: importing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(AppConstants.commonImportAll.tr()),
        ),
      ],
    );
  }
}

class _DeviceTypeSummary extends StatelessWidget {
  const _DeviceTypeSummary({
    required this.documents,
    required this.selectedType,
    required this.onSelected,
  });

  final List<DocumentFile> documents;
  final DocumentType? selectedType;
  final ValueChanged<DocumentType?> onSelected;

  @override
  Widget build(BuildContext context) {
    final counts = {
      for (final type in DocumentType.values)
        type: documents.where((document) => document.type == type).length,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          icon: Icons.category_rounded,
          title: AppConstants.archiveDocumentTypes.tr(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _DeviceTypeChip(
              icon: Icons.layers_rounded,
              label: AppConstants.archiveAll.tr(),
              count: documents.length,
              selected: selectedType == null,
              onTap: () => onSelected(null),
            ),
            for (final type in const [
              DocumentType.pdf,
              DocumentType.word,
              DocumentType.excel,
              DocumentType.image,
            ])
              _DeviceTypeChip(
                icon: _documentIconFor(type),
                label: _documentTypeLabel(type),
                count: counts[type] ?? 0,
                color: _documentColorFor(type),
                selected: selectedType == type,
                onTap: () => onSelected(type),
              ),
          ],
        ),
      ],
    );
  }
}

class _DeviceTypeChip extends StatelessWidget {
  const _DeviceTypeChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppTheme.accent;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 126,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? effectiveColor.withValues(alpha: 0.2)
              : AppTheme.surfaceStrong.withValues(alpha: 0.44),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? effectiveColor.withValues(alpha: 0.72)
                : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? effectiveColor : AppTheme.primarySoft,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppConstants.archiveTypeCount.tr(
                      namedArgs: {'count': '$count'},
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.mutedText,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceScanDocumentCard extends StatefulWidget {
  const _DeviceScanDocumentCard({
    required this.document,
    required this.imported,
    required this.documentsService,
    required this.onImported,
  });

  final DocumentFile document;
  final bool imported;
  final DocumentsService documentsService;
  final VoidCallback onImported;

  @override
  State<_DeviceScanDocumentCard> createState() =>
      _DeviceScanDocumentCardState();
}

class _DeviceScanDocumentCardState extends State<_DeviceScanDocumentCard> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final color = _documentColorFor(document.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => widget.documentsService.openDocument(document),
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
                  icon: _documentIconFor(document.type),
                  extension: _documentExtensionFor(document.type),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                document.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 12,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                AppConstants.archiveSourceFolder.tr(
                  namedArgs: {'folder': _sourceFolderName(document)},
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 34,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.imported || _importing ? null : _import,
                  icon: _importing
                      ? const SizedBox.square(
                          dimension: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          widget.imported
                              ? Icons.check_rounded
                              : Icons.download_rounded,
                          size: 16,
                        ),
                  label: Text(
                    widget.imported
                        ? AppConstants.archiveDocumentImported.tr()
                        : AppConstants.commonImport.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    final imported = await widget.documentsService.importScannedDocuments([
      widget.document,
    ]);
    if (!mounted) return;
    setState(() => _importing = false);
    if (imported > 0) widget.onImported();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          imported > 0
              ? AppConstants.archiveDocumentImported.tr()
              : AppConstants.archiveImportFailed.tr(),
        ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.folder_rounded, color: AppTheme.accent, size: 30),
                const Icon(Icons.chevron_right_rounded, size: 18),
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

IconData _documentIconFor(DocumentType type) {
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

Color _documentColorFor(DocumentType type) {
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

String _documentExtensionFor(DocumentType type) {
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

String _documentTypeLabel(DocumentType type) {
  return switch (type) {
    DocumentType.pdf => 'PDF',
    DocumentType.word => 'Word',
    DocumentType.excel => 'Excel',
    DocumentType.image => AppConstants.archiveImage.tr(),
  };
}

String _sourceFolderName(DocumentFile document) {
  final path = document.localPath;
  if (path == null || path.trim().isEmpty) return '-';
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/')..removeWhere((part) => part.isEmpty);
  if (parts.length < 2) return normalized;
  return parts[parts.length - 2];
}

String? _extractDocxPreviewText(String filePath) {
  try {
    final bytes = File(filePath).readAsBytesSync();
    final files = archive.ZipDecoder().decodeBytes(bytes, verify: false);
    archive.ArchiveFile? documentXml;
    for (final file in files.files) {
      if (file.name == 'word/document.xml' && file.isFile) {
        documentXml = file;
        break;
      }
    }
    if (documentXml == null) return null;

    final xmlText = utf8.decode(documentXml.content, allowMalformed: true);
    final parsed = xml.XmlDocument.parse(xmlText);
    final paragraphs = <String>[];

    final xmlParagraphs = parsed.descendantElements.where((element) {
      return element.name.qualified == 'w:p' || element.name.local == 'p';
    });

    for (final paragraph in xmlParagraphs) {
      final buffer = StringBuffer();
      final textNodes = paragraph.descendantElements.where((element) {
        return element.name.qualified == 'w:t' || element.name.local == 't';
      });
      for (final textNode in textNodes) {
        buffer.write(textNode.innerText);
      }
      final line = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (line.isNotEmpty) paragraphs.add(line);
      if (paragraphs.join('\n').length > 700) break;
    }

    final text = paragraphs.join('\n').trim();
    if (text.isEmpty) return null;
    return text.length > 700 ? '${text.substring(0, 700)}...' : text;
  } catch (_) {
    return null;
  }
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
