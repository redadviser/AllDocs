import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

/// Renders the first page of a PDF (or Word/PowerPoint/Excel file, see
/// [officeThumbnail]) once to a small JPEG and reuses it, instead of keeping
/// a live renderer per gallery card. Keyed by path + size + modification
/// time, so a replaced file gets a fresh thumbnail.
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

  /// Thumbnail of an Office file, drawn by [render] (the in-app viewer's
  /// renderer, which lives in the widget tree) the first time and cached
  /// like the PDF ones. Null when it can't be drawn.
  Future<File?> officeThumbnail(
    String path,
    Future<Uint8List?> Function() render,
  ) {
    return _pending.putIfAbsent('office:$path', () async {
      try {
        final target = await _cacheFile(path);
        if (target == null) return null;
        if (await target.exists()) return target;
        final bytes = await render();
        // Not retried on every rebuild: a file that couldn't be drawn keeps
        // its text preview until the app restarts or [evict] is called.
        if (bytes == null || bytes.isEmpty) return null;
        await target.writeAsBytes(bytes);
        return target;
      } catch (_) {
        _pending.remove('office:$path');
        return null;
      }
    });
  }

  Future<File?> _cacheFile(String path) async {
    final source = File(path);
    if (!await source.exists()) return null;
    final stat = await source.stat();
    final key =
        '${path.hashCode}_${stat.size}_${stat.modified.millisecondsSinceEpoch}';
    return File('${(await _dir()).path}/$key.jpg');
  }

  /// Forgets [path]'s thumbnail (e.g. its content was replaced).
  void evict(String path) {
    _pending.remove(path);
    _pending.remove('office:$path');
  }

  Future<Directory> _dir() async {
    if (_directory != null) return _directory!;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/alldocs_thumbnails');
    await dir.create(recursive: true);
    return _directory = dir;
  }

  Future<File?> _render(String pdfPath) async {
    try {
      final target = await _cacheFile(pdfPath);
      if (target == null) return null;
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
