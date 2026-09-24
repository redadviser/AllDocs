import 'package:flutter/material.dart';

/// Bottom sheet for a list of options. A plain `showModalBottomSheet` caps
/// its height at about half the screen and doesn't scroll, so the last
/// options (often the destructive ones) were cut off; and its bottom edge
/// sits under the system navigation bar. This one grows with its content up
/// to 90% of the screen, scrolls past that, and keeps the last row above
/// the navigation bar.
Future<T?> showOptionsSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: backgroundColor,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(child: builder(context)),
    ),
  );
}

/// Bottom sheet whose content lays itself out (its own list, fixed footer
/// buttons...). Like [showOptionsSheet] it can grow past half the screen
/// and stays clear of the system navigation bar, but it adds no scrolling.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    isDismissible: isDismissible,
    builder: (context) => SafeArea(top: false, child: builder(context)),
  );
}
