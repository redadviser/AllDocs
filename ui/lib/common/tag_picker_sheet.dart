import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/services.dart';
import '../theme/app_theme.dart';
import 'app_constants.dart';
import 'app_sheet.dart';

/// Pick the tags for a document from the ones already in use, with a search
/// box for when there are many. Typing a name that doesn't exist yet offers
/// to create it — this is the only place new tags are made. Returns the
/// picked tags, or null if dismissed.
Future<List<String>?> showTagPickerSheet(
  BuildContext context, {
  required List<String> allTags,
  required List<String> selected,
}) {
  return showAppSheet<List<String>>(
    context: context,
    builder: (context) => _TagPickerSheet(allTags: allTags, selected: selected),
  );
}

/// Strips spaces and leading '#'s from a typed tag name.
String cleanTagName(String value) =>
    value.trim().replaceFirst(RegExp(r'^#+'), '').trim();

class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({required this.allTags, required this.selected});

  final List<String> allTags;
  final List<String> selected;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final TextEditingController _search = TextEditingController();
  late final List<String> _selected = [...widget.selected];
  // Existing tags plus any the user created here, so they stay listed.
  late final List<String> _tags = [
    ...widget.allTags,
    for (final tag in widget.selected)
      if (!widget.allTags.contains(tag)) tag,
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String tag) {
    setState(() {
      _selected.contains(tag) ? _selected.remove(tag) : _selected.add(tag);
    });
  }

  void _create(String tag) {
    setState(() {
      _tags.insert(0, tag);
      _selected.add(tag);
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = cleanTagName(_search.text);
    final key = normalizeForSearch(query);
    final visible = key.isEmpty
        ? _tags
        : _tags.where((t) => normalizeForSearch(t).contains(key)).toList();
    final exists = _tags.any((t) => normalizeForSearch(t) == key);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                AppConstants.tagsChoose.tr(),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: AppConstants.tagsSearch.tr(),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (query.isEmpty) return;
                  if (!exists) {
                    _create(query);
                  } else if (visible.length == 1) {
                    _toggle(visible.first);
                    _search.clear();
                    setState(() {});
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (query.isNotEmpty && !exists)
                    ListTile(
                      leading: Icon(Icons.add_rounded, color: AppTheme.accent),
                      title: Text(
                        AppConstants.tagsCreateNamed.tr(
                          namedArgs: {'tag': query},
                        ),
                        style: TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () => _create(query),
                    ),
                  for (final tag in visible)
                    CheckboxListTile(
                      value: _selected.contains(tag),
                      onChanged: (_) => _toggle(tag),
                      secondary: const Icon(Icons.sell_outlined, size: 20),
                      title: Text('#$tag'),
                    ),
                  if (visible.isEmpty && query.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        AppConstants.tagsEmptyPicker.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.mutedText),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_selected),
                child: Text(AppConstants.tagsApply.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
