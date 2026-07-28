import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/searchable_pdf_builder.dart';

// A valid, minimal 1x1 pixel PNG, used as a stand-in for a scanned page image.
const _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=';

void main() {
  late Directory tempDir;
  late File imageFile;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('searchable_pdf_test_');
    imageFile = File('${tempDir.path}/page.png');
    await imageFile.writeAsBytes(base64Decode(_onePixelPngBase64));
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<String> pdfBytesAsLatin1(String path) async {
    final bytes = await File(path).readAsBytes();
    return latin1.decode(bytes, allowInvalid: true);
  }

  test('writes a valid, non-empty PDF for a single scanned page', () async {
    final outputPath = '${tempDir.path}/single.pdf';

    await buildSearchablePdf(
      outputPath: outputPath,
      pages: [
        ScannedPage(
          imagePath: imageFile.path,
          text: 'hello world',
          lines: const [
            OcrTextLine(text: 'hello world', left: 5, top: 5, width: 40, height: 12),
          ],
        ),
      ],
    );

    final output = File(outputPath);
    expect(output.existsSync(), isTrue);

    final content = await pdfBytesAsLatin1(outputPath);
    expect(content.startsWith('%PDF-'), isTrue);
    expect(content.trim().endsWith('%%EOF'), isTrue);
    expect(RegExp(r'/Count\s+1\b').hasMatch(content), isTrue);
  });

  test('one PDF page is written per scanned page', () async {
    final outputPath = '${tempDir.path}/multi.pdf';

    await buildSearchablePdf(
      outputPath: outputPath,
      pages: [
        ScannedPage(
          imagePath: imageFile.path,
          text: 'first page',
          lines: const [
            OcrTextLine(text: 'first page', left: 5, top: 5, width: 40, height: 12),
          ],
        ),
        ScannedPage(
          imagePath: imageFile.path,
          text: 'second page',
          lines: const [
            OcrTextLine(text: 'second page', left: 5, top: 5, width: 40, height: 12),
          ],
        ),
        ScannedPage(imagePath: imageFile.path, text: '', lines: const []),
      ],
    );

    final content = await pdfBytesAsLatin1(outputPath);
    expect(RegExp(r'/Count\s+3\b').hasMatch(content), isTrue);
    expect(RegExp(r'/MediaBox').allMatches(content).length, 3);
  });

  test(
    'a text line positioned at the page edge does not throw (regression)',
    () async {
      final outputPath = '${tempDir.path}/edge.pdf';

      // A line whose box sits right at (or past) the page boundary used to
      // invert the width/height clamp bounds and crash the whole scan.
      await buildSearchablePdf(
        outputPath: outputPath,
        pages: [
          ScannedPage(
            imagePath: imageFile.path,
            text: 'edge',
            lines: const [
              OcrTextLine(text: 'edge', left: 1, top: 1, width: 40, height: 12),
            ],
          ),
        ],
      );

      expect(File(outputPath).existsSync(), isTrue);
    },
  );
}
