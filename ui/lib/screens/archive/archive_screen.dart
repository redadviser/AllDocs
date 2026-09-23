import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/album_dialog.dart';
import '../../common/app_constants.dart';
import '../../common/document_actions.dart';
import '../../common/document_preview_card.dart';
import '../../common/snapshot_builder.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import '../viewer/document_viewer_screen.dart';

/// Archived documents (hidden from the gallery, archiving is instant and
/// reversible) and the recycle bin (files are only removed from disk on
/// "Delete permanently" or after [LocalDocumentsStore.trashRetention]).
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({
    super.key,
    required this.documentsService,
    this.showBackButton = false,
  });

  final DocumentsService documentsService;

  /// True when opened as its own page (from the gallery header).
  final bool showBackButton;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  bool _showTrash = false;

  DocumentsService get _service => widget.documentsService;

  @override
  Widget build(BuildContext context) {
    return SnapshotBuilder(
      documentsService: _service,
      builder: (context, snapshot) {
        final documents = _showTrash
            ? snapshot.trashDocuments
            : snapshot.archivedDocuments;

        return CustomScrollView(
          key: const PageStorageKey('archive'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    if (widget.showBackButton)
                      Transform.translate(
                        offset: const Offset(-12, 0),
                        child: const BackButton(),
                      ),
                    Text(
                      AppConstants.archiveTitle.tr(),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              sliver: SliverToBoxAdapter(
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.archive_outlined, size: 18),
                      label: Text(
                        '${AppConstants.archiveArchived.tr()} '
                        '(${snapshot.archivedDocuments.length})',
                      ),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text(
                        '${AppConstants.trashTitle.tr()} '
                        '(${snapshot.trashDocuments.length})',
                      ),
                    ),
                  ],
                  selected: {_showTrash},
                  onSelectionChanged: (value) =>
                      setState(() => _showTrash = value.first),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _showTrash
                            ? AppConstants.trashHint.tr(
                                namedArgs: {
                                  'days':
                                      '${LocalDocumentsStore.trashRetention.inDays}',
                                },
                              )
                            : AppConstants.archiveArchivedHint.tr(),
                        style: const TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                    if (_showTrash && documents.isNotEmpty)
                      TextButton(
                        onPressed: () => _emptyTrash(documents.length),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.destructive,
                        ),
                        child: Text(AppConstants.trashEmpty.tr()),
                      ),
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
                        Icon(
                          _showTrash
                              ? Icons.delete_outline_rounded
                              : Icons.archive_outlined,
                          size: 42,
                          color: AppTheme.dimText,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _showTrash
                              ? AppConstants.trashEmptyState.tr()
                              : AppConstants.archiveEmptyState.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.mutedText),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final columns = (constraints.crossAxisExtent / 170)
                        .floor()
                        .clamp(2, 6);
                    return SliverGrid.builder(
                      itemCount: documents.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.62,
                      ),
                      itemBuilder: (context, index) {
                        final document = documents[index];
                        return _showTrash
                            ? _TrashCard(
                                document: document,
                                documentsService: _service,
                              )
                            : DocumentPreviewCard(
                                document: document,
                                onTap: () => openDocumentViewer(
                                  context,
                                  _service,
                                  document,
                                ),
                                onLongPress: () => showDocumentActions(
                                  context,
                                  _service,
                                  document,
                                ),
                                trailing: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    iconSize: 20,
                                    tooltip: AppConstants.actionsUnarchive.tr(),
                                    icon: const Icon(
                                      Icons.unarchive_outlined,
                                      color: AppTheme.mutedText,
                                    ),
                                    onPressed: () async {
                                      await _service.setArchived([
                                        document.id,
                                      ], false);
                                      if (context.mounted) {
                                        showSnack(
                                          context,
                                          AppConstants.actionsUnarchived.tr(),
                                        );
                                      }
                                    },
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
    );
  }

  Future<void> _emptyTrash(int count) async {
    final confirmed = await showConfirmDialog(
      context,
      title: AppConstants.trashEmptyTitle.tr(),
      message: AppConstants.trashDeleteForeverMessage.tr(
        namedArgs: {'count': '$count'},
      ),
      actionLabel: AppConstants.trashEmpty.tr(),
    );
    if (confirmed) await _service.emptyTrash();
  }
}

class _TrashCard extends StatelessWidget {
  const _TrashCard({required this.document, required this.documentsService});

  final DocumentFile document;
  final DocumentsService documentsService;

  @override
  Widget build(BuildContext context) {
    final deletedAt = document.deletedAt!;
    final left =
        LocalDocumentsStore.trashRetention.inDays -
        DateTime.now().difference(deletedAt).inDays;
    return DocumentPreviewCard(
      document: document,
      subtitle: AppConstants.trashDaysLeft.tr(
        namedArgs: {'days': '${left.clamp(0, 999)}'},
      ),
      onTap: () => showDocumentActions(context, documentsService, document),
      trailing: SizedBox(
        width: 28,
        height: 28,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 20,
          tooltip: AppConstants.trashRestore.tr(),
          icon: const Icon(Icons.restore_rounded, color: AppTheme.mutedText),
          onPressed: () async {
            await documentsService.restoreFromTrash([document.id]);
            if (context.mounted) {
              showSnack(context, AppConstants.trashRestored.tr());
            }
          },
        ),
      ),
    );
  }
}
