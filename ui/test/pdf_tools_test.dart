import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:all_docs/services/pdf_tools.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('alldocs_pdf_tools_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<String> pdfWith(String name, int pages) async {
    final doc = pw.Document();
    for (var i = 1; i <= pages; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Text('$name page $i'),
        ),
      );
    }
    final file = File('${dir.path}/$name.pdf');
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  Future<String> write(String name, Uint8List bytes) async {
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  test('merges documents page after page', () async {
    final a = await pdfWith('a', 2);
    final b = await pdfWith('b', 3);
    final merged = await write('merged.pdf', await PdfTools.merge([a, b]));
    expect(await PdfTools.pageCount(merged), 5);
  });

  test('extracts a range of pages counted from 1', () async {
    final source = await pdfWith('source', 5);
    final part = await write(
      'part.pdf',
      await PdfTools.extractPages(source, 2, 4),
    );
    expect(await PdfTools.pageCount(part), 3);
  });

  test('watermarks and signs without losing pages', () async {
    final source = await pdfWith('doc', 2);
    final marked = await write(
      'marked.pdf',
      await PdfTools.watermark(
        source,
        overlay: (width, height) async {
          final mark = img.Image(
            width: width.round(),
            height: height.round(),
            numChannels: 4,
          );
          return Uint8List.fromList(img.encodePng(mark));
        },
      ),
    );
    expect(await PdfTools.pageCount(marked), 2);

    final signature = img.Image(width: 300, height: 100)
      ..clear(img.ColorRgba8(0, 0, 0, 0));
    img.drawLine(
      signature,
      x1: 10,
      y1: 80,
      x2: 290,
      y2: 20,
      color: img.ColorRgb8(0, 0, 0),
      thickness: 4,
    );
    final signed = await write(
      'signed.pdf',
      await PdfTools.sign(
        source,
        signaturePng: Uint8List.fromList(img.encodePng(signature)),
        aspectRatio: 3,
        page: 2,
      ),
    );
    expect(await PdfTools.pageCount(signed), 2);
    expect(File(signed).lengthSync(), greaterThan(File(source).lengthSync()));
  });

  test('compresses a scanned document', () async {
    final photo = img.Image(width: 2400, height: 3200);
    for (var y = 0; y < photo.height; y += 4) {
      for (var x = 0; x < photo.width; x += 4) {
        img.fillRect(
          photo,
          x1: x,
          y1: y,
          x2: x + 3,
          y2: y + 3,
          color: img.ColorRgb8(
            (x * 7 + y) % 256,
            (y * 3) % 256,
            (x + y * 5) % 256,
          ),
        );
      }
    }
    final doc = pw.Document()
      ..addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) =>
              pw.Image(pw.MemoryImage(img.encodeJpg(photo, quality: 95))),
        ),
      );
    final scan = await write('scan.pdf', await doc.save());
    final smaller = await PdfTools.compress(scan);
    expect(smaller.length, lessThan(File(scan).lengthSync()));
  });
}
