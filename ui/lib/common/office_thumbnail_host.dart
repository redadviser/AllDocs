import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_theme.dart';
import 'office_document_view.dart';

/// Draws thumbnails of Word/PowerPoint/Excel files with the same renderers
/// as the in-app viewer (assets/viewer): one tiny, practically invisible
/// WebView kept above every screen renders the first page/slide/sheet and
/// hands back a JPEG, one file at a time. Mount it once (see app.dart);
/// [render] returns null while it isn't mounted (tests, no WebView).
class OfficeThumbnailHost extends StatefulWidget {
  const OfficeThumbnailHost({super.key});

  static _OfficeThumbnailHostState? _active;

  /// Whether this platform has a WebView at all (not the case in tests).
  static bool get supported => WebViewPlatform.instance != null;

  static Future<Uint8List?> render(String path, OfficeKind kind) {
    final host = _active;
    if (host == null) return Future.value(null);
    return host._enqueue(path, kind);
  }

  @override
  State<OfficeThumbnailHost> createState() => _OfficeThumbnailHostState();
}

class _OfficeThumbnailHostState extends State<OfficeThumbnailHost> {
  static const _page = 'assets/viewer/viewer.html';
  static const _chunk = 256 * 1024;
  static const _width = 360;

  // Big files take long to lay out just for a card; they keep the text
  // preview.
  static const _maxBytes = 12 * 1024 * 1024;

  late final WebViewController _controller;
  Future<void> _queue = Future.value();
  Completer<void>? _ready;
  Completer<String?>? _result;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.background)
      ..addJavaScriptChannel('AllDocsViewer', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => request.url.contains(_page)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
    OfficeThumbnailHost._active = this;
  }

  @override
  void dispose() {
    if (OfficeThumbnailHost._active == this) OfficeThumbnailHost._active = null;
    super.dispose();
  }

  void _onMessage(JavaScriptMessage message) {
    final text = message.message;
    final ready = _ready;
    final result = _result;
    if (text == 'ready') {
      if (ready != null && !ready.isCompleted) ready.complete();
    } else if (result != null && !result.isCompleted) {
      if (text.startsWith('thumbnail:')) {
        result.complete(text.substring('thumbnail:'.length));
      } else if (text.startsWith('error:')) {
        result.complete(null);
      }
    }
  }

  /// One file at a time: each gets a fresh page so nothing from the
  /// previous document lingers.
  Future<Uint8List?> _enqueue(String path, OfficeKind kind) {
    final done = Completer<Uint8List?>();
    _queue = _queue.then((_) async {
      done.complete(await _render(path, kind));
    });
    return done.future;
  }

  Future<Uint8List?> _render(String path, OfficeKind kind) async {
    if (!mounted) return null;
    try {
      final file = File(path);
      if (!await file.exists() || await file.length() > _maxBytes) return null;

      _ready = Completer<void>();
      await _controller.loadFlutterAsset(_page);
      await _ready!.future.timeout(const Duration(seconds: 10));

      final encoded = base64Encode(await file.readAsBytes());
      for (var start = 0; start < encoded.length; start += _chunk) {
        final end = (start + _chunk).clamp(0, encoded.length);
        await _controller.runJavaScript(
          "AllDocs.append('${encoded.substring(start, end)}')",
        );
      }

      _result = Completer<String?>();
      await _controller.runJavaScript(
        "AllDocs.thumbnail('${kind.name}', {width: $_width})",
      );
      final jpeg = await _result!.future.timeout(const Duration(seconds: 30));
      return jpeg == null ? null : base64Decode(jpeg);
    } catch (error) {
      debugPrint('OfficeThumbnailHost: $error');
      return null;
    } finally {
      _ready = null;
      _result = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: WebViewWidget(controller: _controller));
  }
}
