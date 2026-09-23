import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/secure_zip_extractor.dart';
import '../services/services.dart';
import '../theme/app_theme.dart';
import 'album_dialog.dart';
import 'app_constants.dart';
import 'document_actions.dart';
import 'document_details_sheet.dart';
import 'scan_filter_sheet.dart';
import 'zip_preview_sheet.dart';
import '../screens/viewer/document_viewer_screen.dart';

/// Picks files via the system file picker and imports them into AllDocs.
/// A .zip among the picked files is decompressed and previewed first (see
/// [showZipPreviewSheet]) instead of being imported whole — this is the one
/// shared entry point for that flow, used everywhere a file can be picked,
/// so the behavior (and the wording the user sees) stays the same.
Future<ImportResult> pickAndImportDocuments(
  BuildContext context,
  DocumentsService documentsService, {
  String? albumId,
  ImportPickKind kind = ImportPickKind.documents,
  bool allowMultiple = true,
  bool showDetails = true,
}) async {
  final files = await documentsService.pickFilesForImport(
    kind: kind,
    allowMultiple: allowMultiple,
  );
  if (files.isEmpty || !context.mounted) return ImportResult.empty;

  final zipFiles = <PlatformFile>[];
  final regularFiles = <PlatformFile>[];
  for (final file in files) {
    final isZip =
        file.name.toLowerCase().endsWith('.zip') && file.bytes != null;
    (isZip ? zipFiles : regularFiles).add(file);
  }

  var result = ImportResult.empty;
  if (regularFiles.isNotEmpty) {
    result += await documentsService.importPickedFiles(
      regularFiles,
      albumId: albumId,
    );
  }

  for (final zipFile in zipFiles) {
    if (!context.mounted) break;
    result += await _extractPreviewAndImport(
      context,
      documentsService,
      readBytes: () async => zipFile.bytes!,
      zipName: zipFile.name,
      albumId: albumId,
    );
  }

  if (context.mounted) {
    await reportImport(
      context,
      documentsService,
      result,
      showDetails: showDetails && albumId == null,
    );
  }
  return result;
}

/// Imports paths coming from outside (share / "open with"), routing .zip
/// files through the preview.
Future<ImportResult> importIncomingFiles(
  BuildContext context,
  DocumentsService documentsService,
  List<String> paths,
) async {
  var result = ImportResult.empty;
  final zips = paths.where((path) => path.toLowerCase().endsWith('.zip'));
  final others = paths.where((path) => !path.toLowerCase().endsWith('.zip'));
  if (others.isNotEmpty) {
    result += await documentsService.importFilePaths(others.toList());
  }
  for (final zip in zips) {
    if (!context.mounted) break;
    result += await extractPreviewAndImportZipFromPath(
      context,
      documentsService,
      path: zip,
    );
  }
  if (!context.mounted) return result;
  // Opened / shared from another app: straight into the gallery, with a
  // shortcut to open it, instead of asking for details first.
  if (result.count == 1 && result.skippedDuplicates == 0) {
    final document = result.documents.single;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppConstants.incomingAdded.tr(namedArgs: {'name': document.title}),
          ),
          action: SnackBarAction(
            label: AppConstants.incomingOpen.tr(),
            onPressed: () =>
                openDocumentViewer(context, documentsService, document),
          ),
        ),
      );
  } else {
    await reportImport(context, documentsService, result, showDetails: false);
  }
  return result;
}

/// Same flow as above, for a .zip already on disk — used when "search the
/// whole device" turns one up, or one is shared into the app.
Future<ImportResult> extractPreviewAndImportZipFromPath(
  BuildContext context,
  DocumentsService documentsService, {
  required String path,
  String? albumId,
}) {
  final name = path.replaceAll(r'\', '/').split('/').last;
  return _extractPreviewAndImport(
    context,
    documentsService,
    readBytes: () => File(path).readAsBytes(),
    zipName: name,
    albumId: albumId,
  );
}

Future<ImportResult> _extractPreviewAndImport(
  BuildContext context,
  DocumentsService documentsService, {
  required Future<Uint8List> Function() readBytes,
  required String zipName,
  String? albumId,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const ExtractingZipDialog(),
  );

  Uint8List bytes;
  try {
    bytes = await readBytes();
  } catch (_) {
    bytes = Uint8List(0);
  }
  const extractor = SecureZipExtractor();
  final inspection = await extractor.inspectInBackground(bytes);
  if (!context.mounted) return ImportResult.empty;

  if (inspection.exceedsLimits) {
    Navigator.of(context, rootNavigator: true).pop();
    final proceed = await showConfirmDialog(
      context,
      title: AppConstants.zipLargeTitle.tr(),
      message: AppConstants.zipLargeMessage.tr(
        namedArgs: {
          'size': formatBytes(inspection.declaredBytes),
          'limit': formatBytes(extractor.limits.maxTotalUncompressedBytes),
        },
      ),
      actionLabel: AppConstants.zipLargeContinue.tr(),
      destructive: false,
    );
    if (!proceed || !context.mounted) return ImportResult.empty;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ExtractingZipDialog(),
    );
  }

  List<ExtractedZipEntry> entries;
  try {
    entries = await documentsService.extractZipPreview(bytes);
  } catch (_) {
    entries = const [];
  }

  if (!context.mounted) return ImportResult.empty;
  Navigator.of(context, rootNavigator: true).pop();

  if (inspection.nestedZipCount > 0) {
    showSnack(
      context,
      AppConstants.zipNestedSkipped.tr(
        namedArgs: {'count': '${inspection.nestedZipCount}'},
      ),
    );
  }

  if (entries.isEmpty) {
    showSnack(context, AppConstants.archiveZipEmpty.tr());
    return ImportResult.empty;
  }

  final selection = await showZipPreviewSheet(
    context,
    entries,
    zipName: zipName,
    documentsService: documentsService,
    initialAlbumId: albumId,
  );
  if (selection == null || selection.entries.isEmpty || !context.mounted) {
    return ImportResult.empty;
  }

  return documentsService.importExtractedZipEntries(
    selection.entries,
    albumId: selection.albumId,
  );
}

Future<ImportResult> scanAndImport(
  BuildContext context,
  DocumentsService documentsService, {
  String? albumId,
}) async {
  try {
    final result = await documentsService.scanDocumentWithCamera(
      albumId: albumId,
      chooseFilter: (pages) => showScanFilterSheet(context, pages),
    );
    if (context.mounted) {
      await reportImport(
        context,
        documentsService,
        result,
        showDetails: albumId == null,
      );
    }
    return result;
  } catch (_) {
    if (context.mounted) {
      showSnack(context, AppConstants.archiveScanFailed.tr());
    }
    return ImportResult.empty;
  }
}

/// Tells the user what happened, then offers the name/album/tags sheet for
/// what was just added.
Future<void> reportImport(
  BuildContext context,
  DocumentsService documentsService,
  ImportResult result, {
  bool showDetails = true,
}) async {
  if (result.isEmpty && result.skippedDuplicates == 0) return;
  if (result.skippedDuplicates > 0) {
    showSnack(
      context,
      result.isEmpty
          ? AppConstants.importAllDuplicates.tr()
          : AppConstants.importSomeDuplicates.tr(
              namedArgs: {
                'count': '${result.count}',
                'skipped': '${result.skippedDuplicates}',
              },
            ),
    );
  } else if (!showDetails) {
    showSnack(
      context,
      AppConstants.archiveImportedCount.tr(
        namedArgs: {'count': '${result.count}'},
      ),
    );
  }
  if (showDetails && !result.isEmpty && context.mounted) {
    await showDocumentDetailsSheet(
      context,
      documentsService,
      documents: result.documents,
      afterImport: true,
    );
  }
}

class ExtractingZipDialog extends StatelessWidget {
  const ExtractingZipDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
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
                    fontWeight: FontWeight.w600,
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
