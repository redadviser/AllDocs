import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class ZipExtractionLimits {
  const ZipExtractionLimits({
    this.maxEntries = 500,
    this.maxTotalUncompressedBytes = 300 * 1024 * 1024,
    this.maxEntryUncompressedBytes = 80 * 1024 * 1024,
  });

  final int maxEntries;
  final int maxTotalUncompressedBytes;
  final int maxEntryUncompressedBytes;
}

class ZipInspection {
  const ZipInspection({
    required this.fileCount,
    required this.declaredBytes,
    required this.nestedZipCount,
    required this.exceedsLimits,
  });

  final int fileCount;
  final int declaredBytes;

  /// Zips inside the zip are never opened (see [SecureZipExtractor]).
  final int nestedZipCount;
  final bool exceedsLimits;
}

class ExtractedZipEntry {
  const ExtractedZipEntry({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

/// Pulls only the document files matching [allowedExtensions] out of a
/// user-picked .zip — common users often don't realize a download needs
/// extracting before AllDocs can read what's inside it.
///
/// Two archive-specific attacks are guarded against:
///
/// - **Zip Slip** (an entry name like `../../etc/passwd` trying to write
///   outside the target folder): structurally impossible here regardless of
///   entry names, because extracted files are never written using the
///   zip's internal path — each one gets a fresh app-generated id and lands
///   directly in AllDocs' own documents folder via the normal import
///   pipeline, the same as any picked file. Suspicious names (`..`, absolute
///   paths, `__MACOSX/`) are still skipped outright as defense in depth.
/// - **Zip bombs** (a tiny archive that expands to gigabytes): the zip
///   central directory is parsed without decompressing anything, so each
///   entry's *declared* uncompressed size is checked before its content is
///   ever read — oversized entries are skipped before decompression, and a
///   running total aborts the whole extraction once a combined budget is
///   exceeded. Nested .zip entries are never opened, which also rules out
///   the classic recursive-bomb amplification technique.
///
/// This does not defend against a single entry whose header *lies* about
/// its own size (a crafted deflate stream that decompresses to far more
/// than it declares) — this package decompresses however much the
/// compressed bytes actually produce, not capped by the declared size.
/// That's an acceptable residual risk for zips a user deliberately picks
/// from their own device, not an untrusted upload from the network.
class SecureZipExtractor {
  const SecureZipExtractor({this.limits = const ZipExtractionLimits()});

  final ZipExtractionLimits limits;

  /// Same as [extract], but decoding/decompression — genuine CPU work for
  /// anything but a tiny zip — runs on a background isolate instead of
  /// blocking the UI thread. Always prefer this from UI code; [extract]
  /// itself stays synchronous so it's trivial to unit test directly.
  Future<List<ExtractedZipEntry>> extractInBackground(
    Uint8List zipBytes, {
    required List<String> allowedExtensions,
  }) {
    return Isolate.run(
      () => extract(zipBytes, allowedExtensions: allowedExtensions),
    );
  }

  /// Reads only the zip's central directory (nothing is decompressed) to
  /// report how much space its contents *declare* they need — so the UI can
  /// warn before extracting a zip that would expand to gigabytes.
  Future<ZipInspection> inspectInBackground(Uint8List zipBytes) {
    return Isolate.run(() {
      try {
        final archive = ZipDecoder().decodeBytes(zipBytes, verify: false);
        var total = 0;
        var files = 0;
        var nestedZips = 0;
        for (final entry in archive.files) {
          if (!entry.isFile) continue;
          files++;
          total += entry.size;
          if (entry.name.toLowerCase().endsWith('.zip')) nestedZips++;
        }
        return ZipInspection(
          fileCount: files,
          declaredBytes: total,
          nestedZipCount: nestedZips,
          exceedsLimits:
              total > limits.maxTotalUncompressedBytes ||
              files > limits.maxEntries,
        );
      } catch (_) {
        return const ZipInspection(
          fileCount: 0,
          declaredBytes: 0,
          nestedZipCount: 0,
          exceedsLimits: false,
        );
      }
    });
  }

  List<ExtractedZipEntry> extract(
    Uint8List zipBytes, {
    required List<String> allowedExtensions,
  }) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    } catch (_) {
      // Corrupted, encrypted, or not actually a zip.
      return const [];
    }

    if (archive.files.length > limits.maxEntries) return const [];

    final results = <ExtractedZipEntry>[];
    var totalBytes = 0;

    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      if (!_isSafeEntryName(entry.name)) continue;

      final fileName = _baseName(entry.name);
      if (fileName.isEmpty || fileName.startsWith('.')) continue;
      if (fileName.toLowerCase().endsWith('.zip')) continue;
      if (!_hasAllowedExtension(fileName, allowedExtensions)) continue;

      if (entry.size > limits.maxEntryUncompressedBytes) continue;
      totalBytes += entry.size;
      if (totalBytes > limits.maxTotalUncompressedBytes) break;

      Uint8List bytes;
      try {
        bytes = entry.content;
      } catch (_) {
        continue;
      }
      if (bytes.length > limits.maxEntryUncompressedBytes) continue;

      results.add(ExtractedZipEntry(fileName: fileName, bytes: bytes));
    }

    return results;
  }

  bool _isSafeEntryName(String name) {
    final normalized = name.replaceAll('\\', '/');
    if (normalized.isEmpty) return false;
    if (normalized.startsWith('/')) return false;
    if (normalized == '..' || normalized.contains('../')) return false;
    if (normalized.startsWith('__MACOSX/')) return false;
    return true;
  }

  String _baseName(String name) {
    final normalized = name.replaceAll('\\', '/');
    final parts = normalized.split('/')..removeWhere((part) => part.isEmpty);
    return parts.isEmpty ? '' : parts.last;
  }

  bool _hasAllowedExtension(String fileName, List<String> allowedExtensions) {
    final lower = fileName.toLowerCase();
    return allowedExtensions.any((ext) => lower.endsWith('.$ext'));
  }
}
