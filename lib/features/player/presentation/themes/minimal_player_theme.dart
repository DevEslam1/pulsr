// lib/features/player/presentation/themes/minimal_player_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../sheets/song_info_sheet.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import 'player_theme.dart';

class MinimalPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const MinimalPlayerTheme({super.key, required this.props});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final bgColor = props.bgColor;
    final song = state.currentSong;

    final settingsState = context.watch<SettingsCubit>().state;
    final visualizerStyle = settingsState.visualizerStyle;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      color: bgColor,
      child: SafeArea(
        child: Column(
          children: [
            // Minimal Header Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_down_rounded, size: 30, color: p.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    'NOW PLAYING',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          letterSpacing: 2.0,
                          fontWeight: FontWeight.w800,
                          color: p.textSecondary,
                        ),
                  ),
                  IconButton(
                    icon: Icon(Icons.more_horiz_rounded, color: p.textPrimary),
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

            const Spacer(flex: 1),

            // Centerpiece: Artwork / Lyrics / Queue + Visualizer overlay
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: state.isLyricsVisible
                          ? SizedBox(
                              height: 280,
                              child: LyricsView(
                                key: const ValueKey('lyrics_view_minimal'),
                                lyrics: state.lyrics,
                                currentPosition: state.position,
                                isLoading: state.isLoadingLyrics,
                                activeColor: activeColor,
                                source: state.lyricsSource,
                              ),
                            )
                          : state.isQueueVisible
                              ? const SizedBox(
                                  height: 280,
                                  child: NowPlayingQueueView(key: ValueKey('queue_view_minimal')),
                                )
                              : Column(
                                  children: [
                                    AspectRatio(
                                      aspectRatio: 1.0,
                                      child: Hero(
                                        tag: 'now_playing_art_minimal',
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(20),
                                            boxShadow: [
                                              BoxShadow(
                                                color: activeColor.withValues(alpha: 0.25),
                                                blurRadius: 28,
                                                spreadRadius: 1,
                                                offset: const Offset(0, 12),
                                              ),
                                            ],
                                          ),
                                          child: song != null
                                              ? CachedArtwork(
                                                  id: song.id,
                                                  type: ArtworkType.AUDIO,
                                                  size: double.infinity,
                                                  borderRadius: 20,
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                    ),
                    const SizedBox(height: 16),
                    // Dedicated Audio Visualizer in Minimal Theme
                    if (visualizerStyle != VisualizerStyle.off)
                      AudioVisualizer(
                        style: visualizerStyle,
                        color: activeColor,
                        height: visualizerStyle == VisualizerStyle.circular ? 100 : 48,
                        isPlaying: state.isPlaying,
                      ),
                  ],
                ),
              ),
            ),

            const Spacer(flex: 1),

            // Track Meta Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Text(
                    song?.title ?? 'No Track Selected',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: p.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    song?.artist ?? 'Unknown Artist',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: p.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (song != null) ...[
                    const SizedBox(height: 8),
                    AudioQualityBadge(song: song, activeColor: activeColor),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Seek Bar
            PlayerSeekBar(
              position: state.position,
              duration: state.duration,
              activeColor: activeColor,
              songId: state.currentSong?.id,
              filePath: state.currentSong?.path,
              onSeek: (pos) => cubit.seek(pos),
            ),

            const SizedBox(height: 8),

            // Controls
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

            const SizedBox(height: 16),

            // Bottom Quick Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.equalizer_rounded,
                      color: state.isEqEnabled ? activeColor : p.textSecondary,
                    ),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const EqualizerSheet(),
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.lyrics_rounded,
                      color: state.isLyricsVisible ? activeColor : p.textSecondary,
                    ),
                    onPressed: () => cubit.toggleLyricsVisibility(),
                  ),
                  IconButton(
                    icon: Icon(
                      song?.isFavorite == true ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: song?.isFavorite == true ? p.favorite : p.textSecondary,
                    ),
                    onPressed: () {
                      if (song != null) cubit.toggleFavorite(song.id);
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.playlist_add_rounded, color: p.textSecondary),
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
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.queue_music_rounded,
                      color: state.isQueueVisible ? activeColor : p.textSecondary,
                    ),
                    onPressed: () => cubit.toggleQueueVisibility(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
