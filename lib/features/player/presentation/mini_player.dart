import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/glass_container.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';

class MiniPlayer extends StatelessWidget {
  final VoidCallback onTap;
  const MiniPlayer({super.key, required this.onTap});

  void _handleSwipe(PlayerCubit cubit, MiniPlayerSwipeAction action, {required bool isLeft}) {
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
          a.isPlaying != b.isPlaying ||
          a.position.inSeconds != b.position.inSeconds ||
          a.duration != b.duration,
      builder: (context, state) {
        final song = state.currentSong;
        if (song == null) return const SizedBox.shrink();

        final cubit = context.read<PlayerCubit>();
        final activeAccent = p.accent;

        final progress = state.duration.inMilliseconds > 0
            ? (state.position.inMilliseconds / state.duration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return GestureDetector(
          onTap: onTap,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -200) onTap();
          },
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -200) _handleSwipe(cubit, settingsState.miniPlayerSwipeLeft, isLeft: true);
            if (v > 200) _handleSwipe(cubit, settingsState.miniPlayerSwipeRight, isLeft: false);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: RepaintBoundary(
              child: GlassContainer(
                blur: 16,
                opacity: p.isDark ? 0.92 : 0.96,
                borderRadius: AppRadii.miniPlayerRadius,
                color: Color.alphaBlend(activeAccent.withValues(alpha: p.isDark ? 0.12 : 0.08), p.surface),
                border: Border.all(color: activeAccent.withValues(alpha: 0.22), width: 1.2),
                child: ClipRRect(
                  borderRadius: AppRadii.miniPlayerRadius,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Hero(
                              tag: 'now_playing_art',
                              child: CachedArtwork(
                                id: song.id,
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                              icon: Icon(
                                state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: activeAccent,
                                size: 32,
                              ),
                              onPressed: cubit.togglePlayPause,
                            ),
                            IconButton(
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
                      // Edge-to-edge full width timeline with direct tap & scrub seeking
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final trackWidth = constraints.maxWidth;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) {
                              if (trackWidth > 0 && state.duration.inMilliseconds > 0) {
                                final ratio = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                                final seekMs = (state.duration.inMilliseconds * ratio).round();
                                cubit.seek(Duration(milliseconds: seekMs));
                              }
                            },
                            onHorizontalDragUpdate: (details) {
                              if (trackWidth > 0 && state.duration.inMilliseconds > 0) {
                                final ratio = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                                final seekMs = (state.duration.inMilliseconds * ratio).round();
                                cubit.seek(Duration(milliseconds: seekMs));
                              }
                            },
                            child: SizedBox(
                              height: 6.0,
                              width: double.infinity,
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  Positioned.fill(
                                    child: ColoredBox(color: p.hairline.withValues(alpha: 0.35)),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: progress,
                                    alignment: Alignment.centerLeft,
                                    child: Container(
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
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
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
