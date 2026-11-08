// lib/features/player/presentation/themes/clean_player_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/services/cast_service.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../../domain/models/audio_quality_info.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../cubit/player_cubit.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/canvas_backdrop.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import '../widgets/player_more_sheet.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart';

/// Clean Apple Music-inspired Player Theme.
///
/// Features:
/// 1. Full-bleed edge-to-edge artwork at the top that dissolves smoothly into
///    the album's ambient background color via a vertical gradient mask.
/// 2. Left-aligned track title and artist with frosted action circles (Favorite & More).
/// 3. Minimal seek bar with tabular timestamps and centered "Lossless" badge pill.
/// 4. Bare, prominent transport controls (no circular background on Play/Pause).
/// 5. Clean bottom actions dock (Lyrics, AirPlay/Audio Output, Queue).
class CleanPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const CleanPlayerTheme({super.key, required this.props});

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (
      :nowPlayingDoubleTap,
      :nowPlayingArtworkSwipe,
      :playerSliderStyle,
      :canvasEnabled,
      :canvasAsBackdrop,
      :themeMode,
    ) = context.select<
        SettingsCubit,
        ({
          NowPlayingDoubleTapAction nowPlayingDoubleTap,
          NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
          PlayerSliderStyle playerSliderStyle,
          bool canvasEnabled,
          bool canvasAsBackdrop,
          AppThemeMode themeMode,
        })>((c) => (
          nowPlayingDoubleTap: c.state.nowPlayingDoubleTap,
          nowPlayingArtworkSwipe: c.state.nowPlayingArtworkSwipe,
          playerSliderStyle: c.state.playerSliderStyle,
          canvasEnabled: c.state.canvasEnabled,
          canvasAsBackdrop: c.state.canvasAsBackdrop,
          themeMode: c.state.themeMode,
        ));

    final isInSplitView = PlayerSplitViewScope.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = PlayerThemeMetrics.calculate(context, constraints);
        final isLandscape = metrics.isLandscape;

        // 1. Upper stage: Full-bleed Artwork with gradient fade, Lyrics, or Queue
        // In tablet split-view, the right pane is dedicated to lyrics / queue / DSP.
        // Therefore, the left deck must ALWAYS display the showcase artwork,
        // never an inline lyrics or queue overlay.
        final Widget upperStage;
        if (!isInSplitView && state.isLyricsVisible) {
          upperStage = KeyedSubtree(
            key: const ValueKey('lyrics_stage'),
            child: SafeArea(
              top: true,
              bottom: false,
              child: SizedBox.expand(
                child: LyricsView(
                  key: ValueKey('lyrics_${song?.id}_${song?.remoteId}'),
                  lyrics: state.lyrics,
                  isLoading: state.isLoadingLyrics,
                  activeColor: activeColor,
                  source: state.lyricsSource,
                  transparentBackground: true,
                ),
              ),
            ),
          );
        } else if (!isInSplitView && state.isQueueVisible) {
          upperStage = KeyedSubtree(
            key: const ValueKey('queue_stage'),
            child: SafeArea(
              top: true,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.sm,
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  bottom: AppSpacing.xs,
                ),
                child: const SizedBox.expand(
                  child: NowPlayingQueueView(key: ValueKey('queue_view')),
                ),
              ),
            ),
          );
        } else {
          // Full-bleed edge-to-edge artwork fading into the background color
          upperStage = KeyedSubtree(
            key: const ValueKey('art_stage'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
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
              child: SizedBox.expand(
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black,
                        Colors.black,
                        Color(0xEE000000),
                        Color(0x99000000),
                        Color(0x33000000),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.58, 0.74, 0.86, 0.95, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: Hero(
                    tag: props.heroTag,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        height: constraints.maxWidth,
                        child: (canvasEnabled &&
                                !canvasAsBackdrop &&
                                song != null)
                            ? CanvasBackdrop(
                                song: song,
                                isPlaying: state.isPlaying,
                                isBackdropMode: false,
                                fallbackArtwork: CachedArtwork(
                                  id: song.id,
                                  albumId: song.albumId,
                                  remoteUrl: song.remoteArtworkUrl ??
                                      song.artworkUri,
                                  type: ArtworkType.AUDIO,
                                  size: constraints.biggest.longestSide,
                                  borderRadius: 0,
                                  highQuality: true,
                                ),
                              )
                            : CachedArtwork(
                                id: song?.id ?? 0,
                                albumId: song?.albumId,
                                remoteUrl: song?.remoteArtworkUrl ??
                                    song?.artworkUri,
                                type: ArtworkType.AUDIO,
                                size: constraints.biggest.longestSide,
                                borderRadius: 0,
                                highQuality: true,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final animatedUpperStage = ClipRect(
          child: AnimatedSwitcher(
            duration: context.motionMs(320),
            transitionBuilder: (child, animation) =>
                playerOverlayTransitionBuilder(context, child, animation),
            child: upperStage,
          ),
        );

        final isShort =
            metrics.isShortHeight || (isInSplitView && constraints.maxHeight < 540);
        final isVeryShort =
            metrics.isVeryShortHeight || (isInSplitView && constraints.maxHeight < 460);

        final spacingTrackToSeek = isVeryShort
            ? 4.0
            : (isShort ? 8.0 : 18.0);
        final spacingSeekToControls = isVeryShort
            ? 6.0
            : (isShort ? 10.0 : 22.0);
        final spacingControlsToDock = isVeryShort
            ? 6.0
            : (isShort ? 12.0 : 26.0);
        final paddingBottom = isVeryShort
            ? 4.0
            : (isShort ? 8.0 : 12.0);

        final horizontalPadding =
            (constraints.maxWidth * 0.06).clamp(12.0, 24.0);

        // 2. Track Header: Title and Artist with Star (Favorite) & More (...) circles
        final trackHeader = Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarqueeText(
                      text: song?.title ?? 'No Track Playing',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize:
                            (metrics.titleFontSize + 2.0).clamp(16.0, 24.0),
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song?.artist ?? 'Unknown Artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize:
                            (metrics.artistFontSize + 1.0).clamp(12.0, 16.5),
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Action buttons on right: Star (Favorite) & More (...)
              _CleanActionCircleButton(
                icon: (song?.isFavorite == true)
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                iconColor: (song?.isFavorite == true)
                    ? const Color(0xFFFFB800)
                    : Colors.white,
                tooltip: 'Favorite',
                onTap: () {
                  if (song != null) {
                    PulsrHaptics.selection();
                    cubit.toggleFavorite(song.id);
                  }
                },
              ),
              const SizedBox(width: 9),
              _CleanActionCircleButton(
                icon: Icons.more_horiz_rounded,
                iconColor: Colors.white,
                tooltip: 'More options',
                onTap: () {
                  HapticFeedback.lightImpact();
                  PlayerMoreSheet.show(context, activeColor: activeColor);
                },
              ),
            ],
          ),
        );

        // 3. Apple-style Seek Bar with Lossless badge & timestamps
        final cleanSeekBar = _CleanSeekBar(
          props: props,
          duration: state.duration,
          song: song,
          activeColor: activeColor,
          sliderStyle: playerSliderStyle,
          horizontalPadding: horizontalPadding,
          isCompact: isShort,
        );

        // 4. Playback Controls (Rewind, Play/Pause without circle, Fast-Forward)
        final transportControls = _CleanTransportControls(
          props: props,
          activeColor: activeColor,
          isCompact: isShort,
        );

        // 5. Down Bar (Lyrics on left, AirPlay/Output centered, Queue on right)
        final downBar = _CleanDownBar(
          props: props,
          activeColor: activeColor,
          horizontalPadding: horizontalPadding,
        );

        // Layout composition
        final Widget content;
        if (isLandscape && !isInSplitView) {
          content = Row(
            children: [
              Expanded(
                flex: 5,
                child: animatedUpperStage,
              ),
              Expanded(
                flex: 5,
                child: SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            trackHeader,
                            SizedBox(height: spacingTrackToSeek),
                            cleanSeekBar,
                            SizedBox(height: spacingSeekToControls),
                            transportControls,
                            SizedBox(height: spacingControlsToDock),
                            downBar,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        } else {
          content = Column(
            children: [
              // Upper Stage: Full-bleed artwork reaching to the top
              Expanded(
                child: animatedUpperStage,
              ),
              // Lower Deck: Metadata, Seek Bar, Transport Controls, and Down Bar
              SafeArea(
                top: false,
                bottom: true,
                child: Padding(
                  padding: EdgeInsets.only(bottom: paddingBottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      trackHeader,
                      SizedBox(height: spacingTrackToSeek),
                      cleanSeekBar,
                      SizedBox(height: spacingSeekToControls),
                      transportControls,
                      SizedBox(height: spacingControlsToDock),
                      downBar,
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        if (isInSplitView) {
          return content;
        }

        final p = context.palette;
        final isAmoled = themeMode == AppThemeMode.amoled;

        final Color topBg;
        final Color bottomBg;
        if (state.isLyricsVisible || state.isQueueVisible) {
          final darkLyricsBg = isAmoled ? Colors.black : p.bg;
          topBg = isDark ? darkLyricsBg : p.bg;
          bottomBg = topBg;
        } else {
          if (isAmoled) {
            topBg = Color.alphaBlend(
              Colors.black.withValues(alpha: 0.40),
              props.bgColor,
            );
            bottomBg = Colors.black;
          } else {
            topBg = props.bgColor;
            bottomBg = Color.alphaBlend(
              Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
              props.bgColor,
            );
          }
        }

        // Rich, dynamic ambient backdrop matching the artwork palette
        return Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [topBg, bottomBg],
                    ),
                  ),
                ),
              ),
            ),
            content,
          ],
        );
      },
    );
  }
}

/// Circular frosted translucent button matching the reference photo (Star and More ...)
class _CleanActionCircleButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String tooltip;
  final VoidCallback onTap;

  const _CleanActionCircleButton({
    required this.icon,
    required this.iconColor,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.16),
            ),
            child: Center(
              child: Icon(icon, size: 20, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sleek seek bar with flanking timestamps and centered "Lossless" badge pill
class _CleanSeekBar extends StatefulWidget {
  final PlayerThemeProps props;
  final Duration duration;
  final SongsTableData? song;
  final Color activeColor;
  final PlayerSliderStyle sliderStyle;
  final double horizontalPadding;
  final bool isCompact;

  const _CleanSeekBar({
    required this.props,
    required this.duration,
    required this.song,
    required this.activeColor,
    required this.sliderStyle,
    this.horizontalPadding = 24.0,
    this.isCompact = false,
  });

  @override
  State<_CleanSeekBar> createState() => _CleanSeekBarState();
}

class _CleanSeekBarState extends State<_CleanSeekBar> {
  double? _dragValue;
  bool _showRemainingTime = true;

  @override
  Widget build(BuildContext context) {
    final position =
        context.select<PlayerCubit, Duration>((c) => c.state.position);
    final isPlaying =
        context.select<PlayerCubit, bool>((c) => c.state.isPlaying);
    final isBuffering =
        context.select<PlayerCubit, bool>((c) => c.state.isBuffering);

    final double maxDuration = widget.duration.inMilliseconds.toDouble();
    final double currentPos = position.inMilliseconds.toDouble();
    final double effectiveValue = (_dragValue ?? currentPos)
        .clamp(0.0, maxDuration > 0 ? maxDuration : 1.0);
    final isDragging = _dragValue != null;
    final currentDuration =
        isDragging ? Duration(milliseconds: _dragValue!.round()) : position;

    final remaining = widget.duration > currentDuration
        ? widget.duration - currentDuration
        : Duration.zero;

    final effectiveStyle = widget.sliderStyle == PlayerSliderStyle.normal
        ? PlayerSliderStyle.capsule
        : widget.sliderStyle;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sleek slider line
          SizedBox(
            height: widget.isCompact ? 22.0 : 28.0,
            child: PulsrSlider(
              value: effectiveValue,
              min: 0.0,
              max: maxDuration > 0 ? maxDuration : 1.0,
              height: widget.isCompact ? 22.0 : 28.0,
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.22),
              thumbColor: Colors.white,
              sliderStyle: effectiveStyle,
              isWavy: effectiveStyle == PlayerSliderStyle.wavy,
              animateWave: isPlaying && !isBuffering,
              onChangeStart: (val) {
                HapticFeedback.selectionClick();
                setState(() => _dragValue = val);
              },
              onChanged: (val) {
                setState(() => _dragValue = val);
              },
              onChangeEnd: (val) {
                widget.props.cubit.seek(Duration(milliseconds: val.round()));
                setState(() => _dragValue = null);
              },
              onChangeCancel: () {
                setState(() => _dragValue = null);
              },
            ),
          ),
          const SizedBox(height: 3),
          // Row with: 0:46 (left), Lossless badge pill (center), -1:30 (right)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                Formatters.formatDuration(currentDuration),
                style: TextStyle(
                  color: isDragging
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: 12.0,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              // Centered Lossless badge pill matching Apple Music
              _CleanLosslessBadgePill(
                song: widget.song,
                activeColor: widget.activeColor,
              ),
              // Right timestamp (toggleable remaining time or duration)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    setState(() => _showRemainingTime = !_showRemainingTime),
                child: Text(
                  _showRemainingTime
                      ? '-${Formatters.formatDuration(remaining)}'
                      : Formatters.formatDuration(widget.duration),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Translucent "Lossless" badge pill matching the photo
class _CleanLosslessBadgePill extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;

  const _CleanLosslessBadgePill({
    required this.song,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    if (song == null) {
      return const SizedBox(height: 22);
    }

    final streamingQuality = context.select<SettingsCubit, YtmAudioQuality>(
      (c) => c.state.streamingQuality,
    );
    final info =
        AudioQualityInfo.fromSong(song, streamingQuality: streamingQuality);

    final String label = (info.tier == AudioQualityTier.lossless ||
            info.shortBadgeLabel.toLowerCase().contains('lossless'))
        ? 'Lossless'
        : (info.tier == AudioQualityTier.hiResLossless
            ? 'Hi-Res Lossless'
            : info.shortBadgeLabel);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => AudioQualitySheet.show(context, song!, activeColor),
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 12,
                color: Colors.white.withValues(alpha: 0.88),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 11.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bare Apple Music Transport Controls (Rewind, Play/Pause, Fast-Forward)
///
/// Play/Pause has NO circular background container — pure, bold icons.
class _CleanTransportControls extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final bool isCompact;

  const _CleanTransportControls({
    required this.props,
    required this.activeColor,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final isPlaying = state.isPlaying;
    final isBuffering = state.isBuffering;

    final double mainIconSize = isCompact ? 46.0 : 56.0;
    final double sideIconSize = isCompact ? 34.0 : 42.0;
    final double buttonGap = isCompact ? 20.0 : 44.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Previous / Rewind
            IconButton(
              iconSize: sideIconSize,
              icon: const Icon(Icons.fast_rewind_rounded),
              color: Colors.white,
              tooltip: 'Previous track',
              onPressed: () {
                PulsrHaptics.selection();
                cubit.previous();
              },
            ),
            SizedBox(width: buttonGap),
            // Play / Pause (bare, large, solid white — no circle backdrop)
            IconButton(
              iconSize: mainIconSize,
              icon: isBuffering
                  ? SizedBox(
                      width: isCompact ? 24 : 32,
                      height: isCompact ? 24 : 32,
                      child: const CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
              tooltip: isPlaying ? 'Pause' : 'Play',
              onPressed: () {
                PulsrHaptics.light();
                cubit.togglePlayPause();
              },
            ),
            SizedBox(width: buttonGap),
            // Next / Fast-Forward
            IconButton(
              iconSize: sideIconSize,
              icon: const Icon(Icons.fast_forward_rounded),
              color: Colors.white,
              tooltip: 'Next track',
              onPressed: () {
                PulsrHaptics.selection();
                cubit.next();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Down Bar matching reference photo:
/// Lyrics (Left), AirPlay / Audio Output (Center), Queue (Right)
class _CleanDownBar extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final double horizontalPadding;

  const _CleanDownBar({
    required this.props,
    required this.activeColor,
    this.horizontalPadding = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final isCast = CastService().sessionStatus.connected;
    final outputDevice = context.select<SettingsCubit, AudioOutputInfo?>(
      (c) => c.state.currentOutputDevice,
    );
    final isInSplit = PlayerSplitViewScope.of(context);
    final splitTabCtrl = PlayerSplitViewScope.tabControllerOf(context);

    final IconData outputIcon = isCast
        ? Icons.cast_connected_rounded
        : (outputDevice?.deviceName.contains('Bluetooth') == true
            ? Icons.bluetooth_audio_rounded
            : (outputDevice?.deviceName.contains('Speaker') == true
                ? Icons.speaker_rounded
                : Icons.airplay_rounded));

    Widget buildBar(BuildContext context) {
      final bool isLyricsActive = isInSplit
          ? (splitTabCtrl?.index == 0)
          : state.isLyricsVisible;
      final bool isQueueActive = isInSplit
          ? (splitTabCtrl?.index == 1)
          : state.isQueueVisible;

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Lyrics Button (Left)
              _DownBarItem(
                icon: isLyricsActive
                    ? Icons.chat_bubble_rounded
                    : Icons.chat_bubble_outline_rounded,
                isActive: isLyricsActive,
                tooltip: 'Lyrics',
                onTap: () {
                  PulsrHaptics.selection();
                  if (isInSplit && splitTabCtrl != null) {
                    splitTabCtrl.animateTo(0);
                  } else {
                    cubit.toggleLyricsVisibility();
                  }
                },
              ),
              const SizedBox(width: 24),
              // 2. Audio Output / Cast / AirPlay Button (Center)
              _DownBarItem(
                icon: outputIcon,
                isActive: isCast,
                tooltip: isCast ? 'Google Cast' : 'Audio Output',
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (state.currentSong != null) {
                    AudioQualitySheet.show(
                        context, state.currentSong!, activeColor);
                  }
                },
              ),
              const SizedBox(width: 24),
              // 3. Queue / Playlist Button (Right)
              _DownBarItem(
                icon: Icons.format_list_bulleted_rounded,
                isActive: isQueueActive,
                tooltip: 'Queue',
                onTap: () {
                  PulsrHaptics.selection();
                  if (isInSplit && splitTabCtrl != null) {
                    splitTabCtrl.animateTo(1);
                  } else {
                    cubit.toggleQueueVisibility();
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    if (isInSplit && splitTabCtrl != null) {
      return AnimatedBuilder(
        animation: splitTabCtrl.animation ?? splitTabCtrl,
        builder: (context, _) => buildBar(context),
      );
    }
    return buildBar(context);
  }
}

class _DownBarItem extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final String tooltip;
  final VoidCallback onTap;

  const _DownBarItem({
    required this.icon,
    required this.isActive,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: context.motionMs(200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isActive
                  ? Colors.white.withValues(alpha: 0.20)
                  : Colors.transparent,
            ),
            child: Icon(
              icon,
              size: 24,
              color: isActive
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.65),
            ),
          ),
        ),
      ),
    );
  }
}
