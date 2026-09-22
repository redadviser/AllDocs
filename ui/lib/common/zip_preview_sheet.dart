import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/secure_zip_extractor.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'document_file_icon.dart';

/// Shows what a .zip actually contains and lets the user pick which of the
/// supported documents to bring into AllDocs — rather than silently
/// importing everything the moment a zip is picked. Returns the entries the
/// user chose (only when they tapped "Import"), or null if they backed out.
Future<List<ExtractedZipEntry>?> showZipPreviewSheet(
  BuildContext context,
  List<ExtractedZipEntry> entries,
) {
  return showModalBottomSheet<List<ExtractedZipEntry>>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ZipPreviewSheet(entries: entries),
  );
}

class _ZipPreviewSheet extends StatefulWidget {
  const _ZipPreviewSheet({required this.entries});

  final List<ExtractedZipEntry> entries;

  @override
  State<_ZipPreviewSheet> createState() => _ZipPreviewSheetState();
}

class _ZipPreviewSheetState extends State<_ZipPreviewSheet> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.entries.length; i++) i,
  };

  bool get _allSelected => _selected.length == widget.entries.length;

  @override
  Widget build(BuildContext context) {
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
                      AppConstants.archiveZipPreviewTitle.tr(
                        namedArgs: {'count': '${widget.entries.length}'},
                      ),
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
              const SizedBox(height: 4),
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
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  itemCount: widget.entries.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = widget.entries[index];
                    final type = documentTypeFromFileName(entry.fileName);
                    final selected = _selected.contains(index);

                    return CheckboxListTile(
                      value: selected,
                      onChanged: (value) {
                        setState(() {
                          if (value ?? false) {
                            _selected.add(index);
                          } else {
                            _selected.remove(index);
                          }
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      secondary: DocumentFileIcon(type: type, size: 36),
                      title: Text(
                        entry.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        _formatBytes(entry.bytes.length),
                        style: const TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 11,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop([
                          for (var i = 0; i < widget.entries.length; i++)
                            if (_selected.contains(i)) widget.entries[i],
                        ]),
                  child: Text(
                    AppConstants.archiveZipPreviewImport.tr(
                      namedArgs: {'count': '${_selected.length}'},
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
