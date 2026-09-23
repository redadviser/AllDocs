import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../../common/app_constants.dart';
import '../../common/document_actions.dart';
import '../../common/document_file_icon.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';

/// Opens [document] full screen inside AllDocs. PDFs and images are shown
/// natively (pinch to zoom); Office/text files show their text, with a
/// button to open them in another app.
Future<void> openDocumentViewer(
  BuildContext context,
  DocumentsService documentsService,
  DocumentFile document,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DocumentViewerScreen(
        documentsService: documentsService,
        document: document,
      ),
    ),
  );
}

class DocumentViewerScreen extends StatefulWidget {
  const DocumentViewerScreen({
    super.key,
    required this.documentsService,
    required this.document,
  });

  final DocumentsService documentsService;
  final DocumentFile document;

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  late DocumentFile _document = widget.document;
  PdfControllerPinch? _pdfController;
  bool _chromeVisible = true;
  bool _pdfFailed = false;
  int _page = 1;
  int _pages = 0;

  String? get _path {
    final path = _document.localPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) return null;
    return path;
  }

  @override
  void initState() {
    super.initState();
    final path = _path;
    if (_document.type == DocumentType.pdf && path != null) {
      _pdfController = PdfControllerPinch(document: PdfDocument.openFile(path));
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    SystemChrome.setEnabledSystemUIMode(
      _chromeVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  Future<void> _toggleFavorite() async {
    await widget.documentsService.toggleFavorite(_document.id);
    if (!mounted) return;
    setState(() {
      _document = _document.copyWith(isFavorite: !_document.isFavorite);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPaper =
        _document.type != DocumentType.image &&
        (_document.type != DocumentType.pdf || _pdfFailed);

    return Scaffold(
      backgroundColor: isPaper ? AppTheme.background : Colors.black,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AnimatedOpacity(
          opacity: _chromeVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !_chromeVisible,
            child: AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.55),
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: Text(
                _document.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
              actions: [
                IconButton(
                  tooltip: _document.isFavorite
                      ? AppConstants.commonRemoveFavorite.tr()
                      : AppConstants.commonFavorite.tr(),
                  icon: Icon(
                    _document.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: _document.isFavorite ? AppTheme.warning : null,
                  ),
                  onPressed: _toggleFavorite,
                ),
                IconButton(
                  tooltip: AppConstants.actionsShare.tr(),
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () =>
                      widget.documentsService.shareDocuments([_document]),
                ),
                IconButton(
                  tooltip: AppConstants.commonMoreOptions.tr(),
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () => showDocumentActions(
                    context,
                    widget.documentsService,
                    _document,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildContent()),
          if (_pdfController != null && !_pdfFailed && _pages > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$_page / $_pages',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final path = _path;
    if (path == null) return _missingFile();

    final controller = _pdfController;
    if (controller != null && !_pdfFailed) {
      return GestureDetector(
        onTap: _toggleChrome,
        child: PdfViewPinch(
          controller: controller,
          padding: 8,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          onDocumentLoaded: (document) =>
              setState(() => _pages = document.pagesCount),
          onPageChanged: (page) => setState(() => _page = page),
          onDocumentError: (_) => setState(() => _pdfFailed = true),
        ),
      );
    }

    if (_document.type == DocumentType.image) {
      return GestureDetector(
        onTap: _toggleChrome,
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Center(
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => _textFallback(),
            ),
          ),
        ),
      );
    }

    return _textFallback();
  }

  /// Word/Excel/PowerPoint/text: the extracted text on a paper-like page,
  /// plus "open in another app" for the real layout.
  Widget _textFallback() {
    final text = _document.ocrText?.trim();
    final top = MediaQuery.of(context).padding.top + kToolbarHeight + 12;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, top, 16, 32),
      children: [
        Row(
          children: [
            DocumentFileIcon(type: _document.type, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${_document.fileName} · ${_document.sizeLabel}',
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => widget.documentsService.openDocument(_document),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(AppConstants.viewerOpenElsewhere.tr()),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            text == null || text.isEmpty
                ? AppConstants.viewerNoPreview.tr()
                : text,
            style: const TextStyle(
              color: Color(0xFF2A2E35),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _missingFile() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          AppConstants.viewerMissingFile.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.mutedText),
        ),
      ),
    );
  }
}
