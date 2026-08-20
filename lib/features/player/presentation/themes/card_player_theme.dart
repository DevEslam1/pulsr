// lib/features/player/presentation/themes/card_player_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/waveform_logo.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../sheets/sleep_timer_sheet.dart';
import '../../../sheets/song_info_sheet.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import '../widgets/speed_picker_sheet.dart';
import 'player_theme.dart';

class CardPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const CardPlayerTheme({super.key, required this.props});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final settingsState = context.watch<SettingsCubit>().state;

    return Stack(
      children: [
        // 1. Full-bleed Artwork Background
        Positioned.fill(
          child: song != null
              ? CachedArtwork(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  size: double.infinity,
                )
              : Container(color: p.bg),
        ),

        // 2. Dark Gradient & Blur Overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.4),
                  Colors.black.withValues(alpha: 0.75),
                  Colors.black.withValues(alpha: 0.95),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),

        // 3. Foreground Content
        SafeArea(
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            WaveformLogo(
                              size: 16,
                              color: state.isPlaying ? activeColor : Colors.white70,
                              animate: state.isPlaying,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'NOW PLAYING',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 10,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white70,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song?.album ?? 'Library',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
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

              // Central Area: Floating Artwork or Lyrics or Queue
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: GestureDetector(
                    onTap: () => cubit.toggleLyricsVisibility(),
                    onDoubleTap: () {
                      switch (settingsState.nowPlayingDoubleTap) {
                        case NowPlayingDoubleTapAction.toggleFavorite:
                          if (song != null) cubit.toggleFavorite(song.id);
                          break;
                        case NowPlayingDoubleTapAction.toggleLyrics:
                          cubit.toggleLyricsVisibility();
                          break;
                        case NowPlayingDoubleTapAction.none:
                          break;
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      if (settingsState.nowPlayingArtworkSwipe == NowPlayingArtworkSwipeAction.nextPrev &&
                          details.primaryVelocity != null) {
                        if (details.primaryVelocity! < -200) {
                          cubit.next();
                        } else if (details.primaryVelocity! > 200) {
                          cubit.previous();
                        }
                      }
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: state.isLyricsVisible
                          ? LyricsView(
                              key: const ValueKey('lyrics_view'),
                              lyrics: state.lyrics,
                              currentPosition: state.position,
                              isLoading: state.isLoadingLyrics,
                              activeColor: activeColor,
                              source: state.lyricsSource,
                            )
                          : state.isQueueVisible
                              ? const NowPlayingQueueView(key: ValueKey('queue_view'))
                              : Center(
                                  key: const ValueKey('artwork_card'),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxHeight: 340, maxWidth: 340),
                                    child: AspectRatio(
                                      aspectRatio: 1.0,
                                      child: Hero(
                                        tag: 'now_playing_art',
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(28),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.6),
                                                blurRadius: 30,
                                                spreadRadius: 4,
                                                offset: const Offset(0, 12),
                                              ),
                                              BoxShadow(
                                                color: activeColor.withValues(alpha: 0.3),
                                                blurRadius: 24,
                                                spreadRadius: -2,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: song != null
                                              ? CachedArtwork(
                                                  id: song.id,
                                                  type: ArtworkType.AUDIO,
                                                  size: 340,
                                                  borderRadius: 28,
                                                )
                                              : Container(
                                                  decoration: BoxDecoration(
                                                    color: p.surfaceContainer,
                                                    borderRadius: BorderRadius.circular(28),
                                                  ),
                                                  child: const Icon(
                                                    Icons.music_note_rounded,
                                                    size: 96,
                                                    color: Colors.white24,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                    ),
                  ),
                ),
              ),

              // Bottom Glass Card: Track Meta, Seek, Controls, Actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(28),
                  blur: 20,
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1,
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Song Title, Artist, Favorite
                      Row(
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
                                        color: Colors.white,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  song?.artist ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                if (song != null) ...[
                                  const SizedBox(height: 6),
                                  AudioQualityBadge(song: song, activeColor: activeColor),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              song?.isFavorite == true
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: song?.isFavorite == true
                                  ? p.favorite
                                  : Colors.white70,
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

                      const SizedBox(height: 8),

                      // Seek Bar
                      PlayerSeekBar(
                        position: state.position,
                        duration: state.duration,
                        activeColor: activeColor,
                        songId: state.currentSong?.id,
                        filePath: state.currentSong?.path,
                        onSeek: (pos) => cubit.seek(pos),
                      ),

                      const SizedBox(height: 4),

                      // Player Controls
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

                      const SizedBox(height: 6),

                      // Bottom Action Strip
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.equalizer_rounded,
                              color: state.isEqEnabled ? activeColor : Colors.white70,
                            ),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => const EqualizerSheet(),
                              );
                            },
                            tooltip: 'Equalizer',
                          ),
                          IconButton(
                            icon: const Icon(Icons.speed_rounded, color: Colors.white70),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                builder: (_) => const SpeedPickerSheet(),
                              );
                            },
                            tooltip: 'Playback Speed',
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.lyrics_rounded,
                              color: state.isLyricsVisible ? activeColor : Colors.white70,
                            ),
                            onPressed: () => cubit.toggleLyricsVisibility(),
                            tooltip: 'Lyrics',
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.timer_outlined,
                              color: state.sleepTimerRemaining != null ? activeColor : Colors.white70,
                            ),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                useRootNavigator: true,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => const SleepTimerSheet(),
                              );
                            },
                            tooltip: 'Sleep Timer',
                          ),
                          IconButton(
                            icon: const Icon(Icons.playlist_add_rounded, color: Colors.white70),
                            onPressed: () {
                              if (song != null) {
                                showModalBottomSheet(
                                  context: context,
                                  useRootNavigator: true,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => AddToPlaylistSheet(song: song),
                                );
                              }
                            },
                            tooltip: 'Add to Playlist',
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.queue_music_rounded,
                              color: state.isQueueVisible ? activeColor : Colors.white70,
                            ),
                            onPressed: () => cubit.toggleQueueVisibility(),
                            tooltip: 'Queue',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
