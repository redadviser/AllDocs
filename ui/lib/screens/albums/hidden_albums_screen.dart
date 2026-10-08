import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/album_dialog.dart';
import '../../common/app_constants.dart';
import '../../common/document_actions.dart' show showSnack;
import '../../common/plan_prompts.dart';
import '../../common/snapshot_builder.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import '../auth/security_gate.dart';
import 'albums_screen.dart';

/// A shelf's name as shown: "Hidden" is named in the app's language.
String shelfDisplayName(DocumentShelf shelf) =>
    shelf.isDefaultHidden ? AppConstants.hiddenDefaultShelf.tr() : shelf.name;

/// Asks for the hidden albums' PIN (or has one chosen, the first time),
/// then opens the hidden shelves.
Future<void> openHiddenAlbums(
  BuildContext context,
  DocumentsService documentsService,
) async {
  final hasPin = await HiddenAlbumsLock.hasPin();
  if (!context.mounted) return;
  final unlocked = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => HiddenAlbumsPinScreen(create: !hasPin)),
  );
  if (unlocked != true || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: AlbumsScreen(documentsService: documentsService, hidden: true),
        ),
      ),
    ),
  );
}

/// Hides [album] (Folio and up; the PIN is chosen the first time) — onto
/// the hidden shelf it came from, or "Hidden" — or shows it again: back on
/// the shelf it came from, or one the user picks if it was made hidden.
/// Returns whether it moved. Showing is never gated: nobody loses their
/// albums by changing plan.
Future<bool> setAlbumHiddenFlow(
  BuildContext context,
  DocumentsService documentsService,
  DocumentAlbum album, {
  required bool hidden,
}) async {
  if (hidden) {
    if (!PlanService.current.value.has(PlanFeature.hiddenAlbums)) {
      await showPlansPrompt(
        context,
        title: AppConstants.hiddenTitle.tr(),
        message: AppConstants.hiddenLocked.tr(),
      );
      return false;
    }
    if (!await HiddenAlbumsLock.hasPin()) {
      if (!context.mounted) return false;
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const HiddenAlbumsPinScreen(create: true),
        ),
      );
      if (created != true) return false;
    }
    await documentsService.hideAlbum(album.id);
    if (context.mounted) {
      showSnack(context, AppConstants.hiddenHiddenDone.tr());
    }
    return true;
  }

  var shelfId = await documentsService.unhideDestination(album.id);
  if (shelfId == null) {
    if (!context.mounted) return false;
    shelfId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _ShelfChooserScreen(
          documentsService: documentsService,
          album: album,
        ),
      ),
    );
    if (shelfId == null) return false;
  }
  await documentsService.moveAlbumToShelf(album.id, shelfId);
  final shelf = (await documentsService.loadSnapshot()).shelfById(shelfId);
  if (context.mounted) {
    showSnack(
      context,
      shelf == null
          ? AppConstants.hiddenUnhiddenDone.tr()
          : AppConstants.hiddenMovedTo.tr(
              namedArgs: {'shelf': shelfDisplayName(shelf)},
            ),
    );
  }
  return true;
}

/// Picks the visible shelf an album made on the hidden side goes to (or
/// starts a new one). Pops with the shelf id.
class _ShelfChooserScreen extends StatelessWidget {
  const _ShelfChooserScreen({
    required this.documentsService,
    required this.album,
  });

  final DocumentsService documentsService;
  final DocumentAlbum album;

  Future<void> _newShelf(BuildContext context) async {
    final name = await showNameDialog(
      context,
      title: AppConstants.docshelfNewShelf.tr(),
      label: AppConstants.docshelfShelfName.tr(),
      actionLabel: AppConstants.commonCreate.tr(),
    );
    if (name == null) return;
    final before = {
      for (final shelf in (await documentsService.loadSnapshot()).shelves)
        shelf.id,
    };
    await documentsService.createShelf(name);
    final created = (await documentsService.loadSnapshot()).shelves
        .where((shelf) => !before.contains(shelf.id))
        .firstOrNull;
    if (created != null && context.mounted) {
      Navigator.of(context).pop(created.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SnapshotBuilder(
          documentsService: documentsService,
          builder: (context, snapshot) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  const BackButton(),
                  Expanded(
                    child: Text(
                      AppConstants.hiddenChooseShelf.tr(),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                child: Row(
                  children: [
                    Icon(
                      albumIconFor(album.iconName),
                      color: Color(album.colorValue),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppConstants.hiddenChooseShelfHint.tr(),
                        style: const TextStyle(
                          color: AppTheme.mutedText,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final shelf in snapshot.shelves) ...[
                _ShelfOption(
                  icon: Icons.shelves,
                  title: shelfDisplayName(shelf),
                  subtitle: [
                    for (final album in shelf.albums) album.name,
                  ].join(' · '),
                  onTap: () => Navigator.of(context).pop(shelf.id),
                ),
                const SizedBox(height: 10),
              ],
              _ShelfOption(
                icon: Icons.add_rounded,
                title: AppConstants.docshelfNewShelf.tr(),
                accent: true,
                onTap: () => _newShelf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfOption extends StatelessWidget {
  const _ShelfOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle = '',
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent
          ? AppTheme.accent.withValues(alpha: 0.12)
          : AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Icon(
                icon,
                color: accent ? AppTheme.accent : AppTheme.primarySoft,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: accent ? AppTheme.accent : AppTheme.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.mutedText),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.dimText),
            ],
          ),
        ),
      ),
    );
  }
}
