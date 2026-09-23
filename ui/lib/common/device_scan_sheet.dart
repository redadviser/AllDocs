import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'document_file_icon.dart';
import 'document_import_flow.dart';

/// Files found on the device (a folder, the whole device, or a text
/// search): pick some or all and add them to the gallery. Files are copied
/// into AllDocs; the originals stay where they are.
Future<void> showDeviceScanSheet(
  BuildContext context,
  DocumentsService documentsService,
  DeviceFolderScan scan, {
  String? albumId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _DeviceScanSheet(
      scan: scan,
      documentsService: documentsService,
      albumId: albumId,
    ),
  );
}

class _DeviceScanSheet extends StatefulWidget {
  const _DeviceScanSheet({
    required this.scan,
    required this.documentsService,
    this.albumId,
  });

  final DeviceFolderScan scan;
  final DocumentsService documentsService;
  final String? albumId;

  @override
  State<_DeviceScanSheet> createState() => _DeviceScanSheetState();
}

class _DeviceScanSheetState extends State<_DeviceScanSheet> {
  final Set<String> _selected = {};
  final Set<String> _imported = {};
  DocumentType? _type;
  bool _importing = false;

  List<DocumentFile> get _visible => [
    for (final document in widget.scan.documents)
      if (_type == null || document.type == _type) document,
  ];

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final types = {
      for (final document in widget.scan.documents) document.type,
    }.toList()..sort((a, b) => a.index.compareTo(b.index));
    final selectable = visible.where((d) => !_imported.contains(d.id));
    final allSelected =
        selectable.isNotEmpty &&
        selectable.every((d) => _selected.contains(d.id));

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.86,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.scan.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        AppConstants.deviceFound.tr(
                          namedArgs: {
                            'count': '${widget.scan.documents.length}',
                          },
                        ),
                        style: const TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (visible.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      if (allSelected) {
                        _selected.removeAll(visible.map((d) => d.id));
                      } else {
                        _selected.addAll(selectable.map((d) => d.id));
                      }
                    }),
                    child: Text(
                      allSelected
                          ? AppConstants.archiveZipPreviewSelectNone.tr()
                          : AppConstants.archiveZipPreviewSelectAll.tr(),
                    ),
                  ),
              ],
            ),
          ),
          if (types.length > 1)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(AppConstants.archiveAll.tr()),
                      selected: _type == null,
                      onSelected: (_) => setState(() => _type = null),
                    ),
                  ),
                  for (final type in types)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          '${documentTypeLabel(type)}  '
                          '${widget.scan.documents.where((d) => d.type == type).length}',
                        ),
                        selected: _type == type,
                        onSelected: (_) => setState(() => _type = type),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        AppConstants.archiveNoSupportedDocuments.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.mutedText),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final document = visible[index];
                      final imported = _imported.contains(document.id);
                      final snippet = document.ocrText;
                      return ListTile(
                        onTap: imported
                            ? null
                            : () => setState(() {
                                _selected.contains(document.id)
                                    ? _selected.remove(document.id)
                                    : _selected.add(document.id);
                              }),
                        leading: DocumentFileIcon(
                          type: document.type,
                          size: 40,
                        ),
                        title: Text(
                          document.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          snippet != null && snippet.isNotEmpty
                              ? '“$snippet”'
                              : '${_folderOf(document)} · ${document.dateLabel} · ${document.sizeLabel}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.mutedText,
                            fontSize: 12,
                          ),
                        ),
                        trailing: imported
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: AppTheme.success,
                              )
                            : Checkbox(
                                value: _selected.contains(document.id),
                                onChanged: (value) => setState(() {
                                  value == true
                                      ? _selected.add(document.id)
                                      : _selected.remove(document.id);
                                }),
                              ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _selected.isEmpty || _importing ? null : _import,
                icon: _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
                label: Text(
                  AppConstants.deviceAddSelected.tr(
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

  String _folderOf(DocumentFile document) {
    final path = (document.localPath ?? '').replaceAll(r'\', '/');
    final parts = path.split('/')..removeWhere((part) => part.isEmpty);
    return parts.length >= 2 ? parts[parts.length - 2] : '';
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    final chosen = widget.scan.documents
        .where((document) => _selected.contains(document.id))
        .toList();
    final zips = chosen.where((d) => d.type == DocumentType.archive).toList();
    final files = chosen.where((d) => d.type != DocumentType.archive).toList();

    var result = await widget.documentsService.importScannedDocuments(
      files,
      albumId: widget.albumId,
    );
    for (final zip in zips) {
      final path = zip.localPath;
      if (path == null || !mounted) continue;
      result += await extractPreviewAndImportZipFromPath(
        context,
        widget.documentsService,
        path: path,
        albumId: widget.albumId,
      );
    }
    if (!mounted) return;
    setState(() {
      _importing = false;
      _imported.addAll(_selected);
      _selected.clear();
    });
    await reportImport(
      context,
      widget.documentsService,
      result,
      showDetails: false,
    );
  }
}
