import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';
import 'album_dialog.dart';
import 'app_constants.dart';
import 'document_preview_card.dart';

/// Name, albums, tags and favorite for one or more documents. Shown right
/// after importing ("Document imported — where should it go?") and from a
/// document's menu ("Edit details"). With several documents the name field
/// is hidden and albums/tags are added to all of them.
Future<void> showDocumentDetailsSheet(
  BuildContext context,
  DocumentsService documentsService, {
  required List<DocumentFile> documents,
  bool afterImport = false,
}) async {
  if (documents.isEmpty) return;
  final snapshot = await documentsService.loadSnapshot();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _DocumentDetailsSheet(
      documentsService: documentsService,
      documents: documents,
      snapshot: snapshot,
      afterImport: afterImport,
    ),
  );
}

class _DocumentDetailsSheet extends StatefulWidget {
  const _DocumentDetailsSheet({
    required this.documentsService,
    required this.documents,
    required this.snapshot,
    required this.afterImport,
  });

  final DocumentsService documentsService;
  final List<DocumentFile> documents;
  final DocumentsSnapshot snapshot;
  final bool afterImport;

  @override
  State<_DocumentDetailsSheet> createState() => _DocumentDetailsSheetState();
}

class _DocumentDetailsSheetState extends State<_DocumentDetailsSheet> {
  late final bool _single = widget.documents.length == 1;
  late final TextEditingController _titleController = TextEditingController(
    text: _single ? widget.documents.first.title : '',
  );
  final TextEditingController _tagController = TextEditingController();
  late final Set<String> _albumIds = _single
      ? widget.documents.first.albumIds.toSet()
      : {};
  late final List<String> _tags = _single
      ? [...widget.documents.first.tags]
      : [];
  late bool _favorite = _single && widget.documents.first.isFavorite;
  late List<DocumentAlbum> _albums = widget.snapshot.albums;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-select the album the detected type points to ("looks like an
    // invoice" → Invoices), only as a suggestion the user can untick.
    if (widget.afterImport && _single && _albumIds.isEmpty) {
      final type = widget.documents.first.semanticType;
      if (type != null) {
        final album = albumForSemanticType(type, _albums);
        if (album != null) _albumIds.add(album.id);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.documents.first;
    final suggestedTags = widget.snapshot.tags
        .where((tag) => !_tags.contains(tag))
        .take(8)
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 52,
                  height: 66,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: DocumentThumbnail(document: first),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.afterImport
                            ? (_single
                                  ? AppConstants.detailsImportedOne.tr()
                                  : AppConstants.detailsImportedMany.tr(
                                      namedArgs: {
                                        'count': '${widget.documents.length}',
                                      },
                                    ))
                            : AppConstants.detailsTitle.tr(),
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _single
                            ? '${first.fileName} · ${first.sizeLabel}'
                            : AppConstants.detailsManyHint.tr(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_single &&
                first.semanticType != null &&
                first.semanticType != DocumentSemanticType.other) ...[
              const SizedBox(height: 14),
              _InfoLine(
                icon: Icons.auto_awesome_outlined,
                text: AppConstants.detailsDetectedType.tr(
                  namedArgs: {'type': semanticTypeLabel(first.semanticType!)},
                ),
              ),
            ],
            if (_single) ...[
              const SizedBox(height: 18),
              _Label(AppConstants.detailsName.tr()),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                textInputAction: TextInputAction.done,
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _Label(AppConstants.detailsAlbums.tr())),
                TextButton.icon(
                  onPressed: _createAlbum,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(AppConstants.docshelfNewAlbum.tr()),
                ),
              ],
            ),
            if (_albums.isEmpty)
              Text(
                AppConstants.detailsNoAlbums.tr(),
                style: const TextStyle(color: AppTheme.mutedText),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final album in _albums)
                    FilterChip(
                      avatar: Icon(
                        albumIconFor(album.iconName),
                        size: 16,
                        color: Color(album.colorValue),
                      ),
                      label: Text(album.name),
                      selected: _albumIds.contains(album.id),
                      onSelected: (selected) => setState(() {
                        selected
                            ? _albumIds.add(album.id)
                            : _albumIds.remove(album.id);
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 18),
            _Label(AppConstants.detailsTags.tr()),
            const SizedBox(height: 8),
            if (_tags.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in _tags)
                    InputChip(
                      label: Text(tag),
                      onDeleted: () => setState(() => _tags.remove(tag)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _tagController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: AppConstants.detailsAddTag.tr(),
                prefixIcon: const Icon(Icons.sell_outlined, size: 20),
              ),
              onSubmitted: (value) {
                _addTag(value);
              },
            ),
            if (suggestedTags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in suggestedTags)
                    ActionChip(
                      label: Text(tag),
                      avatar: const Icon(Icons.add_rounded, size: 16),
                      onPressed: () => _addTag(tag),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.star_outline_rounded),
              title: Text(AppConstants.commonFavorite.tr()),
              value: _favorite,
              onChanged: (value) => setState(() => _favorite = value),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(AppConstants.commonSave.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isEmpty) return;
    setState(() {
      if (!_tags.contains(tag)) _tags.add(tag);
      _tagController.clear();
    });
  }

  Future<void> _createAlbum() async {
    final draft = await showAlbumDialog(context);
    if (draft == null) return;
    final id = await widget.documentsService.createAlbum(
      null,
      draft.name,
      colorValue: draft.colorValue,
      iconName: draft.iconName,
    );
    final snapshot = await widget.documentsService.loadSnapshot();
    if (!mounted) return;
    setState(() {
      _albums = snapshot.albums;
      if (id != null) _albumIds.add(id);
    });
  }

  Future<void> _save() async {
    if (_tagController.text.trim().isNotEmpty) _addTag(_tagController.text);
    setState(() => _saving = true);
    for (final document in widget.documents) {
      await widget.documentsService.updateDocument(
        document.id,
        title: _single ? _titleController.text : null,
        tags: _single ? _tags : {...document.tags, ..._tags}.toList(),
        isFavorite: _single ? _favorite : (_favorite ? true : null),
        albumIds: _single
            ? _albumIds.toList()
            : {...document.albumIds, ..._albumIds}.toList(),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.mutedText,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceStrong,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

String semanticTypeLabel(DocumentSemanticType type) {
  return switch (type) {
    DocumentSemanticType.invoice => AppConstants.documentTypeInvoice.tr(),
    DocumentSemanticType.receipt => AppConstants.documentTypeReceipt.tr(),
    DocumentSemanticType.contract => AppConstants.documentTypeContract.tr(),
    DocumentSemanticType.identityDocument =>
      AppConstants.documentTypeIdentityDocument.tr(),
    DocumentSemanticType.medical => AppConstants.documentTypeMedical.tr(),
    DocumentSemanticType.insurance => AppConstants.documentTypeInsurance.tr(),
    DocumentSemanticType.warranty => AppConstants.documentTypeWarranty.tr(),
    DocumentSemanticType.other => AppConstants.documentTypeOther.tr(),
  };
}

/// Plural album name for a detected type ("Invoices" for an invoice), used
/// when suggesting a new album.
String semanticTypeAlbumName(DocumentSemanticType type) {
  return switch (type) {
    DocumentSemanticType.invoice => AppConstants.albumNameInvoice.tr(),
    DocumentSemanticType.receipt => AppConstants.albumNameReceipt.tr(),
    DocumentSemanticType.contract => AppConstants.albumNameContract.tr(),
    DocumentSemanticType.identityDocument =>
      AppConstants.albumNameIdentity.tr(),
    DocumentSemanticType.medical => AppConstants.albumNameMedical.tr(),
    DocumentSemanticType.insurance => AppConstants.albumNameInsurance.tr(),
    DocumentSemanticType.warranty => AppConstants.albumNameWarranty.tr(),
    DocumentSemanticType.other => AppConstants.albumNameOther.tr(),
  };
}
