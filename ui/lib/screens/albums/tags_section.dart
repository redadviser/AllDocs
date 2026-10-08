import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/album_dialog.dart';
import '../../common/app_constants.dart';
import '../../common/app_sheet.dart';
import '../../common/document_actions.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import 'album_detail_screen.dart';

/// Documents (in the gallery or in albums) tagged [tag], newest first.
List<DocumentFile> documentsWithTag(DocumentsSnapshot snapshot, String tag) {
  final key = normalizeForSearch(tag);
  return snapshot.documents
      .where((d) => d.tags.any((t) => normalizeForSearch(t) == key))
      .toList();
}

/// The tags in use, as chips with their document count: only the first
/// [previewCount] are shown, "See all" opens every tag with a search box.
/// Tap a tag to see its documents, long-press it to rename or delete it.
/// Tags are created from the gallery, when tagging a document.
class TagsSection extends StatelessWidget {
  const TagsSection({
    super.key,
    required this.snapshot,
    required this.documentsService,
    required this.onOpenTag,
  });

  final DocumentsSnapshot snapshot;
  final DocumentsService documentsService;
  final ValueChanged<String> onOpenTag;

  static const previewCount = 3;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sell_outlined, size: 18, color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppConstants.tagsTitle.tr(),
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (snapshot.tags.length > previewCount)
                TextButton(
                  onPressed: () => _showAllTags(context),
                  child: Text(
                    AppConstants.tagsViewAll.tr(
                      namedArgs: {'count': '${snapshot.tags.length}'},
                    ),
                  ),
                )
              else
                const SizedBox(height: 48),
            ],
          ),
          if (snapshot.tags.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                AppConstants.tagsEmpty.tr(),
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in snapshot.tags.take(previewCount))
                  _TagChip(
                    tag: tag,
                    count: documentsWithTag(snapshot, tag).length,
                    onTap: () => onOpenTag(tag),
                    onLongPress: () => _showTagMenu(context, tag),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Every tag, searchable, for when the list gets long.
  void _showAllTags(BuildContext context) {
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => _AllTagsSheet(
        snapshot: snapshot,
        onOpenTag: (tag) {
          Navigator.of(sheetContext).pop();
          onOpenTag(tag);
        },
        onTagMenu: (tag) {
          Navigator.of(sheetContext).pop();
          _showTagMenu(context, tag);
        },
      ),
    );
  }

  void _showTagMenu(BuildContext context, String tag) {
    showOptionsSheet<void>(
      context: context,
      builder: (sheetContext) {
        void run(Future<void> Function() action) {
          Navigator.of(sheetContext).pop();
          action();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '#$tag',
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(AppConstants.tagsView.tr()),
                onTap: () => run(() async => onOpenTag(tag)),
              ),
              ListTile(
                leading: const Icon(Icons.post_add_rounded),
                title: Text(AppConstants.tagsAddDocuments.tr()),
                onTap: () => run(() => _addDocuments(context, tag)),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(AppConstants.tagsRename.tr()),
                onTap: () => run(() => _renameTag(context, tag)),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.destructive,
                ),
                title: Text(
                  AppConstants.tagsDelete.tr(),
                  style: const TextStyle(color: AppTheme.destructive),
                ),
                onTap: () => run(() => _deleteTag(context, tag)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addDocuments(BuildContext context, String tag) async {
    final tagged = documentsWithTag(snapshot, tag).map((d) => d.id).toSet();
    final candidates = snapshot.documents
        .where((d) => !tagged.contains(d.id))
        .toList();
    final picked = await showPickDocumentsSheet(context, candidates);
    if (picked == null || picked.isEmpty) return;
    await documentsService.addTagToDocuments(tag, picked);
  }

  Future<void> _renameTag(BuildContext context, String tag) async {
    final name = await showNameDialog(
      context,
      title: AppConstants.tagsRename.tr(),
      label: AppConstants.tagsName.tr(),
      initial: tag,
    );
    final renamed = name?.trim().replaceFirst(RegExp(r'^#+'), '');
    if (renamed == null || renamed.isEmpty || renamed == tag) return;
    await documentsService.renameTag(tag, renamed);
    if (context.mounted) showSnack(context, AppConstants.tagsRenamed.tr());
  }

  Future<void> _deleteTag(BuildContext context, String tag) async {
    final confirmed = await showConfirmDialog(
      context,
      title: AppConstants.tagsDeleteTitle.tr(namedArgs: {'tag': tag}),
      message: AppConstants.tagsDeleteMessage.tr(
        namedArgs: {'count': '${documentsWithTag(snapshot, tag).length}'},
      ),
      actionLabel: AppConstants.tagsDelete.tr(),
    );
    if (!confirmed) return;
    await documentsService.deleteTag(tag);
  }
}

class _AllTagsSheet extends StatefulWidget {
  const _AllTagsSheet({
    required this.snapshot,
    required this.onOpenTag,
    required this.onTagMenu,
  });

  final DocumentsSnapshot snapshot;
  final ValueChanged<String> onOpenTag;
  final ValueChanged<String> onTagMenu;

  @override
  State<_AllTagsSheet> createState() => _AllTagsSheetState();
}

class _AllTagsSheetState extends State<_AllTagsSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = normalizeForSearch(
      _search.text.trim().replaceFirst(RegExp(r'^#+'), ''),
    );
    final tags = key.isEmpty
        ? widget.snapshot.tags
        : widget.snapshot.tags
              .where((t) => normalizeForSearch(t).contains(key))
              .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                AppConstants.tagsAll.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: AppConstants.tagsSearch.tr(),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: tags.isEmpty
                  ? Center(
                      child: Text(
                        AppConstants.tagsNoResults.tr(),
                        style: const TextStyle(color: AppTheme.mutedText),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisExtent: 48,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: tags.length,
                      itemBuilder: (context, index) {
                        final tag = tags[index];
                        return _TagGridTile(
                          tag: tag,
                          count: documentsWithTag(widget.snapshot, tag).length,
                          onTap: () => widget.onOpenTag(tag),
                          onLongPress: () => widget.onTagMenu(tag),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One cell of the "All tags" grid (two per row).
class _TagGridTile extends StatelessWidget {
  const _TagGridTile({
    required this.tag,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  final String tag;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.sell_outlined, size: 16, color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '#$tag',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  final String tag;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '#$tag',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: '  $count',
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }
}
