// lib/features/player/presentation/now_playing_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/dynamic_theme_cubit.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/waveform_logo.dart';
import '../../../data/repositories/music_repository.dart';
import '../../sheets/add_to_playlist_sheet.dart';
import '../../sheets/sleep_timer_sheet.dart';
import '../../sheets/song_info_sheet.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'widgets/equalizer_sheet.dart';
import 'widgets/lyrics_view.dart';
import 'widgets/now_playing_queue_view.dart';
import 'widgets/player_controls.dart';
import 'widgets/player_seek_bar.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerCubit, PlayerState>(
      builder: (context, state) {
        final song = state.currentSong;
        final cubit = context.read<PlayerCubit>();
        final repository = context.read<MusicRepository>();
        final dynamicTheme = context.watch<DynamicThemeCubit>().state;

        // Trigger dynamic color extraction whenever song changes
        if (song != null) {
          context.read<DynamicThemeCubit>().updateFromSongId(song.id);
        }

        final activeColor = dynamicTheme.primaryColor;
        final bgColor = dynamicTheme.backgroundColor;

        return Dismissible(
          key: const Key('now_playing_dismissible'),
          direction: DismissDirection.down,
          onDismissed: (_) => Navigator.of(context).pop(),
          child: Scaffold(
            body: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    bgColor,
                    AppColors.background,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Top App Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Column(
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  WaveformLogo(
                                    size: 16,
                                    color: state.isPlaying ? activeColor : AppColors.textSecondary,
                                    animate: state.isPlaying,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'PLAYING FROM ALBUM',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontSize: 10,
                                          letterSpacing: 1.2,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song?.album ?? 'Library',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert_rounded),
                            onPressed: () {
                              if (song != null) {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (_) => SongInfoSheet(song: song),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Central Display: Artwork / Lyrics / Queue
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: GestureDetector(
                          onTap: () => cubit.toggleLyricsVisibility(),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: state.isLyricsVisible
                                ? LyricsView(
                                    key: const ValueKey('lyrics_view'),
                                    lyrics: state.lyrics,
                                    currentPosition: state.position,
                                    isLoading: state.isLoadingLyrics,
                                    activeColor: activeColor,
                                  )
                                : state.isQueueVisible
                                    ? const NowPlayingQueueView(key: ValueKey('queue_view'))
                                    : AspectRatio(
                                        key: const ValueKey('artwork_view'),
                                        aspectRatio: 1.0,
                                        child: Hero(
                                          tag: 'now_playing_art',
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(24),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: activeColor.withValues(alpha: 0.35),
                                                  blurRadius: 36,
                                                  spreadRadius: 2,
                                                  offset: const Offset(0, 16),
                                                ),
                                              ],
                                            ),
                                            child: song != null
                                                ? CachedArtwork(
                                                    id: song.id,
                                                    type: ArtworkType.AUDIO,
                                                    size: double.infinity,
                                                    borderRadius: 24,
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                        ),
                                      ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Title, Artist, Favorite
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song?.title ?? 'No Track Selected',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  song?.artist ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              song?.isFavorite == true
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: song?.isFavorite == true
                                  ? AppColors.favorite
                                  : AppColors.textSecondary,
                              size: 28,
                            ),
                            onPressed: () {
                              if (song != null) {
                                cubit.toggleFavorite(song.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Scrubber Seek Bar
                    PlayerSeekBar(
                      position: state.position,
                      duration: state.duration,
                      activeColor: activeColor,
                      onSeek: (pos) => cubit.seek(pos),
                    ),

                    const SizedBox(height: 8),

                    // Playback Controls
                    PlayerControls(
                      isPlaying: state.isPlaying,
                      isShuffle: state.isShuffle,
                      repeatMode: state.repeatMode,
                      primaryColor: activeColor,
                      onPlayPause: () => cubit.togglePlayPause(),
                      onNext: () => cubit.next(),
                      onPrevious: () => cubit.previous(),
                      onToggleShuffle: () => cubit.toggleShuffle(),
                      onToggleRepeat: () => cubit.toggleRepeat(),
                    ),

                    const SizedBox(height: 12),

                    // Bottom Action Strip (EQ, Lyrics, Sleep Timer, Add to Playlist, Queue)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.equalizer_rounded,
                              color: state.isEqEnabled ? activeColor : AppColors.textSecondary,
                            ),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => const EqualizerSheet(),
                              );
                            },
                            tooltip: 'Equalizer',
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.lyrics_rounded,
                              color: state.isLyricsVisible ? activeColor : AppColors.textSecondary,
                            ),
                            onPressed: () => cubit.toggleLyricsVisibility(),
                            tooltip: 'Lyrics',
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.timer_outlined,
                              color: state.sleepTimerRemaining != null ? activeColor : AppColors.textSecondary,
                            ),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                builder: (_) => const SleepTimerSheet(),
                              );
                            },
                            tooltip: 'Sleep Timer',
                          ),
                          IconButton(
                            icon: const Icon(Icons.playlist_add_rounded),
                            color: AppColors.textSecondary,
                            onPressed: () {
                              if (song != null) {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (_) => AddToPlaylistSheet(song: song, repository: repository),
                                );
                              }
                            },
                            tooltip: 'Add to Playlist',
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.queue_music_rounded,
                              color: state.isQueueVisible ? activeColor : AppColors.textSecondary,
                            ),
                            onPressed: () => cubit.toggleQueueVisibility(),
                            tooltip: 'Queue',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
