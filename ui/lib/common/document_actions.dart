import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';
import 'album_dialog.dart';
import 'app_constants.dart';
import 'document_details_sheet.dart';
import 'document_file_icon.dart';
import 'document_preview_card.dart';

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Everything you can do with one document, in a bottom sheet.
Future<void> showDocumentActions(
  BuildContext context,
  DocumentsService documentsService,
  DocumentFile document, {
  String? albumContextId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      void run(Future<void> Function() action) {
        Navigator.of(sheetContext).pop();
        action();
      }

      final deleted = document.isDeleted;
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 56,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: DocumentThumbnail(document: document),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          document.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            documentTypeLabel(document.type),
                            document.sizeLabel,
                            document.dateLabel,
                          ].join(' · '),
                          style: const TextStyle(
                            color: AppTheme.mutedText,
                            fontSize: 12.5,
                          ),
                        ),
                        if (document.tags.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            document.tags.map((tag) => '#$tag').join('  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            if (deleted) ...[
              _Action(
                icon: Icons.restore_rounded,
                label: AppConstants.trashRestore.tr(),
                onTap: () => run(() async {
                  await documentsService.restoreFromTrash([document.id]);
                  if (context.mounted) {
                    showSnack(context, AppConstants.trashRestored.tr());
                  }
                }),
              ),
              _Action(
                icon: Icons.delete_forever_outlined,
                label: AppConstants.trashDeleteForever.tr(),
                destructive: true,
                onTap: () => run(
                  () => confirmDeleteForever(context, documentsService, [
                    document,
                  ]),
                ),
              ),
            ] else ...[
              _Action(
                icon: Icons.open_in_new_rounded,
                label: AppConstants.viewerOpenElsewhere.tr(),
                onTap: () => run(() => documentsService.openDocument(document)),
              ),
              _Action(
                icon: Icons.ios_share_rounded,
                label: AppConstants.actionsShare.tr(),
                onTap: () =>
                    run(() => documentsService.shareDocuments([document])),
              ),
              _Action(
                icon: Icons.edit_outlined,
                label: AppConstants.actionsEditDetails.tr(),
                onTap: () => run(
                  () => showDocumentDetailsSheet(
                    context,
                    documentsService,
                    documents: [document],
                  ),
                ),
              ),
              _Action(
                icon: Icons.create_new_folder_outlined,
                label: AppConstants.actionsAlbums.tr(),
                onTap: () => run(
                  () => showAlbumMembershipSheet(context, documentsService, [
                    document,
                  ]),
                ),
              ),
              if (albumContextId != null)
                _Action(
                  icon: Icons.folder_off_outlined,
                  label: AppConstants.actionsRemoveFromAlbum.tr(),
                  onTap: () => run(
                    () => documentsService.removeDocumentFromAlbum(
                      document.id,
                      albumContextId,
                    ),
                  ),
                ),
              _Action(
                icon: document.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                label: document.isFavorite
                    ? AppConstants.commonRemoveFavorite.tr()
                    : AppConstants.commonFavorite.tr(),
                onTap: () =>
                    run(() => documentsService.toggleFavorite(document.id)),
              ),
              _Action(
                icon: document.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                label: document.isArchived
                    ? AppConstants.actionsUnarchive.tr()
                    : AppConstants.archiveArchive.tr(),
                onTap: () => run(() async {
                  await documentsService.setArchived([
                    document.id,
                  ], !document.isArchived);
                  if (context.mounted) {
                    showSnack(
                      context,
                      document.isArchived
                          ? AppConstants.actionsUnarchived.tr()
                          : AppConstants.actionsArchived.tr(),
                    );
                  }
                }),
              ),
              _Action(
                icon: Icons.delete_outline_rounded,
                label: AppConstants.actionsMoveToTrash.tr(),
                destructive: true,
                onTap: () => run(
                  () => moveToTrashWithUndo(context, documentsService, [
                    document,
                  ]),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

Future<void> moveToTrashWithUndo(
  BuildContext context,
  DocumentsService documentsService,
  List<DocumentFile> documents,
) async {
  final ids = documents.map((document) => document.id).toList();
  await documentsService.moveToTrash(ids);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          AppConstants.actionsMovedToTrash.tr(
            namedArgs: {'count': '${ids.length}'},
          ),
        ),
        action: SnackBarAction(
          label: AppConstants.actionsUndo.tr(),
          onPressed: () => documentsService.restoreFromTrash(ids),
        ),
      ),
    );
}

Future<void> confirmDeleteForever(
  BuildContext context,
  DocumentsService documentsService,
  List<DocumentFile> documents,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: AppConstants.trashDeleteForeverTitle.tr(),
    message: AppConstants.trashDeleteForeverMessage.tr(
      namedArgs: {'count': '${documents.length}'},
    ),
    actionLabel: AppConstants.trashDeleteForever.tr(),
  );
  if (!confirmed) return;
  await documentsService.deletePermanently(
    documents.map((document) => document.id).toList(),
  );
}

/// Tick the albums a document belongs to. Several documents: ticking adds
/// all of them to that album (unticking removes them).
Future<void> showAlbumMembershipSheet(
  BuildContext context,
  DocumentsService documentsService,
  List<DocumentFile> documents,
) async {
  var snapshot = await documentsService.loadSnapshot();
  if (!context.mounted) return;
  final ids = documents.map((document) => document.id).toSet();

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final current = snapshot.documents
              .where((document) => ids.contains(document.id))
              .toList();
          bool inAlbum(String albumId) =>
              current.isNotEmpty &&
              current.every((document) => document.albumIds.contains(albumId));

          Future<void> refresh() async {
            snapshot = await documentsService.loadSnapshot();
            setSheetState(() {});
          }

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppConstants.actionsAlbums.tr(),
                          style: const TextStyle(
                            color: AppTheme.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final draft = await showAlbumDialog(context);
                          if (draft == null) return;
                          final albumId = await documentsService.createAlbum(
                            null,
                            draft.name,
                            colorValue: draft.colorValue,
                            iconName: draft.iconName,
                          );
                          if (albumId != null) {
                            await documentsService.addDocumentsToAlbum(
                              ids.toList(),
                              albumId,
                            );
                          }
                          await refresh();
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(AppConstants.docshelfNewAlbum.tr()),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    AppConstants.actionsAlbumsHint.tr(),
                    style: const TextStyle(
                      color: AppTheme.mutedText,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (snapshot.albums.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      AppConstants.detailsNoAlbums.tr(),
                      style: const TextStyle(color: AppTheme.mutedText),
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final album in snapshot.albums)
                          CheckboxListTile(
                            value: inAlbum(album.id),
                            secondary: Icon(
                              albumIconFor(album.iconName),
                              color: Color(album.colorValue),
                            ),
                            title: Text(album.name),
                            subtitle: Text(
                              AppConstants.docshelfDocumentCount.tr(
                                namedArgs: {
                                  'count':
                                      '${snapshot.documentsForAlbum(album.id).length}',
                                },
                              ),
                            ),
                            onChanged: (value) async {
                              if (value == true) {
                                await documentsService.addDocumentsToAlbum(
                                  ids.toList(),
                                  album.id,
                                );
                              } else {
                                for (final id in ids) {
                                  await documentsService
                                      .removeDocumentFromAlbum(id, album.id);
                                }
                              }
                              await refresh();
                            },
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      );
    },
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppTheme.destructive : AppTheme.text;
    return ListTile(
      leading: Icon(
        icon,
        color: destructive ? AppTheme.destructive : AppTheme.primarySoft,
      ),
      title: Text(label, style: TextStyle(color: color, fontSize: 15)),
      onTap: onTap,
    );
  }
}
