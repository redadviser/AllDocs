import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A single OCR-recognized text line, positioned relative to its page image.
class OcrTextLine {
  const OcrTextLine({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;
}

/// One scanned page: the page image plus the OCR text recognized on it.
class ScannedPage {
  const ScannedPage({
    required this.imagePath,
    required this.text,
    required this.lines,
  });

  final String imagePath;
  final String text;
  final List<OcrTextLine> lines;
}

/// Builds a PDF with each page image and an invisible OCR text layer drawn on
/// top of it, so the resulting file is searchable/selectable while still
/// looking exactly like the original scan. Pulled out of
/// [DocumentScannerService] so this pure, platform-channel-free logic can be
/// unit tested without the ML Kit/camera plugins.
Future<void> buildSearchablePdf({
  required String outputPath,
  required List<ScannedPage> pages,
}) async {
  final pdf = pw.Document();

  for (final page in pages) {
    final bytes = await File(page.imagePath).readAsBytes();
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
                pw.Positioned.fill(
                  child: pw.Image(image, fit: pw.BoxFit.fill),
                ),
                for (final line in page.lines)
                  ocrTextLayer(line, pageWidth, pageHeight),
              ],
            ),
          );
        },
      ),
    );
  }

  await File(outputPath).writeAsBytes(await pdf.save(), flush: true);
}

pw.Widget ocrTextLayer(OcrTextLine line, double pageWidth, double pageHeight) {
  final left = line.left.clamp(0.0, pageWidth);
  final top = line.top.clamp(0.0, pageHeight);
  // The available space can be smaller than 1.0 near the page edge (or on a
  // tiny page), which would otherwise invert the clamp bounds and throw.
  final width = line.width.clamp(1.0, (pageWidth - left).clamp(1.0, pageWidth));
  final height = line.height.clamp(
    1.0,
    (pageHeight - top).clamp(1.0, pageHeight),
  );

  return pw.Positioned(
    left: left,
    top: top,
    child: pw.Opacity(
      opacity: 0.01,
      child: pw.SizedBox(
        width: width,
        height: height,
        child: pw.Text(
          line.text,
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
