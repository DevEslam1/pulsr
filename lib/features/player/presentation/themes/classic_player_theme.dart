// lib/features/player/presentation/themes/classic_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/playlist_suggestions_service.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/responsive/pulsr_layout_metrics.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../core/widgets/waveform_logo.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/usecases/get_songs_usecase.dart';
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
  final ValueNotifier<double?> _dragVolumeNotifier =
      ValueNotifier<double?>(null);
  final ScrollController _queueScrollController = ScrollController();

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

    final (
      :nowPlayingDoubleTap,
      :nowPlayingArtworkSwipe,
      :visualizerStyle,
      :waveformSeekBarEnabled
    ) = context.select<
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

    final isShortLandscape =
        context.isLandscape && MediaQuery.sizeOf(context).height < 480;

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
                  p.deepShade,
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
          top: true,
          bottom: false,
          left: !context.isLandscape,
          right: !context.isLandscape,
          child: Column(
            children: [
              // Top Pull-down Handle Indicator & Top App Bar (hidden in landscape for immersive edge-to-edge view)
              if (!context.isLandscape) ...[
                Padding(
                  padding: const EdgeInsets.only(
                      top: AppSpacing.s6, bottom: AppSpacing.xxs),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm),
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
                                      fontSize: isTablet
                                          ? AppFontSize.body
                                          : AppFontSize.bodySmall,
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
              ],

              // Responsive Two-Pane (Landscape / Tablet) vs Single Column (Portrait)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isLandscape = PulsrLayoutMetrics.isPlayerSplitMode(
                        context, constraints);

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
                        (constraints.maxHeight - (isLandscape ? 56 : 24))
                            .clamp(160.0, isTablet ? 520.0 : 310.0);

                    final double pillBarWidth = math.min(
                      constraints.maxWidth - (isTablet ? 64 : 28),
                      isTablet ? 440.0 : 336.0,
                    );
                    final double pillBarHeight = (isTablet ? 50.0 : 44.0) *
                        heightRatio.clamp(0.85, 1.15);

                    final viewSwitcher = PlayerViewSwitcher(
                      state: state,
                      cubit: cubit,
                      activeColor: activeColor,
                      isTablet: isTablet,
                      barWidth: isLandscape
                          ? math.min(landscapeArtSize, 320.0)
                          : pillBarWidth,
                      barHeight: isLandscape ? 38.0 : pillBarHeight,
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
                                  borderRadius:
                                      BorderRadius.circular(artRadius),
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
                                      color:
                                          Colors.black.withValues(alpha: 0.40),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(artRadius),
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
                                    horizontal: AppSpacing.lg,
                                    vertical: AppSpacing.xxs),
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

                    // Track Info Header: [Download/Playlist] Title/Artist [Heart Favorite]
                    final trackInfoHeader = Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 28 : (isShortLandscape ? 8 : 20),
                        vertical: isShortLandscape ? 0 : AppSpacing.s2,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Left Symmetrical Action: Download (stream) or Add to Playlist (local)
                              SizedBox(
                                width: isShortLandscape ? 38 : 48,
                                height: isShortLandscape ? 38 : 48,
                                child: hasDownload
                                    ? Center(
                                        child: YtmDownloadButton(
                                          song: song,
                                          activeColor: activeColor,
                                          iconColor: p.textSecondary,
                                          iconSize: isTablet
                                              ? 24
                                              : (isShortLandscape ? 20 : 22),
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
                                              AddToPlaylistSheet.show(context,
                                                  song: song);
                                            }
                                          },
                                          child: Center(
                                            child: Icon(
                                              Icons.playlist_add_rounded,
                                              semanticLabel:
                                                  context.l10n.addToPlaylist,
                                              size: isTablet
                                                  ? 24
                                                  : (isShortLandscape
                                                      ? 20
                                                      : 22),
                                              color: p.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),

                              // Center: Title & Artist (Symmetric & Centered)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal:
                                        isShortLandscape ? 6 : AppSpacing.s10,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      MarqueeText(
                                        text: song?.title ??
                                            context.l10n.noTrackSelected,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: isTablet
                                              ? AppFontSize.headline
                                              : (isShortLandscape
                                                  ? AppFontSize.body
                                                  : AppFontSize.title),
                                          fontWeight: FontWeight.w900,
                                          color: p.textPrimary,
                                          height: 1.22,
                                          letterSpacing: AppTracking.title,
                                        ),
                                      ),
                                      SizedBox(
                                          height: isShortLandscape
                                              ? 1
                                              : AppSpacing.xxs),
                                      MarqueeText(
                                        text: song?.artist ??
                                            context.l10n.unknownArtist,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: isTablet
                                              ? AppFontSize.callout
                                              : (isShortLandscape
                                                  ? AppFontSize.caption
                                                  : AppFontSize.bodySmall),
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
                                width: isShortLandscape ? 38 : 48,
                                height: isShortLandscape ? 38 : 48,
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
                                    iconSize: isTablet
                                        ? 24
                                        : (isShortLandscape ? 20 : 22),
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
                            SizedBox(
                                height: isShortLandscape ? 2 : AppSpacing.xs),
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

                          SizedBox(
                              height:
                                  isShortLandscape ? 2.0 : spacingTrackToSeek),

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

                          SizedBox(
                              height: isShortLandscape
                                  ? 2.0
                                  : spacingSeekToControls),

                          // Primary Playback Controls (Shuffle, Previous, Play/Pause, Next, Repeat)
                          PlayerControls(
                            isPlaying: state.isPlaying,
                            isShuffle: state.isShuffle,
                            repeatMode: state.repeatMode,
                            hasPrevious: state.hasPreviousNeighbour,
                            hasNext: state.hasNextNeighbour,
                            abLoopActive: state.abLoopEnabled,
                            primaryColor: activeColor,
                            mainButtonSize: (isTablet
                                    ? 74.0
                                    : (isShortLandscape
                                        ? 52.0
                                        : (isLandscape ? 58.0 : 66.0))) *
                                heightRatio.clamp(0.85, 1.10),
                            onPlayPause: () => cubit.togglePlayPause(),
                            onNext: () => cubit.next(),
                            onPrevious: () => cubit.previous(),
                            onToggleShuffle: () => cubit.toggleShuffle(),
                            onToggleRepeat: () => cubit.toggleRepeat(),
                          ),

                          if (!isShortLandscape) ...[
                            SizedBox(height: spacingControlsToDock),

                            // Secondary advanced playback bar (AB loop, bookmark, delay)
                            const AdvancedPlaybackBar(),

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
                          ] else ...[
                            const SizedBox(height: 6),
                            PlayerBottomActionDock(
                              props: props,
                              isTablet: false,
                              barWidth:
                                  math.min(constraints.maxWidth - 24, 380.0),
                              barHeight: 38.0,
                              dockIconStyle: PlayerDockIconStyle.classic,
                            ),
                          ],
                        ],
                      );
                    }

                    // ── Landscape / Tablet Two-Pane Mode (Inspired by Images 1 & 3) ──
                    // ── Landscape / Tablet Two-Pane Mode (Inspired by Apple Music) ──
                    if (isLandscape) {
                      final bool isLyricsMode = state.isLyricsVisible;
                      final bool isQueueMode = state.isQueueVisible;
                      final bool isSplitContentMode =
                          isLyricsMode || isQueueMode;

                      final Widget leftPaneContent = isSplitContentMode
                          ? Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: isTablet ? 440.0 : 380.0,
                                ),
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // View Switcher Tabs at top of left pane
                                      Padding(
                                        padding: EdgeInsets.only(
                                          bottom: isTablet
                                              ? AppSpacing.lg
                                              : AppSpacing.md,
                                        ),
                                        child: viewSwitcher,
                                      ),
                                      // Controls directly below switcher (Cover and Volume Bar deleted in lyrics mode)
                                      _buildSideControls(
                                        context: context,
                                        state: state,
                                        cubit: cubit,
                                        activeColor: activeColor,
                                        p: p,
                                        song: song,
                                        isTablet: isTablet,
                                        isShortLandscape: isShortLandscape,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Tabs directly above the hero cover
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: AppSpacing.s8),
                                  child: viewSwitcher,
                                ),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: landscapeArtSize,
                                    maxWidth: landscapeArtSize,
                                  ),
                                  child: heroArtwork,
                                ),
                              ],
                            );

                      final insets = MediaQuery.paddingOf(context);
                      final horizontalPad =
                          math.max(16.0, math.max(insets.left, insets.right));

                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet
                              ? math.max(32.0, horizontalPad)
                              : horizontalPad,
                          vertical: isShortLandscape ? 4.0 : 8.0,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Left Pane: Artwork + Controls when in Lyrics/Queue mode, or large Hero Art when in Track mode
                            Expanded(
                              flex: 5,
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: context.motionMs(260),
                                  layoutBuilder:
                                      (currentChild, previousChildren) {
                                    return Stack(
                                      fit: StackFit.expand,
                                      alignment: Alignment.center,
                                      children: <Widget>[
                                        // BUG-FIX: previous panes are fading
                                        // out — prevent them from stealing
                                        // touch events from the incoming pane.
                                        ...previousChildren.map(
                                            (c) => IgnorePointer(child: c)),
                                        if (currentChild != null) currentChild,
                                      ],
                                    );
                                  },
                                  child: KeyedSubtree(
                                    key: ValueKey(
                                        'left_pane_${isSplitContentMode ? "split" : "art"}'),
                                    child: leftPaneContent,
                                  ),
                                ),
                              ),
                            ),

                            SizedBox(width: isTablet ? 32 : 16),

                            // Right Pane: Switchable between Track Controls, Continue Playing Queue, or Lyrics (Apple Music style)
                            Expanded(
                              flex: 6,
                              child: SizedBox.expand(
                                child: AnimatedSwitcher(
                                  duration: context.motionMs(260),
                                  layoutBuilder:
                                      (currentChild, previousChildren) {
                                    return Stack(
                                      fit: StackFit.expand,
                                      alignment: Alignment.center,
                                      children: <Widget>[
                                        // BUG-FIX: previous panes are fading
                                        // out — prevent them from stealing
                                        // touch events from the incoming pane.
                                        ...previousChildren.map(
                                            (c) => IgnorePointer(child: c)),
                                        if (currentChild != null) currentChild,
                                      ],
                                    );
                                  },
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
                                          ? _buildContinuePlayingQueue(
                                              key: const ValueKey(
                                                  'continue_playing_queue'),
                                              context: context,
                                              state: state,
                                              cubit: cubit,
                                              activeColor: activeColor,
                                              p: p,
                                            )
                                          : Center(
                                              key: const ValueKey(
                                                  'track_controls_pane'),
                                              child: SingleChildScrollView(
                                                child: buildControlsColumn(
                                                    includeVolume: true),
                                              ),
                                            ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // ── Portrait / Tablet Left Column Mode ──
                    return Column(
                      children: [
                        // View Switcher Bar (Track | Lyrics | Queue)
                        // Only show on phone portrait where the switcher controls the single screen.
                        // On landscape (e.g. tablet split view), the right pane handles Lyrics/Queue/DSP,
                        // so the left column displays the album artwork on top without a redundant switcher.
                        if (!context.isLandscape)
                          Padding(
                            padding: EdgeInsets.only(
                              top: switcherTopPad,
                              bottom: switcherBottomPad,
                            ),
                            child: viewSwitcher,
                          )
                        else
                          SizedBox(
                              height: isTablet ? AppSpacing.sm : AppSpacing.xs),

                        // Center Display Area (Hero Artwork)
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, artConstraints) {
                              final double availableWidth =
                                  artConstraints.maxWidth -
                                      (isTablet ? 48.0 : 32.0);
                              final double availableHeight =
                                  artConstraints.maxHeight -
                                      (isTablet ? 20.0 : 12.0);
                              final double maxAllowed = isTablet
                                  ? (context.isLandscape ? 400.0 : 560.0)
                                  : 420.0;
                              final double rawSize =
                                  math.min(availableWidth, availableHeight);
                              final double dynamicArtSize = rawSize <= 0
                                  ? 0.0
                                  : math.min(rawSize, maxAllowed);

                              return Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: (state.isLyricsVisible ||
                                                state.isQueueVisible) &&
                                            !context.isLandscape
                                        ? (isTablet ? 560.0 : double.infinity)
                                        : dynamicArtSize,
                                    maxHeight: (state.isLyricsVisible ||
                                                state.isQueueVisible) &&
                                            !context.isLandscape
                                        ? double.infinity
                                        : dynamicArtSize,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: context.motionMs(280),
                                    child: (context.isLandscape ||
                                            (!state.isLyricsVisible &&
                                                !state.isQueueVisible))
                                        ? heroArtwork
                                        : (state.isLyricsVisible
                                            ? LyricsView(
                                                key: ValueKey(
                                                    'lyrics_${song?.id}_${song?.remoteId}'),
                                                lyrics: state.lyrics,
                                                isLoading:
                                                    state.isLoadingLyrics,
                                                activeColor: activeColor,
                                                source: state.lyricsSource,
                                              )
                                            : _buildContinuePlayingQueue(
                                                key: const ValueKey(
                                                    'portrait_queue_view'),
                                                context: context,
                                                state: state,
                                                cubit: cubit,
                                                activeColor: activeColor,
                                                p: p,
                                              )),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        if (showVisualizer && !context.isLandscape) visualizer,

                        buildControlsColumn(
                            includeVolume: context.isLandscape || isTablet),
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

  // ── Apple Music-inspired Side Controls for Lyrics/Queue Two-Pane Mode ──
  Widget _buildSideControls({
    required BuildContext context,
    required PlayerState state,
    required PlayerCubit cubit,
    required Color activeColor,
    required PulsrPalette p,
    required SongsTableData? song,
    required bool isTablet,
    required bool isShortLandscape,
  }) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Track Title & Artist marquee on the left, Favorite and More options on the right
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MarqueeText(
                      text: song?.title ?? l10n.noTrackSelected,
                      style: TextStyle(
                        fontSize: isTablet
                            ? AppFontSize.title
                            : (isShortLandscape ? 13.0 : 15.0),
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                        letterSpacing: AppTracking.title,
                      ),
                    ),
                    const SizedBox(height: 2),
                    MarqueeText(
                      text: (song?.artist != null &&
                              song!.artist.trim().isNotEmpty)
                          ? song.artist.trim()
                          : l10n.unknownArtist,
                      style: TextStyle(
                        fontSize: isTablet
                            ? AppFontSize.bodySmall
                            : (isShortLandscape ? 11.0 : 12.0),
                        fontWeight: FontWeight.w600,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: isShortLandscape ? 32 : 36,
                height: isShortLandscape ? 32 : 36,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: PlayerAnimatedFavoriteButton(
                    isFavorite: song?.isFavorite == true,
                    semanticLabel:
                        song?.isFavorite == true ? l10n.unlike : l10n.like,
                    favoriteColor: p.favorite,
                    inactiveColor: p.textSecondary,
                    iconSize: isShortLandscape ? 18 : 20,
                    onTap: () {
                      if (song != null) cubit.toggleFavorite(song.id);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: isShortLandscape ? 32 : 36,
                height: isShortLandscape ? 32 : 36,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      if (song != null) SongInfoSheet.show(context, song: song);
                    },
                    child: Center(
                      child: Icon(
                        Icons.more_horiz_rounded,
                        semanticLabel: l10n.songInfo,
                        size: isShortLandscape ? 18 : 20,
                        color: p.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: isShortLandscape ? 2 : 4),

        // Scrubber / Seek Bar with timestamps
        PlayerSeekBar(
          duration: state.duration,
          activeColor: activeColor,
          songId: state.currentSong?.id,
          filePath: state.currentSong?.path,
          loopPointA: state.abPointA,
          loopPointB: state.abPointB,
          onSeek: (pos) => cubit.seek(pos),
        ),

        SizedBox(height: isTablet ? AppSpacing.md : AppSpacing.sm),

        // Transport Controls (Shuffle, Prev, Play/Pause, Next, Repeat)
        PlayerControls(
          isPlaying: state.isPlaying,
          isShuffle: state.isShuffle,
          repeatMode: state.repeatMode,
          hasPrevious: state.hasPreviousNeighbour,
          hasNext: state.hasNextNeighbour,
          abLoopActive: state.abLoopEnabled,
          primaryColor: activeColor,
          mainButtonSize: isTablet ? 68.0 : 54.0,
          onPlayPause: () => cubit.togglePlayPause(),
          onNext: () => cubit.next(),
          onPrevious: () => cubit.previous(),
          onToggleShuffle: () => cubit.toggleShuffle(),
          onToggleRepeat: () => cubit.toggleRepeat(),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Continue Playing Queue View (Image 1)
  // ───────────────────────────────────────────────────────────────────────────
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
                  isActive: false,
                  activeColor: activeColor,
                  tooltip: context.l10n.autoplay,
                  onTap: () async {
                    PulsrHaptics.confirm();
                    final seed = state.currentSong;
                    if (seed == null) return;
                    final songsRes =
                        await getIt<GetSongsUseCase>().getAllSongs();
                    if (!context.mounted) return;
                    final all = songsRes.fold<List<SongsTableData>?>(
                        (l) => null, (r) => r);
                    if (all == null || all.isEmpty) return;
                    final exclude = state.queue.map((s) => s.id).toSet();
                    final dj = getIt<PlaylistSuggestionsService>()
                        .buildAutoDjQueue(seed, all,
                            limit: 10, excludeIds: exclude);
                    if (!context.mounted) return;
                    if (dj.isEmpty) {
                      PulsrToast.show(
                        context,
                        message: context.l10n.autoDjEmpty,
                        icon: Icons.all_inclusive_rounded,
                      );
                    } else {
                      await cubit.addAllToQueue(dj);
                      if (context.mounted) {
                        PulsrToast.show(
                          context,
                          message: context.l10n.autoDjAdded(dj.length),
                          icon: Icons.all_inclusive_rounded,
                        );
                      }
                    }
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
                      AudioQualitySheet.show(
                          context, state.currentSong!, activeColor);
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
                  fontSize: AppFontSize.bodyLarge,
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                  letterSpacing: AppTracking.title,
                ),
              ),
              const Spacer(),
              Text(
                context.l10n.trackCount(queue.length),
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Reorderable list of upcoming tracks with thumbnails, titles, and drag handles (≡)
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

                      return Padding(
                        key: ValueKey('queue_${s.id}_$index'),
                        padding: const EdgeInsets.symmetric(vertical: 2.5),
                        child: Material(
                          color: isCurrent
                              ? activeColor.withValues(
                                  alpha: isDark ? 0.16 : 0.10)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadii.r10),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 0),
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
                                fontWeight: isCurrent
                                    ? FontWeight.w800
                                    : FontWeight.w600,
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
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Volume Slider Component (Image 3)
  // ───────────────────────────────────────────────────────────────────────────
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
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 2.0),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget),
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
                constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget),
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

// ─────────────────────────────────────────────────────────────────────────────
// Action Pill Button (Image 1)
// ─────────────────────────────────────────────────────────────────────────────
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
            duration: PulsrDurations.state,
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
