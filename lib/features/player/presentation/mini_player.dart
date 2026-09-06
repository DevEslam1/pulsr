import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/glass_container.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';

class MiniPlayer extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onSwipeDown;
  final VoidCallback? onSwipeUp;

  const MiniPlayer({
    super.key,
    required this.onTap,
    this.onSwipeDown,
    this.onSwipeUp,
  });

  void _handleSwipe(PlayerCubit cubit, MiniPlayerSwipeAction action,
      {required bool isLeft}) {
    switch (action) {
      case MiniPlayerSwipeAction.next:
        cubit.next();
      case MiniPlayerSwipeAction.prev:
        cubit.previous();
      case MiniPlayerSwipeAction.volume:
        cubit.adjustVolume(isLeft ? -0.15 : 0.15);
      case MiniPlayerSwipeAction.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = context.watch<SettingsCubit>().state;
    final p = context.palette;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (a, b) =>
          a.currentSong?.id != b.currentSong?.id ||
          a.currentSong?.title != b.currentSong?.title ||
          a.currentSong?.artist != b.currentSong?.artist ||
          a.currentSong?.remoteArtworkUrl != b.currentSong?.remoteArtworkUrl ||
          a.isPlaying != b.isPlaying ||
          a.duration != b.duration,
      builder: (context, state) {
        final song = state.currentSong;
        if (song == null) return const SizedBox.shrink();

        final cubit = context.read<PlayerCubit>();
        final activeAccent = p.accent;

        double dragDx = 0;
        double dragDy = 0;

        return Semantics(
          label: 'Now playing: ${song.title} by ${song.artist}',
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onPanStart: (_) {
              dragDx = 0;
              dragDy = 0;
            },
            onPanUpdate: (d) {
              dragDx += d.delta.dx;
              dragDy += d.delta.dy;
            },
            onPanEnd: (d) {
              final vx = d.velocity.pixelsPerSecond.dx;
              final vy = d.velocity.pixelsPerSecond.dy;
              final absX = dragDx.abs();
              final absY = dragDy.abs();

              // If drag was very small, treat as tap
              if (absX < 15 && absY < 15 && vx.abs() < 50 && vy.abs() < 50) {
                onTap();
                return;
              }

              // Check if swipe was predominantly vertical or horizontal
              if (absY >= absX) {
                // Vertical swipe:
                if (dragDy > 20 || vy > 80) {
                  onSwipeDown?.call();
                } else if (dragDy < -20 || vy < -80) {
                  if (onSwipeUp != null) {
                    onSwipeUp!();
                  } else {
                    onTap();
                  }
                }
              } else {
                // Horizontal swipe:
                if (dragDx < -20 || vx < -80) {
                  _handleSwipe(cubit, settingsState.miniPlayerSwipeLeft,
                      isLeft: true);
                } else if (dragDx > 20 || vx > 80) {
                  _handleSwipe(cubit, settingsState.miniPlayerSwipeRight,
                      isLeft: false);
                }
              }
              dragDx = 0;
              dragDy = 0;
            },
            onPanCancel: () {
              dragDx = 0;
              dragDy = 0;
            },
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 8),
              child: RepaintBoundary(
                child: GlassContainer(
                  blur: 16,
                  opacity: p.isDark ? 0.92 : 0.96,
                  borderRadius: AppRadii.miniPlayerRadius,
                  color: Color.alphaBlend(
                      activeAccent.withValues(alpha: p.isDark ? 0.12 : 0.08),
                      p.surface),
                  border: Border.all(
                      color: activeAccent.withValues(alpha: 0.22), width: 1.2),
                  child: ClipRRect(
                    borderRadius: AppRadii.miniPlayerRadius,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Hero(
                                  tag: 'now_playing_art_mini',
                                  child: CachedArtwork(
                                    id: song.id,
                                    remoteUrl: song.remoteArtworkUrl,
                                    type: ArtworkType.AUDIO,
                                    size: 48,
                                    borderRadius: 12,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: p.textPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: state.isPlaying
                                      ? context.l10n.pause
                                      : context.l10n.play,
                                  icon: Icon(
                                    state.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: activeAccent,
                                    size: 32,
                                  ),
                                  onPressed: cubit.togglePlayPause,
                                ),
                                IconButton(
                                  tooltip: context.l10n.next,
                                  icon: Icon(
                                    Icons.skip_next_rounded,
                                    color: p.textPrimary,
                                    size: 28,
                                  ),
                                  onPressed: cubit.next,
                                ),
                              ],
                            ),
                          ),
                        ),
                        _MiniPlayerProgressBar(
                          duration: state.duration,
                          activeAccent: activeAccent,
                          hairlineColor: p.hairline,
                          onSeek: (pos) => cubit.seek(pos),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniPlayerProgressBar extends StatelessWidget {
  final Duration duration;
  final Color activeAccent;
  final Color hairlineColor;
  final void Function(Duration) onSeek;

  const _MiniPlayerProgressBar({
    required this.duration,
    required this.activeAccent,
    required this.hairlineColor,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          return BlocSelector<PlayerCubit, PlayerState, Duration>(
            selector: (s) => s.position,
            builder: (context, position) {
              final progress = duration.inMilliseconds > 0
                  ? (position.inMilliseconds / duration.inMilliseconds)
                      .clamp(0.0, 1.0)
                  : 0.0;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  if (trackWidth > 0 && duration.inMilliseconds > 0) {
                    final ratio =
                        (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                    final seekMs = (duration.inMilliseconds * ratio).round();
                    onSeek(Duration(milliseconds: seekMs));
                  }
                },
                onHorizontalDragStart: (_) {},
                onHorizontalDragUpdate: (details) {
                  if (trackWidth > 0 && duration.inMilliseconds > 0) {
                    final ratio =
                        (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                    final seekMs = (duration.inMilliseconds * ratio).round();
                    onSeek(Duration(milliseconds: seekMs));
                  }
                },
                child: SizedBox(
                  height: 6.0,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                            color: hairlineColor.withValues(alpha: 0.35)),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 6.0,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  activeAccent.withValues(alpha: 0.7),
                                  activeAccent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: activeAccent.withValues(alpha: 0.45),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
