import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/services/secure_zip_extractor.dart';

const _documentExtensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'];

Uint8List _buildZip(List<(String name, List<int> data)> entries) {
  final archive = Archive();
  for (final (name, data) in entries) {
    archive.addFile(ArchiveFile(name, data.length, data));
  }
  return ZipEncoder().encodeBytes(archive);
}

List<int> _text(String value) => utf8.encode(value);

void main() {
  group('SecureZipExtractor', () {
    test('extracts only allowed extensions, using the flat base name', () {
      final zip = _buildZip([
        ('report.pdf', _text('pdf bytes')),
        ('notes.txt', _text('hello world')),
        ('docs/nested/invoice.pdf', _text('nested pdf')),
        ('photo.jpg', _text('image bytes')),
        ('installer.exe', _text('binary bytes')),
      ]);

      final entries = const SecureZipExtractor().extract(
        zip,
        allowedExtensions: _documentExtensions,
      );

      final names = entries.map((e) => e.fileName).toSet();
      expect(names, {'report.pdf', 'notes.txt', 'invoice.pdf'});
      expect(
        utf8.decode(entries.firstWhere((e) => e.fileName == 'notes.txt').bytes),
        'hello world',
      );
    });

    test('skips path-traversal entry names (Zip Slip)', () {
      final zip = _buildZip([
        ('../../etc/evil.pdf', _text('a')),
        ('safe.pdf', _text('b')),
      ]);

      final entries = const SecureZipExtractor().extract(
        zip,
        allowedExtensions: _documentExtensions,
      );

      expect(entries.map((e) => e.fileName), ['safe.pdf']);
    });

    test('never opens nested zip entries', () {
      final innerZip = _buildZip([('inner.pdf', _text('inner'))]);
      final zip = _buildZip([
        ('bundle.zip', innerZip),
        ('top.pdf', _text('top')),
      ]);

      final entries = const SecureZipExtractor().extract(
        zip,
        allowedExtensions: _documentExtensions,
      );

      expect(entries.map((e) => e.fileName), ['top.pdf']);
    });

    test('skips macOS junk entries', () {
      final zip = _buildZip([
        ('__MACOSX/._report.pdf', _text('junk')),
        ('.DS_Store', _text('junk')),
        ('report.pdf', _text('real')),
      ]);

      final entries = const SecureZipExtractor().extract(
        zip,
        allowedExtensions: _documentExtensions,
      );

      expect(entries.map((e) => e.fileName), ['report.pdf']);
    });

    test('rejects an entry whose declared size exceeds the per-file cap', () {
      final zip = _buildZip([
        ('huge.pdf', List<int>.filled(1000, 65)),
        ('small.pdf', _text('ok')),
      ]);

      final entries = const SecureZipExtractor(
        limits: ZipExtractionLimits(maxEntryUncompressedBytes: 500),
      ).extract(zip, allowedExtensions: _documentExtensions);

      expect(entries.map((e) => e.fileName), ['small.pdf']);
    });

    test('stops once the combined size budget is exceeded', () {
      final zip = _buildZip([
        ('a.pdf', List<int>.filled(300, 65)),
        ('b.pdf', List<int>.filled(300, 66)),
        ('c.pdf', List<int>.filled(300, 67)),
      ]);

      final entries = const SecureZipExtractor(
        limits: ZipExtractionLimits(maxTotalUncompressedBytes: 500),
      ).extract(zip, allowedExtensions: _documentExtensions);

      expect(entries.length, lessThan(3));
    });

    test('rejects the whole archive past the entry-count cap', () {
      final zip = _buildZip([
        for (var i = 0; i < 10; i++) ('doc_$i.pdf', _text('x')),
      ]);

      final entries = const SecureZipExtractor(
        limits: ZipExtractionLimits(maxEntries: 5),
      ).extract(zip, allowedExtensions: _documentExtensions);

      expect(entries, isEmpty);
    });

    test('returns no entries for corrupted/non-zip bytes', () {
      final entries = const SecureZipExtractor().extract(
        Uint8List.fromList(_text('not a zip file')),
        allowedExtensions: _documentExtensions,
      );

      expect(entries, isEmpty);
    });

    test('extractInBackground runs on an isolate and returns the same result', () async {
      final zip = _buildZip([
        ('report.pdf', _text('pdf bytes')),
        ('photo.jpg', _text('image bytes')),
      ]);

      final entries = await const SecureZipExtractor().extractInBackground(
        zip,
        allowedExtensions: _documentExtensions,
      );

      expect(entries.map((e) => e.fileName), ['report.pdf']);
      expect(utf8.decode(entries.single.bytes), 'pdf bytes');
    });
  });
}
