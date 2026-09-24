import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/add_document_sheet.dart';
import '../../common/album_dialog.dart';
import '../../common/app_constants.dart';
import '../../common/cloud_quick_sheet.dart';
import '../../common/device_scan_sheet.dart';
import '../../common/document_actions.dart';
import '../../common/document_details_sheet.dart';
import '../../common/document_file_icon.dart';
import '../../common/document_import_flow.dart';
import '../../common/document_preview_card.dart';
import '../../common/snapshot_builder.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import '../albums/album_detail_screen.dart';
import '../viewer/document_viewer_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    super.key,
    required this.documentsService,
    required this.onOpenArchive,
    required this.onOpenCloud,
  });

  final DocumentsService documentsService;
  final VoidCallback onOpenArchive;
  final void Function(CloudProviderId? provider) onOpenCloud;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  DocumentSearchFilter _filter = const DocumentSearchFilter();
  DocumentType? _gridType;
  final Set<String> _selected = {};
  bool _searchingDevice = false;
  Timer? _recentExpiry;

  /// How many recent documents the gallery shows before "View all".
  static const _recentPreviewCount = 3;

  DocumentsService get _service => widget.documentsService;
  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _recentExpiry?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SnapshotBuilder(
      documentsService: _service,
      builder: (context, snapshot) {
        _selected.removeWhere(
          (id) => !snapshot.documents.any((document) => document.id == id),
        );
        final searching = !_filter.isEmpty;
        return PopScope(
          canPop: !_selecting && !searching,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_selecting) {
              setState(_selected.clear);
            } else {
              _clearSearch();
            }
          },
          child: CustomScrollView(
            key: const PageStorageKey('gallery'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: _selecting
                      ? _SelectionBar(
                          count: _selected.length,
                          onClose: () => setState(_selected.clear),
                          onAlbums: () => _selectionAction(
                            snapshot,
                            (documents) => showAlbumMembershipSheet(
                              context,
                              _service,
                              documents,
                            ),
                          ),
                          onTags: () => _selectionAction(
                            snapshot,
                            (documents) => showDocumentDetailsSheet(
                              context,
                              _service,
                              documents: documents,
                            ),
                          ),
                          onShare: () => _selectionAction(
                            snapshot,
                            _service.shareDocuments,
                          ),
                          onArchive: () =>
                              _selectionAction(snapshot, (documents) async {
                                await _service.setArchived(
                                  documents.map((d) => d.id).toList(),
                                  true,
                                );
                                if (context.mounted) {
                                  showSnack(
                                    context,
                                    AppConstants.actionsArchived.tr(),
                                  );
                                }
                              }, clear: true),
                          onTrash: () => _selectionAction(
                            snapshot,
                            (documents) => moveToTrashWithUndo(
                              context,
                              _service,
                              documents,
                            ),
                            clear: true,
                          ),
                        )
                      : _Header(
                          profile: snapshot.profile,
                          archivedCount:
                              snapshot.archivedDocuments.length +
                              snapshot.trashDocuments.length,
                          onOpenArchive: widget.onOpenArchive,
                          onOpenClouds: () => showCloudQuickSheet(
                            context,
                            _service,
                            onOpenCloud: widget.onOpenCloud,
                          ),
                        ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                sliver: SliverToBoxAdapter(child: _buildSearchField()),
              ),
              if (searching)
                ..._buildSearchResults(snapshot)
              else
                ..._buildHome(snapshot),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      textInputAction: TextInputAction.search,
      onChanged: (value) => setState(() {
        _filter = _filter.copyWith(query: value);
      }),
      // "Search" on the keyboard looks on the phone too, so files can be
      // brought in without opening the file manager.
      onSubmitted: (value) {
        final query = value.trim();
        if (query.isNotEmpty) _searchDevice(query);
      },
      decoration: InputDecoration(
        hintText: AppConstants.gallerySearchHint.tr(),
        prefixIcon: const Icon(Icons.phone_android_outlined),
        suffixIcon: _filter.isEmpty
            ? null
            : IconButton(
                tooltip: AppConstants.commonClose.tr(),
                icon: const Icon(Icons.close_rounded),
                onPressed: _clearSearch,
              ),
      ),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() => _filter = const DocumentSearchFilter());
  }

  // Home ------------------------------------------------------------------

  List<Widget> _buildHome(DocumentsSnapshot snapshot) {
    // Documents that went into an album live there now; the gallery only
    // keeps what still needs organizing.
    final documents = snapshot.unorganizedDocuments;
    final gridDocuments = _gridType == null
        ? documents
        : documents.where((d) => d.type == _gridType).toList();
    final recents = snapshot.recentAt(DateTime.now());
    _scheduleRecentExpiry(recents);

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showAddDocumentSheet(
                    context,
                    _service,
                    onOpenCloud: widget.onOpenCloud,
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(AppConstants.galleryAdd.tr()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => scanAndImport(context, _service),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(AppConstants.galleryScan.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
      if (snapshot.documents.isEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 0),
          sliver: SliverToBoxAdapter(child: _EmptyGallery()),
        )
      else ...[
        if (snapshot.suggestions.isNotEmpty) ...[
          _sectionHeader(AppConstants.gallerySuggestions.tr()),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: snapshot.suggestions.length.clamp(0, 3),
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _SuggestionCard(
                suggestion: snapshot.suggestions[index],
                documentsService: _service,
              ),
            ),
          ),
        ],
        if (recents.isNotEmpty) ...[
          _sectionHeader(
            AppConstants.docshelfRecent.tr(),
            action: recents.length > _recentPreviewCount
                ? AppConstants.commonViewAll.tr()
                : null,
            onAction: _openAllRecents,
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 196,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: recents.length.clamp(0, _recentPreviewCount),
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  return SizedBox(width: 124, child: _card(recents[index]));
                },
              ),
            ),
          ),
        ],
        _sectionHeader(
          AppConstants.galleryAllDocuments.tr(
            namedArgs: {'count': '${documents.length}'},
          ),
        ),
        SliverToBoxAdapter(
          child: _TypeChips(
            selected: _gridType,
            documents: documents,
            onSelected: (type) => setState(() => _gridType = type),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (documents.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Text(
                AppConstants.galleryAllOrganized.tr(),
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
              ),
            ),
          )
        else
          _grid(gridDocuments),
      ],
    ];
  }

  /// Rebuilds when the oldest recent document ages out of the "Recent" row,
  /// so it disappears on time even if nothing else changes.
  void _scheduleRecentExpiry(List<DocumentFile> recents) {
    _recentExpiry?.cancel();
    final oldest = recents.lastOrNull?.importedAt;
    if (oldest == null) return;
    final delay = oldest
        .add(DocumentsSnapshot.recentWindow)
        .difference(DateTime.now());
    _recentExpiry = Timer(
      delay.isNegative ? Duration.zero : delay + const Duration(seconds: 1),
      () {
        if (mounted) setState(() {});
      },
    );
  }

  void _openAllRecents() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumDetailScreen(
          documentsService: _service,
          title: AppConstants.docshelfRecent.tr(),
          select: (snapshot) => snapshot.recentAt(DateTime.now()),
        ),
      ),
    );
  }

  // Search ----------------------------------------------------------------

  List<Widget> _buildSearchResults(DocumentsSnapshot snapshot) {
    final albumNames = {for (final a in snapshot.albums) a.id: a.name};
    final hits = searchDocuments(
      snapshot.documents,
      _filter,
      albumNames: albumNames,
    );
    final archivedHits = _filter.query.trim().isEmpty
        ? const <DocumentSearchHit>[]
        : searchDocuments(
            snapshot.archivedDocuments,
            _filter,
            albumNames: albumNames,
          );
    final query = _filter.query.trim();

    return [
      SliverToBoxAdapter(
        child: _SearchFilters(
          filter: _filter,
          tags: snapshot.tags,
          onChanged: (filter) => setState(() => _filter = filter),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
        sliver: SliverToBoxAdapter(
          child: Text(
            AppConstants.galleryResults.tr(
              namedArgs: {'count': '${hits.length}'},
            ),
            style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
          ),
        ),
      ),
      if (hits.isNotEmpty)
        _grid(
          hits.map((hit) => hit.document).toList(),
          subtitles: {
            for (final hit in hits)
              if (hit.textSnippet != null) hit.document.id: hit.textSnippet!,
          },
        ),
      if (archivedHits.isNotEmpty) ...[
        _sectionHeader(
          AppConstants.galleryAlsoArchived.tr(
            namedArgs: {'count': '${archivedHits.length}'},
          ),
        ),
        _grid(archivedHits.map((hit) => hit.document).toList()),
      ],
      if (query.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: _DeviceSearchCard(
              query: query,
              loading: _searchingDevice,
              onTap: () => _searchDevice(query),
            ),
          ),
        ),
    ];
  }

  Future<void> _searchDevice(String query) async {
    if (_searchingDevice) return;
    setState(() => _searchingDevice = true);
    try {
      final scan = await _service.searchDevice(
        query,
        title: AppConstants.galleryDeviceResultsTitle.tr(
          namedArgs: {'query': query},
        ),
      );
      if (!mounted) return;
      if (scan == null || scan.documents.isEmpty) {
        showSnack(context, AppConstants.galleryDeviceNothing.tr());
        return;
      }
      await showDeviceScanSheet(context, _service, scan);
    } catch (_) {
      if (mounted) {
        showSnack(context, AppConstants.archiveFolderOpenFailed.tr());
      }
    } finally {
      if (mounted) setState(() => _searchingDevice = false);
    }
  }

  // Shared pieces -----------------------------------------------------------

  Widget _sectionHeader(
    String title, {
    String? action,
    VoidCallback? onAction,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 24, 12, 10),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (action != null)
              TextButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }

  Widget _grid(
    List<DocumentFile> documents, {
    Map<String, String> subtitles = const {},
  }) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.crossAxisExtent / 170).floor().clamp(
            2,
            6,
          );
          return SliverGrid.builder(
            itemCount: documents.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              childAspectRatio: 0.66,
            ),
            itemBuilder: (context, index) {
              final document = documents[index];
              return _card(document, subtitle: subtitles[document.id]);
            },
          );
        },
      ),
    );
  }

  Widget _card(DocumentFile document, {String? subtitle}) {
    return DocumentPreviewCard(
      document: document,
      subtitle: subtitle,
      selected: _selecting ? _selected.contains(document.id) : null,
      onTap: () {
        if (_selecting) {
          _toggleSelected(document);
        } else {
          openDocumentViewer(context, _service, document);
        }
      },
      onLongPress: () {
        if (_selecting) {
          _toggleSelected(document);
        } else {
          setState(() => _selected.add(document.id));
        }
      },
      trailing: _selecting
          ? null
          : SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 20,
                tooltip: AppConstants.commonMoreOptions.tr(),
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppTheme.mutedText,
                ),
                onPressed: () =>
                    showDocumentActions(context, _service, document),
              ),
            ),
    );
  }

  void _toggleSelected(DocumentFile document) {
    setState(() {
      _selected.contains(document.id)
          ? _selected.remove(document.id)
          : _selected.add(document.id);
    });
  }

  Future<void> _selectionAction(
    DocumentsSnapshot snapshot,
    Future<void> Function(List<DocumentFile> documents) action, {
    bool clear = false,
  }) async {
    final documents = snapshot.documents
        .where((document) => _selected.contains(document.id))
        .toList();
    if (clear) setState(_selected.clear);
    await action(documents);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.archivedCount,
    required this.onOpenArchive,
    required this.onOpenClouds,
  });

  final UserProfile profile;
  final int archivedCount;
  final VoidCallback onOpenArchive;
  final VoidCallback onOpenClouds;

  @override
  Widget build(BuildContext context) {
    final firstName = profile.name.trim().split(RegExp(r'\s+')).first;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                firstName.isEmpty
                    ? AppConstants.galleryHello.tr()
                    : AppConstants.galleryHelloName.tr(
                        namedArgs: {'name': firstName},
                      ),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AppConstants.galleryDocumentsCount.tr(
                  namedArgs: {'count': '${profile.documentsCount}'},
                ),
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: AppConstants.navCloud.tr(),
          onPressed: onOpenClouds,
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.surfaceStrong,
            foregroundColor: AppTheme.text,
          ),
          icon: const Icon(Icons.cloud_outlined),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: AppConstants.archiveTitle.tr(),
          onPressed: onOpenArchive,
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.surfaceStrong,
            foregroundColor: AppTheme.text,
          ),
          icon: Badge(
            isLabelVisible: archivedCount > 0,
            label: Text('$archivedCount'),
            child: const Icon(Icons.inventory_2_outlined),
          ),
        ),
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onClose,
    required this.onAlbums,
    required this.onTags,
    required this.onShare,
    required this.onArchive,
    required this.onTrash,
  });

  final int count;
  final VoidCallback onClose;
  final VoidCallback onAlbums;
  final VoidCallback onTags;
  final VoidCallback onShare;
  final VoidCallback onArchive;
  final VoidCallback onTrash;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            tooltip: AppConstants.commonClose.tr(),
          ),
          Expanded(
            child: Text(
              AppConstants.gallerySelected.tr(namedArgs: {'count': '$count'}),
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: onAlbums,
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: AppConstants.actionsAlbums.tr(),
          ),
          IconButton(
            onPressed: onTags,
            icon: const Icon(Icons.sell_outlined),
            tooltip: AppConstants.detailsTags.tr(),
          ),
          IconButton(
            onPressed: onShare,
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: AppConstants.actionsShare.tr(),
          ),
          IconButton(
            onPressed: onArchive,
            icon: const Icon(Icons.archive_outlined),
            tooltip: AppConstants.archiveArchive.tr(),
          ),
          IconButton(
            onPressed: onTrash,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppTheme.destructive,
            ),
            tooltip: AppConstants.actionsMoveToTrash.tr(),
          ),
        ],
      ),
    );
  }
}

class _TypeChips extends StatelessWidget {
  const _TypeChips({
    required this.selected,
    required this.documents,
    required this.onSelected,
  });

  final DocumentType? selected;
  final List<DocumentFile> documents;
  final ValueChanged<DocumentType?> onSelected;

  @override
  Widget build(BuildContext context) {
    final types = {for (final document in documents) document.type}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (types.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(AppConstants.archiveAll.tr()),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final type in types)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(
                  documentTypeIcon(type),
                  size: 16,
                  color: documentTypeColor(type),
                ),
                label: Text(documentTypeName(type)),
                selected: selected == type,
                onSelected: (_) => onSelected(selected == type ? null : type),
              ),
            ),
        ],
      ),
    );
  }
}

String documentTypeName(DocumentType type) {
  return switch (type) {
    DocumentType.pdf => 'PDF',
    DocumentType.word => 'Word',
    DocumentType.excel => 'Excel',
    DocumentType.presentation => 'PowerPoint',
    DocumentType.archive => 'ZIP',
    DocumentType.image => AppConstants.galleryImages.tr(),
  };
}

class _SearchFilters extends StatelessWidget {
  const _SearchFilters({
    required this.filter,
    required this.tags,
    required this.onChanged,
  });

  final DocumentSearchFilter filter;
  final List<String> tags;
  final ValueChanged<DocumentSearchFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        children: [
          _chip(
            label: AppConstants.galleryFilterFavorites.tr(),
            icon: Icons.star_outline_rounded,
            selected: filter.favoritesOnly,
            onTap: () => onChanged(
              filter.copyWith(favoritesOnly: !filter.favoritesOnly),
            ),
          ),
          PopupMenuButton<SearchDateRange>(
            onSelected: (range) => onChanged(filter.copyWith(dateRange: range)),
            itemBuilder: (context) => [
              for (final range in SearchDateRange.values)
                PopupMenuItem(value: range, child: Text(_dateLabel(range))),
            ],
            child: IgnorePointer(
              child: _chip(
                label: filter.dateRange == SearchDateRange.any
                    ? AppConstants.galleryFilterDate.tr()
                    : _dateLabel(filter.dateRange),
                icon: Icons.calendar_today_outlined,
                selected: filter.dateRange != SearchDateRange.any,
                onTap: () {},
              ),
            ),
          ),
          PopupMenuButton<DocumentType?>(
            onSelected: (type) => onChanged(
              type == null
                  ? filter.copyWith(clearType: true)
                  : filter.copyWith(type: type),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: null,
                child: Text(AppConstants.archiveAll.tr()),
              ),
              for (final type in DocumentType.values)
                if (type != DocumentType.archive)
                  PopupMenuItem(
                    value: type,
                    child: Text(documentTypeName(type)),
                  ),
            ],
            child: IgnorePointer(
              child: _chip(
                label: filter.type == null
                    ? AppConstants.galleryFilterType.tr()
                    : documentTypeName(filter.type!),
                icon: Icons.description_outlined,
                selected: filter.type != null,
                onTap: () {},
              ),
            ),
          ),
          for (final tag in tags)
            _chip(
              label: '#$tag',
              selected: filter.tag == tag,
              onTap: () => onChanged(
                filter.tag == tag
                    ? filter.copyWith(clearTag: true)
                    : filter.copyWith(tag: tag),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    IconData? icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        avatar: icon == null ? null : Icon(icon, size: 16),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  String _dateLabel(SearchDateRange range) {
    return switch (range) {
      SearchDateRange.any => AppConstants.galleryDateAny.tr(),
      SearchDateRange.last7Days => AppConstants.galleryDate7.tr(),
      SearchDateRange.last30Days => AppConstants.galleryDate30.tr(),
      SearchDateRange.thisYear => AppConstants.galleryDateYear.tr(),
      SearchDateRange.older => AppConstants.galleryDateOlder.tr(),
    };
  }
}

class _DeviceSearchCard extends StatelessWidget {
  const _DeviceSearchCard({
    required this.query,
    required this.loading,
    required this.onTap,
  });

  final String query;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.phone_android_outlined, color: AppTheme.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.galleryDeviceSearch.tr(
                        namedArgs: {'query': query},
                      ),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loading
                          ? AppConstants.archiveSearchingDevice.tr()
                          : AppConstants.galleryDeviceSearchHint.tr(),
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.documentsService,
  });

  final AlbumSuggestion suggestion;
  final DocumentsService documentsService;

  @override
  Widget build(BuildContext context) {
    final album = suggestion.album;
    final typeLabel = semanticTypeLabel(suggestion.semanticType);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 38,
                height: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: DocumentThumbnail(document: suggestion.document),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.document.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      album == null
                          ? AppConstants.suggestionCreate.tr(
                              namedArgs: {'type': typeLabel},
                            )
                          : AppConstants.suggestionAdd.tr(
                              namedArgs: {
                                'type': typeLabel,
                                'album': album.name,
                              },
                            ),
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppConstants.commonClose.tr(),
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () =>
                    documentsService.dismissSuggestion(suggestion.document.id),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => showAlbumMembershipSheet(
                  context,
                  documentsService,
                  [suggestion.document],
                ),
                child: Text(AppConstants.suggestionChooseOther.tr()),
              ),
              TextButton(
                onPressed: () => _accept(context),
                child: Text(
                  album == null
                      ? AppConstants.suggestionCreateAction.tr(
                          namedArgs: {
                            'album': semanticTypeAlbumName(
                              suggestion.semanticType,
                            ),
                          },
                        )
                      : AppConstants.suggestionYes.tr(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _accept(BuildContext context) async {
    var albumId = suggestion.album?.id;
    if (albumId == null) {
      final draft = await showAlbumDialog(
        context,
        suggestedName: semanticTypeAlbumName(suggestion.semanticType),
      );
      if (draft == null) return;
      albumId = await documentsService.createAlbum(
        null,
        draft.name,
        colorValue: draft.colorValue,
        iconName: draft.iconName,
      );
    }
    if (albumId == null) return;
    await documentsService.addDocumentsToAlbum([
      suggestion.document.id,
    ], albumId);
  }
}

class _EmptyGallery extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(
          Icons.description_outlined,
          size: 44,
          color: AppTheme.dimText,
        ),
        const SizedBox(height: 14),
        Text(
          AppConstants.galleryEmptyTitle.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          AppConstants.galleryEmptyMessage.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.mutedText, height: 1.4),
        ),
      ],
    );
  }
}
