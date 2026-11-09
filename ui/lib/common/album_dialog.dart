import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/albums/hidden_albums_screen.dart' show shelfDisplayName;
import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';

/// A shelf picked in a dialog: one that exists, or a new one to make.
class ShelfChoice {
  const ShelfChoice.existing(String this.shelfId) : newShelfName = null;
  const ShelfChoice.create(String this.newShelfName) : shelfId = null;

  final String? shelfId;
  final String? newShelfName;

  /// The shelf's id, making it first if it's new (on the hidden side
  /// when [hidden]).
  Future<String?> resolve(DocumentsService service, {bool hidden = false}) {
    final name = newShelfName;
    if (name == null) return Future.value(shelfId);
    return service.createShelf(name, hidden: hidden);
  }
}

class AlbumDraft {
  const AlbumDraft({
    required this.name,
    required this.colorValue,
    required this.iconName,
    this.shelf,
  });

  final String name;
  final int colorValue;
  final String iconName;

  /// Where the album goes; null when the dialog didn't ask.
  final ShelfChoice? shelf;
}

/// Creates the album [draft] describes, on the shelf it picked (made now
/// if new). Without a pick the album goes on the first visible shelf.
Future<String?> createAlbumFromDraft(
  DocumentsService service,
  AlbumDraft draft, {
  bool hidden = false,
}) async {
  return service.createAlbum(
    await draft.shelf?.resolve(service, hidden: hidden),
    draft.name,
    colorValue: draft.colorValue,
    iconName: draft.iconName,
  );
}

/// Picks the shelf to move an album to: one of [shelves] (the album's
/// own, [currentShelfId], is ticked and can't be picked) or a new one.
Future<ShelfChoice?> showMoveToShelfDialog(
  BuildContext context, {
  required List<DocumentShelf> shelves,
  required String currentShelfId,
}) {
  return showDialog<ShelfChoice>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(AppConstants.albumsMoveToShelf.tr()),
      children: [
        for (final shelf in shelves)
          SimpleDialogOption(
            onPressed: shelf.id == currentShelfId
                ? null
                : () => Navigator.of(
                    context,
                  ).pop(ShelfChoice.existing(shelf.id)),
            child: Row(
              children: [
                Icon(
                  shelf.id == currentShelfId
                      ? Icons.check_rounded
                      : Icons.shelves,
                  size: 20,
                  color: shelf.id == currentShelfId
                      ? AppTheme.accent
                      : AppTheme.mutedText,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    shelfDisplayName(shelf),
                    style: TextStyle(
                      color: shelf.id == currentShelfId
                          ? AppTheme.mutedText
                          : AppTheme.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SimpleDialogOption(
          onPressed: () async {
            final name = await _askShelfName(context);
            if (name != null && context.mounted) {
              Navigator.of(context).pop(ShelfChoice.create(name));
            }
          },
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 20, color: AppTheme.accent),
              const SizedBox(width: 12),
              Text(
                AppConstants.docshelfNewShelf.tr(),
                style: TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<String?> _askShelfName(BuildContext context) {
  return showNameDialog(
    context,
    title: AppConstants.docshelfNewShelf.tr(),
    label: AppConstants.docshelfShelfName.tr(),
    actionLabel: AppConstants.commonCreate.tr(),
  );
}

const albumColors = [
  0xFF5B8DEF,
  0xFFD9667F,
  0xFFD6A243,
  0xFF5DB37E,
  0xFF4FAFBF,
  0xFF8D7AE0,
  0xFFD9644F,
  0xFF7D8794,
];

const albumIcons = [
  'folder',
  'person',
  'work',
  'finance',
  'school',
  'health',
  'home',
  'car',
  'receipt',
  'shield',
  'star',
  'travel',
];

IconData albumIconFor(String iconName) {
  return switch (iconName) {
    'person' => Icons.person_outline_rounded,
    'work' => Icons.business_center_outlined,
    'finance' => Icons.euro_rounded,
    'school' => Icons.school_outlined,
    'health' => Icons.health_and_safety_outlined,
    'home' => Icons.home_outlined,
    'car' => Icons.directions_car_outlined,
    'receipt' => Icons.receipt_long_outlined,
    'shield' => Icons.shield_outlined,
    'star' => Icons.star_outline_rounded,
    'travel' => Icons.flight_takeoff_rounded,
    _ => Icons.folder_outlined,
  };
}

/// Create (or, with [initial], edit) an album: name, colour and icon. With
/// [shelves] it also asks which shelf it goes on (starting on [shelfId],
/// else the album's own, else the first), or makes a new one.
Future<AlbumDraft?> showAlbumDialog(
  BuildContext context, {
  DocumentAlbum? initial,
  String? suggestedName,
  List<DocumentShelf>? shelves,
  String? shelfId,
}) {
  return showDialog<AlbumDraft>(
    context: context,
    builder: (context) => _AlbumDialog(
      initial: initial,
      suggestedName: suggestedName,
      shelves: shelves,
      shelfId: shelfId,
    ),
  );
}

Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String? actionLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(
      title: title,
      label: label,
      initial: initial,
      actionLabel: actionLabel,
    ),
  );
}

/// Owns its TextEditingController so it is disposed only when the dialog
/// is really gone. Disposing it as soon as showDialog's future completes
/// (while the exit animation still renders the TextField) crashed with
/// "_dependents.isEmpty is not true".
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initial,
    this.actionLabel,
  });

  final String title;
  final String label;
  final String initial;
  final String? actionLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    // Drop focus (and the keyboard) before the route starts closing.
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppConstants.commonCancel.tr()),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.actionLabel ?? AppConstants.commonSave.tr()),
        ),
      ],
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  bool destructive = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppConstants.commonCancel.tr()),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: AppTheme.destructive)
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

class _AlbumDialog extends StatefulWidget {
  const _AlbumDialog({
    this.initial,
    this.suggestedName,
    this.shelves,
    this.shelfId,
  });

  final DocumentAlbum? initial;
  final String? suggestedName;
  final List<DocumentShelf>? shelves;
  final String? shelfId;

  @override
  State<_AlbumDialog> createState() => _AlbumDialogState();
}

class _AlbumDialogState extends State<_AlbumDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial?.name ?? widget.suggestedName ?? '',
  );
  late int _selectedColor = widget.initial?.colorValue ?? albumColors.first;
  late String _selectedIcon = widget.initial?.iconName ?? albumIcons.first;
  late String? _selectedShelfId =
      widget.shelfId ??
      widget.initial?.shelfId ??
      widget.shelves?.firstOrNull?.id;

  /// A shelf typed in here, made only when the dialog is saved.
  String? _newShelfName;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _newShelf() async {
    final name = await _askShelfName(context);
    if (name == null || !mounted) return;
    setState(() {
      _newShelfName = name;
      _selectedShelfId = null;
    });
  }

  Widget _shelfSection(List<DocumentShelf> shelves) {
    final newName = _newShelfName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(
          AppConstants.docshelfShelf.tr(),
          style: const TextStyle(
            color: AppTheme.mutedText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final shelf in shelves)
              ChoiceChip(
                label: Text(shelfDisplayName(shelf)),
                selected: _selectedShelfId == shelf.id,
                onSelected: (_) => setState(() => _selectedShelfId = shelf.id),
              ),
            if (newName != null)
              ChoiceChip(
                avatar: const Icon(Icons.fiber_new_outlined, size: 18),
                label: Text(newName),
                selected: _selectedShelfId == null,
                onSelected: (_) => setState(() => _selectedShelfId = null),
              ),
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: Text(AppConstants.docshelfNewShelf.tr()),
              onPressed: _newShelf,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? AppConstants.docshelfNewAlbum.tr()
            : AppConstants.albumsEditAlbum.tr(),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: widget.initial == null,
              decoration: InputDecoration(
                labelText: AppConstants.docshelfAlbumName.tr(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            if (widget.shelves case final shelves?) _shelfSection(shelves),
            const SizedBox(height: 18),
            Text(
              AppConstants.docshelfColor.tr(),
              style: const TextStyle(
                color: AppTheme.mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in albumColors)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(color),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == _selectedColor
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              AppConstants.docshelfIcon.tr(),
              style: const TextStyle(
                color: AppTheme.mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final iconName in albumIcons)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _selectedIcon = iconName),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconName == _selectedIcon
                            ? Color(_selectedColor).withValues(alpha: 0.2)
                            : AppTheme.surfaceStrong,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        albumIconFor(iconName),
                        size: 20,
                        color: iconName == _selectedIcon
                            ? Color(_selectedColor)
                            : AppTheme.mutedText,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppConstants.commonCancel.tr()),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget.initial == null
                ? AppConstants.commonCreate.tr()
                : AppConstants.commonSave.tr(),
          ),
        ),
      ],
    );
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final shelfId = _selectedShelfId;
    final newShelfName = _newShelfName;
    Navigator.of(context).pop(
      AlbumDraft(
        name: name,
        colorValue: _selectedColor,
        iconName: _selectedIcon,
        shelf: widget.shelves == null
            ? null
            : shelfId != null
            ? ShelfChoice.existing(shelfId)
            : newShelfName != null
            ? ShelfChoice.create(newShelfName)
            : null,
      ),
    );
  }
}
