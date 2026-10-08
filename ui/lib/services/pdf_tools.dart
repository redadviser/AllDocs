import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

/// Where a signature goes on its page.
enum SignatureCorner { bottomLeft, bottomCenter, bottomRight }

/// PDF editing for the Folio and Vault plans: merge, extract pages,
/// compress, sign and watermark. Everything runs off the main thread in
/// pdf_manipulator's engine; results come back as the new file's bytes.
class PdfTools {
  PdfTools._();

  static Pdf? _engine;
  static Pdf get _pdf => _engine ??= Pdf();

  static Future<int> pageCount(String path) async {
    final doc = await _pdf.open(FileSource(File(path)));
    try {
      return doc.pageCount;
    } finally {
      await doc.dispose();
    }
  }

  /// [paths] in order, one after the other.
  static Future<Uint8List> merge(List<String> paths) async {
    final output = MemorySink();
    await _pdf.merge([
      for (final path in paths) FileSource(File(path)),
    ], output);
    return output.takeBytes();
  }

  /// Pages [from] to [to], both counted from 1 and included.
  static Future<Uint8List> extractPages(String path, int from, int to) async {
    final output = MemorySink();
    await _pdf.extractPages(
      FileSource(File(path)),
      output,
      pages: [for (var page = from; page <= to; page++) page - 1],
    );
    return output.takeBytes();
  }

  /// Downsamples the images (where scans keep most of their weight) and
  /// rewrites the file compactly. Text and vector content are untouched.
  static Future<Uint8List> compress(String path) async {
    final output = MemorySink();
    await _pdf.compress(FileSource(File(path)), output);
    return output.takeBytes();
  }

  /// [overlay] (a transparent PNG drawn for a page of the given size)
  /// stamped over every page — see renderWatermarkOverlay. Stamped as an
  /// image, the mark can't simply be deleted as text could.
  static Future<Uint8List> watermark(
    String path, {
    required Future<Uint8List> Function(double width, double height) overlay,
  }) async {
    final editor = await _pdf.edit(FileSource(File(path)));
    try {
      final pages = await editor.pageCount;
      // Documents usually have one page size; draw each size once.
      final overlays = <String, Uint8List>{};
      for (var page = 0; page < pages; page++) {
        final box = await editor.pageMediaBox(page);
        final key = '${box.width.round()}x${box.height.round()}';
        final png = overlays[key] ??= await overlay(box.width, box.height);
        await editor.addImageStamp(
          page,
          MemorySource(png),
          rect: PdfRect(
            x: box.x,
            y: box.y,
            width: box.width,
            height: box.height,
          ),
        );
      }
      final output = MemorySink();
      await editor.save(output);
      return output.takeBytes();
    } finally {
      await editor.dispose();
    }
  }

  /// Turns an image (a photographed document) into a one-page PDF, so it
  /// can be watermarked like any other.
  static Future<Uint8List> imageToPdf(String path) async {
    final output = MemorySink();
    await _pdf.imagesToPdf([FileSource(File(path))], output);
    return output.takeBytes();
  }

  /// Stamps [signaturePng] on [page] (counted from 1), at the bottom of the
  /// page in [corner]. [aspectRatio] is the image's width / height.
  static Future<Uint8List> sign(
    String path, {
    required Uint8List signaturePng,
    required double aspectRatio,
    required int page,
    SignatureCorner corner = SignatureCorner.bottomRight,
  }) async {
    final editor = await _pdf.edit(FileSource(File(path)));
    try {
      final box = await editor.pageMediaBox(page - 1);
      final width = box.width * 0.32;
      final height = width / aspectRatio;
      final margin = box.width * 0.06;
      final x = switch (corner) {
        SignatureCorner.bottomLeft => box.x + margin,
        SignatureCorner.bottomCenter => box.x + (box.width - width) / 2,
        SignatureCorner.bottomRight => box.x + box.width - margin - width,
      };
      await editor.addImageStamp(
        page - 1,
        MemorySource(signaturePng),
        rect: PdfRect(x: x, y: box.y + margin, width: width, height: height),
      );
      final output = MemorySink();
      await editor.save(output);
      return output.takeBytes();
    } finally {
      await editor.dispose();
    }
  }
}
