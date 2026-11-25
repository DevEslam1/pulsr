// lib/core/widgets/song_tile.dart
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../core/utils/formatters.dart';
import '../../data/db/app_database.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../../features/player/cubit/player_state.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import '../utils/l10n_extensions.dart';
import '../utils/track_display_info.dart';
import 'cached_artwork.dart';
import 'gesture_hint_overlay.dart';
import 'pulsr_pressable.dart';

/// {@category DesignSystem}
/// The universal premium song row. Auto-highlights the active track with an
/// animated EQ indicator and left accent bar.
class SongTile extends StatefulWidget {
  final SongsTableData song;
  final VoidCallback onTap;
  final VoidCallback? onMorePressed;
  final String? subtitleOverride;
  final int? index;
  final bool showArtwork;
  final double artworkSize;
  final bool selected;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool? isDownloaded;
  final Color? backgroundColor;
  final bool dense;

  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.onMorePressed,
    this.subtitleOverride,
    this.index,
    this.showArtwork = true,
    this.artworkSize = 52,
    this.selected = false,
    this.onLongPress,
    this.trailing,
    this.isDownloaded,
    this.backgroundColor,
    this.dense = false,
  });

  @override
  State<SongTile> createState() => _SongTileState();
}

class _SongTileState extends State<SongTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final song = widget.song;
    final displayInfo = TrackDisplayInfo.resolve(
      rawTitle: song.title,
      rawArtist: song.artist,
    );
    final isCompact = MediaQuery.sizeOf(context).width < 360;
    final baseArtwork = widget.dense ? 44.0 : widget.artworkSize;
    final effectiveArtworkSize =
        isCompact ? (baseArtwork * 0.88).clamp(40.0, 52.0) : baseArtwork;

    final isDownloadedTrack = widget.isDownloaded ??
        (song.isDownloaded == true ||
            (song.source == SongSource.local &&
                song.remoteId != null &&
                song.remoteId!.isNotEmpty));

    return BlocSelector<PlayerCubit, PlayerState,
        ({bool isActive, bool isPlaying})>(
      selector: (state) {
        final isActive = state.currentSong?.id == song.id;
        return (isActive: isActive, isPlaying: isActive && state.isPlaying);
      },
      builder: (context, playback) {
        final isActive = playback.isActive;
        final isPlaying = playback.isPlaying;

        final resolvedBg = widget.backgroundColor ??
            (widget.selected
                ? p.accentSoft
                : (isActive
                    ? Color.alphaBlend(
                        p.accent.withValues(alpha: p.isDark ? 0.12 : 0.08),
                        p.surfaceContainer.withValues(alpha: 0.75),
                      )
                    : (_hovered
                        ? p.surfaceContainer.withValues(alpha: 0.55)
                        : Colors.transparent)));

        final materialRow = Container(
          decoration: BoxDecoration(
            color: resolvedBg,
            borderRadius: AppRadii.r16All,
            border: Border.all(
              color: widget.selected
                  ? (p.isHighContrast
                      ? p.accent
                      : p.accent.withValues(alpha: 0.55))
                  : (isActive
                      ? p.accent.withValues(
                          alpha: p.isHighContrast
                              ? 0.85
                              : (p.isDark ? 0.28 : 0.22),
                        )
                      : (_hovered ? p.borderSubtle : Colors.transparent)),
              width:
                  (widget.selected || isActive) && p.isHighContrast ? 1.5 : 1.0,
            ),
            boxShadow: isPlaying && p.chromeGlowScale > 0
                ? [
                    BoxShadow(
                      color: p.accent.withValues(
                        alpha: (p.isDark ? 0.14 : 0.08) * p.chromeGlowScale,
                      ),
                      blurRadius: 14,
                      spreadRadius: -2,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : double.infinity;
              final isTileNarrow = availableWidth < 280;
              final isTileUltraNarrow = availableWidth < 180;
              final isTileMicro = availableWidth < 120;
              final padH = isTileMicro
                  ? AppSpacing.xxs
                  : (isTileUltraNarrow ? AppSpacing.s6 : AppSpacing.s10);

              final showIndex = !isTileUltraNarrow && widget.index != null;
              final showArtworkInTile =
                  widget.showArtwork && (!isTileMicro || availableWidth >= 70);
              final showDurationInTile = !isTileNarrow && song.durationMs > 0;
              final showTrailingInTile = !isTileUltraNarrow &&
                  (widget.trailing != null || widget.onMorePressed != null);

              final double effectiveArtwork = isTileMicro
                  ? 32.0
                  : (isTileUltraNarrow
                      ? 36.0
                      : (isTileNarrow
                          ? (baseArtwork * 0.85).clamp(36.0, 44.0)
                          : effectiveArtworkSize));
              final double spacingArtwork = isTileMicro
                  ? 4.0
                  : (isTileUltraNarrow ? 6.0 : (isCompact ? 8.0 : 12.0));
              final double artRadius = effectiveArtwork > 36 ? 12.0 : 8.0;

              final vPad = widget.dense ? AppSpacing.s2 : AppSpacing.s6;
              return Container(
                constraints: BoxConstraints(
                    minHeight: widget.dense
                        ? AppSpacing.minTouchTarget
                        : (isTileNarrow ? 50 : 58)),
                padding: EdgeInsetsDirectional.fromSTEB(
                  padH,
                  vPad,
                  showTrailingInTile ? AppSpacing.xxs : padH,
                  vPad,
                ),
                child: ClipRect(
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          label: context.l10n.songByArtist(
                              displayInfo.title, displayInfo.artist),
                          selected: isActive || widget.selected,
                          button: true,
                          excludeSemantics: true,
                          child: PulsrPressable(
                            pressedScale: 0.985,
                            focusBorderRadius: AppRadii.r16All,
                            onTap: widget.onTap,
                            onLongPress: widget.onLongPress,
                            child: Row(
                              children: [
                                // Active playback vertical pill indicator (when no artwork is shown or in indexed lists)
                                if (isActive &&
                                    !showArtworkInTile &&
                                    !isTileMicro) ...[
                                  Container(
                                    width: 3.5,
                                    height: 22,
                                    margin: const EdgeInsetsDirectional.only(
                                        end: AppSpacing.xs),
                                    decoration: BoxDecoration(
                                      color: p.accent,
                                      borderRadius: AppRadii.full,
                                    ),
                                  ),
                                ],
                                if (showIndex)
                                  SizedBox(
                                    width: isCompact ? 24 : 32,
                                    child: Center(
                                      child: isActive && !showArtworkInTile
                                          ? NowPlayingIndicator(
                                              color: p.accent,
                                              isPlaying: isPlaying)
                                          : Text(
                                              '${widget.index! + 1}',
                                              style: TextStyle(
                                                color: isActive
                                                    ? p.accent
                                                    : p.textTertiary,
                                                fontWeight: isActive
                                                    ? FontWeight.w800
                                                    : FontWeight.w700,
                                                fontSize: isCompact
                                                    ? AppFontSize.label
                                                    : AppFontSize.bodySmall,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures()
                                                ],
                                              ),
                                            ),
                                    ),
                                  ),
                                if (showArtworkInTile) ...[
                                  SizedBox(
                                    width: effectiveArtwork,
                                    height: effectiveArtwork,
                                    child: widget.selected
                                        ? Container(
                                            decoration: BoxDecoration(
                                              color: p.accent,
                                              borderRadius:
                                                  AppRadii.circular(artRadius),
                                            ),
                                            child: Icon(
                                              Icons.check_rounded,
                                              color: p.onAccent,
                                              size: effectiveArtwork > 36
                                                  ? 22
                                                  : 18,
                                            ),
                                          )
                                        : DecoratedBox(
                                            position:
                                                DecorationPosition.foreground,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  AppRadii.circular(artRadius),
                                              border: Border.all(
                                                color: isActive
                                                    ? p.accent.withValues(
                                                        alpha: p.isHighContrast
                                                            ? 0.90
                                                            : 0.65,
                                                      )
                                                    : (p.isDark
                                                        ? AppColors.specularAt(
                                                            p.isAmoled
                                                                ? 0.14
                                                                : 0.10,
                                                          )
                                                        : p.hairline),
                                                width: isActive ? 1.4 : 0.8,
                                              ),
                                            ),
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                CachedArtwork(
                                                  id: song.id,
                                                  remoteUrl:
                                                      song.remoteArtworkUrl ??
                                                          song.artworkUri,
                                                  albumId: song.albumId,
                                                  type: ArtworkType.AUDIO,
                                                  size: effectiveArtwork,
                                                  borderRadius: artRadius,
                                                  title: displayInfo.title,
                                                  artist: displayInfo.artist,
                                                ),
                                                if (isActive)
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: AppColors.scrimAt(
                                                          0.56),
                                                      borderRadius:
                                                          AppRadii.circular(
                                                              artRadius),
                                                    ),
                                                    child: Center(
                                                      child:
                                                          NowPlayingIndicator(
                                                        color: p.isDark
                                                            ? p.accent
                                                            : Colors.white,
                                                        isPlaying: isPlaying,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                  ),
                                  SizedBox(width: spacingArtwork),
                                ],
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, textConstraints) {
                                      final textScale =
                                          MediaQuery.textScalerOf(context)
                                              .scale(1.0);
                                      final titleFontSize =
                                          isCompact || isTileNarrow
                                              ? AppFontSize.bodySmall
                                              : AppFontSize.body;
                                      final content = SizedBox(
                                        width: textConstraints.maxWidth,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              displayInfo.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isActive
                                                    ? p.accent
                                                    : p.textPrimary,
                                                fontWeight: isActive
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                                letterSpacing:
                                                    AppTracking.title,
                                                fontSize: titleFontSize,
                                                height: 1.25,
                                              ),
                                            ),
                                            const SizedBox(
                                                height: AppSpacing.s2),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                if (isDownloadedTrack) ...[
                                                  Container(
                                                    width: isCompact ? 14 : 15,
                                                    height: isCompact ? 14 : 15,
                                                    decoration: BoxDecoration(
                                                      color:
                                                          p.accent.withValues(
                                                        alpha: p.isDark
                                                            ? 0.16
                                                            : 0.14,
                                                      ),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Icon(
                                                      Icons
                                                          .arrow_downward_rounded,
                                                      size: isCompact
                                                          ? 9.5
                                                          : 10.5,
                                                      color: p.accent,
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                      width: AppSpacing.s6),
                                                ],
                                                Expanded(
                                                  child: Text(
                                                    widget.subtitleOverride ??
                                                        displayInfo.artist,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: isActive
                                                          ? (p.isHighContrast
                                                              ? p.textPrimary
                                                              : p.textPrimary
                                                                  .withValues(
                                                                      alpha:
                                                                          0.80))
                                                          : p.textSecondary,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontSize:
                                                          AppFontSize.label,
                                                      height: 1.25,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                      // FittedBox cancels the user's text-size
                                      // setting by shrinking the row back down.
                                      // Above 1.3x let text lay out at its real
                                      // size unless a fixed-height parent
                                      // constrains height tighter than the text.
                                      final estimatedHeight =
                                          (titleFontSize + AppFontSize.label) *
                                                  textScale *
                                                  1.35 +
                                              AppSpacing.s2;
                                      final overflowsBound =
                                          textConstraints.hasBoundedHeight &&
                                              textConstraints.maxHeight > 0 &&
                                              estimatedHeight >
                                                  textConstraints.maxHeight;
                                      return textScale > 1.3 && !overflowsBound
                                          ? content
                                          : FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: AlignmentDirectional
                                                  .centerStart,
                                              child: content,
                                            );
                                    },
                                  ),
                                ),
                                if (showDurationInTile) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    Formatters.formatDurationMs(
                                        song.durationMs),
                                    style: TextStyle(
                                      color: isActive
                                          ? p.accent.withValues(alpha: 0.85)
                                          : p.textTertiary,
                                      fontSize: isCompact
                                          ? AppFontSize.caption
                                          : AppFontSize.label,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (showTrailingInTile) ...[
                        if (widget.trailing != null)
                          RepaintBoundary(child: widget.trailing!),
                        if (widget.onMorePressed != null)
                          RepaintBoundary(
                            child: IconButton(
                              constraints: const BoxConstraints(
                                minWidth: AppSpacing.minTouchTarget,
                                minHeight: AppSpacing.minTouchTarget,
                              ),
                              icon: Icon(
                                Icons.more_vert_rounded,
                                size: 20,
                                color: p.textTertiary,
                              ),
                              tooltip: MaterialLocalizations.of(context)
                                  .moreButtonTooltip,
                              onPressed: widget.onMorePressed,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );

        final tile = MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
            child: materialRow,
          ),
        );

        if (widget.index == 0) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureHintOverlay(
                hintKey: 'song_tile_swipe',
                message: context.l10n.swipeToPlayNextFavoriteHint,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
                icon: Icons.swipe_rounded,
              ),
              tile,
            ],
          );
        }

        return tile;
      },
    );
  }
}

/// Animated 3-bar "now playing" EQ glyph using zero-allocation [CustomPaint]
/// repaints for locked 120fps scrolling performance.
class NowPlayingIndicator extends StatefulWidget {
  final Color color;
  final bool isPlaying;
  const NowPlayingIndicator({
    super.key,
    required this.color,
    this.isPlaying = true,
  });

  @override
  State<NowPlayingIndicator> createState() => _NowPlayingIndicatorState();
}

class _NowPlayingIndicatorState extends State<NowPlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.isPlaying) _c.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.duration = context.motionMs(900);
    if (!context.motionEnabled) {
      _c.stop();
    } else if (widget.isPlaying && !_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(NowPlayingIndicator old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying != old.isPlaying) {
      if (widget.isPlaying && context.motionEnabled) {
        _c.repeat(reverse: true);
      } else {
        _c.value = 0.0;
        _c.stop();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(AppSpacing.s18, 16),
        painter: _NowPlayingBarsPainter(
          animation: _c,
          color: widget.color,
          isPlaying: widget.isPlaying,
        ),
      ),
    );
  }
}

class _NowPlayingBarsPainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;
  final bool isPlaying;

  _NowPlayingBarsPainter({
    required this.animation,
    required this.color,
    required this.isPlaying,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    const barWidth = 3.4;
    const radius = Radius.circular(2.0);
    final gap = (size.width - (barWidth * 3)) / 2.0;

    for (var i = 0; i < 3; i++) {
      final phase = animation.value * math.pi + i * 1.05;
      final h = isPlaying ? 4.5 + (math.sin(phase).abs() * 11.5) : 4.5;
      final x = i * (barWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h, barWidth, h),
        radius,
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NowPlayingBarsPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isPlaying != isPlaying;
  }
}
