import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/secure_zip_extractor.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'zip_preview_sheet.dart';

/// Picks files via the system file picker and imports them into AllDocs.
/// A .zip among the picked files is decompressed and previewed first (see
/// [showZipPreviewSheet]) instead of being imported whole — this is the one
/// shared entry point for that flow, used by both the Archive tab's "Add"
/// button and an album's own "Import" action, so the behavior (and the
/// wording the user sees) stays the same everywhere a zip can be picked.
Future<int> pickAndImportDocuments(
  BuildContext context,
  DocumentsService documentsService, {
  String? albumId,
}) async {
  final files = await documentsService.pickFilesForImport();
  if (files.isEmpty) return 0;

  final zipFiles = <PlatformFile>[];
  final regularFiles = <PlatformFile>[];
  for (final file in files) {
    final isZip = file.name.toLowerCase().endsWith('.zip') && file.bytes != null;
    (isZip ? zipFiles : regularFiles).add(file);
  }

  var imported = 0;
  if (regularFiles.isNotEmpty) {
    imported += await documentsService.importPickedFiles(
      regularFiles,
      albumId: albumId,
    );
  }

  for (final zipFile in zipFiles) {
    if (!context.mounted) break;
    imported += await _extractPreviewAndImport(
      context,
      documentsService,
      extract: () => documentsService.extractZipPreview(zipFile.bytes!),
      albumId: albumId,
    );
  }

  return imported;
}

/// Same flow as above, for a .zip already found on disk — used when
/// "search the whole device" turns one up, instead of picking a file.
Future<int> extractPreviewAndImportZipFromPath(
  BuildContext context,
  DocumentsService documentsService, {
  required String path,
  String? albumId,
}) {
  return _extractPreviewAndImport(
    context,
    documentsService,
    extract: () => documentsService.extractZipPreviewFromPath(path),
    albumId: albumId,
  );
}

Future<int> _extractPreviewAndImport(
  BuildContext context,
  DocumentsService documentsService, {
  required Future<List<ExtractedZipEntry>> Function() extract,
  String? albumId,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const ExtractingZipDialog(),
  );

  final entries = await extract();

  if (!context.mounted) return 0;
  Navigator.of(context, rootNavigator: true).pop();

  if (entries.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppConstants.archiveZipEmpty.tr())));
    return 0;
  }

  final selected = await showZipPreviewSheet(context, entries);
  if (selected == null || selected.isEmpty || !context.mounted) return 0;

  return documentsService.importExtractedZipEntries(
    selected,
    albumId: albumId,
  );
}

class ExtractingZipDialog extends StatelessWidget {
  const ExtractingZipDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  AppConstants.archiveExtractingZip.tr(),
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
