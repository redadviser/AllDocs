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
import 'album_detail_screen.dart';

/// Asks for the hidden albums' PIN (or has one chosen, the first time),
/// then opens them.
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
      builder: (_) => HiddenAlbumsScreen(documentsService: documentsService),
    ),
  );
}

/// Hides [album] behind the hidden-albums PIN (Folio and up; the PIN is
/// chosen the first time), or puts it back on its shelf. Returns whether it
/// changed. Showing it again is never gated: nobody loses their albums by
/// changing plan.
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
  }
  await documentsService.setAlbumHidden(album.id, hidden);
  if (context.mounted) {
    showSnack(
      context,
      (hidden ? AppConstants.hiddenHiddenDone : AppConstants.hiddenUnhiddenDone)
          .tr(),
    );
  }
  return true;
}

class HiddenAlbumsScreen extends StatelessWidget {
  const HiddenAlbumsScreen({super.key, required this.documentsService});

  final DocumentsService documentsService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SnapshotBuilder(
          documentsService: documentsService,
          builder: (context, snapshot) {
            final albums = snapshot.hiddenAlbums;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
                    child: Row(
                      children: [
                        const BackButton(),
                        const Icon(
                          Icons.visibility_off_rounded,
                          color: AppTheme.premium,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          AppConstants.hiddenTitle.tr(),
                          style: const TextStyle(
                            color: AppTheme.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (albums.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          AppConstants.hiddenEmpty.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.mutedText,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: albums.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final album = albums[index];
                        final count = snapshot
                            .documentsForAlbum(album.id)
                            .length;
                        return _HiddenAlbumTile(
                          album: album,
                          count: count,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AlbumDetailScreen(
                                documentsService: documentsService,
                                albumId: album.id,
                              ),
                            ),
                          ),
                          onUnhide: () => setAlbumHiddenFlow(
                            context,
                            documentsService,
                            album,
                            hidden: false,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HiddenAlbumTile extends StatelessWidget {
  const _HiddenAlbumTile({
    required this.album,
    required this.count,
    required this.onTap,
    required this.onUnhide,
  });

  final DocumentAlbum album;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onUnhide;

  @override
  Widget build(BuildContext context) {
    final color = Color(album.colorValue);
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(albumIconFor(album.iconName), color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.name,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppConstants.hiddenCount.tr(
                        namedArgs: {'count': '$count'},
                      ),
                      style: const TextStyle(color: AppTheme.mutedText),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppConstants.hiddenUnhide.tr(),
                icon: const Icon(Icons.visibility_outlined),
                onPressed: onUnhide,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
