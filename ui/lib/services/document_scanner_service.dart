import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
        .map((page) => page['text']?.toString() ?? '')
        .where((value) => value.trim().isNotEmpty)
        .join('\n\n')
        .trim();
    final outputFile = await _temporaryPdfFile();

    try {
      await Isolate.run(() async {
        await _writeSearchablePdf(outputPath: outputFile.path, pages: pages);
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

  Future<List<Map<String, Object?>>> _recognizePages(
    List<String> imagePaths,
  ) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final pages = <Map<String, Object?>>[];
      for (final imagePath in imagePaths) {
        final recognized = await recognizer.processImage(
          InputImage.fromFilePath(imagePath),
        );
        final lines = <Map<String, Object?>>[];
        for (final block in recognized.blocks) {
          for (final line in block.lines) {
            final text = line.text.trim().replaceAll(RegExp(r'\s+'), ' ');
            final box = line.boundingBox;
            if (text.isEmpty || box.width <= 1 || box.height <= 1) continue;
            lines.add({
              'text': text,
              'left': box.left,
              'top': box.top,
              'width': box.width,
              'height': box.height,
            });
          }
        }

        pages.add({
          'imagePath': imagePath,
          'text': recognized.text.trim(),
          'lines': lines,
        });
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

Future<void> _writeSearchablePdf({
  required String outputPath,
  required List<Map<String, Object?>> pages,
}) async {
  final pdf = pw.Document();

  for (final page in pages) {
    final imagePath = page['imagePath']?.toString();
    if (imagePath == null || imagePath.isEmpty) continue;
    final bytes = await File(imagePath).readAsBytes();
    final image = pw.MemoryImage(bytes);
    final pageWidth = (image.width ?? 1240).toDouble();
    final pageHeight = (image.height ?? 1754).toDouble();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, pageHeight, marginAll: 0),
        build: (_) {
          return pw.FullPage(
            ignoreMargins: true,
            child: pw.Stack(
              children: [
                pw.Positioned.fill(child: pw.Image(image, fit: pw.BoxFit.fill)),
                for (final line in (page['lines'] as List<dynamic>? ?? []))
                  _ocrTextLayer(line, pageWidth, pageHeight),
              ],
            ),
          );
        },
      ),
    );
  }

  await File(outputPath).writeAsBytes(await pdf.save(), flush: true);
}

pw.Widget _ocrTextLayer(dynamic rawLine, double pageWidth, double pageHeight) {
  final line = rawLine is Map ? rawLine : const <String, Object?>{};
  final text = line['text']?.toString() ?? '';
  final left = _doubleValue(line['left']).clamp(0.0, pageWidth);
  final top = _doubleValue(line['top']).clamp(0.0, pageHeight);
  final width = _doubleValue(line['width']).clamp(1.0, pageWidth - left);
  final height = _doubleValue(line['height']).clamp(1.0, pageHeight - top);

  return pw.Positioned(
    left: left,
    top: top,
    child: pw.Opacity(
      opacity: 0.01,
      child: pw.SizedBox(
        width: width,
        height: height,
        child: pw.Text(
          text,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
          softWrap: false,
          style: pw.TextStyle(
            color: PdfColors.black,
            fontSize: (height * 0.78).clamp(4.0, 42.0),
          ),
        ),
      ),
    ),
  );
}

double _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
