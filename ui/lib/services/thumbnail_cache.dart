import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

/// Renders the first page of a PDF once to a small JPEG and reuses it,
/// instead of keeping a live PDF renderer per gallery card. Keyed by path +
/// size + modification time, so a replaced file gets a fresh thumbnail.
class ThumbnailCache {
  ThumbnailCache._();

  static final instance = ThumbnailCache._();
  static const _width = 360.0;

  final Map<String, Future<File?>> _pending = {};
  Directory? _directory;

  // PDF rendering happens on the platform side; firing dozens at once when
  // a grid first appears starves the UI. Two at a time is plenty.
  static const _maxConcurrent = 2;
  int _running = 0;
  final List<Completer<void>> _queue = [];

  Future<File?> pdfThumbnail(String pdfPath) {
    return _pending.putIfAbsent(pdfPath, () => _throttled(pdfPath));
  }

  Future<File?> _throttled(String pdfPath) async {
    if (_running >= _maxConcurrent) {
      final slot = Completer<void>();
      _queue.add(slot);
      await slot.future;
    }
    _running++;
    try {
      return await _render(pdfPath);
    } finally {
      _running--;
      if (_queue.isNotEmpty) _queue.removeAt(0).complete();
    }
  }

  void evict(String pdfPath) => _pending.remove(pdfPath);

  Future<Directory> _dir() async {
    if (_directory != null) return _directory!;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/alldocs_thumbnails');
    await dir.create(recursive: true);
    return _directory = dir;
  }

  Future<File?> _render(String pdfPath) async {
    try {
      final source = File(pdfPath);
      if (!await source.exists()) return null;
      final stat = await source.stat();
      final key =
          '${pdfPath.hashCode}_${stat.size}_${stat.modified.millisecondsSinceEpoch}';
      final target = File('${(await _dir()).path}/$key.jpg');
      if (await target.exists()) return target;

      final document = await PdfDocument.openFile(pdfPath);
      try {
        final page = await document.getPage(1);
        try {
          final height = _width * page.height / page.width;
          final image = await page.render(
            width: _width,
            height: height,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
            quality: 80,
          );
          if (image == null) return null;
          await target.writeAsBytes(image.bytes);
          return target;
        } finally {
          await page.close();
        }
      } finally {
        await document.close();
      }
    } catch (_) {
      _pending.remove(pdfPath);
      return null;
    }
  }
}
