import 'dart:async';

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
import '../profile/plans_screen.dart';
import 'album_detail_screen.dart';
import 'hidden_albums_screen.dart';
import 'tags_section.dart';

const double _addAlbumSpineWidth = 30;
const double _modernAlbumCardWidth = 132;
const double _classicLaneHeight = 130;
const double _modernLaneHeight = 176;

enum _AlbumDisplayMode { classic, modern }

/// Bookshelf: shelves stacked like AllPhotos', each holding its albums as
/// book spines (classic) or cover cards (modern). Long-press a shelf's name
/// bar to drag the shelf; long-press an album to drag it anywhere on its
/// shelf or onto another one.
class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({
    super.key,
    required this.documentsService,
    this.hidden = false,
  });

  final DocumentsService documentsService;

  /// The hidden side (behind its PIN): the same shelves and spines, its own
  /// shelves and albums, without the greeting and collections.
  final bool hidden;

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  static const _displayModeKey = 'albums.display_mode';
  _AlbumDisplayMode _mode = _AlbumDisplayMode.classic;
  final _scroll = ScrollController();
  final _listKey = GlobalKey();

  /// Scrolls the shelves while an album is dragged near the top or bottom,
  /// so it can reach a shelf that's off screen.
  Timer? _autoScroll;
  double _autoScrollSpeed = 0;

  DocumentsService get _service => widget.documentsService;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onAlbumDragUpdate(Offset globalPosition) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    const edge = 80.0;
    const maxSpeed = 14.0;
    final y = box.globalToLocal(globalPosition).dy;
    final height = box.size.height;
    _autoScrollSpeed = y < edge
        ? -maxSpeed * (edge - y).clamp(0, edge) / edge
        : y > height - edge
        ? maxSpeed * (y - height + edge).clamp(0, edge) / edge
        : 0;
    if (_autoScrollSpeed == 0) {
      _stopAutoScroll();
    } else {
      _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!_scroll.hasClients) return;
        final position = _scroll.position;
        final to = (position.pixels + _autoScrollSpeed).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (to != position.pixels) _scroll.jumpTo(to);
      });
    }
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  /// Puts [album] at [index] among [shelf]'s albums: a new place on its own
  /// shelf, or a move from another one.
  Future<void> _dropAlbum(
    DocumentShelf shelf,
    DocumentAlbum album,
    int index,
  ) async {
    _stopAutoScroll();
    if (album.shelfId != shelf.id) {
      await _service.moveAlbumToShelf(album.id, shelf.id, index: index);
      return;
    }
    final ids = shelf.albums.map((a) => a.id).toList();
    final from = ids.indexOf(album.id);
    if (from < 0) return;
    // Taking it out first shifts the places after it by one.
    final to = (from < index ? index - 1 : index).clamp(0, ids.length - 1);
    if (to == from) return;
    ids
      ..removeAt(from)
      ..insert(to, album.id);
    await _service.reorderAlbums(shelf.id, ids);
  }

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
        final shelves = widget.hidden
            ? snapshot.hiddenShelves
            : snapshot.shelves;
        // The plan was dropped: the safe opens read-only.
        final readOnlySafe = widget.hidden && !safeIncluded;
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(widget.hidden ? 4 : 20, 12, 8, 4),
              child: Row(
                children: [
                  if (widget.hidden) ...[
                    const BackButton(),
                    const Icon(
                      Icons.visibility_off_rounded,
                      color: AppTheme.premium,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppConstants.hiddenTitle.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ] else
                    Expanded(child: _Greeting(profile: snapshot.profile)),
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
                  if (!readOnlySafe)
                    IconButton(
                      tooltip: AppConstants.docshelfNewShelf.tr(),
                      icon: const Icon(Icons.add_rounded),
                      onPressed: _createShelf,
                    ),
                ],
              ),
            ),
            if (readOnlySafe) const _ReadOnlySafeBanner(),
            Expanded(
              // Always the same list widget: swapping a plain ListView for
              // the reorderable one when the first shelf appeared replaced
              // the whole subtree mid-frame.
              child: ReorderableListView.builder(
                key: _listKey,
                scrollController: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                buildDefaultDragHandles: false,
                header: widget.hidden
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Collections(
                              snapshot: snapshot,
                              onOpen: _openCollection,
                            ),
                            const SizedBox(height: 14),
                            TagsSection(
                              snapshot: snapshot,
                              documentsService: _service,
                              onOpenTag: (tag) => _openCollection(
                                '#$tag',
                                (snapshot) => documentsWithTag(snapshot, tag),
                              ),
                            ),
                          ],
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
                  return _ShelfWidget(
                    key: ValueKey('shelf-${shelf.id}'),
                    index: index,
                    shelf: shelf,
                    snapshot: snapshot,
                    mode: _mode,
                    editable: !readOnlySafe,
                    isFirst: index == 0,
                    isLast: index == shelves.length - 1,
                    onAddAlbum: () => _createAlbum(shelf.id, shelves),
                    // "Hidden" keeps its translated name and stays.
                    onRename: shelf.isDefaultHidden
                        ? null
                        : () => _renameShelf(shelf),
                    onSort: () => _service.sortAlbumsByName(shelf.id),
                    onDelete: shelf.isDefaultHidden
                        ? null
                        : () => _deleteShelf(shelf),
                    onOpenAlbum: _openAlbum,
                    onAlbumDropped: (album, to) => _dropAlbum(shelf, album, to),
                    onAlbumDragUpdate: _onAlbumDragUpdate,
                    onAlbumDragEnd: _stopAutoScroll,
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

  Future<void> _createAlbum(String shelfId, List<DocumentShelf> shelves) async {
    if (widget.hidden && !await ensureSafeIncluded(context)) return;
    if (!mounted) return;
    final draft = await showAlbumDialog(
      context,
      shelves: shelves,
      shelfId: shelfId,
    );
    if (draft == null) return;
    await createAlbumFromDraft(_service, draft, hidden: widget.hidden);
  }

  Future<void> _createShelf() async {
    if (widget.hidden && !await ensureSafeIncluded(context)) return;
    if (!mounted) return;
    final name = await showNameDialog(
      context,
      title: AppConstants.docshelfNewShelf.tr(),
      label: AppConstants.docshelfShelfName.tr(),
      actionLabel: AppConstants.commonCreate.tr(),
    );
    if (name == null) return;
    await _service.createShelf(name, hidden: widget.hidden);
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
      message:
          (shelf.hidden
                  ? AppConstants.hiddenDeleteShelfMessage
                  : AppConstants.docshelfDeleteShelfMessage)
              .tr(),
      actionLabel: AppConstants.commonDelete.tr(),
    );
    if (confirmed) await _service.deleteShelf(shelf.id);
  }
}

/// On top of a safe the plan no longer includes.
class _ReadOnlySafeBanner extends StatelessWidget {
  const _ReadOnlySafeBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: AppTheme.premium.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => ensureSafeIncluded(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lock_clock_outlined,
                      color: AppTheme.premium,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppConstants.hiddenReadOnly.tr(),
                        style: const TextStyle(
                          color: AppTheme.text,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    AppConstants.hiddenSeePlans.tr(),
                    style: const TextStyle(
                      color: AppTheme.premium,
                      fontWeight: FontWeight.w700,
                    ),
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

class _ShelfWidget extends StatefulWidget {
  const _ShelfWidget({
    super.key,
    required this.index,
    required this.shelf,
    required this.snapshot,
    required this.mode,
    required this.editable,
    required this.isFirst,
    required this.isLast,
    required this.onAddAlbum,
    required this.onRename,
    required this.onSort,
    required this.onDelete,
    required this.onOpenAlbum,
    required this.onAlbumDropped,
    required this.onAlbumDragUpdate,
    required this.onAlbumDragEnd,
  });

  /// Its place in the list of shelves (for dragging the shelf).
  final int index;
  final DocumentShelf shelf;
  final DocumentsSnapshot snapshot;
  final _AlbumDisplayMode mode;

  /// False on a read-only safe: albums can't be dragged.
  final bool editable;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onAddAlbum;
  final VoidCallback? onRename;
  final VoidCallback onSort;
  final VoidCallback? onDelete;
  final ValueChanged<DocumentAlbum> onOpenAlbum;

  /// An album (from this shelf or another) dropped at [index] among this
  /// shelf's albums.
  final void Function(DocumentAlbum album, int index) onAlbumDropped;
  final ValueChanged<Offset> onAlbumDragUpdate;
  final VoidCallback onAlbumDragEnd;

  @override
  State<_ShelfWidget> createState() => _ShelfWidgetState();
}

class _ShelfWidgetState extends State<_ShelfWidget> {
  /// Where an album dragged over this shelf would land, as an index among
  /// its albums; null when nothing is over it.
  int? _dropIndex;

  void _hover(int? index) {
    if (_dropIndex != index) setState(() => _dropIndex = index);
  }

  void _drop(DocumentAlbum album, int index) {
    _hover(null);
    widget.onAlbumDropped(album, index);
  }

  Widget _albumView(DocumentAlbum album, List<DocumentFile> documents) {
    return widget.mode == _AlbumDisplayMode.modern
        ? _ModernAlbumCard(album: album, documents: documents)
        : AlbumSpine(album: album, count: documents.length);
  }

  Widget _album(BuildContext context, int index, double itemHeight) {
    final albums = widget.shelf.albums;
    final album = albums[index];
    final documents = widget.snapshot.documentsForAlbum(album.id);
    final view = _albumView(album, documents);
    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onOpenAlbum(album),
      child: view,
    );
    if (!widget.editable) return tappable;

    final modern = widget.mode == _AlbumDisplayMode.modern;
    final size = Size(
      modern ? _modernAlbumCardWidth : albumSpineWidth + 8,
      itemHeight,
    );
    return Builder(
      builder: (itemContext) => DragTarget<DocumentAlbum>(
        // Over its left half it goes before this album, over the right
        // half after it.
        onMove: (details) {
          final box = itemContext.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return;
          final x = box.globalToLocal(details.offset).dx;
          _hover(x < box.size.width / 2 ? index : index + 1);
        },
        onLeave: (_) => _hover(null),
        onAcceptWithDetails: (details) =>
            _drop(details.data, _dropIndex ?? index),
        builder: (context, candidates, rejected) {
          final before = _dropIndex == index;
          final after = _dropIndex == index + 1 && index == albums.length - 1;
          return LongPressDraggable<DocumentAlbum>(
            data: album,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            onDragUpdate: (details) =>
                widget.onAlbumDragUpdate(details.globalPosition),
            onDragEnd: (_) => widget.onAlbumDragEnd(),
            feedback: _DraggedAlbum(size: size, child: view),
            childWhenDragging: Opacity(opacity: 0.3, child: view),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                tappable,
                if (before) const _DropMarker(left: true),
                if (after) const _DropMarker(left: false),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final albums = widget.shelf.albums;
    final modern = widget.mode == _AlbumDisplayMode.modern;
    final laneHeight = modern ? _modernLaneHeight : _classicLaneHeight;
    final lanePadding = modern
        ? const EdgeInsets.fromLTRB(10, 12, 10, 4)
        : const EdgeInsets.fromLTRB(8, 14, 8, 0);
    final itemHeight = laneHeight - lanePadding.vertical;
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
                  // Long-press the shelf's name bar to move the shelf.
                  ReorderableDelayedDragStartListener(
                    index: widget.index,
                    child: Container(
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
                              shelfDisplayName(widget.shelf).toUpperCase(),
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
                          if (widget.onRename case final onRename?)
                            _ShelfIcon(
                              icon: Icons.edit_outlined,
                              tooltip: AppConstants.albumsRenameShelf.tr(),
                              onTap: onRename,
                            ),
                          _ShelfIcon(
                            icon: Icons.sort_by_alpha,
                            tooltip: AppConstants.albumsSortByName.tr(),
                            onTap: widget.onSort,
                          ),
                          if (widget.onDelete case final onDelete?)
                            _ShelfIcon(
                              icon: Icons.delete_outline,
                              tooltip: AppConstants.docshelfDeleteShelf.tr(),
                              color: AppTheme.destructive,
                              onTap: onDelete,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                    // Dropped on the lane's empty space, an album goes at
                    // the end of the shelf.
                    child: DragTarget<DocumentAlbum>(
                      onMove: (_) => _hover(albums.length),
                      onLeave: (_) => _hover(null),
                      onAcceptWithDetails: (details) =>
                          _drop(details.data, albums.length),
                      builder: (context, candidates, rejected) {
                        final over = _dropIndex != null;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
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
                              color: over
                                  ? AppTheme.accent
                                  : AppTheme.shelfEdge.withValues(alpha: 0.5),
                              width: over ? 2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: lanePadding,
                              itemCount: albums.length + 1,
                              itemBuilder: (context, index) {
                                if (index == albums.length) {
                                  return modern
                                      ? _AddModernAlbumButton(
                                          onTap: widget.onAddAlbum,
                                        )
                                      : _AddAlbumSpine(
                                          onTap: widget.onAddAlbum,
                                        );
                                }
                                return KeyedSubtree(
                                  key: ValueKey(albums[index].id),
                                  child: _album(context, index, itemHeight),
                                );
                              },
                            ),
                          ),
                        );
                      },
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

/// The album under the finger while it's dragged: lifted a little and
/// centred on the finger.
class _DraggedAlbum extends StatelessWidget {
  const _DraggedAlbum({required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(-size.width / 2, -size.height / 2),
      child: Transform.scale(
        scale: 1.08,
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      ),
    );
  }
}

/// The line showing where a dragged album will land.
class _DropMarker extends StatelessWidget {
  const _DropMarker({required this.left});

  final bool left;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      bottom: 0,
      left: left ? -3 : null,
      right: left ? null : -3,
      child: Container(
        width: 4,
        decoration: BoxDecoration(
          color: AppTheme.accent,
          borderRadius: BorderRadius.circular(2),
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
/// "Hello, Ana" and the account's document count — the app opens on the
/// shelf, so the welcome lives here.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final firstName = profile.name.trim().split(RegExp(r'\s+')).first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                firstName.isEmpty
                    ? AppConstants.galleryHello.tr()
                    : AppConstants.galleryHelloName.tr(
                        namedArgs: {'name': firstName},
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // The plan, one tap from the home screen.
            PlanChip(summary: profile.storageSummary),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          AppConstants.galleryDocumentsCount.tr(
            namedArgs: {'count': '${profile.documentsCount}'},
          ),
          style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
        ),
      ],
    );
  }
}

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
