import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/add_document_sheet.dart';
import '../../common/album_dialog.dart';
import '../../common/app_constants.dart';
import '../../common/app_sheet.dart';
import '../../common/document_actions.dart';
import '../../common/document_preview_card.dart';
import '../../common/snapshot_builder.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import '../viewer/document_viewer_screen.dart';

/// One album (by [albumId]) or a computed collection (by [select], e.g.
/// favorites).
class AlbumDetailScreen extends StatelessWidget {
  const AlbumDetailScreen({
    super.key,
    required this.documentsService,
    this.albumId,
    this.title,
    this.select,
  }) : assert(albumId != null || select != null);

  final DocumentsService documentsService;
  final String? albumId;
  final String? title;
  final List<DocumentFile> Function(DocumentsSnapshot snapshot)? select;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SnapshotBuilder(
          documentsService: documentsService,
          builder: (context, snapshot) {
            final album = albumId == null ? null : snapshot.albumById(albumId!);
            if (albumId != null && album == null) {
              // Deleted from here; nothing left to show.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) Navigator.of(context).maybePop();
              });
              return const SizedBox.shrink();
            }
            final documents = album == null
                ? select!(snapshot)
                : snapshot.documentsForAlbum(album.id);

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                    child: Row(
                      children: [
                        const BackButton(),
                        if (album != null) ...[
                          Icon(
                            albumIconFor(album.iconName),
                            color: Color(album.colorValue),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                album?.name ?? title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.text,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                AppConstants.docshelfDocumentCount.tr(
                                  namedArgs: {'count': '${documents.length}'},
                                ),
                                style: const TextStyle(
                                  color: AppTheme.mutedText,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (album != null) ...[
                          IconButton(
                            tooltip: AppConstants.albumsAddDocuments.tr(),
                            icon: const Icon(Icons.add_rounded),
                            onPressed: () =>
                                _addDocuments(context, snapshot, album),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') _edit(context, album);
                              if (value == 'delete') _delete(context, album);
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(AppConstants.albumsEditAlbum.tr()),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  AppConstants.docshelfDeleteAlbum.tr(),
                                  style: const TextStyle(
                                    color: AppTheme.destructive,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (documents.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.folder_open_outlined,
                              size: 42,
                              color: AppTheme.dimText,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              AppConstants.docshelfAlbumEmptyTitle.tr(),
                              style: const TextStyle(
                                color: AppTheme.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              AppConstants.docshelfAlbumEmptyMessage.tr(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.mutedText),
                            ),
                            if (album != null) ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () =>
                                    _addDocuments(context, snapshot, album),
                                icon: const Icon(Icons.add_rounded),
                                label: Text(
                                  AppConstants.albumsAddDocuments.tr(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final columns = (constraints.crossAxisExtent / 170)
                            .floor()
                            .clamp(2, 6);
                        return SliverGrid.builder(
                          itemCount: documents.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 16,
                                childAspectRatio: 0.66,
                              ),
                          itemBuilder: (context, index) {
                            final document = documents[index];
                            void actions() => showDocumentActions(
                              context,
                              documentsService,
                              document,
                              albumContextId: album?.id,
                            );
                            return DocumentPreviewCard(
                              document: document,
                              onTap: () => openDocumentViewer(
                                context,
                                documentsService,
                                document,
                              ),
                              onLongPress: actions,
                              trailing: SizedBox(
                                width: 28,
                                height: 28,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  iconSize: 20,
                                  icon: const Icon(
                                    Icons.more_vert_rounded,
                                    color: AppTheme.mutedText,
                                  ),
                                  onPressed: actions,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _addDocuments(
    BuildContext context,
    DocumentsSnapshot snapshot,
    DocumentAlbum album,
  ) async {
    final choice = await showOptionsSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.collections_outlined),
              title: Text(AppConstants.albumsFromGallery.tr()),
              onTap: () => Navigator.of(context).pop('gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text(AppConstants.albumsImportNew.tr()),
              onTap: () => Navigator.of(context).pop('import'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'import') {
      await showAddDocumentSheet(context, documentsService, albumId: album.id);
      return;
    }
    final candidates = snapshot.documents
        .where((document) => !document.albumIds.contains(album.id))
        .toList();
    final picked = await showAppSheet<List<String>>(
      context: context,
      builder: (context) => _PickDocumentsSheet(documents: candidates),
    );
    if (picked == null || picked.isEmpty) return;
    await documentsService.addDocumentsToAlbum(picked, album.id);
  }

  Future<void> _edit(BuildContext context, DocumentAlbum album) async {
    final draft = await showAlbumDialog(context, initial: album);
    if (draft == null) return;
    await documentsService.updateAlbum(
      album.id,
      name: draft.name,
      colorValue: draft.colorValue,
      iconName: draft.iconName,
    );
  }

  Future<void> _delete(BuildContext context, DocumentAlbum album) async {
    final confirmed = await showConfirmDialog(
      context,
      title: AppConstants.docshelfDeleteAlbumTitle.tr(),
      message: AppConstants.docshelfDeleteAlbumMessage.tr(
        namedArgs: {'name': album.name},
      ),
      actionLabel: AppConstants.commonDelete.tr(),
    );
    if (confirmed) await documentsService.deleteAlbum(album.id);
  }
}

class _PickDocumentsSheet extends StatefulWidget {
  const _PickDocumentsSheet({required this.documents});

  final List<DocumentFile> documents;

  @override
  State<_PickDocumentsSheet> createState() => _PickDocumentsSheetState();
}

class _PickDocumentsSheetState extends State<_PickDocumentsSheet> {
  final Set<String> _selected = {};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = searchDocuments(
      widget.documents,
      DocumentSearchFilter(query: _query),
    ).map((hit) => hit.document).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: AppConstants.albumsSearchGallery.tr(),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: visible.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              itemBuilder: (context, index) {
                final document = visible[index];
                return DocumentPreviewCard(
                  document: document,
                  selected: _selected.contains(document.id),
                  onTap: () => setState(() {
                    _selected.contains(document.id)
                        ? _selected.remove(document.id)
                        : _selected.add(document.id);
                  }),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_selected.toList()),
                child: Text(
                  AppConstants.albumsAddCount.tr(
                    namedArgs: {'count': '${_selected.length}'},
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
