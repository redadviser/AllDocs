import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/app_constants.dart';
import '../../common/document_tile.dart';
import '../../common/glass_panel.dart';
import '../../common/snapshot_builder.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';

class DocshelfScreen extends StatelessWidget {
  const DocshelfScreen({super.key, required this.documentsService});

  final DocumentsService documentsService;

  @override
  Widget build(BuildContext context) {
    return SnapshotBuilder(
      documentsService: documentsService,
      builder: (context, snapshot) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: CustomScrollView(
            key: const PageStorageKey('docshelf'),
            slivers: [
              SliverToBoxAdapter(
                child: _ScreenTitle(
                  title: AppConstants.docshelfTitle.tr(),
                  actionIcon: Icons.add_rounded,
                  onAction: () => _createShelf(context),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              if (snapshot.shelves.isEmpty)
                SliverToBoxAdapter(
                  child: _EmptyPanel(
                    title: AppConstants.docshelfCreateFirstShelfTitle.tr(),
                    message: AppConstants.docshelfCreateFirstShelfMessage.tr(),
                    actionLabel: AppConstants.docshelfNewShelf.tr(),
                    onAction: () => _createShelf(context),
                  ),
                )
              else
                for (final shelf in snapshot.shelves) ...[
                  SliverToBoxAdapter(
                    child: _ShelfPanel(
                      shelf: shelf,
                      snapshot: snapshot,
                      documentsService: documentsService,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              SliverToBoxAdapter(
                child: _DocumentsPanel(
                  title: AppConstants.docshelfRecent.tr(),
                  icon: Icons.schedule_rounded,
                  actionLabel: AppConstants.commonViewAll.tr(),
                  documents: snapshot.recentDocuments,
                  allDocuments: snapshot.documents,
                  emptyMessage: AppConstants.docshelfRecentEmpty.tr(),
                  documentsService: documentsService,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: _DocumentsPanel(
                  title: AppConstants.docshelfFavorites.tr(),
                  icon: Icons.star_rounded,
                  actionLabel: AppConstants.commonViewAll.tr(),
                  documents: snapshot.favoriteDocuments,
                  allDocuments: snapshot.documents
                      .where((document) => document.isFavorite)
                      .toList(),
                  emptyMessage: AppConstants.docshelfFavoritesEmpty.tr(),
                  favorites: true,
                  documentsService: documentsService,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createShelf(BuildContext context) async {
    final name = await _showNameDialog(
      context,
      title: AppConstants.docshelfNewShelf.tr(),
      label: AppConstants.docshelfShelfName.tr(),
      fallback: AppConstants.docshelfDefaultShelfName.tr(),
    );
    if (name == null) return;
    await documentsService.createShelf(name);
  }
}

class _ScreenTitle extends StatelessWidget {
  const _ScreenTitle({required this.title, this.actionIcon, this.onAction});

  final String title;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (actionIcon != null)
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.surfaceStrong,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(14),
            ),
            onPressed: onAction,
            icon: Icon(actionIcon, size: 30),
          ),
      ],
    );
  }
}

class _ShelfPanel extends StatelessWidget {
  const _ShelfPanel({
    required this.shelf,
    required this.snapshot,
    required this.documentsService,
  });

  final DocumentShelf shelf;
  final DocumentsSnapshot snapshot;
  final DocumentsService documentsService;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            icon: Icons.view_week_rounded,
            title: shelf.name,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: AppConstants.docshelfCreateAlbum.tr(),
                  onPressed: () => _createAlbum(context),
                  icon: const Icon(Icons.add_box_outlined),
                  color: AppTheme.primarySoft,
                ),
                IconButton(
                  tooltip: AppConstants.docshelfDeleteShelf.tr(),
                  onPressed: () => _deleteShelf(context),
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppTheme.mutedText,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 172,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                if (index == shelf.albums.length) {
                  return _AddAlbumSpine(onTap: () => _createAlbum(context));
                }
                final album = shelf.albums[index];
                return _AlbumSpine(
                  album: album,
                  count: snapshot.documentsForAlbum(album.id).length,
                  onTap: () => _openAlbum(context, album),
                  onDelete: () => _deleteAlbum(context, album),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemCount: shelf.albums.length + 1,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createAlbum(BuildContext context) async {
    final draft = await _showAlbumDialog(context);
    if (draft == null) return;
    await documentsService.createAlbum(
      shelf.id,
      draft.name,
      colorValue: draft.colorValue,
      iconName: draft.iconName,
    );
  }

  Future<void> _deleteShelf(BuildContext context) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: AppConstants.docshelfDeleteShelfTitle.tr(),
      message: AppConstants.docshelfDeleteShelfMessage.tr(),
      actionLabel: AppConstants.commonDelete.tr(),
    );
    if (confirmed != true) return;
    await documentsService.deleteShelf(shelf.id);
  }

  Future<void> _deleteAlbum(BuildContext context, DocumentAlbum album) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: AppConstants.docshelfDeleteAlbumTitle.tr(),
      message: AppConstants.docshelfDeleteAlbumMessage.tr(
        namedArgs: {'name': album.name},
      ),
      actionLabel: AppConstants.commonDelete.tr(),
    );
    if (confirmed != true) return;
    await documentsService.deleteAlbum(album.id);
  }

  void _openAlbum(BuildContext context, DocumentAlbum album) {
    final documents = snapshot.documentsForAlbum(album.id);

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
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
                      _AlbumCover(album: album, count: documents.length),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              album.name,
                              style: const TextStyle(
                                color: AppTheme.text,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              AppConstants.docshelfDocumentCount.tr(
                                namedArgs: {'count': '${documents.length}'},
                              ),
                              style: const TextStyle(color: AppTheme.mutedText),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filled(
                        onPressed: () async {
                          final imported = await documentsService
                              .importDocuments(albumId: album.id);
                          if (context.mounted && imported > 0) {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Icon(Icons.upload_file_rounded),
                      ),
                      IconButton(
                        tooltip: AppConstants.docshelfDeleteAlbum.tr(),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _deleteAlbum(context, album);
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                        color: AppTheme.mutedText,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: documents.isEmpty
                        ? _InlineEmptyState(
                            icon: Icons.folder_open_rounded,
                            title: AppConstants.docshelfAlbumEmptyTitle.tr(),
                            message: AppConstants.docshelfAlbumEmptyMessage
                                .tr(),
                            actionLabel: AppConstants.commonImport.tr(),
                            onAction: () async {
                              final imported = await documentsService
                                  .importDocuments(albumId: album.id);
                              if (context.mounted && imported > 0) {
                                Navigator.of(context).pop();
                              }
                            },
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
                                onTap: () =>
                                    documentsService.openDocument(document),
                                trailing: _DocumentActions(
                                  document: document,
                                  documentsService: documentsService,
                                  compact: true,
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

class _AlbumSpine extends StatelessWidget {
  const _AlbumSpine({
    required this.album,
    required this.count,
    required this.onTap,
    required this.onDelete,
  });

  final DocumentAlbum album;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = Color(album.colorValue);

    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        width: 58,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.95),
              color.withValues(alpha: 0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -8,
              top: -10,
              child: _CountBadge(count: count, color: color),
            ),
            Center(
              child: RotatedBox(
                quarterTurns: -1,
                child: SizedBox(
                  width: 122,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _iconForName(album.iconName),
                          color: Colors.white.withValues(alpha: 0.88),
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          album.name.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            height: 1.1,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
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

class _AddAlbumSpine extends StatelessWidget {
  const _AddAlbumSpine({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(),
        child: SizedBox(
          width: 58,
          child: Center(
            child: Icon(
              Icons.add_rounded,
              color: AppTheme.primarySoft.withValues(alpha: 0.9),
              size: 38,
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumCover extends StatelessWidget {
  const _AlbumCover({required this.album, required this.count});

  final DocumentAlbum album;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Color(album.colorValue);
    return Container(
      width: 58,
      height: 70,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_iconForName(album.iconName), color: Colors.white, size: 30),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DocumentsPanel extends StatelessWidget {
  const _DocumentsPanel({
    required this.title,
    required this.icon,
    required this.actionLabel,
    required this.documents,
    required this.allDocuments,
    required this.emptyMessage,
    required this.documentsService,
    this.favorites = false,
  });

  final String title;
  final IconData icon;
  final String actionLabel;
  final List<DocumentFile> documents;
  final List<DocumentFile> allDocuments;
  final String emptyMessage;
  final DocumentsService documentsService;
  final bool favorites;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        children: [
          SectionTitle(
            icon: icon,
            title: title,
            trailing: SectionAction(
              label: actionLabel,
              onTap: () => _showDocumentsSheet(context),
            ),
          ),
          const SizedBox(height: 12),
          if (documents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.mutedText),
              ),
            )
          else
            for (final document in documents) ...[
              DocumentTile(
                document: document,
                showFavoriteMarker: favorites,
                onTap: () => documentsService.openDocument(document),
                trailing: _DocumentActions(
                  document: document,
                  documentsService: documentsService,
                ),
              ),
              if (document != documents.last) const Divider(height: 1),
            ],
        ],
      ),
    );
  }

  void _showDocumentsSheet(BuildContext context) {
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
                    child: allDocuments.isEmpty
                        ? Center(
                            child: Text(
                              emptyMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.mutedText),
                            ),
                          )
                        : ListView.separated(
                            controller: controller,
                            itemCount: allDocuments.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final document = allDocuments[index];
                              return DocumentTile(
                                document: document,
                                showFavoriteMarker: favorites,
                                onTap: () =>
                                    documentsService.openDocument(document),
                                trailing: _DocumentActions(
                                  document: document,
                                  documentsService: documentsService,
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

class _DocumentActions extends StatelessWidget {
  const _DocumentActions({
    required this.document,
    required this.documentsService,
    this.compact = false,
  });

  final DocumentFile document;
  final DocumentsService documentsService;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: document.isFavorite
              ? AppConstants.commonRemoveFavorite.tr()
              : AppConstants.commonFavorite.tr(),
          onPressed: () => documentsService.toggleFavorite(document.id),
          icon: Icon(
            document.isFavorite
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            color: document.isFavorite
                ? AppTheme.warning
                : AppTheme.primarySoft,
          ),
        ),
        if (!compact)
          IconButton(
            tooltip: AppConstants.commonOpenDocument.tr(),
            onPressed: () => documentsService.openDocument(document),
            icon: const Icon(Icons.open_in_new_rounded),
            color: AppTheme.primarySoft,
          ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: _InlineEmptyState(
        icon: Icons.view_week_outlined,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: AppTheme.primarySoft),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.mutedText),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 8.0;
    const dashSpace = 6.0;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(9),
    );
    final paint = Paint()
      ..color = AppTheme.primarySoft.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<String?> _showNameDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String fallback,
}) {
  final controller = TextEditingController(text: fallback);

  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            final value = controller.text.trim();
            Navigator.of(context).pop(value.isEmpty ? null : value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppConstants.commonCancel.tr()),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              Navigator.of(context).pop(value.isEmpty ? null : value);
            },
            child: Text(AppConstants.commonCreate.tr()),
          ),
        ],
      );
    },
  );
}

Future<_AlbumDraft?> _showAlbumDialog(BuildContext context) {
  return showDialog<_AlbumDraft>(
    context: context,
    builder: (context) => const _AlbumDialog(),
  );
}

Future<bool?> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppConstants.commonCancel.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.destructive,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel),
          ),
        ],
      );
    },
  );
}

class _AlbumDialog extends StatefulWidget {
  const _AlbumDialog();

  @override
  State<_AlbumDialog> createState() => _AlbumDialogState();
}

class _AlbumDialogState extends State<_AlbumDialog> {
  static const _colors = [
    0xFF2467D9,
    0xFFD61C73,
    0xFFC99112,
    0xFF1B9E47,
    0xFF1397A9,
    0xFF6A45E7,
    0xFFD72D4C,
    0xFF64748B,
  ];

  static const _icons = [
    'folder',
    'person',
    'work',
    'finance',
    'school',
    'health',
    'home',
    'car',
    'receipt',
    'shield',
    'star',
    'travel',
  ];

  final TextEditingController _controller = TextEditingController();
  int _selectedColor = _colors.first;
  String _selectedIcon = _icons.first;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(AppConstants.docshelfNewAlbum.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: AppConstants.docshelfAlbumName.tr(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 18),
            Text(
              AppConstants.docshelfColor.tr(),
              style: const TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in _colors)
                  _AlbumColorChoice(
                    colorValue: color,
                    selected: color == _selectedColor,
                    onTap: () => setState(() => _selectedColor = color),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              AppConstants.docshelfIcon.tr(),
              style: const TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final iconName in _icons)
                  _AlbumIconChoice(
                    iconName: iconName,
                    selected: iconName == _selectedIcon,
                    colorValue: _selectedColor,
                    onTap: () => setState(() => _selectedIcon = iconName),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppConstants.commonCancel.tr()),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(AppConstants.commonCreate.tr()),
        ),
      ],
    );
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      _AlbumDraft(
        name: name,
        colorValue: _selectedColor,
        iconName: _selectedIcon,
      ),
    );
  }
}

class _AlbumColorChoice extends StatelessWidget {
  const _AlbumColorChoice({
    required this.colorValue,
    required this.selected,
    required this.onTap,
  });

  final int colorValue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : AppTheme.border,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}

class _AlbumIconChoice extends StatelessWidget {
  const _AlbumIconChoice({
    required this.iconName,
    required this.selected,
    required this.colorValue,
    required this.onTap,
  });

  final String iconName;
  final bool selected;
  final int colorValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.24)
              : AppTheme.surfaceStrong,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : AppTheme.border),
        ),
        child: Icon(
          _iconForName(iconName),
          color: selected ? color : AppTheme.primarySoft,
        ),
      ),
    );
  }
}

class _AlbumDraft {
  const _AlbumDraft({
    required this.name,
    required this.colorValue,
    required this.iconName,
  });

  final String name;
  final int colorValue;
  final String iconName;
}

IconData _iconForName(String iconName) {
  return switch (iconName) {
    'person' => Icons.person_rounded,
    'work' => Icons.business_center_rounded,
    'finance' => Icons.euro_rounded,
    'school' => Icons.school_rounded,
    'health' => Icons.health_and_safety_rounded,
    'home' => Icons.home_rounded,
    'car' => Icons.directions_car_rounded,
    'receipt' => Icons.receipt_long_rounded,
    'shield' => Icons.shield_rounded,
    'star' => Icons.star_rounded,
    'travel' => Icons.flight_takeoff_rounded,
    _ => Icons.folder_rounded,
  };
}
