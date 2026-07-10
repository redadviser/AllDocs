import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';

class DocumentPreviewCard extends StatelessWidget {
  const DocumentPreviewCard({
    super.key,
    required this.document,
    required this.onTap,
    this.trailing,
    this.showNewBadge = false,
  });

  final DocumentFile document;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showNewBadge;

  @override
  Widget build(BuildContext context) {
    final color = _documentColor(document.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.surfaceStrong.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border.withValues(alpha: 0.72)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _DocumentPreview(
                  document: document,
                  color: color,
                  icon: _documentIcon(document.type),
                  extension: _documentExtension(document.type),
                  showNewBadge: showNewBadge && document.isNew,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: Text(
                  document.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 12.5,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${document.dateLabel} • ${document.sizeLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(height: 8),
                SizedBox(height: 36, child: trailing),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({
    required this.document,
    required this.color,
    required this.icon,
    required this.extension,
    required this.showNewBadge,
  });

  final DocumentFile document;
  final Color color;
  final IconData icon;
  final String extension;
  final bool showNewBadge;

  @override
  Widget build(BuildContext context) {
    final localPath = _existingLocalPath(document.localPath);
    final imagePreview =
        document.type == DocumentType.image && localPath != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.22)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imagePreview)
              Image.file(
                File(localPath),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _FallbackDocumentPreview(
                    color: color,
                    icon: icon,
                    extension: extension,
                    type: document.type,
                  );
                },
              )
            else if (document.type == DocumentType.pdf && localPath != null)
              _PdfFirstPagePreview(
                filePath: localPath,
                fallback: _FallbackDocumentPreview(
                  color: color,
                  icon: icon,
                  extension: extension,
                  type: document.type,
                ),
              )
            else
              _FallbackDocumentPreview(
                color: color,
                icon: icon,
                extension: extension,
                type: document.type,
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: _ExtensionBadge(extension: extension, color: color),
            ),
            if (showNewBadge)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Text(
                    AppConstants.archiveNew.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PdfFirstPagePreview extends StatefulWidget {
  const _PdfFirstPagePreview({required this.filePath, required this.fallback});

  final String filePath;
  final Widget fallback;

  @override
  State<_PdfFirstPagePreview> createState() => _PdfFirstPagePreviewState();
}

class _PdfFirstPagePreviewState extends State<_PdfFirstPagePreview> {
  late PdfController _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = PdfController(
      document: PdfDocument.openFile(widget.filePath),
      initialPage: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _PdfFirstPagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _controller.dispose();
      _hasError = false;
      _controller = PdfController(
        document: PdfDocument.openFile(widget.filePath),
        initialPage: 1,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) return widget.fallback;

    return IgnorePointer(
      child: PdfView(
        controller: _controller,
        scrollDirection: Axis.vertical,
        physics: const NeverScrollableScrollPhysics(),
        onDocumentError: (_) => setState(() => _hasError = true),
      ),
    );
  }
}

class _FallbackDocumentPreview extends StatelessWidget {
  const _FallbackDocumentPreview({
    required this.color,
    required this.icon,
    required this.extension,
    required this.type,
  });

  final Color color;
  final IconData icon;
  final String extension;
  final DocumentType type;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Center(
        child: AspectRatio(
          aspectRatio: 0.72,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.26)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const Spacer(),
                    Text(
                      extension,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (type == DocumentType.excel)
                  Expanded(child: _ExcelSkeleton(color: color))
                else
                  Expanded(child: _TextSkeleton(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextSkeleton extends StatelessWidget {
  const _TextSkeleton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 10,
          width: 54,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(height: 12),
        for (final widthFactor in const [1.0, 0.78, 0.92, 0.55]) ...[
          FractionallySizedBox(
            widthFactor: widthFactor,
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: AppTheme.surfaceStrong.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 7),
        ],
      ],
    );
  }
}

class _ExcelSkeleton extends StatelessWidget {
  const _ExcelSkeleton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1.7,
      ),
      itemCount: 15,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: index < 3
                ? color.withValues(alpha: 0.22)
                : AppTheme.surfaceStrong.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      },
    );
  }
}

class _ExtensionBadge extends StatelessWidget {
  const _ExtensionBadge({required this.extension, required this.color});

  final String extension;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        extension,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String? _existingLocalPath(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('file://')) {
    path = Uri.tryParse(path)?.toFilePath() ?? path;
  }

  try {
    return File(path).existsSync() ? path : null;
  } catch (_) {
    return null;
  }
}

IconData _documentIcon(DocumentType type) {
  return switch (type) {
    DocumentType.pdf => Icons.picture_as_pdf_rounded,
    DocumentType.word => Icons.description_rounded,
    DocumentType.excel => Icons.table_chart_rounded,
    DocumentType.image => Icons.image_rounded,
  };
}

Color _documentColor(DocumentType type) {
  return switch (type) {
    DocumentType.pdf => const Color(0xFFFF6868),
    DocumentType.word => const Color(0xFF5C8DFF),
    DocumentType.excel => const Color(0xFF4CC58A),
    DocumentType.image => const Color(0xFF9B6DFF),
  };
}

String _documentExtension(DocumentType type) {
  return switch (type) {
    DocumentType.pdf => 'PDF',
    DocumentType.word => 'DOC',
    DocumentType.excel => 'XLS',
    DocumentType.image => AppConstants.archiveImage.tr().toUpperCase(),
  };
}
