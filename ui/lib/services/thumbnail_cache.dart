import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../models/document_file.dart';
import 'vault/document_vault.dart';

/// Renders the first page of a PDF (or Word/PowerPoint/Excel file, see
/// [officeThumbnail]) once to a small JPEG and reuses it, instead of keeping
/// a live renderer per gallery card. Keyed by the stored file's path, size
/// and modification time, so a replaced file gets a fresh thumbnail. Sealed
/// documents are decrypted to the private temp folder only while drawn.
class ThumbnailCache {
  ThumbnailCache._();

  static final instance = ThumbnailCache._();
  static const _width = 360.0;

  // Most recent thumbnails, in memory; the rest are read back from disk.
  static const _keptInMemory = 200;
  final Map<String, Future<Uint8List?>> _pending = {};
  Directory? _directory;

  // PDF rendering happens on the platform side; firing dozens at once when
  // a grid first appears starves the UI. Two at a time is plenty.
  static const _maxConcurrent = 2;
  int _running = 0;
  final List<Completer<void>> _queue = [];

  Future<Uint8List?> pdfThumbnail(DocumentFile document) =>
      _cached('pdf', document, 'jpg', () => _throttled(document));

  /// A small copy of a sealed image (a plain one is shown from its file).
  Future<Uint8List?> imageThumbnail(DocumentFile document) => _cached(
    'image',
    document,
    'png',
    () async {
      final codec = await ui.instantiateImageCodec(
        await DocumentVault.readBytes(document),
        targetWidth: _width.toInt(),
      );
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      return png?.buffer.asUint8List();
    },
  );

  /// Thumbnail of an Office file, drawn by [render] (the in-app viewer's
  /// renderer, which lives in the widget tree) the first time and cached
  /// like the PDF ones. Null when it can't be drawn.
  Future<Uint8List?> officeThumbnail(
    DocumentFile document,
    Future<Uint8List?> Function(String plainPath) render,
  ) => _cached('office', document, 'jpg', () async {
    final opened = await DocumentVault.materialize(document);
    try {
      return await render(opened.file.path);
    } finally {
      await opened.release();
    }
  });

  /// The thumbnail drawn by [draw] once and kept on disk; sealed with the
  /// library's key when the document is, so it's no more readable than the
  /// document itself.
  Future<Uint8List?> _cached(
    String kind,
    DocumentFile document,
    String extension,
    Future<Uint8List?> Function() draw,
  ) {
    final key = '$kind:${document.localPath!}';
    final existing = _pending.remove(key);
    if (existing != null) return _pending[key] = existing;
    if (_pending.length >= _keptInMemory) _pending.remove(_pending.keys.first);
    return _pending[key] = () async {
      try {
        final target = await _cacheFile(
          document.localPath!,
          extension: document.sealed ? 'adv' : extension,
        );
        if (target == null) return null;
        if (await target.exists()) {
          final stored = await target.readAsBytes();
          return document.sealed
              ? await DocumentVault.format.openBytes(stored)
              : stored;
        }
        final bytes = await draw();
        // Not retried on every rebuild: a file that couldn't be drawn keeps
        // its text preview until the app restarts or [evict] is called.
        if (bytes == null || bytes.isEmpty) return null;
        await target.writeAsBytes(
          document.sealed ? await DocumentVault.format.sealBytes(bytes) : bytes,
        );
        return bytes;
      } catch (_) {
        _pending.remove(key);
        return null;
      }
    }();
  }

  Future<Uint8List?> _throttled(DocumentFile document) async {
    if (_running >= _maxConcurrent) {
      final slot = Completer<void>();
      _queue.add(slot);
      await slot.future;
    }
    _running++;
    try {
      return await _render(document);
    } finally {
      _running--;
      if (_queue.isNotEmpty) _queue.removeAt(0).complete();
    }
  }

  Future<File?> _cacheFile(String path, {required String extension}) async {
    final source = File(path);
    if (!await source.exists()) return null;
    final stat = await source.stat();
    final key =
        '${path.hashCode}_${stat.size}_${stat.modified.millisecondsSinceEpoch}';
    return File('${(await _dir()).path}/$key.$extension');
  }

  /// Deletes the thumbnails kept in plain files (drawn before the library
  /// was encrypted); sealed ones stay.
  Future<void> purgePlain() async {
    _pending.clear();
    try {
      await for (final entity in (await _dir()).list()) {
        if (entity is File && !entity.path.endsWith('.adv')) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  /// Forgets [path]'s thumbnail (e.g. its content was replaced).
  void evict(String path) {
    for (final kind in ['pdf', 'office', 'image']) {
      _pending.remove('$kind:$path');
    }
  }

  Future<Directory> _dir() async {
    if (_directory != null) return _directory!;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/alldocs_thumbnails');
    await dir.create(recursive: true);
    return _directory = dir;
  }

  Future<Uint8List?> _render(DocumentFile source) async {
    final opened = await DocumentVault.materialize(source);
    try {
      final document = await PdfDocument.openFile(opened.file.path);
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
          return image?.bytes;
        } finally {
          await page.close();
        }
      } finally {
        await document.close();
      }
    } finally {
      await opened.release();
    }
  }
}
