// lib/features/player/presentation/themes/circle_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/waveform_logo.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../sheets/sleep_timer_sheet.dart';
import '../../../sheets/song_info_sheet.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import '../widgets/speed_picker_sheet.dart';
import 'player_theme.dart';

class CirclePlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const CirclePlayerTheme({super.key, required this.props});

  @override
  State<CirclePlayerTheme> createState() => _CirclePlayerThemeState();
}

class _CirclePlayerThemeState extends State<CirclePlayerTheme> with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    if (widget.props.state.isPlaying) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CirclePlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.state.isPlaying != oldWidget.props.state.isPlaying) {
      if (widget.props.state.isPlaying) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.props.state;
    final cubit = widget.props.cubit;
    final repository = widget.props.repository;
    final activeColor = widget.props.activeColor;
    final bgColor = widget.props.bgColor;
    final song = state.currentSong;
    final settingsState = context.watch<SettingsCubit>().state;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.2,
          colors: [
            bgColor,
            AppColors.background,
          ],
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
                            'VINYL CIRCLE',
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

            // Central Area: Vinyl Rotating Circle / Lyrics / Queue
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                                key: const ValueKey('circle_artwork_view'),
                                child: RotationTransition(
                                  turns: _rotationController,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final vinylSize = math.min(constraints.maxWidth, constraints.maxHeight) * 0.9;
                                      return Container(
                                        width: vinylSize,
                                        height: vinylSize,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF121212),
                                          border: Border.all(
                                            color: AppColors.outline.withValues(alpha: 0.6),
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: activeColor.withValues(alpha: 0.35),
                                              blurRadius: 36,
                                              spreadRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // Concentric vinyl grooves pattern
                                            Container(
                                              margin: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white10,
                                                  width: 1.5,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              margin: const EdgeInsets.all(28),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white10,
                                                  width: 1,
                                                ),
                                              ),
                                            ),
                                            // Circular Artwork Center
                                            ClipOval(
                                              child: SizedBox(
                                                width: vinylSize * 0.65,
                                                height: vinylSize * 0.65,
                                                child: song != null
                                                    ? CachedArtwork(
                                                        id: song.id,
                                                        type: ArtworkType.AUDIO,
                                                        size: double.infinity,
                                                      )
                                                    : const SizedBox.shrink(),
                                              ),
                                            ),
                                            // Vinyl Center Spindle Hole Dot
                                            Container(
                                              width: 22,
                                              height: 22,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: AppColors.background,
                                                border: Border.all(
                                                  color: AppColors.outline,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Song Info (Title, Artist, Favorite)
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

            const SizedBox(height: 12),

            // Bottom Action Strip
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
                  Badge(
                    isLabelVisible: state.playbackSpeed != 1.0,
                    label: Text(SpeedPickerSheet.formatSpeed(state.playbackSpeed)),
                    child: IconButton(
                      icon: Icon(
                        Icons.speed_rounded,
                        color: state.playbackSpeed != 1.0 ? activeColor : AppColors.textSecondary,
                      ),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (_) => const SpeedPickerSheet(),
                        );
                      },
                      tooltip: 'Playback Speed',
                    ),
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
    );
  }
}
