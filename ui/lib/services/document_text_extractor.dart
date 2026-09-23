import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Pulls plain text out of the formats that store it directly (text files
/// and the zip+XML Office/OpenDocument formats), so their contents can be
/// searched without OCR. Pure Dart and synchronous on purpose: callers run
/// it inside `Isolate.run`. PDFs and images are not handled here — they go
/// through OCR in [DocumentTextIndexer].
class DocumentTextExtractor {
  const DocumentTextExtractor();

  /// Upper bound on stored text per document, so the state file (which keeps
  /// this text for search) doesn't balloon with a few huge spreadsheets.
  static const maxChars = 20000;
  static const _maxFileBytes = 25 * 1024 * 1024;

  static bool canExtract(String fileName) {
    final ext = _extension(fileName);
    return const {
      'txt',
      'csv',
      'rtf',
      'docx',
      'xlsx',
      'pptx',
      'odt',
      'ods',
      'odp',
    }.contains(ext);
  }

  String? extractFromPath(String path, {int maxChars = maxChars}) {
    try {
      final file = File(path);
      if (file.lengthSync() > _maxFileBytes) return null;
      final ext = _extension(path);
      final text = switch (ext) {
        'txt' || 'csv' => _decodeText(file.readAsBytesSync()),
        'rtf' => _stripRtf(_decodeText(file.readAsBytesSync())),
        'docx' => _zipXmlText(
          file.readAsBytesSync(),
          (name) => name == 'word/document.xml',
          paragraphTag: 'p',
          textTag: 't',
        ),
        'xlsx' => _zipXmlText(
          file.readAsBytesSync(),
          (name) => name == 'xl/sharedStrings.xml',
          paragraphTag: 'si',
          textTag: 't',
        ),
        'pptx' => _zipXmlText(
          file.readAsBytesSync(),
          (name) =>
              name.startsWith('ppt/slides/slide') && name.endsWith('.xml'),
          paragraphTag: 'p',
          textTag: 't',
        ),
        'odt' || 'ods' || 'odp' => _zipXmlText(
          file.readAsBytesSync(),
          (name) => name == 'content.xml',
          paragraphTag: 'p',
          textTag: null,
        ),
        _ => null,
      };
      if (text == null) return null;
      final normalized = text
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
      if (normalized.isEmpty) return null;
      return normalized.length > maxChars
          ? normalized.substring(0, maxChars)
          : normalized;
    } catch (_) {
      return null;
    }
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  String _decodeText(List<int> bytes) {
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _stripRtf(String rtf) {
    return rtf
        .replaceAll(RegExp(r'\\par[d]?'), '\n')
        .replaceAll(RegExp(r'\{\\\*[^{}]*\}'), '')
        .replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '')
        .replaceAll(RegExp(r'[{}]'), '');
  }

  String? _zipXmlText(
    List<int> bytes,
    bool Function(String name) isContentPart, {
    required String paragraphTag,
    required String? textTag,
  }) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final parts =
        archive.files
            .where((file) => file.isFile && isContentPart(file.name))
            .toList()
          ..sort((a, b) => _naturalCompare(a.name, b.name));
    if (parts.isEmpty) return null;

    final lines = <String>[];
    var total = 0;
    for (final part in parts) {
      final document = XmlDocument.parse(
        utf8.decode(part.content, allowMalformed: true),
      );
      for (final paragraph in document.descendantElements.where(
        (element) => element.name.local == paragraphTag,
      )) {
        final line = textTag == null
            ? paragraph.innerText
            : paragraph.descendantElements
                  .where((element) => element.name.local == textTag)
                  .map((element) => element.innerText)
                  .join();
        final trimmed = line.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (trimmed.isEmpty) continue;
        lines.add(trimmed);
        total += trimmed.length;
        if (total > maxChars) return lines.join('\n');
      }
    }
    return lines.join('\n');
  }

  // slide2.xml before slide10.xml.
  int _naturalCompare(String a, String b) {
    final numberA = int.tryParse(
      RegExp(r'(\d+)\.xml$').firstMatch(a)?[1] ?? '',
    );
    final numberB = int.tryParse(
      RegExp(r'(\d+)\.xml$').firstMatch(b)?[1] ?? '',
    );
    if (numberA != null && numberB != null) return numberA.compareTo(numberB);
    return a.compareTo(b);
  }
}
