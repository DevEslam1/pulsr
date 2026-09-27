// lib/features/player/presentation/themes/classic_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../core/widgets/waveform_logo.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../sheets/song_info_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/advanced_playback_bar.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_shape.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class ClassicPlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const ClassicPlayerTheme({super.key, required this.props});

  @override
  State<ClassicPlayerTheme> createState() => _ClassicPlayerThemeState();
}

class _ClassicPlayerThemeState extends State<ClassicPlayerTheme> {
  final ValueNotifier<double?> _dragVolumeNotifier = ValueNotifier<double?>(null);
  final ScrollController _queueScrollController = ScrollController();
  bool _autoplayActive = false;

  @override
  void dispose() {
    _dragVolumeNotifier.dispose();
    _queueScrollController.dispose();
    super.dispose();
  }

  double _getHandlerVolume(BuildContext context) {
    try {
      return context.read<PulsrAudioHandler>().volume.clamp(0.0, 1.0);
    } catch (_) {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        return getIt<PulsrAudioHandler>().volume.clamp(0.0, 1.0);
      }
      return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.props;
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final bgColor = props.bgColor;
    final song = state.currentSong;
    final isTablet = context.isTablet;

    final (:nowPlayingDoubleTap, :nowPlayingArtworkSwipe, :visualizerStyle, :waveformSeekBarEnabled) =
        context.select<
            SettingsCubit,
            ({
              NowPlayingDoubleTapAction nowPlayingDoubleTap,
              NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
              VisualizerStyle visualizerStyle,
              bool waveformSeekBarEnabled,
            })>((c) => (
              nowPlayingDoubleTap: c.state.nowPlayingDoubleTap,
              nowPlayingArtworkSwipe: c.state.nowPlayingArtworkSwipe,
              visualizerStyle: c.state.visualizerStyle,
              waveformSeekBarEnabled: c.state.waveformSeekBarEnabled,
            ));

    final artRadius = resolveCustomRadius(context, AppRadii.r28);

    final showVisualizer = visualizerStyle != VisualizerStyle.off &&
        !waveformSeekBarEnabled &&
        !state.isLyricsVisible &&
        !state.isQueueVisible;

    final bool hasDownload = song != null &&
        (song.source == SongSource.youtube ||
            (song.remoteId != null && song.remoteId!.isNotEmpty));

    return Stack(
      children: [
        // 1. Dynamic Ambient Backdrop
        Positioned.fill(
          child: AnimatedContainer(
            duration: context.motionMs(500),
            curve: context.motionCurve(Curves.easeInOut),
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
        PositionedDirectional(
          top: -40,
          start: -30,
          end: -30,
          height: isTablet ? 540 : 420,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: context.motionMs(500),
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
        PositionedDirectional(
          bottom: -70,
          start: 0,
          end: 0,
          height: isTablet ? 420 : 320,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: context.motionMs(500),
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
                padding: const EdgeInsets.only(top: AppSpacing.s6, bottom: AppSpacing.xxs),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(AppRadii.r2),
                    ),
                  ),
                ),
              ),

              // Top App Bar
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 28 : 20,
                  vertical: AppSpacing.xxs,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Dismiss Button
                    SizedBox(
                      width: 48,
                      height: 48,
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
                              semanticLabel: context.l10n.close,
                              size: isTablet ? 26 : 24,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Center: "PLAYING FROM" / Album Header
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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
                                const SizedBox(width: AppSpacing.s6),
                                Text(
                                  context.l10n.playingFrom.toUpperCase(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontSize: AppFontSize.tiny,
                                        letterSpacing: AppTracking.wide,
                                        fontWeight: FontWeight.w800,
                                        color: p.textSecondary
                                            .withValues(alpha: 0.8),
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s2),
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
                                    fontSize: isTablet ? AppFontSize.body : AppFontSize.bodySmall,
                                    color: p.textPrimary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // More Options Button
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.07),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            if (song != null) {
                              SongInfoSheet.show(context, song: song);
                            }
                          },
                          child: Center(
                            child: Icon(
                              Icons.more_horiz_rounded,
                              semanticLabel: context.l10n.songInfo,
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

              const SizedBox(height: AppSpacing.s2),

              // Responsive Two-Pane (Landscape / Tablet) vs Single Column (Portrait)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isLandscape = context.isLandscape ||
                        (context.isTwoPane || constraints.maxWidth >= 600);

                    final double heightRatio =
                        (constraints.maxHeight / 720.0).clamp(0.55, 1.25);
                    final double spacingTrackToSeek =
                        (isTablet ? 14.0 : 8.0) * heightRatio;
                    final double spacingSeekToControls =
                        (isTablet ? 14.0 : 8.0) * heightRatio;
                    final double spacingControlsToDock =
                        (isTablet ? 14.0 : 8.0) * heightRatio;
                    final double spacingBelowDock =
                        (isTablet ? 10.0 : 6.0) * heightRatio;
                    final double switcherTopPad =
                        (isTablet ? 8.0 : 4.0) * heightRatio;
                    final double switcherBottomPad =
                        (isTablet ? 10.0 : 6.0) * heightRatio;

                    final double landscapeArtSize =
                        (constraints.maxHeight - (isTablet ? 36 : 24)).clamp(160.0, isTablet ? 520.0 : 340.0);

                    final double pillBarWidth = math.min(
                      constraints.maxWidth - (isTablet ? 64 : 28),
                      isTablet ? 440.0 : 336.0,
                    );
                    final double pillBarHeight = (isTablet ? 50.0 : 44.0) * heightRatio.clamp(0.85, 1.15);

                    final viewSwitcher = PlayerViewSwitcher(
                      state: state,
                      cubit: cubit,
                      activeColor: activeColor,
                      isTablet: isTablet,
                      barWidth: pillBarWidth,
                      barHeight: pillBarHeight,
                      trackIcon: Icons.music_note_rounded,
                      surfaceFillAlpha: 0.06,
                      borderAlpha: 0.12,
                    );

                    // Hero Album Artwork Widget
                    final heroArtwork = GestureDetector(
                      onTap: () => cubit.toggleLyricsVisibility(),
                      onDoubleTap: () {
                        switch (nowPlayingDoubleTap) {
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
                        if (nowPlayingArtworkSwipe ==
                                NowPlayingArtworkSwipeAction.nextPrev &&
                            details.primaryVelocity != null) {
                          if (details.primaryVelocity! < -200) {
                            cubit.next();
                          } else if (details.primaryVelocity! > 200) {
                            cubit.previous();
                          }
                        }
                      },
                      child: Center(
                        key: const ValueKey('artwork_view'),
                        child: AnimatedScale(
                          scale: state.isPlaying ? 1.0 : 0.97,
                          duration: context.motionMs(320),
                          curve: context.motionCurve(Curves.easeOutCubic),
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: Hero(
                              tag: 'now_playing_art_full',
                              child: AnimatedContainer(
                                duration: context.motionMs(320),
                                curve: context.motionCurve(Curves.easeOutCubic),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(artRadius),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: activeColor.withValues(
                                        alpha: state.isPlaying ? 0.38 : 0.16,
                                      ),
                                      blurRadius: state.isPlaying ? 44 : 26,
                                      spreadRadius: state.isPlaying ? 2 : 0,
                                      offset: const Offset(0, 14),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.40),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(artRadius),
                                  child: song != null
                                      ? CachedArtwork(
                                          id: song.id,
                                          remoteUrl: song.remoteArtworkUrl,
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
                    );

                    final visualizer = showVisualizer
                        ? Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.lg, vertical: AppSpacing.xxs),
                                child: AudioVisualizer(
                                  style: visualizerStyle,
                                  color: activeColor,
                                  height: visualizerStyle == VisualizerStyle.circular
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

                    // Track Info Header: [Download/Playlist] Title/Artist [Heart Favorite]
                    final trackInfoHeader = Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 28 : 20,
                        vertical: AppSpacing.s2,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Left Symmetrical Action: Download (stream) or Add to Playlist (local)
                              SizedBox(
                                width: 48,
                                height: 48,
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
                                        color: Colors.white.withValues(alpha: 0.06),
                                        shape: const CircleBorder(),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          onTap: () {
                                            if (song != null) {
                                              HapticFeedback.lightImpact();
                                              AddToPlaylistSheet.show(context, song: song);
                                            }
                                          },
                                          child: Center(
                                            child: Icon(
                                              Icons.playlist_add_rounded,
                                              semanticLabel: context.l10n.addToPlaylist,
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
                                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      MarqueeText(
                                        text: song?.title ?? context.l10n.noTrackSelected,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: isTablet ? AppFontSize.headline : AppFontSize.title,
                                          fontWeight: FontWeight.w900,
                                          color: p.textPrimary,
                                          height: 1.22,
                                          letterSpacing: AppTracking.title,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.xxs),
                                      MarqueeText(
                                        text: song?.artist ?? context.l10n.unknownArtist,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: isTablet ? AppFontSize.callout : AppFontSize.bodySmall,
                                          fontWeight: FontWeight.w600,
                                          color: p.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Right Symmetrical Action: Animated Heart Favorite Button
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: Material(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  shape: const CircleBorder(),
                                  clipBehavior: Clip.antiAlias,
                                  child: PlayerAnimatedFavoriteButton(
                                    isFavorite: song?.isFavorite == true,
                                    semanticLabel: song?.isFavorite == true
                                        ? context.l10n.unlike
                                        : context.l10n.like,
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

                          // Symmetrical Audio Quality Badge
                          if (song != null) ...[
                            const SizedBox(height: AppSpacing.xs),
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
                    );

                    // Reusable Controls Column
                    Widget buildControlsColumn({required bool includeVolume}) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          trackInfoHeader,

                          SizedBox(height: spacingTrackToSeek),

                          // Interactive Scrubber / Seek Bar
                          PlayerSeekBar(
                            duration: state.duration,
                            activeColor: activeColor,
                            songId: state.currentSong?.id,
                            filePath: state.currentSong?.path,
                            loopPointA: state.abPointA,
                            loopPointB: state.abPointB,
                            onSeek: (pos) => cubit.seek(pos),
                          ),

                          SizedBox(height: spacingSeekToControls),

                          // Advanced playback bar (AB loop, bookmark, delay)
                          const AdvancedPlaybackBar(),

                          // Playback Controls (Shuffle, Previous, Play/Pause, Next, Repeat)
                          PlayerControls(
                            isPlaying: state.isPlaying,
                            isShuffle: state.isShuffle,
                            repeatMode: state.repeatMode,
                            hasPrevious: state.hasPreviousNeighbour,
                            hasNext: state.hasNextNeighbour,
                            abLoopActive: state.abLoopEnabled,
                            primaryColor: activeColor,
                            mainButtonSize:
                                (isTablet ? 74.0 : (isLandscape ? 58.0 : 66.0)) * heightRatio.clamp(0.85, 1.10),
                            onPlayPause: () => cubit.togglePlayPause(),
                            onNext: () => cubit.next(),
                            onPrevious: () => cubit.previous(),
                            onToggleShuffle: () => cubit.toggleShuffle(),
                            onToggleRepeat: () => cubit.toggleRepeat(),
                          ),

                          // Volume Slider (Image 3)
                          if (includeVolume) ...[
                            const SizedBox(height: 4),
                            _buildVolumeSlider(
                              context: context,
                              cubit: cubit,
                              p: p,
                            ),
                          ],

                          SizedBox(height: spacingControlsToDock),

                          // Floating Glass Bottom Action Dock (EQ / Output / Speed / Timer / Quran / Playlist)
                          PlayerBottomActionDock(
                            props: props,
                            isTablet: isTablet,
                            barWidth: pillBarWidth,
                            barHeight: pillBarHeight,
                            dockIconStyle: PlayerDockIconStyle.classic,
                          ),

                          SizedBox(height: spacingBelowDock),
                        ],
                      );
                    }

                    // â”€â”€ Landscape / Tablet Two-Pane Mode (Inspired by Images 1 & 3) â”€â”€
                    if (isLandscape) {
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 32 : 16,
                          vertical: 4,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Left Pane: Always Large Hero Album Artwork Card
                            Expanded(
                              flex: 5,
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: landscapeArtSize,
                                    maxWidth: landscapeArtSize,
                                  ),
                                  child: heroArtwork,
                                ),
                              ),
                            ),

                            SizedBox(width: isTablet ? 32 : 16),

                            // Right Pane: Switchable between Track Controls, Continue Playing Queue, or Lyrics
                            Expanded(
                              flex: 6,
                              child: Column(
                                children: [
                                  // Switcher across the top of right pane
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2, bottom: 8),
                                    child: viewSwitcher,
                                  ),

                                  Expanded(
                                    child: AnimatedSwitcher(
                                      duration: context.motionMs(260),
                                      child: state.isLyricsVisible
                                          ? LyricsView(
                                              key: ValueKey('lyrics_${song?.id}_${song?.remoteId}'),
                                              lyrics: state.lyrics,
                                              isLoading: state.isLoadingLyrics,
                                              activeColor: activeColor,
                                              source: state.lyricsSource,
                                            )
                                          : state.isQueueVisible
                                              ? _buildContinuePlayingQueue(
                                                  key: const ValueKey('continue_playing_queue'),
                                                  context: context,
                                                  state: state,
                                                  cubit: cubit,
                                                  activeColor: activeColor,
                                                  p: p,
                                                )
                                              : Center(
                                                  key: const ValueKey('track_controls_pane'),
                                                  child: SingleChildScrollView(
                                                    child: buildControlsColumn(includeVolume: true),
                                                  ),
                                                ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // â”€â”€ Portrait Mode (Phone & Tablet) â”€â”€
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

                        // Center Display Area
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, artConstraints) {
                              final double availableWidth =
                                  artConstraints.maxWidth - (isTablet ? 64.0 : 32.0);
                              final double availableHeight =
                                  artConstraints.maxHeight - (isTablet ? 24.0 : 12.0);
                              final double maxAllowed = isTablet ? 560.0 : 420.0;
                              final double rawSize = math.min(availableWidth, availableHeight);
                              final double dynamicArtSize = rawSize <= 0 ? 0.0 : math.min(rawSize, maxAllowed);

                              return Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: (state.isLyricsVisible || state.isQueueVisible)
                                        ? (isTablet ? 560.0 : double.infinity)
                                        : dynamicArtSize,
                                    maxHeight: (state.isLyricsVisible || state.isQueueVisible)
                                        ? double.infinity
                                        : dynamicArtSize,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: context.motionMs(280),
                                    child: state.isLyricsVisible
                                        ? LyricsView(
                                            key: ValueKey('lyrics_${song?.id}_${song?.remoteId}'),
                                            lyrics: state.lyrics,
                                            isLoading: state.isLoadingLyrics,
                                            activeColor: activeColor,
                                            source: state.lyricsSource,
                                          )
                                        : state.isQueueVisible
                                            ? _buildContinuePlayingQueue(
                                                key: const ValueKey('portrait_queue_view'),
                                                context: context,
                                                state: state,
                                                cubit: cubit,
                                                activeColor: activeColor,
                                                p: p,
                                              )
                                            : heroArtwork,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        if (showVisualizer) visualizer,

                        buildControlsColumn(includeVolume: false),
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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Continue Playing Queue View (Image 1)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildContinuePlayingQueue({
    Key? key,
    required BuildContext context,
    required PlayerState state,
    required PlayerCubit cubit,
    required Color activeColor,
    required PulsrPalette p,
  }) {
    final queue = state.queue;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      key: key,
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppRadii.r24),
        border: Border.all(color: p.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top 4 Frosted Action Pills: [Shuffle] [Repeat] [Autoplay/Infinity] [Cast/Route] (Image 1)
          Row(
            children: [
              Expanded(
                child: _ActionPillButton(
                  icon: Icons.shuffle_rounded,
                  isActive: state.isShuffle,
                  activeColor: activeColor,
                  tooltip: context.l10n.shuffle,
                  onTap: () {
                    PulsrHaptics.confirm();
                    cubit.toggleShuffle();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionPillButton(
                  icon: state.repeatMode == PlayerRepeatMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  isActive: state.repeatMode != PlayerRepeatMode.off,
                  activeColor: activeColor,
                  tooltip: state.repeatMode == PlayerRepeatMode.one
                      ? context.l10n.repeatOne
                      : (state.repeatMode == PlayerRepeatMode.all
                          ? context.l10n.repeatAll
                          : context.l10n.repeatOff),
                  onTap: () {
                    PulsrHaptics.confirm();
                    cubit.toggleRepeat();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionPillButton(
                  icon: Icons.all_inclusive_rounded,
                  isActive: _autoplayActive,
                  activeColor: activeColor,
                  tooltip: 'Autoplay',
                  onTap: () {
                    PulsrHaptics.confirm();
                    setState(() => _autoplayActive = !_autoplayActive);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionPillButton(
                  icon: Icons.airplay_rounded,
                  isActive: false,
                  activeColor: activeColor,
                  tooltip: context.l10n.audioOutputAndDac,
                  onTap: () {
                    PulsrHaptics.confirm();
                    if (state.currentSong != null) {
                      AudioQualitySheet.show(context, state.currentSong!, activeColor);
                    }
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Header: "Continue Playing"
          Row(
            children: [
              Text(
                context.l10n.queue,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              Text(
                '${queue.length} tracks',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Reorderable list of upcoming tracks with thumbnails, titles, and drag handles (â‰¡)
          Expanded(
            child: queue.isEmpty
                ? Center(
                    child: Text(
                      context.l10n.queueEmpty,
                      style: TextStyle(color: p.textSecondary),
                    ),
                  )
                : ReorderableListView.builder(
                    scrollController: _queueScrollController,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: queue.length,
                    onReorderItem: (oldIndex, newIndex) {
                      PulsrHaptics.selection();
                      cubit.reorderQueue(oldIndex, newIndex);
                    },
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        elevation: 6,
                        color: p.surfaceContainerHigh.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(AppRadii.r14),
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final s = queue[index];
                      final isCurrent = index == state.currentIndex;

                      return Container(
                        key: ValueKey('queue_${s.id}_$index'),
                        margin: const EdgeInsets.symmetric(vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? activeColor.withValues(alpha: isDark ? 0.16 : 0.10)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadii.r10),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.r8),
                            child: CachedArtwork(
                              id: s.id,
                              remoteUrl: s.remoteArtworkUrl,
                              type: ArtworkType.AUDIO,
                              size: 42,
                              borderRadius: 8,
                            ),
                          ),
                          title: Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                              color: isCurrent ? activeColor : p.textPrimary,
                              fontSize: AppFontSize.bodySmall,
                            ),
                          ),
                          subtitle: Text(
                            s.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.caption,
                            ),
                          ),
                          trailing: ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.menu_rounded,
                                color: p.textSecondary.withValues(alpha: 0.6),
                                size: 20,
                              ),
                            ),
                          ),
                          onTap: () {
                            PulsrHaptics.selection();
                            cubit.playSong(s);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Volume Slider Component (Image 3)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildVolumeSlider({
    required BuildContext context,
    required PlayerCubit cubit,
    required PulsrPalette p,
  }) {
    final handlerVolume = _getHandlerVolume(context);
    final l10n = context.l10n;

    return ValueListenableBuilder<double?>(
      valueListenable: _dragVolumeNotifier,
      builder: (context, dragVolume, _) {
        final effectiveVolume = (dragVolume ?? handlerVolume).clamp(0.0, 1.0);
        final isMuted = cubit.isMuted || effectiveVolume <= 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2.0),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  isMuted
                      ? Icons.volume_off_rounded
                      : (effectiveVolume < 0.5
                          ? Icons.volume_down_rounded
                          : Icons.volume_mute_rounded),
                  color: p.textSecondary,
                  size: 20,
                ),
                tooltip: isMuted ? l10n.unmute : l10n.mute,
                onPressed: () {
                  PulsrHaptics.light();
                  cubit.toggleMute();
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: PulsrSlider(
                  min: 0.0,
                  max: 1.0,
                  value: effectiveVolume,
                  height: 26,
                  isWavy: false,
                  activeColor: p.textPrimary,
                  inactiveColor: p.hairline.withValues(alpha: 0.5),
                  onChangeStart: (v) => _dragVolumeNotifier.value = v,
                  onChanged: (v) {
                    _dragVolumeNotifier.value = v;
                    cubit.setVolume(v);
                  },
                  onChangeEnd: (v) {
                    _dragVolumeNotifier.value = null;
                    cubit.setVolume(v);
                  },
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  Icons.volume_up_rounded,
                  color: p.textSecondary,
                  size: 20,
                ),
                tooltip: l10n.volume,
                onPressed: () {
                  PulsrHaptics.light();
                  cubit.adjustVolume(0.05);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Action Pill Button (Image 1)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ActionPillButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionPillButton({
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.r20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.r20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withValues(alpha: 0.28)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05)),
              borderRadius: BorderRadius.circular(AppRadii.r20),
              border: Border.all(
                color: isActive
                    ? activeColor.withValues(alpha: 0.5)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.08)),
                width: 1.0,
              ),
            ),
            child: Icon(
              icon,
              size: 19,
              color: isActive ? activeColor : p.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
