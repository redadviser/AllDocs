import 'package:flutter/services.dart';

import 'searchable_pdf_builder.dart' show OcrTextLine;

/// Text found in one image, with each line's box in image pixels (top-left
/// origin), as the searchable PDF builder expects.
class RecognizedText {
  const RecognizedText(this.text, this.lines);

  final String text;
  final List<OcrTextLine> lines;
}

/// On-device OCR through the native `alldocs/ocr` channel: ML Kit on
/// Android (MainActivity.kt), Apple Vision on iOS (AppDelegate.swift).
/// Apple Vision keeps Google's ML Kit pods out of the iOS build, which have
/// no arm64 simulator slice.
class TextRecognition {
  const TextRecognition({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('alldocs/ocr');

  final MethodChannel _channel;

  Future<RecognizedText> recognize(String imagePath) async {
    final raw = await _channel.invokeMapMethod<String, Object?>('recognize', {
      'path': imagePath,
    });
    return parseRecognizedText(raw ?? const {});
  }
}

RecognizedText parseRecognizedText(Map<Object?, Object?> raw) {
  final lines = <OcrTextLine>[];
  for (final item in (raw['lines'] as List?) ?? const []) {
    final line = item as Map;
    final text = (line['text'] as String? ?? '').trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final width = (line['width'] as num).toDouble();
    final height = (line['height'] as num).toDouble();
    if (text.isEmpty || width <= 1 || height <= 1) continue;
    lines.add(
      OcrTextLine(
        text: text,
        left: (line['left'] as num).toDouble(),
        top: (line['top'] as num).toDouble(),
        width: width,
        height: height,
      ),
    );
  }
  return RecognizedText((raw['text'] as String? ?? '').trim(), lines);
}
