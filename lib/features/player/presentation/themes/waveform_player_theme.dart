// lib/features/player/presentation/themes/waveform_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/motion/pulsr_motion.dart';
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
import '../../../sheets/song_info_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import '../widgets/advanced_playback_bar.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'player_shape.dart';

class WaveformPlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const WaveformPlayerTheme({super.key, required this.props});

  @override
  State<WaveformPlayerTheme> createState() => _WaveformPlayerThemeState();
}

class _WaveformPlayerThemeState extends State<WaveformPlayerTheme>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _waveController.duration = context.motionMs(4000);
    _syncWave();
  }

  void _syncWave() {
    final shouldAnimate = widget.props.state.isPlaying && context.motionEnabled;
    if (shouldAnimate) {
      if (!_waveController.isAnimating) {
        _waveController.repeat();
      }
    } else {
      if (_waveController.isAnimating) {
        _waveController.stop();
      }
    }
  }

  @override
  void didUpdateWidget(covariant WaveformPlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWave();
  }

  @override
  void dispose() {
    _waveController.dispose();
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
    final (:nowPlayingDoubleTap, :nowPlayingArtworkSwipe) =
        context.select<
            SettingsCubit,
            ({
              NowPlayingDoubleTapAction nowPlayingDoubleTap,
              NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
            })>((c) => (
              nowPlayingDoubleTap: c.state.nowPlayingDoubleTap,
              nowPlayingArtworkSwipe: c.state.nowPlayingArtworkSwipe,
            ));
    final isTablet = context.isTablet;

    final bool hasDownload = song != null &&
        (song.source == SongSource.youtube ||
            (song.remoteId != null && song.remoteId!.isNotEmpty));

    return AnimatedContainer(
      duration: context.motionMs(400),
      curve: context.motionCurve(Curves.easeInOut),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 1.3,
          colors: [
            bgColor,
            p.bg,
          ],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = context.isLandscape &&
                (context.isTwoPane || constraints.maxWidth >= 680);

            final double heightRatio =
                (constraints.maxHeight / 720.0).clamp(0.85, 1.25);
            final double spacingTrackToSeek =
                (isTablet ? 10.0 : 6.0) * heightRatio;
            final double spacingSeekToControls =
                (isTablet ? 12.0 : 8.0) * heightRatio;
            final double spacingControlsToDock =
                (isTablet ? 12.0 : 8.0) * heightRatio;
            final double spacingBelowDock =
                (isTablet ? 8.0 : 4.0) * heightRatio;
            final double switcherTopPad =
                (isTablet ? 4.0 : 2.0) * heightRatio;
            final double switcherBottomPad =
                (isTablet ? 6.0 : 3.0) * heightRatio;

            final double pillBarWidth = math.min(
              constraints.maxWidth - (isTablet ? 64 : 36),
              isTablet ? 440.0 : 336.0,
            );
            final double pillBarHeight = isTablet ? 50.0 : 44.0;

            final viewSwitcher = PlayerViewSwitcher(
              state: state,
              cubit: cubit,
              activeColor: activeColor,
              isTablet: isTablet,
              barWidth: pillBarWidth,
              barHeight: pillBarHeight,
              trackIcon: Icons.album_rounded,
              surfaceFillAlpha: 0.06,
              borderAlpha: 0.12,
            );

            final bottomDock = PlayerBottomActionDock(
              props: widget.props,
              isTablet: isTablet,
              barWidth: pillBarWidth,
              barHeight: pillBarHeight,
              dockIconStyle: PlayerDockIconStyle.common,
            );

            final centerDisplay = GestureDetector(
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
              child: AnimatedSwitcher(
                duration: context.motionMs(300),
                child: state.isLyricsVisible
                    ? LyricsView(
                        key: ValueKey('lyrics_${song?.id}_${song?.remoteId}'),
                        lyrics: state.lyrics,
                        isLoading: state.isLoadingLyrics,
                        activeColor: activeColor,
                        source: state.lyricsSource,
                      )
                    : state.isQueueVisible
                        ? const NowPlayingQueueView(
                            key: ValueKey('queue_view_waveform'),
                          )
                        : _WaveformHeroStage(
                            key: const ValueKey('waveform_hero_stage'),
                            song: song,
                            activeColor: activeColor,
                            isPlaying: state.isPlaying,
                            isLandscape: isLandscape,
                            isTablet: isTablet,
                            waveController: _waveController,
                          ),
              ),
            );

            final controlsColumn = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Symmetrical Track Header: [Download/Playlist] Title/Artist [Favorite]
                Padding(
                  padding: EdgeInsets.symmetric(

                    horizontal: isTablet ? 28 : 16,
                    vertical: AppSpacing.s2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left Action: Download (stream) or Add to Playlist (local)
                          SizedBox(
                            width: isTablet ? 48 : 44,
                            height: isTablet ? 48 : 44,
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

                          // Center: Title & Artist
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  MarqueeText(
                                    text: song?.title ??
                                        context.l10n.noTrackSelected,
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
                                    text: song?.artist ??
                                        context.l10n.unknownArtist,
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

                          // Right Symmetrical Action: Animated Favorite Button
                          SizedBox(width: AppSpacing.xxl,
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

                      // Symmetrical Audio Quality Badge & Waveform Indicator
                      if (song != null) ...[
                        const SizedBox(height: AppSpacing.s6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AudioQualityBadge(
                              song: song,
                              activeColor: activeColor,
                              compact: true,
                              showDevice: false,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(

                                  horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
                              decoration: BoxDecoration(
                                color: activeColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(AppRadii.r6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.graphic_eq_rounded,
                                      size: 11, color: activeColor),
                                  const SizedBox(width: AppSpacing.xxs),
                                  Text(
                                    context.l10n.waveformLabel,
                                    style: TextStyle(
                                      fontSize: AppFontSize.micro,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: AppTracking.overline,
                                      color: activeColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                SizedBox(height: spacingTrackToSeek),

                // Seek Bar
                PlayerSeekBar(
                  duration: state.duration,
                  activeColor: activeColor,
                  songId: song?.id,
                  filePath: song?.path,
                  loopPointA: state.abPointA,
                  loopPointB: state.abPointB,
                  onSeek: (pos) => cubit.seek(pos),
                ),

                SizedBox(height: spacingSeekToControls),

                // F1/F2/F11 advanced playback (AB loop, delay, bookmark)
                const AdvancedPlaybackBar(),

                // Playback Controls
                PlayerControls(
                  isPlaying: state.isPlaying,
                  isShuffle: state.isShuffle,
                  repeatMode: state.repeatMode,
                  hasPrevious: state.hasPreviousNeighbour,
                  hasNext: state.hasNextNeighbour,
                  primaryColor: activeColor,
                  mainButtonSize: isTablet ? 72 : (isLandscape ? 56 : 64),
                  onPlayPause: () => cubit.togglePlayPause(),
                  onNext: () => cubit.next(),
                  onPrevious: () => cubit.previous(),
                  onToggleShuffle: () => cubit.toggleShuffle(),
                  onToggleRepeat: () => cubit.toggleRepeat(),
                ),

                SizedBox(height: spacingControlsToDock),

                // Floating Glass Bottom Action Dock (EQ bar)
                bottomDock,

                SizedBox(height: spacingBelowDock),
              ],
            );

            if (isLandscape) {
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              top: switcherTopPad,
                              bottom: switcherBottomPad,
                            ),
                            child: viewSwitcher,
                          ),
                          Expanded(
                            child: centerDisplay,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(
                        child: controlsColumn,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                // Top Pull-down Handle Indicator
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs, bottom: AppSpacing.s2),
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

                // Top App Bar - Symmetrical Left/Right Targets & Centered Header
                Padding(
                  padding: EdgeInsets.symmetric(

                    horizontal: isTablet ? 28 : 20,
                    vertical: AppSpacing.s2,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Dismiss Button
                      SizedBox(
                        width: isTablet ? 48 : 44,
                        height: isTablet ? 48 : 44,
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
                                Icons.keyboard_arrow_down_rounded, semanticLabel: context.l10n.close,
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
                        width: isTablet ? 48 : 44,
                        height: isTablet ? 48 : 44,
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
                                Icons.more_horiz_rounded, semanticLabel: context.l10n.songInfo,
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

                // Top View Switcher (lyrics bar: Track | Lyrics | Queue)
                Padding(
                  padding: EdgeInsets.only(
                    top: switcherTopPad,
                    bottom: switcherBottomPad,
                  ),
                  child: viewSwitcher,
                ),

                // Center: Waveform Hero Stage / Lyrics / Queue
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isTablet ? 560.0 : double.infinity,
                        maxHeight: double.infinity,
                      ),
                      child: centerDisplay,
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xxs),

                // Bottom Controls Section
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: controlsColumn,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

}

// ---------------------------------------------------------------------------
// Waveform Hero Stage: Concentric Sonic Pulse + Floating Art + Neon Waves
// ---------------------------------------------------------------------------
class _WaveformHeroStage extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;
  final bool isPlaying;
  final bool isLandscape;
  final bool isTablet;
  final AnimationController waveController;

  const _WaveformHeroStage({
    super.key,
    required this.song,
    required this.activeColor,
    required this.isPlaying,
    required this.isLandscape,
    required this.isTablet,
    required this.waveController,
  });

  @override
  Widget build(BuildContext context) {
    final song = this.song;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth - (isTablet ? 40.0 : 16.0);
        final availableH = constraints.maxHeight - (isTablet ? 24.0 : 8.0);
        final maxDimension = math.min(availableW, availableH);

        final double artSize = isLandscape
            ? (constraints.maxHeight * 0.82).clamp(160.0, 320.0)
            : math.min(
                maxDimension,
                isTablet ? 560.0 : 420.0,
              ).clamp(180.0, double.infinity);

        final double waveBaselineY =
            (constraints.maxHeight / 2) + (artSize * 0.28);

        return Stack(
          alignment: Alignment.center,
          children: [
            // 1. Concentric Sonic Pulse Rings expanding from center
            Positioned.fill(
              child: AnimatedBuilder(
                animation: waveController,
                builder: (context, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: _SonicRipplesPainter(
                        color: activeColor,
                        progress: waveController.value,
                        isPlaying: isPlaying,
                        baseRadius: artSize * 0.52,
                      ),
                    ),
                  );
                },
              ),
            ),

            // 2. Full-Width Glowing Fluid Soundwave Spectrum (Spanning Across Stage)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: waveController,
                builder: (context, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: _FluidAudioWavesPainter(
                        color: activeColor,
                        progress: waveController.value,
                        isPlaying: isPlaying,
                        baselineY: waveBaselineY,
                      ),
                    ),
                  );
                },
              ),
            ),

            // 3. Center Floating Artwork Squircle with Neon Shadow and Border
            Positioned(
              child: Container(
                width: artSize,
                height: artSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                          resolveCustomRadius(context, AppRadii.r28)),
                  boxShadow: [
                    BoxShadow(
                      color:
                          activeColor.withValues(alpha: isPlaying ? 0.42 : 0.22),
                      blurRadius: isPlaying ? 48 : 28,
                      spreadRadius: isPlaying ? 4 : 1,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.50),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: song != null
                    ? CachedArtwork(
                        id: song.id,
                        remoteUrl: song.remoteArtworkUrl,
                        type: ArtworkType.AUDIO,
                        size: artSize,
                        borderRadius: 28,
                        highQuality: true,
                        fallbackIcon: Icons.music_note_rounded,
                      )
                    : Container(
                        color: Colors.black26,
                        child: Icon(
                          Icons.music_note_rounded,
                          size: artSize * 0.4,
                          color: Colors.white54,
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

// ---------------------------------------------------------------------------
// Sonic Ripples Painter: Expanding acoustic wavefronts radiating outward
// ---------------------------------------------------------------------------
class _SonicRipplesPainter extends CustomPainter {
  final Color color;
  final double progress;
  final bool isPlaying;
  final double baseRadius;

  _SonicRipplesPainter({
    required this.color,
    required this.progress,
    required this.isPlaying,
    required this.baseRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isPlaying) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxExpansion = math.max(size.width, size.height) * 0.50;

    const ringCount = 3;
    for (int i = 0; i < ringCount; i++) {
      final ringProgress = (progress + (i / ringCount)) % 1.0;
      final currentRadius = baseRadius + (ringProgress * maxExpansion);
      // Smooth bell curve opacity: fades in, glows brightly, fades out gently
      final alpha = (math.sin(ringProgress * math.pi) * 0.40).clamp(0.0, 1.0);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.5 * (1.0 - ringProgress * 0.6)).clamp(1.0, 2.5)
        ..color = color.withValues(alpha: alpha);

      canvas.drawCircle(center, currentRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SonicRipplesPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.color != color ||
        oldDelegate.baseRadius != baseRadius;
  }
}

// ---------------------------------------------------------------------------
// Fluid Audio Waves Painter: Harmonic multi-layer neon waves with gradient fills
// ---------------------------------------------------------------------------
class _FluidAudioWavesPainter extends CustomPainter {
  final Color color;
  final double progress;
  final bool isPlaying;
  final double baselineY;

  _FluidAudioWavesPainter({
    required this.color,
    required this.progress,
    required this.isPlaying,
    required this.baselineY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final phase = progress * 2 * math.pi;

    final double midY = baselineY.clamp(height * 0.45, height * 0.85);
    final double amp1 = isPlaying ? 38.0 : 12.0;
    final double amp2 = isPlaying ? 26.0 : 8.0;

    // --- Wave Layer 1: Ambient Background Sine (Deeper tone, soft fill) ---
    final path1 = Path();
    final fill1 = Path();

    fill1.moveTo(0, height);
    path1.moveTo(0, midY);
    fill1.lineTo(0, midY);

    const int steps = 54;
    for (int i = 0; i <= steps; i++) {
      final x = (i / steps) * width;
      final normalX = (i / steps) * 2 * math.pi;
      final y = midY +
          math.sin(normalX * 1.6 + phase * 0.8) * amp1 +
          math.cos(normalX * 0.8 - phase * 0.4) * (amp1 * 0.45);
      path1.lineTo(x, y);
      fill1.lineTo(x, y);
    }

    fill1.lineTo(width, height);
    fill1.close();

    final fillPaint1 = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: isPlaying ? 0.28 : 0.12),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(
          Rect.fromLTWH(0, midY - amp1, width, height - (midY - amp1)));

    final strokePaint1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withValues(alpha: isPlaying ? 0.50 : 0.22);

    canvas.drawPath(fill1, fillPaint1);
    canvas.drawPath(path1, strokePaint1);

    // --- Wave Layer 2: Foreground Crisp Harmonic (Brighter neon crest) ---
    final path2 = Path();
    final fill2 = Path();

    fill2.moveTo(0, height);
    path2.moveTo(0, midY + 6);
    fill2.lineTo(0, midY + 6);

    for (int i = 0; i <= steps; i++) {
      final x = (i / steps) * width;
      final normalX = (i / steps) * 2 * math.pi;
      final y = (midY + 6) +
          math.sin(normalX * 2.2 - phase * 1.2) * amp2 +
          math.sin(normalX * 1.1 + phase * 0.6) * (amp2 * 0.55);
      path2.lineTo(x, y);
      fill2.lineTo(x, y);
    }

    fill2.lineTo(width, height);
    fill2.close();

    final fillPaint2 = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: isPlaying ? 0.40 : 0.18),
          Colors.transparent,
        ],
      ).createShader(
          Rect.fromLTWH(0, midY - amp2, width, height - (midY - amp2)));

    // Neon glow underneath
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..color = color.withValues(alpha: isPlaying ? 0.35 : 0.12);

    final strokePaint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: isPlaying ? 0.95 : 0.50);

    canvas.drawPath(fill2, fillPaint2);
    canvas.drawPath(path2, glowPaint);
    canvas.drawPath(path2, strokePaint2);

    // Peak sparkling neon dots
    if (isPlaying) {
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white;

      final dotGlow = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.6);

      for (int i = 3; i < steps; i += 6) {
        final x = (i / steps) * width;
        final normalX = (i / steps) * 2 * math.pi;
        final y = (midY + 6) +
            math.sin(normalX * 2.2 - phase * 1.2) * amp2 +
            math.sin(normalX * 1.1 + phase * 0.6) * (amp2 * 0.55);
        canvas.drawCircle(Offset(x, y), 5.0, dotGlow);
        canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FluidAudioWavesPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.color != color ||
        oldDelegate.baselineY != baselineY;
  }
}

