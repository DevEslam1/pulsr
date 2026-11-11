// lib/features/player/presentation/themes/clean_player_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/services/ambient_sound_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/services/cast_service.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../../domain/models/audio_quality_info.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../sheets/sleep_timer_sheet.dart';
import '../../../sheets/song_options_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/ambient_sound_sheet.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/canvas_backdrop.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import '../widgets/player_volume_bar.dart';
import '../widgets/quran_mode_sheet.dart';
import '../widgets/speed_picker_sheet.dart';
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
      :experienceMode,
    ) = context.select<
        SettingsCubit,
        ({
          NowPlayingDoubleTapAction nowPlayingDoubleTap,
          NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
          PlayerSliderStyle playerSliderStyle,
          bool canvasEnabled,
          bool canvasAsBackdrop,
          AppThemeMode themeMode,
          ExperienceMode experienceMode,
        })>((c) => (
          nowPlayingDoubleTap: c.state.nowPlayingDoubleTap,
          nowPlayingArtworkSwipe: c.state.nowPlayingArtworkSwipe,
          playerSliderStyle: c.state.playerSliderStyle,
          canvasEnabled: c.state.canvasEnabled,
          canvasAsBackdrop: c.state.canvasAsBackdrop,
          themeMode: c.state.themeMode,
          experienceMode: c.state.experienceMode,
        ));

    final isInSplitView = PlayerSplitViewScope.of(context);
    final showAbControls = experienceMode == ExperienceMode.professional ||
        state.abPointA != null ||
        state.abPointB != null;
    final hasDownload = song != null &&
        (song.source == SongSource.youtube ||
            (song.remoteId != null && song.remoteId!.isNotEmpty));

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
                padding: const EdgeInsetsDirectional.only(
                  top: AppSpacing.sm,
                  start: AppSpacing.md,
                  end: AppSpacing.md,
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
          // Uses lightweight gradient overlay and clamped size for 60/120fps minimization
          final artworkSize = (constraints.maxWidth * 1.5).clamp(360.0, 720.0);
          final Widget artworkChild = (canvasEnabled &&
                  !canvasAsBackdrop &&
                  song != null)
              ? CanvasBackdrop(
                  song: song,
                  isPlaying: state.isPlaying,
                  isBackdropMode: false,
                  fallbackArtwork: CachedArtwork(
                    id: song.id,
                    albumId: song.albumId,
                    remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                    type: ArtworkType.AUDIO,
                    size: artworkSize,
                    borderRadius: 0,
                  ),
                )
              : CachedArtwork(
                  id: song?.id ?? 0,
                  albumId: song?.albumId,
                  remoteUrl: song?.remoteArtworkUrl ?? song?.artworkUri,
                  type: ArtworkType.AUDIO,
                  size: artworkSize,
                  borderRadius: 0,
                );

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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: Hero(
                      tag: props.heroTag,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxWidth,
                          child: artworkChild,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.transparent,
                              bottomBg.withValues(alpha: 0.18),
                              bottomBg.withValues(alpha: 0.65),
                              bottomBg,
                            ],
                            stops: const [0.0, 0.52, 0.70, 0.88, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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

        // 2. Track Header: Title and Artist with Download/Add to Playlist, Star (Favorite) & More (...) circles
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
                      text: song?.title ?? context.l10n.noTrackSelected,
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
                      song?.artist ?? context.l10n.unknownArtist,
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
              const SizedBox(width: 10),
              // Action buttons on right: Download / Add to Playlist, Star (Favorite) & More (...)
              if (song != null) ...[
                if (hasDownload)
                  _CleanActionCircleButton(
                    tooltip: 'Download',
                    child: YtmDownloadButton(
                      song: song,
                      activeColor: activeColor,
                      iconColor: Colors.white,
                      iconSize: 19,
                    ),
                  )
                else
                  _CleanActionCircleButton(
                    icon: Icons.playlist_add_rounded,
                    iconColor: Colors.white,
                    tooltip: context.l10n.addToPlaylist,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      AddToPlaylistSheet.show(context, song: song);
                    },
                  ),
                const SizedBox(width: 8),
              ],
              _CleanActionCircleButton(
                icon: (song?.isFavorite == true)
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                iconColor: (song?.isFavorite == true)
                    ? AppColors.amberDeep
                    : Colors.white,
                tooltip: (song?.isFavorite == true)
                    ? context.l10n.unlike
                    : context.l10n.like,
                onTap: () {
                  if (song != null) {
                    PulsrHaptics.selection();
                    cubit.toggleFavorite(song.id);
                  }
                },
              ),
              const SizedBox(width: 8),
              _CleanActionCircleButton(
                icon: Icons.more_horiz_rounded,
                iconColor: Colors.white,
                tooltip: context.l10n.moreOptions,
                onTap: () {
                  if (song != null) {
                    HapticFeedback.lightImpact();
                    SongOptionsSheet.show(context, song: song);
                  }
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

        // Bookmark Prompt Banner (Resume playback from saved position)
        final Widget? bookmarkBanner = state.bookmarkPosition != null
            ? Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: PlayerBookmarkPromptBanner(
                  cubit: cubit,
                  position: state.bookmarkPosition!,
                ),
              )
            : null;

        // 4. Playback Controls (Shuffle, Previous, Play/Pause, Next, Repeat, AB Loop)
        final transportControls = _CleanTransportControls(
          props: props,
          activeColor: activeColor,
          isCompact: isShort,
          showAbControls: showAbControls,
        );

        // Volume Bar for tablet / split-view
        final Widget? volumeBar =
            ((isInSplitView || context.isTablet) && !isVeryShort)
                ? Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child:
                        PlayerVolumeBar(cubit: cubit, activeColor: activeColor),
                  )
                : null;

        // 5. Down Bar (Lyrics, EQ, Speed, Audio Output/Cast, Quran, Ambient, Timer, Queue)
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
                            if (bookmarkBanner != null) ...[
                              const SizedBox(height: 8.0),
                              bookmarkBanner,
                              const SizedBox(height: 8.0),
                            ] else ...[
                              SizedBox(height: spacingSeekToControls),
                            ],
                            transportControls,
                            if (volumeBar != null) ...[
                              const SizedBox(height: 8.0),
                              volumeBar,
                              const SizedBox(height: 8.0),
                            ] else ...[
                              SizedBox(height: spacingControlsToDock),
                            ],
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
                  child: RepaintBoundary(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        trackHeader,
                        SizedBox(height: spacingTrackToSeek),
                        cleanSeekBar,
                        if (bookmarkBanner != null) ...[
                          const SizedBox(height: 8.0),
                          bookmarkBanner,
                          const SizedBox(height: 8.0),
                        ] else ...[
                          SizedBox(height: spacingSeekToControls),
                        ],
                        transportControls,
                        if (volumeBar != null) ...[
                          const SizedBox(height: 8.0),
                          volumeBar,
                          const SizedBox(height: 8.0),
                        ] else ...[
                          SizedBox(height: spacingControlsToDock),
                        ],
                        downBar,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        if (isInSplitView) {
          return content;
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
            RepaintBoundary(child: content),
            // Top bar affordance: Grab handle (center)
            const PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              child: SafeArea(
                top: true,
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6.0),
                  child: Center(
                    child: PlayerPlayHandle(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Circular frosted translucent button matching the reference photo (Star and More ...)
class _CleanActionCircleButton extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final Color iconColor;
  final String tooltip;
  final VoidCallback? onTap;

  const _CleanActionCircleButton({
    this.icon,
    this.child,
    this.iconColor = Colors.white,
    required this.tooltip,
    this.onTap,
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
              child: child ?? Icon(icon, size: 20, color: iconColor),
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
  void didUpdateWidget(covariant _CleanSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.song?.id != oldWidget.song?.id) {
      _dragValue = null;
    }
  }

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

/// Bare Apple Music Transport Controls with Shuffle, Repeat & AB Loop affordances
class _CleanTransportControls extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final bool isCompact;
  final bool showAbControls;

  const _CleanTransportControls({
    required this.props,
    required this.activeColor,
    this.isCompact = false,
    this.showAbControls = false,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final isPlaying = state.isPlaying;
    final isBuffering = state.isBuffering;
    final isShuffle = state.isShuffle;
    final repeatMode = state.repeatMode;
    final hasPrev = state.hasPreviousNeighbour;
    final hasNext = state.hasNextNeighbour;
    final abLoopActive = state.abPointA != null && state.abPointB != null;

    final double mainIconSize = isCompact ? 44.0 : 54.0;
    final double sideIconSize = isCompact ? 32.0 : 40.0;
    final double auxIconSize = isCompact ? 22.0 : 25.0;
    final double abButtonSize = isCompact ? 24.0 : 28.0;
    final double buttonGap = isCompact ? 10.0 : 18.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Shuffle Button
            IconButton(
              iconSize: auxIconSize,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: auxIconSize + 14,
                minHeight: auxIconSize + 14,
              ),
              icon: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.shuffle_rounded,
                    color: isShuffle
                        ? activeColor
                        : Colors.white.withValues(alpha: 0.65),
                  ),
                  if (isShuffle)
                    Positioned(
                      bottom: 0,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: activeColor,
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: context.l10n.shuffle,
              onPressed: () {
                PulsrHaptics.selection();
                cubit.toggleShuffle();
              },
            ),
            SizedBox(width: buttonGap),

            // 2. Point A Button (if AB controls active)
            if (showAbControls) ...[
              _CleanAbButton(
                label: 'A',
                point: state.abPointA,
                isActive: state.abPointA != null,
                isLoopActive: abLoopActive,
                activeColor: activeColor,
                buttonSize: abButtonSize,
                tooltip: state.abPointA != null && state.abPointB != null
                    ? context.l10n.repeat
                    : state.abPointA != null
                        ? 'Point A: ${Formatters.formatDuration(state.abPointA!)} (${context.l10n.clearAbLoop})'
                        : context.l10n.abLoopSetA,
                onPressed: () {
                  PulsrHaptics.selection();
                  if (state.abPointA != null && state.abPointB != null) {
                    cubit.toggleAbLoop();
                  } else {
                    cubit.setAbPointA();
                  }
                },
                onLongPress: () {
                  if (state.abPointA != null || state.abPointB != null) {
                    PulsrHaptics.confirm();
                    cubit.clearAbLoop();
                    PulsrToast.show(
                      context,
                      message: context.l10n.clearAbLoop,
                      icon: Icons.clear_rounded,
                      duration: const Duration(milliseconds: 1200),
                    );
                  }
                },
              ),
              SizedBox(width: buttonGap),
            ],

            // 3. Previous / Rewind Button
            IconButton(
              iconSize: sideIconSize,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: sideIconSize + 8,
                minHeight: sideIconSize + 8,
              ),
              icon: const Icon(Icons.fast_rewind_rounded),
              color: hasPrev
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.35),
              tooltip: context.l10n.previous,
              onPressed: hasPrev
                  ? () {
                      PulsrHaptics.selection();
                      cubit.previous();
                    }
                  : null,
            ),
            SizedBox(width: buttonGap),

            // 4. Play / Pause Button
            IconButton(
              iconSize: mainIconSize,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: mainIconSize + 8,
                minHeight: mainIconSize + 8,
              ),
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
              tooltip: isPlaying ? context.l10n.pause : context.l10n.play,
              onPressed: () {
                PulsrHaptics.light();
                cubit.togglePlayPause();
              },
            ),
            SizedBox(width: buttonGap),

            // 5. Next / Fast-Forward Button
            IconButton(
              iconSize: sideIconSize,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: sideIconSize + 8,
                minHeight: sideIconSize + 8,
              ),
              icon: const Icon(Icons.fast_forward_rounded),
              color: hasNext
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.35),
              tooltip: context.l10n.next,
              onPressed: hasNext
                  ? () {
                      PulsrHaptics.selection();
                      cubit.next();
                    }
                  : null,
            ),
            SizedBox(width: buttonGap),

            // 6. Point B Button (if AB controls active)
            if (showAbControls) ...[
              _CleanAbButton(
                label: 'B',
                point: state.abPointB,
                isActive: state.abPointB != null,
                isLoopActive: abLoopActive,
                activeColor: activeColor,
                buttonSize: abButtonSize,
                tooltip: state.abPointA != null && state.abPointB != null
                    ? context.l10n.repeat
                    : state.abPointB != null
                        ? 'Point B: ${Formatters.formatDuration(state.abPointB!)} (${context.l10n.clearAbLoop})'
                        : 'Set loop point B',
                onPressed: () {
                  PulsrHaptics.selection();
                  if (state.abPointA != null && state.abPointB != null) {
                    cubit.toggleAbLoop();
                  } else {
                    cubit.setAbPointB();
                  }
                },
                onLongPress: () {
                  if (state.abPointA != null || state.abPointB != null) {
                    PulsrHaptics.confirm();
                    cubit.clearAbLoop();
                    PulsrToast.show(
                      context,
                      message: context.l10n.clearAbLoop,
                      icon: Icons.clear_rounded,
                      duration: const Duration(milliseconds: 1200),
                    );
                  }
                },
              ),
              SizedBox(width: buttonGap),
            ],

            // 7. Repeat Button
            IconButton(
              iconSize: auxIconSize,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: auxIconSize + 14,
                minHeight: auxIconSize + 14,
              ),
              icon: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    repeatMode == PlayerRepeatMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    color: repeatMode != PlayerRepeatMode.off
                        ? activeColor
                        : Colors.white.withValues(alpha: 0.65),
                  ),
                  if (repeatMode != PlayerRepeatMode.off)
                    Positioned(
                      bottom: 0,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: activeColor,
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: context.l10n.repeat,
              onPressed: () {
                PulsrHaptics.selection();
                cubit.toggleRepeat();
                final nextMode = switch (repeatMode) {
                  PlayerRepeatMode.off => PlayerRepeatMode.all,
                  PlayerRepeatMode.all => PlayerRepeatMode.one,
                  PlayerRepeatMode.one => PlayerRepeatMode.off,
                };
                final nextLabel = switch (nextMode) {
                  PlayerRepeatMode.one => context.l10n.repeatOne,
                  PlayerRepeatMode.all => context.l10n.repeatAll,
                  PlayerRepeatMode.off => context.l10n.repeatOff,
                };
                final nextIcon = switch (nextMode) {
                  PlayerRepeatMode.one => Icons.repeat_one_rounded,
                  PlayerRepeatMode.all => Icons.repeat_rounded,
                  PlayerRepeatMode.off => Icons.repeat_rounded,
                };
                PulsrToast.show(
                  context,
                  message: nextLabel,
                  icon: nextIcon,
                  duration: const Duration(milliseconds: 1200),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular pill button for setting & displaying loop points A & B
class _CleanAbButton extends StatelessWidget {
  final String label;
  final Duration? point;
  final bool isActive;
  final bool isLoopActive;
  final Color activeColor;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;
  final String tooltip;
  final double buttonSize;

  const _CleanAbButton({
    required this.label,
    required this.point,
    required this.isActive,
    required this.isLoopActive,
    required this.activeColor,
    required this.onPressed,
    required this.onLongPress,
    required this.tooltip,
    this.buttonSize = 28.0,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(buttonSize / 2),
          child: Container(
            width: buttonSize,
            height: buttonSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? activeColor.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.12),
              border: Border.all(
                color: isLoopActive
                    ? activeColor
                    : (isActive
                        ? activeColor.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.2)),
                width: isLoopActive ? 1.5 : 1.0,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white70,
                fontSize: buttonSize * 0.44,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Down Bar matching reference photo & loaded with all dock features:
/// Lyrics, Equalizer, Speed, Output / Cast, Quran, Ambient, Timer, Queue
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

    final isUsb = outputDevice?.isUsbDac == true;
    final IconData outputIcon = isCast
        ? Icons.cast_connected_rounded
        : (isUsb
            ? Icons.usb_rounded
            : (outputDevice?.deviceName.contains('Bluetooth') == true ||
                    outputDevice?.deviceName.contains('A2DP') == true
                ? Icons.bluetooth_audio_rounded
                : (outputDevice?.deviceName.contains('Speaker') == true
                    ? Icons.speaker_rounded
                    : (outputDevice?.deviceName.contains('Headphones') == true ||
                            outputDevice?.deviceName.contains('Headset') == true
                        ? Icons.headphones_rounded
                        : Icons.airplay_rounded))));

    int? remainingTracks;
    try {
      remainingTracks = props.state.sleepTimerRemainingTracks ??
          props.cubit.sleepTimerRemainingTracks;
    } catch (_) {
      remainingTracks = props.state.sleepTimerRemainingTracks;
    }
    bool isEndQ = false;
    try {
      isEndQ = props.cubit.isEndOfQueueSleepTimer == true;
    } catch (_) {
      isEndQ = false;
    }
    final hasTimer = props.state.sleepTimerRemaining != null ||
        remainingTracks != null ||
        isEndQ;
    final isEqActive = state.isEqEnabled;
    final speed = state.playbackSpeed;

    Widget buildBar(BuildContext context) {
      final bool isLyricsActive = isInSplit
          ? (splitTabCtrl?.index == 0)
          : state.isLyricsVisible;
      final bool isQueueActive = isInSplit
          ? (splitTabCtrl?.index == 1)
          : state.isQueueVisible;

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 1. Lyrics Button (Left)
                    _DownBarItem(
                      icon: isLyricsActive
                          ? Icons.chat_bubble_rounded
                          : Icons.chat_bubble_outline_rounded,
                      isActive: isLyricsActive,
                      activeColor: activeColor,
                      tooltip: context.l10n.lyrics,
                      onTap: () {
                        PulsrHaptics.selection();
                        if (isInSplit && splitTabCtrl != null) {
                          splitTabCtrl.animateTo(0);
                        } else {
                          cubit.toggleLyricsVisibility();
                        }
                      },
                    ),
                    const SizedBox(width: 4),

                    // 2. Equalizer & DSP Button
                    _DownBarItem(
                      icon: Icons.tune_rounded,
                      isActive: isEqActive,
                      activeColor: activeColor,
                      tooltip: context.l10n.equalizer,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        EqualizerSheet.show(context);
                      },
                    ),
                    const SizedBox(width: 4),

                    // 3. Playback Speed Button
                    _DownBarItem(
                      icon: Icons.speed_rounded,
                      isActive: speed != 1.0,
                      badgeText: speed != 1.0
                          ? '${speed.toStringAsFixed(1)}x'
                          : null,
                      activeColor: activeColor,
                      tooltip: context.l10n.playbackSpeed,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        SpeedPickerSheet.show(context);
                      },
                    ),
                    const SizedBox(width: 4),

                    // 4. Audio Output / Cast / AirPlay Button
                    _DownBarItem(
                      icon: outputIcon,
                      isActive: isCast || isUsb,
                      badgeText: isCast ? 'CAST' : (isUsb ? 'DAC' : null),
                      activeColor: isCast
                          ? AppColors.accentCyan
                          : (isUsb ? AppColors.dacGold : activeColor),
                      tooltip: isCast
                          ? 'Google Cast'
                          : context.l10n.audioOutputAndDac,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (state.currentSong != null) {
                          AudioQualitySheet.show(
                              context, state.currentSong!, activeColor);
                        }
                      },
                    ),
                    const SizedBox(width: 4),

                    // 5. Quran Mode Button
                    _DownBarItem(
                      icon: Icons.auto_stories_rounded,
                      isActive: state.isQuranModeEnabled,
                      activeColor: AppColors.quranEmerald,
                      tooltip: context.l10n.quranMode,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        QuranModeSheet.show(context);
                      },
                    ),
                    const SizedBox(width: 4),

                    // 6. Ambient Sounds Button
                    AnimatedBuilder(
                      animation: AmbientSoundService(),
                      builder: (context, _) {
                        final isAmbientActive =
                            AmbientSoundService().isEnabled;
                        return _DownBarItem(
                          icon: Icons.water_drop_rounded,
                          isActive: isAmbientActive,
                          activeColor: activeColor,
                          tooltip: context.l10n.ambientSounds,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            AmbientSoundSheet.show(context);
                          },
                        );
                      },
                    ),
                    const SizedBox(width: 4),

                    // 7. Sleep Timer Button
                    _DownBarItem(
                      icon: Icons.timer_outlined,
                      isActive: hasTimer,
                      badgeText: hasTimer
                          ? (remainingTracks != null
                              ? '$remainingTracks tr'
                              : (isEndQ
                                  ? 'End'
                                  : (state.sleepTimerRemaining != null
                                      ? formatSleepTimerRemaining(
                                          state.sleepTimerRemaining!)
                                      : '')))
                          : null,
                      activeColor: activeColor,
                      tooltip: isEndQ
                          ? 'Sleep Timer: End of Queue'
                          : (remainingTracks != null
                              ? 'Sleep Timer: $remainingTracks tracks remaining'
                              : (state.sleepTimerRemaining != null
                                  ? 'Sleep Timer: ${formatSleepTimerRemaining(state.sleepTimerRemaining!)} remaining'
                                  : context.l10n.sleepTimer)),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        SleepTimerSheet.show(context);
                      },
                    ),
                    const SizedBox(width: 4),

                    // 8. Queue / Playlist Button (Right)
                    _DownBarItem(
                      icon: Icons.format_list_bulleted_rounded,
                      isActive: isQueueActive,
                      badgeText: state.queue.isNotEmpty
                          ? '${state.queue.length}'
                          : null,
                      activeColor: activeColor,
                      tooltip: context.l10n.queue,
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
            ),
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
  final Color? activeColor;
  final String? badgeText;
  final String tooltip;
  final VoidCallback onTap;

  const _DownBarItem({
    required this.icon,
    required this.isActive,
    this.activeColor,
    this.badgeText,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedColor = activeColor ?? Colors.white;
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: context.motionMs(200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isActive
                      ? resolvedColor.withValues(alpha: 0.22)
                      : Colors.transparent,
                  border: isActive
                      ? Border.all(
                          color: resolvedColor.withValues(alpha: 0.40),
                          width: 1.0,
                        )
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isActive
                      ? resolvedColor
                      : Colors.white.withValues(alpha: 0.70),
                ),
              ),
              if (badgeText != null && badgeText!.isNotEmpty)
                PositionedDirectional(
                  top: -2,
                  end: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 1.0,
                    ),
                    decoration: BoxDecoration(
                      color: resolvedColor,
                      borderRadius: BorderRadius.circular(6.0),
                    ),
                    child: Text(
                      badgeText!,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: resolvedColor.computeLuminance() > 0.4
                            ? Colors.black
                            : Colors.white,
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
