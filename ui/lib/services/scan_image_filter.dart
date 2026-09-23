import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

/// Look applied to scanned pages before they become the PDF.
enum ScanFilter { original, grayscale, blackAndWhite, highContrast }

/// Applies [filter] to every JPEG page, writing new files next to the
/// originals (so the originals can still be cleaned up by the caller).
/// Returns the paths to use for OCR/PDF building. Runs on a background
/// isolate: decoding and re-encoding full-resolution pages is slow.
Future<List<String>> applyScanFilter(
  List<String> imagePaths,
  ScanFilter filter,
) async {
  if (filter == ScanFilter.original || imagePaths.isEmpty) return imagePaths;
  return Isolate.run(() {
    final output = <String>[];
    for (final path in imagePaths) {
      try {
        final decoded = img.decodeImage(File(path).readAsBytesSync());
        if (decoded == null) {
          output.add(path);
          continue;
        }
        final filtered = applyScanFilterToImage(decoded, filter);
        final target = '${path}_${filter.name}.jpg';
        File(target).writeAsBytesSync(img.encodeJpg(filtered, quality: 90));
        output.add(target);
      } catch (_) {
        output.add(path);
      }
    }
    return output;
  });
}

img.Image applyScanFilterToImage(img.Image source, ScanFilter filter) {
  return switch (filter) {
    ScanFilter.original => source,
    ScanFilter.grayscale => img.grayscale(source),
    // Normalize first so the threshold works on dim photos too.
    ScanFilter.blackAndWhite => img.luminanceThreshold(
      img.normalize(img.grayscale(source), min: 0, max: 255),
      threshold: 0.55,
    ),
    ScanFilter.highContrast => img.contrast(
      img.adjustColor(source, saturation: 0.9),
      contrast: 160,
    ),
  };
}

/// Small preview (long side ~[maxSide]px) of the first page with [filter],
/// as JPEG bytes, for the filter picker.
Future<List<int>?> scanFilterPreview(
  String imagePath,
  ScanFilter filter, {
  int maxSide = 700,
}) {
  return Isolate.run(() {
    try {
      final decoded = img.decodeImage(File(imagePath).readAsBytesSync());
      if (decoded == null) return null;
      final resized = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxSide)
          : img.copyResize(decoded, height: maxSide);
      return img.encodeJpg(
        applyScanFilterToImage(resized, filter),
        quality: 80,
      );
    } catch (_) {
      return null;
    }
  });
}
