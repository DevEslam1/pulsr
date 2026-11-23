part of '../clean_player_theme.dart';

/// Left-aligned bold track title & artist block with frosted Favorite & More
/// action buttons (and Download when streaming a remote track).
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
    final isFavorite = song?.isFavorite == true;

    final double titleFontSize = metrics.isTablet
        ? AppFontSize.headline
        : (metrics.isVeryShortHeight
            ? AppFontSize.title
            : AppFontSize.titleLarge);
    final double artistFontSize = metrics.isTablet
        ? AppFontSize.bodyLarge
        : (metrics.isVeryShortHeight
            ? AppFontSize.bodySmall
            : AppFontSize.callout);

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
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: AppTracking.heading,
                    height: 1.18,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  song?.artist ?? context.l10n.unknownArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: deck.secondary,
                    fontSize: artistFontSize,
                    fontWeight: FontWeight.w500,
                    letterSpacing: AppTracking.title,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (hasDownload && song != null)
            _CleanActionCircleButton(
              tooltip: context.l10n.downloadLabel,
              child: YtmDownloadButton(
                song: song,
                activeColor: activeColor,
                iconColor: deck.primary,
                iconSize: 19,
              ),
            ),
          _CleanActionCircleButton(
            icon: isFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            iconColor: isFavorite ? context.palette.favorite : deck.primary,
            isToggled: isFavorite,
            tooltip: isFavorite ? context.l10n.unlike : context.l10n.like,
            onTap: song == null
                ? null
                : () {
                    PulsrHaptics.selection();
                    cubit.toggleFavorite(song.id);
                  },
          ),
          _CleanActionCircleButton(
            icon: Icons.more_horiz_rounded,
            iconColor: deck.primary,
            tooltip: context.l10n.moreOptions,
            onTap: song == null
                ? null
                : () {
                    PulsrHaptics.lightImpact();
                    SongOptionsSheet.show(context, song: song);
                  },
          ),
        ],
      ),
    );
  }
}

/// Accessible >= 48dp frosted circular action button with 36dp visual disc.
class _CleanActionCircleButton extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final Color? iconColor;
  final bool isToggled;
  final String tooltip;
  final VoidCallback? onTap;

  const _CleanActionCircleButton({
    this.icon,
    this.child,
    this.iconColor,
    this.isToggled = false,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final deck = _CleanDeckColors.of(context);
    return Semantics(
      button: true,
      toggled: isToggled,
      enabled: onTap != null || child != null,
      label: tooltip,
      excludeSemantics: child == null,
      child: Material(
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
                    border: Border.all(
                      color: deck.frostedBorder,
                      width: 0.8,
                    ),
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
      ),
    );
  }
}
