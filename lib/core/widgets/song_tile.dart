import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../motion/pulsr_motion.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../data/db/app_database.dart';
import '../../core/utils/formatters.dart';
import '../theme/aura_theme.dart';
import 'cached_artwork.dart';
import '../utils/l10n_extensions.dart';
import 'gesture_hint_overlay.dart';
import 'pulsr_pressable.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../../features/player/cubit/player_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// {@category DesignSystem}
/// The universal premium song row. Auto-highlights the active track with an
/// animated EQ indicator. Reused by Home/Library/Search/Albums/Playlists/etc.
class SongTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final p = context.palette;
    final isCompact = MediaQuery.sizeOf(context).width < 360;
    final baseArtwork = dense ? 44.0 : artworkSize;
    final effectiveArtworkSize =
        isCompact ? (baseArtwork * 0.88).clamp(40.0, 52.0) : baseArtwork;

    final isDownloadedTrack = isDownloaded ??
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

        final tile = Semantics(
          label: context.l10n.songByArtist(song.title, song.artist),
          button: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
            child: PulsrPressable(
              pressedScale: 0.98,
              onTap: onTap,
              onLongPress: onLongPress,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: AppRadii.r16All,
                  boxShadow: isPlaying
                      ? [
                          BoxShadow(
                            color: p.accent.withValues(alpha: 0.16),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: backgroundColor ??
                      (selected
                          ? p.accentContainer
                          : (isActive ? p.surfaceContainer : p.surface)),
                  borderRadius: AppRadii.r16All,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: AppRadii.r16All,
                    onTap: onTap,
                    onLongPress: onLongPress,
                    child: Container(
                      constraints: BoxConstraints(minHeight: dense ? 48 : 56),
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.s10,
                        vertical: dense ? AppSpacing.s2 : AppSpacing.s6,
                      ),
                      child: Row(
                        children: [
                          if (index != null)
                            SizedBox(
                              width: isCompact ? 24 : 32,
                              child: Center(
                                child: Text(
                                  '${index! + 1}',
                                  style: TextStyle(
                                    color: isActive ? p.accent : p.textTertiary,
                                    fontWeight: FontWeight.w700,
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
                          if (showArtwork) ...[
                            SizedBox(
                              width: effectiveArtworkSize,
                              height: effectiveArtworkSize,
                              child: selected
                                  ? Container(
                                      decoration: BoxDecoration(
                                        color: p.accent,
                                        borderRadius: AppRadii.r12All,
                                      ),
                                      child: Icon(Icons.check_rounded,
                                          color: p.onAccent, size: 24),
                                    )
                                  : Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        CachedArtwork(
                                          id: song.id,
                                          remoteUrl: song.remoteArtworkUrl ??
                                              song.artworkUri,
                                          albumId: song.albumId,
                                          type: ArtworkType.AUDIO,
                                          size: effectiveArtworkSize,
                                          borderRadius: 13,
                                        ),
                                        if (isActive)
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black
                                                  .withValues(alpha: 0.45),
                                              borderRadius: AppRadii.r12All,
                                            ),
                                            child: Center(
                                              child: NowPlayingIndicator(
                                                  color: p.accent,
                                                  isPlaying: isPlaying),
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                            SizedBox(width: isCompact ? 8 : 12),
                          ],
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isActive ? p.accent : p.textPrimary,
                                    fontWeight: isActive
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    fontSize: isCompact
                                        ? AppFontSize.bodySmall
                                        : AppFontSize.body,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s2),
                                Row(
                                  children: [
                                    if (isDownloadedTrack) ...[
                                      Icon(
                                        Icons.download_done_rounded,
                                        size: isCompact ? 12 : 13,
                                        color: p.accent,
                                      ),
                                      const SizedBox(width: AppSpacing.xxs),
                                    ],
                                    Expanded(
                                      child: Text(
                                        subtitleOverride ?? song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: isCompact
                                              ? AppFontSize.label
                                              : AppFontSize.label,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (song.durationMs > 0) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              Formatters.formatDurationMs(song.durationMs),
                              style: TextStyle(
                                color: p.textTertiary,
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
                          if (trailing != null)
                            RepaintBoundary(child: trailing!)
                          else if (onMorePressed != null)
                            RepaintBoundary(
                              child: IconButton(
                                icon: Icon(Icons.more_vert_rounded,
                                    size: 20, color: p.textTertiary),
                                tooltip: MaterialLocalizations.of(context)
                                    .moreButtonTooltip,
                                onPressed: onMorePressed,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (index == 0) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureHintOverlay(
                hintKey: 'song_tile_swipe',
                message: context.l10n.swipeToPlayNextFavoriteHint,
                padding: EdgeInsets.symmetric(
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

/// Animated 3-bar "now playing" EQ glyph.
class NowPlayingIndicator extends StatefulWidget {
  final Color color;
  final bool isPlaying;
  const NowPlayingIndicator(
      {super.key, required this.color, this.isPlaying = true});

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
      if (widget.isPlaying) {
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
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return SizedBox(
          width: AppSpacing.s18,
          height: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final phase = _c.value * math.pi + i * 0.9;
              final h =
                  widget.isPlaying ? 5 + (math.sin(phase).abs() * 11) : 5.0;
              return Container(
                width: 3.5,
                height: h,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: AppRadii.r2All,
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
