part of '../clean_player_theme.dart';

/// Left-aligned title/artist block plus the frosted action circles.
///
/// Extracted so the layout composition in [CleanPlayerTheme] reads as structure
/// rather than text styling — the hardcoded whites hid here, not in the layout.
class _CleanTrackHeader extends StatelessWidget {
  final PlayerThemeProps props;
  final PlayerThemeMetrics metrics;
  final double horizontalPadding;
  final bool hasDownload;

  const _CleanTrackHeader({
    required this.props,
    required this.metrics,
    required this.horizontalPadding,
    required this.hasDownload,
  });

  @override
  Widget build(BuildContext context) {
    final song = props.state.currentSong;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final deck = _CleanDeckColors.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarqueeText(
                  text: song?.title ?? context.l10n.noTrackSelected,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    color: deck.primary,
                    fontSize:
                        (metrics.titleFontSize + 2.0).clamp(16.0, 24.0),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  song?.artist ?? context.l10n.unknownArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: deck.secondary,
                    fontSize:
                        (metrics.artistFontSize + 1.0).clamp(12.0, 16.5),
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Action buttons on right: Download / Add to Playlist, Star (Favorite)
          // & More (...)
          if (song != null) ...[
            if (hasDownload)
              _CleanActionCircleButton(
                tooltip: context.l10n.downloadLabel,
                child: YtmDownloadButton(
                  song: song,
                  activeColor: activeColor,
                  iconColor: deck.primary,
                  iconSize: 19,
                ),
              )
            else
              _CleanActionCircleButton(
                icon: Icons.playlist_add_rounded,
                iconColor: deck.primary,
                tooltip: context.l10n.addToPlaylist,
                onTap: () {
                  PulsrHaptics.lightImpact();
                  AddToPlaylistSheet.show(context, song: song);
                },
              ),
            const SizedBox(width: 8),
          ],
          _CleanActionCircleButton(
            icon: (song?.isFavorite == true)
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            iconColor: (song?.isFavorite == true)
                ? AppColors.amberDeep
                : deck.primary,
            tooltip: (song?.isFavorite == true)
                ? context.l10n.unlike
                : context.l10n.like,
            onTap: () {
              if (song != null) {
                PulsrHaptics.selection();
                cubit.toggleFavorite(song.id);
              }
            },
          ),
          const SizedBox(width: 8),
          _CleanActionCircleButton(
            icon: Icons.more_horiz_rounded,
            iconColor: deck.primary,
            tooltip: context.l10n.moreOptions,
            onTap: () {
              if (song != null) {
                PulsrHaptics.lightImpact();
                SongOptionsSheet.show(context, song: song);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Circular frosted translucent button matching the reference photo (Star and
/// More ...).
///
/// The visible circle stays 36 dp so the header keeps its Apple-tight rhythm,
/// but the tap target is padded out to [AppSpacing.minTouchTarget] (48 dp): a
/// 36 dp `InkWell` misses the Android accessibility minimum, and these circles
/// sit in the hardest-to-reach strip of the screen.
class _CleanActionCircleButton extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final Color? iconColor;
  final String tooltip;
  final VoidCallback? onTap;

  const _CleanActionCircleButton({
    this.icon,
    this.child,
    this.iconColor,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final deck = _CleanDeckColors.of(context);
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: AppSpacing.minTouchTarget,
            height: AppSpacing.minTouchTarget,
            child: Center(
              child: Ink(
                width: _cleanActionCircleSize,
                height: _cleanActionCircleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: deck.frostedFill,
                ),
                child: Center(
                  child: child ??
                      Icon(icon, size: 20, color: iconColor ?? deck.primary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
