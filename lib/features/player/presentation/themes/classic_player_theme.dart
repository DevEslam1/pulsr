// lib/features/player/presentation/themes/classic_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/waveform_logo.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../sheets/sleep_timer_sheet.dart';
import '../../../sheets/song_info_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import '../widgets/speed_picker_sheet.dart';
import 'player_theme.dart';

class ClassicPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const ClassicPlayerTheme({super.key, required this.props});

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

    final isTablet = context.isTablet;

    // Only show standalone audio visualizer if waveform seekbar is NOT already
    // visualizing the audio and the visualizer is explicitly turned on.
    final showVisualizer = visualizerStyle != VisualizerStyle.off &&
        !settingsState.waveformSeekBarEnabled &&
        !state.isLyricsVisible &&
        !state.isQueueVisible;

    return Stack(
      children: [
        // 1. Dynamic Ambient Backdrop
        Positioned.fill(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color.lerp(bgColor, Colors.black, 0.45) ?? bgColor,
                  p.bg,
                  const Color(0xFF080910),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.50, 1.0],
              ),
            ),
          ),
        ),

        // Ambient Top Glow Sphere (Behind Artwork)
        Positioned(
          top: -40,
          left: -30,
          right: -30,
          height: isTablet ? 540 : 420,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.85,
                  colors: [
                    activeColor.withValues(alpha: 0.30),
                    activeColor.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.52, 1.0],
                ),
              ),
            ),
          ),
        ),

        // Ambient Bottom Glow (Near Controls)
        Positioned(
          bottom: -60,
          right: -40,
          width: isTablet ? 420 : 320,
          height: isTablet ? 420 : 320,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.75,
                  colors: [
                    activeColor.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // 2. Main Foreground Layout
        SafeArea(
          child: Column(
            children: [
              // Top Pull-down Handle Indicator
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // Top App Bar
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 24 : 16,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Dismiss Button
                    Material(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/');
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 26,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                    ),

                    // Center: "PLAYING FROM" Album Header
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                WaveformLogo(
                                  size: 14,
                                  color: state.isPlaying
                                      ? activeColor
                                      : p.textSecondary,
                                  animate: state.isPlaying,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  context.l10n.playingFrom.toUpperCase(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontSize: 10,
                                        letterSpacing: 1.2,
                                        fontWeight: FontWeight.w800,
                                        color: p.textSecondary
                                            .withValues(alpha: 0.8),
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song?.album ?? context.l10n.navLibrary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: isTablet ? 14 : 13,
                                    color: p.textPrimary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // More Options Button
                    Material(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          if (song != null) {
                            showModalBottomSheet<void>(
                              context: context,
                              builder: (_) => SongInfoSheet(song: song),
                            );
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.more_horiz_rounded,
                            size: 24,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 2),

              // Responsive Two-Pane (Landscape / Tablet) vs Single Column (Portrait)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isLandscape = context.isLandscape &&
                        (context.isTwoPane || constraints.maxWidth >= 680);

                    // Dynamic sizing for artwork based on viewport dimensions
                    final double portraitArtSize = math.min(
                      constraints.maxWidth - (isTablet ? 64 : 48),
                      (constraints.maxHeight - (isTablet ? 370 : 320))
                          .clamp(240.0, isTablet ? 500.0 : 380.0),
                    );

                    final double landscapeArtSize =
                        (constraints.maxHeight - 80).clamp(280.0, 480.0);

                    final viewSwitcher = _buildViewSwitcher(
                      context: context,
                      state: state,
                      cubit: cubit,
                      activeColor: activeColor,
                      isTablet: isTablet,
                    );

                    final centerDisplay = GestureDetector(
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
                        if (settingsState.nowPlayingArtworkSwipe ==
                                NowPlayingArtworkSwipeAction.nextPrev &&
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
                                key: ValueKey(
                                    'lyrics_${song?.id}_${song?.remoteId}'),
                                lyrics: state.lyrics,
                                isLoading: state.isLoadingLyrics,
                                activeColor: activeColor,
                                source: state.lyricsSource,
                              )
                            : state.isQueueVisible
                                ? const NowPlayingQueueView(
                                    key: ValueKey('queue_view'),
                                  )
                                : Center(
                                    key: const ValueKey('artwork_view'),
                                    child: AnimatedScale(
                                      scale: state.isPlaying ? 1.0 : 0.93,
                                      duration:
                                          const Duration(milliseconds: 320),
                                      curve: Curves.easeOutCubic,
                                      child: AspectRatio(
                                        aspectRatio: 1.0,
                                        child: Hero(
                                          tag: 'now_playing_art_full',
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 320),
                                            curve: Curves.easeOutCubic,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(28),
                                              border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.14),
                                                width: 1.2,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: activeColor.withValues(
                                                    alpha: state.isPlaying
                                                        ? 0.40
                                                        : 0.18,
                                                  ),
                                                  blurRadius: state.isPlaying
                                                      ? 44
                                                      : 26,
                                                  spreadRadius:
                                                      state.isPlaying ? 2 : 0,
                                                  offset:
                                                      const Offset(0, 16),
                                                ),
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.35),
                                                  blurRadius: 18,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(26.8),
                                              child: song != null
                                                  ? CachedArtwork(
                                                      id: song.id,
                                                      remoteUrl:
                                                          song.remoteArtworkUrl,
                                                      type: ArtworkType.AUDIO,
                                                      size: double.infinity,
                                                      borderRadius: 26.8,
                                                    )
                                                  : const SizedBox.shrink(),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                      ),
                    );

                    final visualizer = showVisualizer
                        ? Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 4),
                                child: AudioVisualizer(
                                  style: visualizerStyle,
                                  color: activeColor,
                                  height: visualizerStyle ==
                                          VisualizerStyle.circular
                                      ? 65
                                      : 36,
                                  isPlaying: state.isPlaying,
                                  audioSessionId: state.audioSessionId,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink();

                    final controlsColumn = Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title, Artist, Quality Badge, Download & Favorite
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 24 : 20,
                            vertical: 2,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Title & Artist Column
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      song?.title ??
                                          context.l10n.noTrackSelected,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: isTablet ? 24 : 20,
                                        fontWeight: FontWeight.w900,
                                        color: p.textPrimary,
                                        height: 1.25,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          song?.artist ??
                                              context.l10n.unknownArtist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: isTablet ? 16 : 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: p.textSecondary,
                                          ),
                                        ),
                                        if (song != null)
                                          AudioQualityBadge(
                                            song: song,
                                            activeColor: activeColor,
                                            compact: true,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // YTM Download Button (if available)
                              if (song != null &&
                                  (song.source == SongSource.youtube ||
                                      (song.remoteId != null &&
                                          song.remoteId!.isNotEmpty))) ...[
                                YtmDownloadButton(
                                  song: song,
                                  activeColor: activeColor,
                                  iconColor: p.textSecondary,
                                  iconSize: isTablet ? 26 : 24,
                                ),
                                const SizedBox(width: 4),
                              ],

                              // Animated Favorite Heart Button
                              _AnimatedFavoriteButton(
                                isFavorite: song?.isFavorite == true,
                                favoriteColor: p.favorite,
                                inactiveColor: p.textSecondary,
                                iconSize: isTablet ? 30 : 28,
                                onTap: () {
                                  if (song != null) {
                                    cubit.toggleFavorite(song.id);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: isTablet ? 12 : 4),

                        // Interactive Scrubber / Seek Bar
                        PlayerSeekBar(
                          duration: state.duration,
                          activeColor: activeColor,
                          songId: state.currentSong?.id,
                          filePath: state.currentSong?.path,
                          onSeek: (pos) => cubit.seek(pos),
                        ),

                        SizedBox(height: isTablet ? 10 : 4),

                        // Studio-grade Playback Controls
                        PlayerControls(
                          isPlaying: state.isPlaying,
                          isShuffle: state.isShuffle,
                          repeatMode: state.repeatMode,
                          primaryColor: activeColor,
                          mainButtonSize: isTablet ? 74 : (isLandscape ? 58 : 66),
                          onPlayPause: () => cubit.togglePlayPause(),
                          onNext: () => cubit.next(),
                          onPrevious: () => cubit.previous(),
                          onToggleShuffle: () => cubit.toggleShuffle(),
                          onToggleRepeat: () => cubit.toggleRepeat(),
                        ),

                        SizedBox(height: isTablet ? 14 : 6),

                        // Floating Glass Bottom Action Dock
                        _buildBottomActionDock(
                          context: context,
                          props: props,
                          settingsState: settingsState,
                          isTablet: isTablet,
                        ),

                        SizedBox(height: isTablet ? 10 : 6),
                      ],
                    );

                    // Landscape / Tablet Two-Pane Mode
                    if (isLandscape) {
                      return Column(
                        children: [
                          // Centralized Switcher across the top
                          Padding(
                            padding: const EdgeInsets.only(top: 2, bottom: 10),
                            child: viewSwitcher,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Left Pane: Artwork
                                  Expanded(
                                    flex: 5,
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxHeight: landscapeArtSize,
                                          maxWidth: landscapeArtSize,
                                        ),
                                        child: centerDisplay,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 28),
                                  // Right Pane: Controls
                                  Expanded(
                                    flex: 6,
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                            maxWidth: 540),
                                        child: SingleChildScrollView(
                                          child: controlsColumn,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    // Portrait Mode
                    return Column(
                      children: [
                        // View Switcher Bar (Track | Lyrics | Queue)
                        Padding(
                          padding: EdgeInsets.only(
                            top: isTablet ? 6 : 2,
                            bottom: isTablet ? 10 : 6,
                          ),
                          child: viewSwitcher,
                        ),
                        Expanded(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: isTablet ? 32 : 24,
                                vertical: 4,
                              ),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: portraitArtSize,
                                  maxWidth: portraitArtSize,
                                ),
                                child: centerDisplay,
                              ),
                            ),
                          ),
                        ),
                        if (showVisualizer) visualizer,
                        controlsColumn,
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // View Switcher Pill Bar (Track / Lyrics / Queue)
  // ---------------------------------------------------------------------------
  Widget _buildViewSwitcher({
    required BuildContext context,
    required PlayerState state,
    required PlayerCubit cubit,
    required Color activeColor,
    required bool isTablet,
  }) {
    final isLyrics = state.isLyricsVisible;
    final isQueue = state.isQueueVisible;
    final isTrack = !isLyrics && !isQueue;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(3.5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SwitcherItem(
              label: 'Track',
              icon: Icons.music_note_rounded,
              isSelected: isTrack,
              activeColor: activeColor,
              isTablet: isTablet,
              onTap: () {
                if (!isTrack) {
                  HapticFeedback.selectionClick();
                  if (isLyrics) cubit.toggleLyricsVisibility();
                  if (isQueue) cubit.toggleQueueVisibility();
                }
              },
            ),
            _SwitcherItem(
              label: 'Lyrics',
              icon: Icons.lyrics_rounded,
              isSelected: isLyrics,
              activeColor: activeColor,
              isTablet: isTablet,
              onTap: () {
                if (!isLyrics) {
                  HapticFeedback.selectionClick();
                  cubit.toggleLyricsVisibility();
                }
              },
            ),
            _SwitcherItem(
              label: 'Queue',
              icon: Icons.queue_music_rounded,
              isSelected: isQueue,
              badgeCount: state.queue.length,
              activeColor: activeColor,
              isTablet: isTablet,
              onTap: () {
                if (!isQueue) {
                  HapticFeedback.selectionClick();
                  cubit.toggleQueueVisibility();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Floating Glass Bottom Action Dock (5 Actions)
  // ---------------------------------------------------------------------------
  Widget _buildBottomActionDock({
    required BuildContext context,
    required PlayerThemeProps props,
    required SettingsState settingsState,
    required bool isTablet,
  }) {
    final song = props.state.currentSong;
    final p = context.palette;
    final isUsb = settingsState.currentOutputDevice?.isUsbDac == true;
    final outputDevice = settingsState.currentOutputDevice;
    final isEqActive = props.state.isEqEnabled;
    final speed = props.state.playbackSpeed;
    final hasTimer = props.state.sleepTimerRemaining != null;

    final IconData outputIcon = isUsb
        ? Icons.usb_rounded
        : (outputDevice?.deviceName.contains('Bluetooth') == true ||
                outputDevice?.deviceName.contains('A2DP') == true
            ? Icons.bluetooth_audio_rounded
            : (outputDevice?.deviceName.contains('Speaker') == true
                ? Icons.speaker_rounded
                : Icons.headphones_rounded));

    final dockMaxWidth = isTablet ? 500.0 : 420.0;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dockMaxWidth),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 14 : 10,
            vertical: isTablet ? 4 : 3,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 1. Equalizer & DSP
              _DockIconButton(
                icon: Icons.tune_rounded,
                tooltip: context.l10n.equalizer,
                isActive: isEqActive,
                activeColor: props.activeColor,
                inactiveColor: p.textSecondary,
                isTablet: isTablet,
                onTap: () {
                  HapticFeedback.lightImpact();
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const EqualizerSheet(),
                  );
                },
              ),

              // 2. Audio Output & DAC
              _DockIconButton(
                icon: outputIcon,
                tooltip: 'Audio Output & DAC',
                isActive: isUsb,
                activeColor: const Color(0xFFFFD700),
                inactiveColor: p.textSecondary,
                isTablet: isTablet,
                onTap: () {
                  if (song != null) {
                    HapticFeedback.lightImpact();
                    AudioQualitySheet.show(context, song, props.activeColor);
                  }
                },
              ),

              // 3. Playback Speed
              _DockIconButton(
                icon: Icons.speed_rounded,
                tooltip: context.l10n.playbackSpeed,
                badgeText: speed != 1.0
                    ? '${speed.toStringAsFixed(1)}x'
                    : null,
                isActive: speed != 1.0,
                activeColor: props.activeColor,
                inactiveColor: p.textSecondary,
                isTablet: isTablet,
                onTap: () {
                  HapticFeedback.lightImpact();
                  SpeedPickerSheet.show(context);
                },
              ),

              // 4. Sleep Timer
              _DockIconButton(
                icon: Icons.timer_outlined,
                tooltip: context.l10n.sleepTimer,
                badgeText: hasTimer
                    ? '${props.state.sleepTimerRemaining!.inMinutes}m'
                    : null,
                isActive: hasTimer,
                activeColor: props.activeColor,
                inactiveColor: p.textSecondary,
                isTablet: isTablet,
                onTap: () {
                  HapticFeedback.lightImpact();
                  showModalBottomSheet<void>(
                    context: context,
                    useRootNavigator: true,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const SleepTimerSheet(),
                  );
                },
              ),

              // 5. Add to Playlist
              _DockIconButton(
                icon: Icons.playlist_add_rounded,
                tooltip: context.l10n.addToPlaylist,
                isActive: false,
                activeColor: props.activeColor,
                inactiveColor: p.textSecondary,
                isTablet: isTablet,
                onTap: () {
                  if (song != null) {
                    HapticFeedback.lightImpact();
                    showModalBottomSheet<void>(
                      context: context,
                      useRootNavigator: true,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => AddToPlaylistSheet(song: song),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sub-widgets
// -----------------------------------------------------------------------------

class _SwitcherItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final int? badgeCount;
  final bool isTablet;
  final VoidCallback onTap;

  const _SwitcherItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    this.badgeCount,
    this.isTablet = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 18 : 14,
          vertical: isTablet ? 7 : 6,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? Border.all(
                  color: activeColor.withValues(alpha: 0.45),
                  width: 1.0,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isTablet ? 16 : 15,
              color: isSelected ? activeColor : Colors.white60,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: isTablet ? 13 : 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : Colors.white60,
                letterSpacing: 0.2,
              ),
            ),
            if (badgeCount != null && badgeCount! > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor
                      : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.black : Colors.white70,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnimatedFavoriteButton extends StatelessWidget {
  final bool isFavorite;
  final Color favoriteColor;
  final Color inactiveColor;
  final double iconSize;
  final VoidCallback onTap;

  const _AnimatedFavoriteButton({
    required this.isFavorite,
    required this.favoriteColor,
    required this.inactiveColor,
    this.iconSize = 28,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: child,
            ),
            child: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              key: ValueKey(isFavorite),
              color: isFavorite ? favoriteColor : inactiveColor,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

class _DockIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final String? badgeText;
  final bool isTablet;
  final VoidCallback onTap;

  const _DockIconButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    this.badgeText,
    this.isTablet = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 12 : 8,
              vertical: isTablet ? 7 : 6,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.all(isTablet ? 9 : 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? activeColor.withValues(alpha: 0.22)
                        : Colors.transparent,
                    border: isActive
                        ? Border.all(
                            color: activeColor.withValues(alpha: 0.45),
                            width: 1.2,
                          )
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: isTablet ? 24 : 22,
                    color: isActive ? activeColor : inactiveColor,
                  ),
                ),
                if (badgeText != null)
                  Positioned(
                    top: -2,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: activeColor,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        badgeText!,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
