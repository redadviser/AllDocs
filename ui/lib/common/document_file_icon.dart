import 'package:flutter/material.dart';

import '../models/models.dart';

/// Small file-type badge: tinted square with the type's icon and label.
class DocumentFileIcon extends StatelessWidget {
  const DocumentFileIcon({super.key, required this.type, this.size = 48});

  final DocumentType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = documentTypeColor(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(documentTypeIcon(type), color: color, size: size * 0.42),
          if (size >= 40) ...[
            const SizedBox(height: 1),
            Text(
              documentTypeLabel(type),
              style: TextStyle(
                color: color,
                fontSize: size * 0.18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String documentTypeLabel(DocumentType type) {
  return switch (type) {
    DocumentType.pdf => 'PDF',
    DocumentType.word => 'DOC',
    DocumentType.excel => 'XLS',
    DocumentType.presentation => 'PPT',
    DocumentType.archive => 'ZIP',
    DocumentType.image => 'IMG',
  };
}

/// Muted per-type colours — enough to tell types apart at a glance without
/// turning the gallery into a rainbow.
Color documentTypeColor(DocumentType type) {
  return switch (type) {
    DocumentType.pdf => const Color(0xFFE06A5F),
    DocumentType.word => const Color(0xFF6A9AE8),
    DocumentType.excel => const Color(0xFF5DB37E),
    DocumentType.presentation => const Color(0xFFE09A55),
    DocumentType.archive => const Color(0xFF9AA1AB),
    DocumentType.image => const Color(0xFFA487DE),
  };
}

IconData documentTypeIcon(DocumentType type) {
  return switch (type) {
    DocumentType.pdf => Icons.picture_as_pdf_outlined,
    DocumentType.word => Icons.description_outlined,
    DocumentType.excel => Icons.table_chart_outlined,
    DocumentType.presentation => Icons.slideshow_outlined,
    DocumentType.archive => Icons.folder_zip_outlined,
    DocumentType.image => Icons.image_outlined,
  };
}
