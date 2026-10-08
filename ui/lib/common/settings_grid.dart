import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// The settings-style screens (profile, connections) share AllPhotos' layout:
// a titled card per section and its options two per row. A section holds an
// even number of options (2 or 4) so no row is left half empty.

class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: child,
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// [children] two per row (four per row on a wide screen when
/// [wideColumns] is 4). With an odd count, the last one takes a whole row
/// rather than leaving a hole.
class SettingsGrid extends StatelessWidget {
  const SettingsGrid({
    super.key,
    required this.children,
    this.spacing = 8,
    this.wideColumns = 2,
    this.square = false,
  }) : assert(
         !square || children.length % 2 == 0,
         'Square grids hold an even number of options',
       );

  final List<Widget> children;
  final double spacing;
  final int wideColumns;

  /// Square cells instead of the children's own height.
  final bool square;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? wideColumns : 2;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < children.length; i++)
              SizedBox(
                width: i == children.length - 1 && children.length.isOdd
                    ? constraints.maxWidth
                    : width,
                child: square
                    ? AspectRatio(aspectRatio: 1, child: children[i])
                    : children[i],
              ),
          ],
        );
      },
    );
  }
}

class _GridTileFrame extends StatelessWidget {
  const _GridTileFrame({
    required this.child,
    this.onTap,
    this.destructive = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceStrong.withValues(
        alpha: onTap == null ? 0.32 : 0.56,
      ),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: destructive
                  ? AppTheme.destructive.withValues(alpha: 0.42)
                  : AppTheme.border,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// An option that opens something: icon over its name (and current value).
class SettingsGridAction extends StatelessWidget {
  const SettingsGridAction({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.iconColor,
    this.destructive = false,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String? value;

  /// Null greys the option out.
  final VoidCallback? onTap;
  final Color? iconColor;
  final bool destructive;

  /// A spinner in place of the icon while the option's work runs.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppTheme.destructive
        : iconColor ?? AppTheme.accent;
    return _GridTileFrame(
      onTap: onTap,
      destructive: destructive,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
            )
          else
            Icon(icon, size: 24, color: color),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: value == null ? 2 : 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: destructive ? AppTheme.destructive : AppTheme.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.08,
            ),
          ),
          if (value != null) ...[
            const SizedBox(height: 3),
            Text(
              value!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.accent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// An on/off option: icon and switch over its name.
class SettingsGridToggle extends StatelessWidget {
  const SettingsGridToggle({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return _GridTileFrame(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 24, color: AppTheme.accent),
              const Spacer(),
              SizedBox(
                height: 28,
                child: FittedBox(
                  child: Switch(value: value, onChanged: onChanged),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.08,
            ),
          ),
        ],
      ),
    );
  }
}
