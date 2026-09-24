import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/album_dialog.dart';
import '../../common/app_constants.dart';
import '../../common/bookshelf.dart';
import '../../common/document_preview_card.dart';
import '../../common/snapshot_builder.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import 'album_detail_screen.dart';

const double _addAlbumSpineWidth = 30;
const double _modernAlbumCardWidth = 132;
const double _classicLaneHeight = 130;
const double _modernLaneHeight = 176;

enum _AlbumDisplayMode { classic, modern }

/// Bookshelf: shelves stacked like AllPhotos', each holding its albums as
/// book spines (classic) or cover cards (modern). Long-press a shelf to drag
/// it, long-press an album and slide sideways to move it along the shelf.
class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key, required this.documentsService});

  final DocumentsService documentsService;

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  static const _displayModeKey = 'albums.display_mode';
  _AlbumDisplayMode _mode = _AlbumDisplayMode.classic;

  DocumentsService get _service => widget.documentsService;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_displayModeKey);
      if (!mounted || saved == null) return;
      setState(() {
        _mode = saved == 'modern'
            ? _AlbumDisplayMode.modern
            : _AlbumDisplayMode.classic;
      });
    });
  }

  Future<void> _toggleMode() async {
    setState(() {
      _mode = _mode == _AlbumDisplayMode.modern
          ? _AlbumDisplayMode.classic
          : _AlbumDisplayMode.modern;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayModeKey, _mode.name);
  }

  @override
  Widget build(BuildContext context) {
    return SnapshotBuilder(
      documentsService: _service,
      builder: (context, snapshot) {
        final shelves = snapshot.shelves;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppConstants.albumsTitle.tr(),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _mode == _AlbumDisplayMode.modern
                        ? AppConstants.albumsClassicView.tr()
                        : AppConstants.albumsModernView.tr(),
                    icon: Icon(
                      _mode == _AlbumDisplayMode.modern
                          ? Icons.view_agenda_outlined
                          : Icons.grid_view_rounded,
                    ),
                    onPressed: _toggleMode,
                  ),
                  IconButton(
                    tooltip: AppConstants.docshelfNewShelf.tr(),
                    icon: const Icon(Icons.add_rounded),
                    onPressed: _createShelf,
                  ),
                ],
              ),
            ),
            Expanded(
              // Always the same list widget: swapping a plain ListView for
              // the reorderable one when the first shelf appeared replaced
              // the whole subtree mid-frame.
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                buildDefaultDragHandles: false,
                header: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _Collections(
                    snapshot: snapshot,
                    onOpen: _openCollection,
                  ),
                ),
                footer: shelves.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 48),
                        child: _EmptyShelves(onCreate: _createShelf),
                      )
                    : null,
                proxyDecorator: (child, index, animation) => Material(
                  color: Colors.transparent,
                  elevation: 8,
                  child: child,
                ),
                itemCount: shelves.length,
                onReorderItem: (oldIndex, newIndex) {
                  if (oldIndex == newIndex) return;
                  final ids = shelves.map((shelf) => shelf.id).toList();
                  final moved = ids.removeAt(oldIndex);
                  ids.insert(newIndex, moved);
                  _service.reorderShelves(ids);
                },
                itemBuilder: (context, index) {
                  final shelf = shelves[index];
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey('shelf-${shelf.id}'),
                    index: index,
                    child: _ShelfWidget(
                      shelf: shelf,
                      snapshot: snapshot,
                      mode: _mode,
                      isFirst: index == 0,
                      isLast: index == shelves.length - 1,
                      onAddAlbum: () => _createAlbum(shelf.id),
                      onRename: () => _renameShelf(shelf),
                      onSort: () => _service.sortAlbumsByName(shelf.id),
                      onDelete: () => _deleteShelf(shelf),
                      onOpenAlbum: _openAlbum,
                      onAlbumsReordered: (albumIds) =>
                          _service.reorderAlbums(shelf.id, albumIds),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _openAlbum(DocumentAlbum album) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AlbumDetailScreen(documentsService: _service, albumId: album.id),
      ),
    );
  }

  void _openCollection(
    String title,
    List<DocumentFile> Function(DocumentsSnapshot snapshot) select,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumDetailScreen(
          documentsService: _service,
          title: title,
          select: select,
        ),
      ),
    );
  }

  Future<void> _createAlbum(String shelfId) async {
    final draft = await showAlbumDialog(context);
    if (draft == null) return;
    await _service.createAlbum(
      shelfId,
      draft.name,
      colorValue: draft.colorValue,
      iconName: draft.iconName,
    );
  }

  Future<void> _createShelf() async {
    final name = await showNameDialog(
      context,
      title: AppConstants.docshelfNewShelf.tr(),
      label: AppConstants.docshelfShelfName.tr(),
      actionLabel: AppConstants.commonCreate.tr(),
    );
    if (name == null) return;
    await _service.createShelf(name);
  }

  Future<void> _renameShelf(DocumentShelf shelf) async {
    final name = await showNameDialog(
      context,
      title: AppConstants.albumsRenameShelf.tr(),
      label: AppConstants.docshelfShelfName.tr(),
      initial: shelf.name,
    );
    if (name == null) return;
    await _service.renameShelf(shelf.id, name);
  }

  Future<void> _deleteShelf(DocumentShelf shelf) async {
    final confirmed = await showConfirmDialog(
      context,
      title: AppConstants.docshelfDeleteShelfTitle.tr(),
      message: AppConstants.docshelfDeleteShelfMessage.tr(),
      actionLabel: AppConstants.commonDelete.tr(),
    );
    if (confirmed) await _service.deleteShelf(shelf.id);
  }
}

class _ShelfWidget extends StatefulWidget {
  const _ShelfWidget({
    required this.shelf,
    required this.snapshot,
    required this.mode,
    required this.isFirst,
    required this.isLast,
    required this.onAddAlbum,
    required this.onRename,
    required this.onSort,
    required this.onDelete,
    required this.onOpenAlbum,
    required this.onAlbumsReordered,
  });

  final DocumentShelf shelf;
  final DocumentsSnapshot snapshot;
  final _AlbumDisplayMode mode;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onAddAlbum;
  final VoidCallback onRename;
  final VoidCallback onSort;
  final VoidCallback onDelete;
  final ValueChanged<DocumentAlbum> onOpenAlbum;
  final ValueChanged<List<String>> onAlbumsReordered;

  @override
  State<_ShelfWidget> createState() => _ShelfWidgetState();
}

class _ShelfWidgetState extends State<_ShelfWidget> {
  late List<DocumentAlbum> _albums = List.of(widget.shelf.albums);
  int? _draggingIndex;
  double _dragOffset = 0;

  @override
  void didUpdateWidget(covariant _ShelfWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shelf.albums != widget.shelf.albums) {
      _albums = List.of(widget.shelf.albums);
      _draggingIndex = null;
      _dragOffset = 0;
    }
  }

  void _endDragging() {
    final from = _draggingIndex;
    if (from == null) return;
    const minDrag = 28.0;
    final step = widget.mode == _AlbumDisplayMode.modern ? 132.0 : 42.0;
    final distance = _dragOffset.abs();
    if (distance >= minDrag) {
      final direction = _dragOffset.isNegative ? -1 : 1;
      final change = direction * (1 + ((distance - minDrag) / step).floor());
      final to = (from + change).clamp(0, _albums.length - 1);
      if (to != from) {
        final album = _albums.removeAt(from);
        _albums.insert(to, album);
        widget.onAlbumsReordered(_albums.map((a) => a.id).toList());
      }
    }
    setState(() {
      _draggingIndex = null;
      _dragOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final modern = widget.mode == _AlbumDisplayMode.modern;
    final laneHeight = modern ? _modernLaneHeight : _classicLaneHeight;
    final radius = BorderRadius.vertical(
      top: Radius.circular(widget.isFirst ? 12 : 0),
      bottom: Radius.circular(widget.isLast ? 12 : 0),
    );
    final edge = AppTheme.shelfEdge.withValues(alpha: 0.8);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border(
          left: BorderSide(color: edge),
          right: BorderSide(color: edge),
          top: widget.isFirst ? BorderSide(color: edge) : BorderSide.none,
          bottom: BorderSide(color: edge),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(AppTheme.shelfSurface, AppTheme.shelfBack, 0.55)!,
            AppTheme.shelfBack,
          ],
        ),
        boxShadow: [
          if (widget.isLast)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 50,
                    padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.shelfSurface,
                          Color.lerp(
                            AppTheme.shelfSurface,
                            AppTheme.shelfBack,
                            0.78,
                          )!,
                        ],
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: AppTheme.shelfEdge.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.shelf.name.toUpperCase(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.mutedText,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.16,
                              letterSpacing: 1.05,
                            ),
                          ),
                        ),
                        _ShelfIcon(
                          icon: Icons.edit_outlined,
                          tooltip: AppConstants.albumsRenameShelf.tr(),
                          onTap: widget.onRename,
                        ),
                        _ShelfIcon(
                          icon: Icons.sort_by_alpha,
                          tooltip: AppConstants.albumsSortByName.tr(),
                          onTap: widget.onSort,
                        ),
                        _ShelfIcon(
                          icon: Icons.delete_outline,
                          tooltip: AppConstants.docshelfDeleteShelf.tr(),
                          color: AppTheme.destructive,
                          onTap: widget.onDelete,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                    child: Container(
                      height: laneHeight,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.lerp(
                              AppTheme.shelfSurface,
                              AppTheme.shelfBack,
                              0.62,
                            )!,
                            Color.lerp(
                              AppTheme.shelfBack,
                              AppTheme.shelfEdge,
                              0.65,
                            )!,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppTheme.shelfEdge.withValues(alpha: 0.5),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: modern
                              ? const EdgeInsets.fromLTRB(10, 12, 10, 4)
                              : const EdgeInsets.fromLTRB(8, 14, 8, 0),
                          itemCount: _albums.length + 1,
                          itemBuilder: (context, index) {
                            if (index == _albums.length) {
                              return modern
                                  ? _AddModernAlbumButton(
                                      onTap: widget.onAddAlbum,
                                    )
                                  : _AddAlbumSpine(onTap: widget.onAddAlbum);
                            }
                            final album = _albums[index];
                            final documents = widget.snapshot.documentsForAlbum(
                              album.id,
                            );
                            final dragging = _draggingIndex == index;
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: dragging
                                  ? null
                                  : () => widget.onOpenAlbum(album),
                              onLongPressStart: (_) => setState(() {
                                _draggingIndex = index;
                                _dragOffset = 0;
                              }),
                              onLongPressMoveUpdate: (details) {
                                if (_draggingIndex == index) {
                                  setState(
                                    () => _dragOffset =
                                        details.offsetFromOrigin.dx,
                                  );
                                }
                              },
                              onLongPressEnd: (_) => _endDragging(),
                              onLongPressCancel: _endDragging,
                              child: AnimatedOpacity(
                                opacity: dragging ? 0.7 : 1,
                                duration: const Duration(milliseconds: 140),
                                child: Transform.translate(
                                  offset: dragging
                                      ? Offset(_dragOffset, -6)
                                      : Offset.zero,
                                  child: modern
                                      ? _ModernAlbumCard(
                                          album: album,
                                          documents: documents,
                                        )
                                      : AlbumSpine(
                                          album: album,
                                          count: documents.length,
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // The wooden plank the books stand on.
            Positioned(
              left: 8,
              right: 8,
              bottom: 5,
              child: Container(
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(
                        AppTheme.shelfSurface,
                        AppTheme.shelfBack,
                        0.35,
                      )!,
                      Color.lerp(AppTheme.shelfBack, AppTheme.shelfEdge, 0.2)!,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 4,
                color: AppTheme.shelfEdge.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShelfIcon extends StatelessWidget {
  const _ShelfIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color ?? AppTheme.accent),
      tooltip: tooltip,
      splashRadius: 20,
      onPressed: onTap,
    );
  }
}

class _ModernAlbumCard extends StatelessWidget {
  const _ModernAlbumCard({required this.album, required this.documents});

  final DocumentAlbum album;
  final List<DocumentFile> documents;

  @override
  Widget build(BuildContext context) {
    final color = Color(album.colorValue);
    final cover = documents.isEmpty ? null : documents.first;
    return SizedBox(
      width: _modernAlbumCardWidth,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: _modernAlbumCardWidth - 10,
          height: _modernAlbumCardWidth - 10,
          decoration: BoxDecoration(
            color: AppTheme.shelfSurface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppTheme.shelfEdge),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.34),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(5),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cover != null)
                  DocumentThumbnail(document: cover)
                else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [color, Color.lerp(color, Colors.black, 0.2)!],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        albumIconFor(album.iconName),
                        color: Colors.white.withValues(alpha: 0.85),
                        size: 30,
                      ),
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.05),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.65),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Text(
                    album.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.06,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
                if (documents.isNotEmpty)
                  Positioned(
                    top: 7,
                    right: 7,
                    child: AlbumCountBadge(
                      count: documents.length,
                      height: 22,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _addAlbumSpineWidth,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: CustomPaint(
          painter: _DashedBorderPainter(color: AppTheme.accent, radius: 2),
          child: Center(
            child: Icon(Icons.add, size: 20, color: AppTheme.accent),
          ),
        ),
      ),
    );
  }
}

class _AddModernAlbumButton extends StatelessWidget {
  const _AddModernAlbumButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _modernAlbumCardWidth,
      child: Align(
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: _modernAlbumCardWidth - 10,
            height: _modernAlbumCardWidth - 10,
            child: CustomPaint(
              painter: _DashedBorderPainter(color: AppTheme.accent, radius: 13),
              child: Center(
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Icon(Icons.add, color: AppTheme.accent, size: 25),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 5.0;
    const gap = 4.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}

/// Favorites and "expiring soon", above the shelves.
class _Collections extends StatelessWidget {
  const _Collections({required this.snapshot, required this.onOpen});

  final DocumentsSnapshot snapshot;
  final void Function(
    String title,
    List<DocumentFile> Function(DocumentsSnapshot snapshot) select,
  )
  onOpen;

  @override
  Widget build(BuildContext context) {
    final favorites = snapshot.documents.where((d) => d.isFavorite).length;
    final expiring = snapshot.documents
        .where((d) => d.validityDate != null)
        .length;
    return Row(
      children: [
        Expanded(
          child: _CollectionTile(
            icon: Icons.star_outline_rounded,
            color: AppTheme.warning,
            title: AppConstants.docshelfFavorites.tr(),
            count: favorites,
            onTap: () => onOpen(
              AppConstants.docshelfFavorites.tr(),
              (snapshot) =>
                  snapshot.documents.where((d) => d.isFavorite).toList(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CollectionTile(
            icon: Icons.event_outlined,
            color: AppTheme.destructive,
            title: AppConstants.remindersSectionTitle.tr(),
            count: expiring,
            onTap: () => onOpen(
              AppConstants.remindersSectionTitle.tr(),
              (snapshot) =>
                  snapshot.documents
                      .where((d) => d.validityDate != null)
                      .toList()
                    ..sort(
                      (a, b) => a.validityDate!.compareTo(b.validityDate!),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Text('$count', style: const TextStyle(color: AppTheme.mutedText)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyShelves extends StatelessWidget {
  const _EmptyShelves({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.menu_book_rounded, size: 64, color: AppTheme.border),
        const SizedBox(height: 16),
        Text(
          AppConstants.docshelfCreateFirstShelfTitle.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.mutedText,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppConstants.docshelfCreateFirstShelfMessage.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.mutedText, fontSize: 14),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: Text(AppConstants.docshelfNewShelf.tr()),
        ),
      ],
    );
  }
}
