import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_theme.dart';

/// What [OfficeDocumentView] can lay out, by file extension.
enum OfficeKind { docx, pptx, sheet }

OfficeKind? officeKindFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (fileName.substring(dot + 1).toLowerCase()) {
    'docx' || 'docm' || 'dotx' => OfficeKind.docx,
    'pptx' || 'ppsx' || 'potx' => OfficeKind.pptx,
    'xlsx' || 'xlsm' || 'xls' || 'ods' || 'csv' => OfficeKind.sheet,
    _ => null,
  };
}

/// Shows a Word, PowerPoint or Excel file with its real layout (fonts,
/// colours, tables, images, slides, sheets) inside the app, instead of just
/// its text. It runs local JavaScript renderers in a WebView
/// (assets/viewer) that has no network access, so the document never
/// leaves the phone. [onFailed] fires when the file can't be laid out, so
/// the caller can fall back to the plain text.
class OfficeDocumentView extends StatefulWidget {
  const OfficeDocumentView({
    super.key,
    required this.path,
    required this.kind,
    required this.topInset,
    required this.onFailed,
  });

  final String path;
  final OfficeKind kind;

  /// Space to leave above the content for the app bar floating over it.
  final double topInset;
  final VoidCallback onFailed;

  /// Past this, streaming the file into the WebView gets slow and
  /// memory-hungry on a phone; such files use the text preview.
  static const maxBytes = 25 * 1024 * 1024;

  @override
  State<OfficeDocumentView> createState() => _OfficeDocumentViewState();
}

class _OfficeDocumentViewState extends State<OfficeDocumentView> {
  static const _page = 'assets/viewer/viewer.html';
  // Base64 characters per call into the page (a multiple of 4, so every
  // chunk decodes on its own).
  static const _chunk = 256 * 1024;

  late final WebViewController _controller;
  bool _started = false;
  bool _rendered = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.background)
      ..enableZoom(true)
      ..addJavaScriptChannel('AllDocsViewer', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Only the viewer page itself; links inside a document go nowhere.
          onNavigationRequest: (request) =>
              request.url.contains(_page) && !_started
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      )
      ..loadFlutterAsset(_page);
  }

  Future<void> _onMessage(JavaScriptMessage message) async {
    final text = message.message;
    if (text == 'ready' && !_started) {
      _started = true;
      await _sendDocument();
    } else if (text == 'rendered') {
      if (mounted) setState(() => _rendered = true);
    } else if (text.startsWith('error:')) {
      debugPrint('OfficeDocumentView: $text');
      widget.onFailed();
    }
  }

  Future<void> _sendDocument() async {
    try {
      final file = File(widget.path);
      if (await file.length() > OfficeDocumentView.maxBytes) {
        widget.onFailed();
        return;
      }
      final encoded = base64Encode(await file.readAsBytes());
      for (var start = 0; start < encoded.length; start += _chunk) {
        final end = (start + _chunk).clamp(0, encoded.length);
        // Base64 has no quotes or backslashes, so it's safe in a JS string.
        await _controller.runJavaScript(
          "AllDocs.append('${encoded.substring(start, end)}')",
        );
      }
      await _controller.runJavaScript(
        "AllDocs.render('${widget.kind.name}', "
        '{top: ${widget.topInset.round()}})',
      );
    } catch (error) {
      debugPrint('OfficeDocumentView: $error');
      widget.onFailed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _controller)),
        if (!_rendered)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
