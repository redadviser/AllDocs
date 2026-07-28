import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'searchable_pdf_builder.dart';

class ScannedDocumentResult {
  const ScannedDocumentResult({
    required this.filePath,
    required this.fileName,
    required this.pageCount,
    required this.searchable,
    required this.ocrText,
    required this.cleanupPaths,
  });

  final String filePath;
  final String fileName;
  final int pageCount;
  final bool searchable;
  final String? ocrText;
  final List<String> cleanupPaths;

  Future<void> cleanup() async {
    for (final path in cleanupPaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Temporary scanner files are best-effort cleanup.
      }
    }
  }
}

class DocumentScannerService {
  const DocumentScannerService();

  Future<ScannedDocumentResult?> scanDocument() async {
    if (Platform.isAndroid) {
      return _scanWithMlKitDocumentScanner();
    }

    return _scanWithFallbackCamera();
  }

  Future<ScannedDocumentResult?> _scanWithMlKitDocumentScanner() async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg, DocumentFormat.pdf},
        mode: ScannerMode.full,
        pageLimit: 20,
        isGalleryImport: true,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      final imagePaths = _existingPaths(result.images ?? const []);
      final pdfPath = _existingPath(result.pdf?.uri);

      if (imagePaths.isNotEmpty) {
        return _buildSearchableScanResult(
          imagePaths: imagePaths,
          fallbackPdfPath: pdfPath,
        );
      }

      if (pdfPath == null) return null;
      return ScannedDocumentResult(
        filePath: pdfPath,
        fileName: _scanFileName(),
        pageCount: result.pdf?.pageCount ?? 1,
        searchable: false,
        ocrText: null,
        cleanupPaths: [pdfPath],
      );
    } on PlatformException catch (error) {
      if (_isCancellation(error)) return null;
      rethrow;
    } finally {
      await scanner.close();
    }
  }

  // Known gap: unlike the Android path above, this has no edge detection,
  // auto-crop, or multi-page capture. Accepted for now; see "iOS scanning
  // parity" in docs/architecture.md for the plan to close it.
  Future<ScannedDocumentResult?> _scanWithFallbackCamera() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 96,
    );
    if (picked == null) return null;

    return _buildSearchableScanResult(imagePaths: [picked.path]);
  }

  Future<ScannedDocumentResult> _buildSearchableScanResult({
    required List<String> imagePaths,
    String? fallbackPdfPath,
  }) async {
    final pages = await _recognizePages(imagePaths);
    final text = pages
        .map((page) => page.text)
        .where((value) => value.trim().isNotEmpty)
        .join('\n\n')
        .trim();
    final outputFile = await _temporaryPdfFile();

    try {
      await Isolate.run(() async {
        await buildSearchablePdf(outputPath: outputFile.path, pages: pages);
      });

      return ScannedDocumentResult(
        filePath: outputFile.path,
        fileName: _scanFileName(),
        pageCount: pages.length,
        searchable: text.isNotEmpty,
        ocrText: text.isEmpty ? null : text,
        cleanupPaths: [
          outputFile.path,
          ?fallbackPdfPath,
          ...imagePaths,
        ],
      );
    } catch (_) {
      if (fallbackPdfPath != null) {
        return ScannedDocumentResult(
          filePath: fallbackPdfPath,
          fileName: _scanFileName(),
          pageCount: imagePaths.length,
          searchable: false,
          ocrText: text.isEmpty ? null : text,
          cleanupPaths: [fallbackPdfPath, ...imagePaths],
        );
      }
      rethrow;
    }
  }

  Future<List<ScannedPage>> _recognizePages(List<String> imagePaths) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final pages = <ScannedPage>[];
      for (final imagePath in imagePaths) {
        final recognized = await recognizer.processImage(
          InputImage.fromFilePath(imagePath),
        );
        final lines = <OcrTextLine>[];
        for (final block in recognized.blocks) {
          for (final line in block.lines) {
            final text = line.text.trim().replaceAll(RegExp(r'\s+'), ' ');
            final box = line.boundingBox;
            if (text.isEmpty || box.width <= 1 || box.height <= 1) continue;
            lines.add(
              OcrTextLine(
                text: text,
                left: box.left,
                top: box.top,
                width: box.width,
                height: box.height,
              ),
            );
          }
        }

        pages.add(
          ScannedPage(
            imagePath: imagePath,
            text: recognized.text.trim(),
            lines: lines,
          ),
        );
      }
      return pages;
    } finally {
      await recognizer.close();
    }
  }

  Future<File> _temporaryPdfFile() async {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/alldocs_scans');
    await dir.create(recursive: true);
    return File('${dir.path}/${_scanFileName()}');
  }

  String _scanFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'scan_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.pdf';
  }

  String? _existingPath(String? rawPath) {
    if (rawPath == null || rawPath.trim().isEmpty) return null;
    final path = rawPath.trim().replaceFirst('file://', '');
    if (File(path).existsSync()) return path;
    return null;
  }

  List<String> _existingPaths(List<String> paths) {
    return [
      for (final path in paths)
        if (_existingPath(path) != null) _existingPath(path)!,
    ];
  }

  bool _isCancellation(PlatformException error) {
    final message = '${error.code} ${error.message ?? ''}'.toLowerCase();
    return message.contains('cancel');
  }
}
