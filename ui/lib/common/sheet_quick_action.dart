import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One round shortcut in the row of main actions at the top of a bottom
/// sheet (document actions, "+ Add"); the less used options go in a list
/// below it.
class SheetQuickAction extends StatelessWidget {
  const SheetQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Small muted line under the label (e.g. an account's status).
  final String? caption;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppTheme.destructive : AppTheme.primarySoft;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: destructive ? AppTheme.destructive : AppTheme.text,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 2),
                Text(
                  caption!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
