import 'package:flutter/material.dart';

import '../models/models.dart';

class DocumentFileIcon extends StatelessWidget {
  const DocumentFileIcon({super.key, required this.type, this.size = 48});

  final DocumentType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size + 8,
      decoration: BoxDecoration(
        color: _colorFor(type),
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: _colorFor(type).withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: CustomPaint(
              size: Size(size * 0.3, size * 0.3),
              painter: _FoldPainter(color: Colors.white.withValues(alpha: 0.3)),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_iconFor(type), color: Colors.white, size: size * 0.36),
                const SizedBox(height: 3),
                Text(
                  _labelFor(type),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String documentTypeLabel(DocumentType type) {
  return switch (type) {
    DocumentType.pdf => 'PDF',
    DocumentType.word => 'DOCX',
    DocumentType.excel => 'XLSX',
    DocumentType.image => 'JPG',
  };
}

Color _colorFor(DocumentType type) {
  return switch (type) {
    DocumentType.pdf => const Color(0xFFD94343),
    DocumentType.word => const Color(0xFF2D7BD8),
    DocumentType.excel => const Color(0xFF2F9A43),
    DocumentType.image => const Color(0xFF7E45D8),
  };
}

IconData _iconFor(DocumentType type) {
  return switch (type) {
    DocumentType.pdf => Icons.picture_as_pdf_rounded,
    DocumentType.word => Icons.description_rounded,
    DocumentType.excel => Icons.table_chart_rounded,
    DocumentType.image => Icons.image_rounded,
  };
}

String _labelFor(DocumentType type) {
  return documentTypeLabel(type);
}

class _FoldPainter extends CustomPainter {
  const _FoldPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FoldPainter oldDelegate) {
    return color != oldDelegate.color;
  }
}
