import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/thumbnail_cache.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'document_file_icon.dart';

/// Gallery card: a real preview of the document (first PDF page, the image
/// itself, or the start of its text) with the name and date underneath.
class DocumentPreviewCard extends StatelessWidget {
  const DocumentPreviewCard({
    super.key,
    required this.document,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.showNewBadge = false,
    this.selected,
    this.subtitle,
  });

  final DocumentFile document;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool showNewBadge;

  /// Non-null puts the card in selection mode (shows a check circle).
  final bool? selected;

  /// Replaces the default "date · size" line (e.g. a search snippet).
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == true;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.accent
                        : AppTheme.border.withValues(alpha: 0.7),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radius - 1),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DocumentThumbnail(document: document),
                      if (showNewBadge && document.isNew)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _Pill(
                            label: AppConstants.archiveNew.tr(),
                            color: AppTheme.accent,
                          ),
                        ),
                      if (document.isFavorite)
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: Icon(
                            Icons.star_rounded,
                            color: AppTheme.warning,
                            size: 18,
                            shadows: [Shadow(blurRadius: 6)],
                          ),
                        ),
                      if (selected != null)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: isSelected ? AppTheme.accent : Colors.white,
                            size: 22,
                            shadows: const [Shadow(blurRadius: 6)],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle ??
                            '${documentTypeLabel(document.type)} · ${document.dateLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The preview area on its own, reusable in lists and sheets.
class DocumentThumbnail extends StatelessWidget {
  const DocumentThumbnail({super.key, required this.document});

  final DocumentFile document;

  @override
  Widget build(BuildContext context) {
    final path = _existingLocalPath(document.localPath);
    final fallback = _TextPagePreview(document: document);
    if (path == null) return fallback;

    if (document.type == DocumentType.image) {
      return ColoredBox(
        color: AppTheme.surfaceStrong,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          cacheWidth: 400,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      );
    }
    if (document.type == DocumentType.pdf) {
      return _PdfThumbnail(path: path, fallback: fallback);
    }
    return fallback;
  }
}

class _PdfThumbnail extends StatelessWidget {
  const _PdfThumbnail({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: ThumbnailCache.instance.pdfThumbnail(path),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          return snapshot.connectionState == ConnectionState.done
              ? fallback
              : const ColoredBox(color: Color(0xFFF4F5F7));
        }
        return ColoredBox(
          color: Colors.white,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            cacheWidth: 360,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => fallback,
          ),
        );
      },
    );
  }
}

/// A paper-like page: the first lines of the document's extracted text
/// when there is any, otherwise just the file type.
class _TextPagePreview extends StatelessWidget {
  const _TextPagePreview({required this.document});

  final DocumentFile document;

  @override
  Widget build(BuildContext context) {
    final color = documentTypeColor(document.type);
    final raw = document.ocrText?.trim();
    // Only the first lines are visible; laying out 20k chars per card was
    // a big part of the gallery's scroll jank.
    final text = raw == null || raw.length <= 320 ? raw : raw.substring(0, 320);
    return Container(
      color: const Color(0xFFF4F5F7),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(documentTypeIcon(document.type), color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                documentTypeLabel(document.type),
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: text == null || text.isEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final factor in const [1.0, 0.8, 0.92, 0.6, 0.85])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: FractionallySizedBox(
                            widthFactor: factor,
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDADDE2),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : Text(
                    text,
                    maxLines: 14,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      color: Color(0xFF454B55),
                      fontSize: 7.5,
                      height: 1.35,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// No disk check here: this runs for every visible card on every rebuild,
/// and a missing file already falls back through the image error builders.
String? _existingLocalPath(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('file://')) {
    return Uri.tryParse(path)?.toFilePath() ?? path;
  }
  return path;
}
