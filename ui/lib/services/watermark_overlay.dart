import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../theme/app_theme.dart';

/// A transparent PNG the size of a page ([pageWidth] × [pageHeight] points)
/// with [text] repeated diagonally across it — stamped over each page of a
/// shared copy. Drawn here rather than by the PDF engine so any language's
/// accents come out right, in the app's own typeface.
Future<Uint8List> renderWatermarkOverlay(
  String text, {
  required double pageWidth,
  required double pageHeight,
}) async {
  const scale = 2.0;
  final width = (pageWidth * scale).round();
  final height = (pageHeight * scale).round();

  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: pageWidth * scale * 0.034,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: const Color(0xFFC0392B).withValues(alpha: 0.3),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // Rotate about the centre, then cover a square larger than the page so
  // the tilted rows reach every corner.
  canvas.translate(width / 2, height / 2);
  canvas.rotate(-math.pi / 6);
  final reach = math.sqrt(width * width + height * height) / 2;
  final stepX = painter.width + width * 0.12;
  final stepY = painter.height * 4.2;
  var row = 0;
  for (var y = -reach; y < reach; y += stepY, row++) {
    // Alternate rows shift by half a step, like a brick wall.
    final shift = row.isOdd ? stepX / 2 : 0.0;
    for (var x = -reach - shift; x < reach; x += stepX) {
      painter.paint(canvas, Offset(x, y));
    }
  }

  final image = await recorder.endRecording().toImage(width, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}
