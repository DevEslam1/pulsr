// lib/features/player/presentation/mini_player.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/theme/dynamic_theme_cubit.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';

class MiniPlayer extends StatelessWidget {
  final VoidCallback onTap;

  const MiniPlayer({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerCubit, PlayerState>(
      builder: (context, state) {
        final song = state.currentSong;
        if (song == null) return const SizedBox.shrink();

        final cubit = context.read<PlayerCubit>();
        final dynamicTheme = context.watch<DynamicThemeCubit>().state;
        final primaryColor = dynamicTheme.primaryColor;

        final progress = state.duration.inMilliseconds > 0
            ? (state.position.inMilliseconds / state.duration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return GestureDetector(
          onTap: onTap,
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
              // Swiped Up -> Expand
              onTap();
            }
          },
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null) {
              if (details.primaryVelocity! < -200) {
                // Swiped Left -> Next Track
                cubit.next();
              } else if (details.primaryVelocity! > 200) {
                // Swiped Right -> Previous Track
                cubit.previous();
              }
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: GlassContainer(
              blur: 24,
              opacity: 0.92,
              borderRadius: AppRadii.miniPlayerRadius,
              color: Color.alphaBlend(primaryColor.withValues(alpha: 0.12), AppColors.surface),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'now_playing_art',
                          child: CachedArtwork(
                            id: song.id,
                            type: ArtworkType.AUDIO,
                            size: 46,
                            borderRadius: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: primaryColor,
                            size: 30,
                          ),
                          onPressed: () {
                            cubit.togglePlayPause();
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            color: AppColors.textSecondary,
                            size: 26,
                          ),
                          onPressed: () {
                            cubit.next();
                          },
                        ),
                      ],
                    ),
                  ),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 2.5,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
