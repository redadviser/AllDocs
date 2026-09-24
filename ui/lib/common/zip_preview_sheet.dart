import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/secure_zip_extractor.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';
import 'album_dialog.dart';
import 'app_constants.dart';
import 'app_sheet.dart';
import 'document_file_icon.dart';

class ZipSelection {
  const ZipSelection({required this.entries, this.albumId});
  final List<ExtractedZipEntry> entries;
  final String? albumId;
}

/// Shows what a .zip actually contains and lets the user pick which of the
/// supported documents to bring into AllDocs, and into which album — rather
/// than silently importing everything the moment a zip is picked. Returns
/// null if they backed out.
Future<ZipSelection?> showZipPreviewSheet(
  BuildContext context,
  List<ExtractedZipEntry> entries, {
  required String zipName,
  required DocumentsService documentsService,
  String? initialAlbumId,
}) async {
  final snapshot = await documentsService.loadSnapshot();
  if (!context.mounted) return null;
  return showAppSheet<ZipSelection>(
    context: context,
    builder: (context) => _ZipPreviewSheet(
      entries: entries,
      zipName: zipName,
      albums: snapshot.albums,
      documentsService: documentsService,
      initialAlbumId: initialAlbumId,
    ),
  );
}

class _ZipPreviewSheet extends StatefulWidget {
  const _ZipPreviewSheet({
    required this.entries,
    required this.zipName,
    required this.albums,
    required this.documentsService,
    this.initialAlbumId,
  });

  final List<ExtractedZipEntry> entries;
  final String zipName;
  final List<DocumentAlbum> albums;
  final DocumentsService documentsService;
  final String? initialAlbumId;

  @override
  State<_ZipPreviewSheet> createState() => _ZipPreviewSheetState();
}

class _ZipPreviewSheetState extends State<_ZipPreviewSheet> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.entries.length; i++) i,
  };
  late String? _albumId = widget.initialAlbumId;
  late List<DocumentAlbum> _albums = widget.albums;

  bool get _allSelected => _selected.length == widget.entries.length;

  int get _selectedBytes => [
    for (final index in _selected) widget.entries[index].bytes.length,
  ].fold(0, (sum, value) => sum + value);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          children: [
            Row(
              children: [
                const DocumentFileIcon(type: DocumentType.archive, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.zipName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        AppConstants.archiveZipPreviewTitle.tr(
                          namedArgs: {'count': '${widget.entries.length}'},
                        ),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppConstants.archiveZipPreviewSubtitle.tr(),
                    style: const TextStyle(
                      color: AppTheme.mutedText,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_allSelected) {
                        _selected.clear();
                      } else {
                        _selected.addAll(
                          List.generate(widget.entries.length, (i) => i),
                        );
                      }
                    });
                  },
                  child: Text(
                    _allSelected
                        ? AppConstants.archiveZipPreviewSelectNone.tr()
                        : AppConstants.archiveZipPreviewSelectAll.tr(),
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: widget.entries.length,
                itemBuilder: (context, index) {
                  final entry = widget.entries[index];
                  final type = documentTypeFromFileName(entry.fileName);
                  return CheckboxListTile(
                    value: _selected.contains(index),
                    onChanged: (value) {
                      setState(() {
                        value == true
                            ? _selected.add(index)
                            : _selected.remove(index);
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    secondary: DocumentFileIcon(type: type, size: 34),
                    title: Text(
                      entry.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      formatBytes(entry.bytes.length),
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: _albumId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: AppConstants.zipDestinationAlbum.tr(),
                prefixIcon: const Icon(Icons.folder_outlined, size: 20),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(AppConstants.zipNoAlbum.tr()),
                ),
                for (final album in _albums)
                  DropdownMenuItem<String?>(
                    value: album.id,
                    child: Text(album.name),
                  ),
                DropdownMenuItem<String?>(
                  value: _newAlbumValue,
                  child: Text('+ ${AppConstants.docshelfNewAlbum.tr()}'),
                ),
              ],
              onChanged: (value) async {
                if (value != _newAlbumValue) {
                  setState(() => _albumId = value);
                  return;
                }
                final draft = await showAlbumDialog(
                  context,
                  suggestedName: _suggestedAlbumName(),
                );
                if (draft == null || !mounted) {
                  setState(() {});
                  return;
                }
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
                  _albumId = id;
                });
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(
                        ZipSelection(
                          entries: [
                            for (var i = 0; i < widget.entries.length; i++)
                              if (_selected.contains(i)) widget.entries[i],
                          ],
                          albumId: _albumId,
                        ),
                      ),
                child: Text(
                  '${AppConstants.archiveZipPreviewImport.tr(namedArgs: {'count': '${_selected.length}'})}'
                  '  ·  ${formatBytes(_selectedBytes)}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _suggestedAlbumName() {
    final name = widget.zipName;
    final dot = name.toLowerCase().lastIndexOf('.zip');
    return (dot > 0 ? name.substring(0, dot) : name).replaceAll('_', ' ');
  }
}

const _newAlbumValue = '__new_album__';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
