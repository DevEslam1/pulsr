// lib/features/player/presentation/themes/classic_player_theme.dart
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
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
import '../widgets/advanced_playback_bar.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import '../widgets/quran_mode_button.dart';
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

        // Ambient Bottom Glow (Near Controls) - Centered for visual symmetry
        Positioned(
          bottom: -70,
          left: 0,
          right: 0,
          height: isTablet ? 420 : 320,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.85,
                  colors: [
                    activeColor.withValues(alpha: 0.16),
                    activeColor.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
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
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // Top App Bar - Symmetrical Left/Right Touch Targets & Centered Header
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 28 : 20,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Dismiss Button (Symmetrical 40x40 circle)
                    SizedBox(
                      width: isTablet ? 44 : 40,
                      height: isTablet ? 44 : 40,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.07),
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
                          child: Center(
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: isTablet ? 26 : 24,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Center: "PLAYING FROM" / Album Header (Symmetric & Centered)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                WaveformLogo(
                                  size: 13,
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
                              (song?.album != null &&
                                      song!.album.trim().isNotEmpty)
                                  ? song.album.trim()
                                  : (song?.artist != null &&
                                          song!.artist.trim().isNotEmpty)
                                      ? song.artist.trim()
                                      : context.l10n.navLibrary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
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

                    // More Options Button (Symmetrical 40x40 circle)
                    SizedBox(
                      width: isTablet ? 44 : 40,
                      height: isTablet ? 44 : 40,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.07),
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
                          child: Center(
                            child: Icon(
                              Icons.more_horiz_rounded,
                              size: isTablet ? 24 : 22,
                              color: p.textPrimary,
                            ),
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

                    // Dynamic vertical spacing ratio for balanced, centered content distribution
                    final double heightRatio =
                        (constraints.maxHeight / 720.0).clamp(0.85, 1.25);
                    final double spacingTrackToSeek =
                        (isTablet ? 16.0 : 12.0) * heightRatio;
                    final double spacingSeekToControls =
                        (isTablet ? 18.0 : 14.0) * heightRatio;
                    final double spacingControlsToDock =
                        (isTablet ? 18.0 : 14.0) * heightRatio;
                    final double spacingBelowDock =
                        (isTablet ? 14.0 : 10.0) * heightRatio;
                    final double switcherTopPad =
                        (isTablet ? 8.0 : 4.0) * heightRatio;
                    final double switcherBottomPad =
                        (isTablet ? 10.0 : 6.0) * heightRatio;

                    final double landscapeArtSize =
                        (constraints.maxHeight - 36).clamp(280.0, 520.0);

                    // Symmetrical twin pill capsule dimensions for top (view switcher) & bottom (eq dock)
                    final double pillBarWidth = math.min(
                      constraints.maxWidth - (isTablet ? 64 : 36),
                      isTablet ? 440.0 : 336.0,
                    );
                    final double pillBarHeight = isTablet ? 50.0 : 44.0;

                    final viewSwitcher = _buildViewSwitcher(
                      context: context,
                      state: state,
                      cubit: cubit,
                      activeColor: activeColor,
                      isTablet: isTablet,
                      barWidth: pillBarWidth,
                      barHeight: pillBarHeight,
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
                                      scale: state.isPlaying ? 1.0 : 0.97,
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
                                                      highQuality: true,
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
                                  trackSeed: song?.id,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink();

                    final bool hasDownload = song != null &&
                        (song.source == SongSource.youtube ||
                            (song.remoteId != null &&
                                song.remoteId!.isNotEmpty));

                    final controlsColumn = Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Symmetrical Track Header: [Action] Title/Artist [Favorite]
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 28 : 20,
                            vertical: 2,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Left Symmetrical Action: Download (stream) or Add to Playlist (local)
                                  SizedBox(
                                    width: isTablet ? 46 : 40,
                                    height: isTablet ? 46 : 40,
                                    child: hasDownload
                                        ? Center(
                                            child: YtmDownloadButton(
                                              song: song,
                                              activeColor: activeColor,
                                              iconColor: p.textSecondary,
                                              iconSize: isTablet ? 24 : 22,
                                            ),
                                          )
                                        : Material(
                                            color: Colors.white
                                                .withValues(alpha: 0.06),
                                            shape: const CircleBorder(),
                                            clipBehavior: Clip.antiAlias,
                                            child: InkWell(
                                              onTap: () {
                                                if (song != null) {
                                                  HapticFeedback.lightImpact();
                                                  showModalBottomSheet<void>(
                                                    context: context,
                                                    useRootNavigator: true,
                                                    isScrollControlled: true,
                                                    backgroundColor:
                                                        Colors.transparent,
                                                    builder: (_) =>
                                                        AddToPlaylistSheet(
                                                            song: song),
                                                  );
                                                }
                                              },
                                              child: Center(
                                                child: Icon(
                                                  Icons.playlist_add_rounded,
                                                  size: isTablet ? 24 : 22,
                                                  color: p.textSecondary,
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),

                                  // Center: Title & Artist (Symmetric & Centered)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          MarqueeText(
                                            text: song?.title ??
                                                context.l10n.noTrackSelected,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: isTablet ? 23 : 19,
                                              fontWeight: FontWeight.w900,
                                              color: p.textPrimary,
                                              height: 1.22,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          MarqueeText(
                                            text: song?.artist ??
                                                context.l10n.unknownArtist,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: isTablet ? 15 : 13.5,
                                              fontWeight: FontWeight.w600,
                                              color: p.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Right Symmetrical Action: Animated Favorite Button
                                  SizedBox(
                                    width: isTablet ? 46 : 40,
                                    height: isTablet ? 46 : 40,
                                    child: Material(
                                      color: Colors.white
                                          .withValues(alpha: 0.06),
                                      shape: const CircleBorder(),
                                      clipBehavior: Clip.antiAlias,
                                      child: _AnimatedFavoriteButton(
                                        isFavorite: song?.isFavorite == true,
                                        favoriteColor: p.favorite,
                                        inactiveColor: p.textSecondary,
                                        iconSize: isTablet ? 24 : 22,
                                        onTap: () {
                                          if (song != null) {
                                            cubit.toggleFavorite(song.id);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // Symmetrical Audio Quality Badge (Clean & Centered)
                              if (song != null) ...[
                                const SizedBox(height: 7),
                                Center(
                                  child: AudioQualityBadge(
                                    song: song,
                                    activeColor: activeColor,
                                    compact: true,
                                    showDevice: false,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        SizedBox(height: spacingTrackToSeek),

                        // Interactive Scrubber / Seek Bar
                        PlayerSeekBar(
                          duration: state.duration,
                          activeColor: activeColor,
                          songId: state.currentSong?.id,
                          filePath: state.currentSong?.path,
                          onSeek: (pos) => cubit.seek(pos),
                        ),

                        SizedBox(height: spacingSeekToControls),

                        // F1/F2/F11 advanced playback (AB loop, delay, bookmark)
                        const AdvancedPlaybackBar(),

                        // Studio-grade Playback Controls
                        PlayerControls(
                          isPlaying: state.isPlaying,
                          isShuffle: state.isShuffle,
                          repeatMode: state.repeatMode,
                          primaryColor: activeColor,
                          mainButtonSize:
                              isTablet ? 74 : (isLandscape ? 58 : 66),
                          onPlayPause: () => cubit.togglePlayPause(),
                          onNext: () => cubit.next(),
                          onPrevious: () => cubit.previous(),
                          onToggleShuffle: () => cubit.toggleShuffle(),
                          onToggleRepeat: () => cubit.toggleRepeat(),
                        ),

                        SizedBox(height: spacingControlsToDock),

                        // Floating Glass Bottom Action Dock (Symmetric to View Switcher)
                        _buildBottomActionDock(
                          context: context,
                          props: props,
                          settingsState: settingsState,
                          isTablet: isTablet,
                          barWidth: pillBarWidth,
                          barHeight: pillBarHeight,
                        ),

                        SizedBox(height: spacingBelowDock),
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
                            top: switcherTopPad,
                            bottom: switcherBottomPad,
                          ),
                          child: viewSwitcher,
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, artConstraints) {
                              final double availableWidth =
                                  artConstraints.maxWidth -
                                      (isTablet ? 64.0 : 32.0);
                              final double availableHeight =
                                  artConstraints.maxHeight -
                                      (isTablet ? 24.0 : 12.0);
                              final double maxAllowed =
                                  isTablet ? 560.0 : 420.0;
                              final double dynamicArtSize = math.min(
                                math.min(availableWidth, availableHeight),
                                maxAllowed,
                              ).clamp(180.0, double.infinity);

                              return Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: (state.isLyricsVisible ||
                                            state.isQueueVisible)
                                        ? (isTablet ? 560.0 : double.infinity)
                                        : dynamicArtSize,
                                    maxHeight: (state.isLyricsVisible ||
                                            state.isQueueVisible)
                                        ? double.infinity
                                        : dynamicArtSize,
                                  ),
                                  child: centerDisplay,
                                ),
                              );
                            },
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
  // View Switcher Pill Bar (Track / Lyrics / Queue) - Twin Capsule to EQ Dock
  // ---------------------------------------------------------------------------
  Widget _buildViewSwitcher({
    required BuildContext context,
    required PlayerState state,
    required PlayerCubit cubit,
    required Color activeColor,
    required bool isTablet,
    required double barWidth,
    required double barHeight,
  }) {
    final isLyrics = state.isLyricsVisible;
    final isQueue = state.isQueueVisible;
    final isTrack = !isLyrics && !isQueue;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: barWidth,
          minWidth: barWidth,
          maxHeight: barHeight,
          minHeight: barHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(3.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _SwitcherItem(
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
                  ),
                  Expanded(
                    child: _SwitcherItem(
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
                  ),
                  Expanded(
                    child: _SwitcherItem(
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Floating Glass Bottom Action Dock (5 Actions) - Twin Capsule to Lyrics Bar
  // ---------------------------------------------------------------------------
  Widget _buildBottomActionDock({
    required BuildContext context,
    required PlayerThemeProps props,
    required SettingsState settingsState,
    required bool isTablet,
    required double barWidth,
    required double barHeight,
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

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: barWidth,
          minWidth: barWidth,
          maxHeight: barHeight,
          minHeight: barHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(3.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 1. Equalizer & DSP
                  Expanded(
                    child: _DockIconButton(
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
                  ),

                  // 2. Audio Output & DAC
                  Expanded(
                    child: _DockIconButton(
                      icon: outputIcon,
                      tooltip: 'Audio Output & DAC',
                      isActive: isUsb,
                      activeColor: const Color(0xFFFFD700),
                      inactiveColor: p.textSecondary,
                      isTablet: isTablet,
                      onTap: () {
                        if (song != null) {
                          HapticFeedback.lightImpact();
                          AudioQualitySheet.show(
                              context, song, props.activeColor);
                        }
                      },
                    ),
                  ),

                  // 3. Playback Speed
                  Expanded(
                    child: _DockIconButton(
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
                  ),

                  // 4. Sleep Timer
                  Expanded(
                    child: _DockIconButton(
                      icon: Icons.timer_outlined,
                      tooltip: context.l10n.sleepTimer,
                      badgeText: hasTimer
                          ? (props.cubit.sleepTimerRemainingTracks != null
                              ? '${props.cubit.sleepTimerRemainingTracks} tr'
                              : '${props.state.sleepTimerRemaining!.inMinutes}m')
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
                  ),

                  // 5. Quran Mode
                  Expanded(
                    child: QuranModeDockButton(
                      activeColor: props.activeColor,
                      inactiveColor: p.textSecondary,
                      isTablet: isTablet,
                    ),
                  ),

                  // 6. Add to Playlist
                  Expanded(
                    child: _DockIconButton(
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
                  ),
                ],
              ),
            ),
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
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(
                  color: activeColor.withValues(alpha: 0.45),
                  width: 1.0,
                )
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isTablet ? 16 : 14,
              color: isSelected ? activeColor : Colors.white60,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isTablet ? 13 : 11.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.white60,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            if (badgeCount != null && badgeCount! > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor
                      : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    fontSize: 9.5,
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
    this.iconSize = 24,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Center(
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Tooltip(
        message: tooltip,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.all(isTablet ? 8 : 6),
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
                  size: isTablet ? 22 : 20,
                  color: isActive ? activeColor : inactiveColor,
                ),
              ),
              if (badgeText != null)
                Positioned(
                  top: -2,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
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
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
