import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// Pieces of the bookshelf look (albums as book spines on wooden shelves),
/// shared by the albums screen and the "add to albums" picker.
const double albumSpineWidth = 34;
const int maxSpineTitleLength = 25;

/// An album as a book spine standing on a shelf. [selected] is for pickers:
/// true lifts the book and ticks it, false dims it, null (the albums screen)
/// shows it plain with its document count.
class AlbumSpine extends StatelessWidget {
  const AlbumSpine({
    super.key,
    required this.album,
    required this.count,
    this.selected,
  });

  final DocumentAlbum album;
  final int count;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final color = Color(album.colorValue);
    final raw = album.name.trim().toUpperCase();
    final name = raw.length > maxSpineTitleLength
        ? raw.substring(0, maxSpineTitleLength)
        : raw;
    final fontSize = name.length <= 10
        ? 8.0
        : name.length <= 15
        ? 7.6
        : name.length <= 20
        ? 7.2
        : 6.8;

    final spine = Container(
      width: albumSpineWidth,
      height: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 8,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.lerp(color, Colors.white, 0.06)!,
                  color,
                  Color.lerp(color, Colors.black, 0.18)!,
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 9,
            right: 9,
            child: Container(
              height: 1.2,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 9,
            right: 9,
            child: Container(
              height: 1.2,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          Center(
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.94),
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: name.length > 18 ? 0.28 : 0.42,
                  shadows: const [
                    Shadow(
                      color: Color(0x55000000),
                      offset: Offset(0.8, 0.8),
                      blurRadius: 1.6,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (selected == true)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            )
          else if (count > 0)
            Positioned(
              top: -6,
              right: -6,
              child: AlbumCountBadge(count: count, height: 18, fontSize: 9),
            ),
        ],
      ),
    );
    if (selected == null) return spine;
    // Picked books are pulled up off the shelf, the others fade back.
    return AnimatedOpacity(
      opacity: selected! ? 1 : 0.55,
      duration: const Duration(milliseconds: 160),
      child: AnimatedPadding(
        padding: EdgeInsets.only(
          top: selected! ? 0 : 10,
          bottom: selected! ? 10 : 0,
        ),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: spine,
      ),
    );
  }
}

/// Small round count (or tick) badge on an album.
class AlbumCountBadge extends StatelessWidget {
  const AlbumCountBadge({
    super.key,
    required this.count,
    required this.height,
    required this.fontSize,
  });

  final int count;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      constraints: BoxConstraints(minWidth: height),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        count > 999 ? '999+' : '$count',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A single shelf lane with its wooden plank, holding [child] (usually a
/// horizontal list of [AlbumSpine]s).
class BookshelfLane extends StatelessWidget {
  const BookshelfLane({super.key, required this.child, this.height = 130});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height + 20,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.shelfEdge.withValues(alpha: 0.8)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(AppTheme.shelfSurface, AppTheme.shelfBack, 0.55)!,
            AppTheme.shelfBack,
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Positioned.fill(bottom: 20, child: child),
            // The wooden plank the books stand on.
            Positioned(
              left: 6,
              right: 6,
              bottom: 5,
              child: Container(
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(
                        AppTheme.shelfSurface,
                        AppTheme.shelfBack,
                        0.35,
                      )!,
                      Color.lerp(AppTheme.shelfBack, AppTheme.shelfEdge, 0.2)!,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 4,
                color: AppTheme.shelfEdge.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
