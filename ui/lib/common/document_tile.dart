import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'app_constants.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'document_file_icon.dart';

class DocumentTile extends StatelessWidget {
  const DocumentTile({
    super.key,
    required this.document,
    this.showFavoriteMarker = false,
    this.showImportedStatus = false,
    this.trailing,
    this.onTap,
  });

  final DocumentFile document;
  final bool showFavoriteMarker;
  final bool showImportedStatus;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final validityDate = document.validityDate;
    final metaParts = [
      documentTypeLabel(document.type),
      document.dateLabel,
      if (document.timeLabel != null) document.timeLabel!,
      document.sizeLabel,
      if (validityDate != null)
        AppConstants.remindersDueLabel.tr(
          namedArgs: {'date': DateFormat.yMMMd().format(validityDate)},
        ),
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (showFavoriteMarker) ...[
              const Icon(Icons.star_rounded, color: AppTheme.warning, size: 24),
              const SizedBox(width: 10),
            ],
            DocumentFileIcon(type: document.type, size: 36),
            const SizedBox(width: 10),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metaParts.join('  •  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.mutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (showImportedStatus)
              const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.success,
                size: 24,
              )
            else if (trailing != null)
              trailing!
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}
