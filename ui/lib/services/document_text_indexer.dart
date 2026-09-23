import 'dart:io';
import 'dart:isolate';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../models/models.dart';
import 'document_text_extractor.dart';

/// Builds the searchable text for an imported document: direct extraction
/// for text/Office formats, on-device OCR (ML Kit) for images and the first
/// pages of PDFs. OCR only exists on Android/iOS; elsewhere those formats
/// simply stay unindexed.
class DocumentTextIndexer {
  const DocumentTextIndexer();

  static const _maxPdfPages = 4;

  static bool get ocrAvailable => Platform.isAndroid || Platform.isIOS;

  /// Cheap, synchronous-format extraction (no OCR). Runs off the UI thread.
  Future<String?> extractPlainText(String path) {
    if (!DocumentTextExtractor.canExtract(path)) return Future.value(null);
    return Isolate.run(
      () => const DocumentTextExtractor().extractFromPath(path),
    );
  }

  bool needsOcr(DocumentType type) {
    return ocrAvailable &&
        (type == DocumentType.pdf || type == DocumentType.image);
  }

  Future<String?> recognizeText(String path, DocumentType type) async {
    if (!needsOcr(type)) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      if (type == DocumentType.image) {
        final result = await recognizer.processImage(
          InputImage.fromFilePath(path),
        );
        return _clean(result.text);
      }
      return await _recognizePdf(path, recognizer);
    } catch (_) {
      return null;
    } finally {
      await recognizer.close();
    }
  }

  Future<String?> _recognizePdf(String path, TextRecognizer recognizer) async {
    final document = await PdfDocument.openFile(path);
    final temp = await getTemporaryDirectory();
    final buffer = StringBuffer();
    try {
      final pages = document.pagesCount.clamp(0, _maxPdfPages);
      for (var index = 1; index <= pages; index++) {
        final page = await document.getPage(index);
        try {
          // ~1600px on the long side is plenty for ML Kit on A4 text.
          final scale =
              1600 / (page.width > page.height ? page.width : page.height);
          final image = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
            quality: 90,
          );
          if (image == null) continue;
          final file = File(
            '${temp.path}/alldocs_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
          );
          await file.writeAsBytes(image.bytes);
          try {
            final result = await recognizer.processImage(
              InputImage.fromFilePath(file.path),
            );
            if (result.text.trim().isNotEmpty) {
              buffer.writeln(result.text.trim());
              buffer.writeln();
            }
          } finally {
            if (await file.exists()) await file.delete();
          }
        } finally {
          await page.close();
        }
      }
    } finally {
      await document.close();
    }
    return _clean(buffer.toString());
  }

  String? _clean(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length > DocumentTextExtractor.maxChars
        ? trimmed.substring(0, DocumentTextExtractor.maxChars)
        : trimmed;
  }
}
