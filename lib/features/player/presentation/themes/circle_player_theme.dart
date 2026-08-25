// lib/features/player/presentation/themes/circle_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/love_feedback.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/waveform_logo.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../sheets/sleep_timer_sheet.dart';
import '../../../sheets/song_info_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../widgets/audio_quality_badge.dart';
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
    final p = context.palette;
    final state = widget.props.state;
    final cubit = widget.props.cubit;
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
            p.bg,
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
                    icon: Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: p.textPrimary),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                  ),
                  Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WaveformLogo(
                            size: 16,
                            color: state.isPlaying ? activeColor : p.textSecondary,
                            animate: state.isPlaying,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'DR. BASBOSA EDITION',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFFF85BC),
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song?.album ?? 'Library',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: p.textPrimary,
                            ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert_rounded, color: p.textPrimary),
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
                                            color: p.hairline.withValues(alpha: 0.6),
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
                                                        remoteUrl: song.remoteArtworkUrl,
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
                                                color: p.bg,
                                                border: Border.all(
                                                  color: p.hairline,
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
                                color: p.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song?.artist ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: p.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (song != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              AudioQualityBadge(song: song, activeColor: activeColor),
                              const SizedBox(width: 8),
                              InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => showNowPlayingLoveMessage(
                                  context,
                                  songTitle: song.title,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF2A85).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFFFF2A85).withValues(alpha: 0.3),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.favorite_rounded, size: 10, color: Color(0xFFFF2A85)),
                                      SizedBox(width: 4),
                                      Text(
                                        'For Dr. Basbosa ❤️',
                                        style: TextStyle(
                                          color: Color(0xFFFF85BC),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (song != null && (song.source == SongSource.youtube || (song.remoteId != null && song.remoteId!.isNotEmpty))) ...[
                    YtmDownloadButton(
                      song: song,
                      activeColor: activeColor,
                      iconColor: p.textSecondary,
                      iconSize: 24,
                    ),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    icon: Icon(
                      song?.isFavorite == true
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: song?.isFavorite == true
                          ? p.favorite
                          : p.textSecondary,
                      size: 28,
                    ),
                    onPressed: () {
                      if (song != null) {
                        cubit.toggleFavorite(song.id);
                        showFavoriteFeedback(context, !song.isFavorite);
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
                    tooltip: 'Equalizer',
                  ),
                  IconButton(
                    icon: Icon(Icons.speed_rounded, color: p.textSecondary),
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
                      color: state.isLyricsVisible ? activeColor : p.textSecondary,
                    ),
                    onPressed: () => cubit.toggleLyricsVisibility(),
                    tooltip: 'Lyrics',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.timer_outlined,
                      color: state.sleepTimerRemaining != null ? activeColor : p.textSecondary,
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
                    tooltip: 'Add to Playlist',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.queue_music_rounded,
                      color: state.isQueueVisible ? activeColor : p.textSecondary,
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
