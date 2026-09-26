// lib/features/player/presentation/themes/circle_player_theme.dart
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
import '../../../../core/utils/love_feedback.dart';
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

class CirclePlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const CirclePlayerTheme({super.key, required this.props});

  @override
  State<CirclePlayerTheme> createState() => _CirclePlayerThemeState();
}

class _CirclePlayerThemeState extends State<CirclePlayerTheme>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rotationController.duration = context.motionMs(15000);
    _syncRotation();
  }

  void _syncRotation() {
    final shouldAnimate = widget.props.state.isPlaying && context.motionEnabled;
    if (shouldAnimate) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      if (_rotationController.isAnimating) {
        _rotationController.stop();
      }
    }
  }

  @override
  void didUpdateWidget(covariant CirclePlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRotation();
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
          center: const Alignment(0, -0.3),
          radius: 1.2,
          colors: [
            bgColor,
            p.bg,
          ],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = context.isLandscape ||
                (context.isTwoPane || constraints.maxWidth >= 600);

            final double heightRatio =
                (constraints.maxHeight / 720.0).clamp(0.55, 1.25);
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
                            key: ValueKey('queue_view'),
                          )
                        : Center(
                            key: const ValueKey('circle_artwork_view'),
                            child: RotationTransition(
                              turns: _rotationController,
                              child: LayoutBuilder(
                                builder: (context, vinylConstraints) {
                                  final maxDimension =
                                      isLandscape ? 300.0 : (isTablet ? 540.0 : 420.0);
                                  final vinylSize = math.min(
                                    math.min(vinylConstraints.maxWidth,
                                            vinylConstraints.maxHeight) *
                                        0.95,
                                    maxDimension,
                                  );
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
                                        // Outer vinyl grooves
                                        CustomPaint(
                                          size: Size(vinylSize, vinylSize),
                                          painter: _VinylGroovesPainter(),
                                        ),
                                        // Center circular artwork
                                        Container(
                                          width: vinylSize * 0.58,
                                          height: vinylSize * 0.58,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white24,
                                              width: 2,
                                            ),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: song != null
                                              ? CachedArtwork(
                                                  id: song.id,
                                                  remoteUrl: song.remoteArtworkUrl,
                                                  type: ArtworkType.AUDIO,
                                                  size: vinylSize * 0.58,
                                                  borderRadius: 999,
                                                  highQuality: true,
                                                )
                                              : Icon(
                                                  Icons.album_rounded,
                                                  size: vinylSize * 0.25,
                                                  color: Colors.white54,
                                                ),
                                        ),
                                        // Center Spindle Hole
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: p.bg,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white38,
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
                                    showFavoriteFeedback(context, !song.isFavorite);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Symmetrical Audio Quality Badge & Dr. Basbosa Love Pill
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
                  mainButtonSize: (isTablet ? 72.0 : (isLandscape ? 56.0 : 64.0)) * heightRatio.clamp(0.85, 1.10),
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
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
                                    'DR. BASBOSA EDITION',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontSize: AppFontSize.tiny,
                                          letterSpacing: AppTracking.wide,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFFFF85BC),
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

                // Center: Spinning Circle / Lyrics / Queue
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, artConstraints) {
                      final double availableWidth =
                          artConstraints.maxWidth - (isTablet ? 64.0 : 36.0);
                      final double availableHeight =
                          artConstraints.maxHeight - (isTablet ? 24.0 : 12.0);
                      final double maxAllowed = isTablet ? 560.0 : 420.0;
                      final double rawSize =
                          math.min(availableWidth, availableHeight);
                      final double circleArtSize = rawSize <= 0
                          ? 0.0
                          : math.min(rawSize, maxAllowed);

                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: (state.isLyricsVisible ||
                                    state.isQueueVisible)
                                ? (isTablet ? 560.0 : double.infinity)
                                : circleArtSize,
                            maxHeight: (state.isLyricsVisible ||
                                    state.isQueueVisible)
                                ? double.infinity
                                : circleArtSize,
                          ),
                          child: centerDisplay,
                        ),
                      );
                    },
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

class _VinylGroovesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final groovePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (double r = radius * 0.58; r < radius - 8; r += 8) {
      canvas.drawCircle(center, r, groovePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// Sub-widgets
// -----------------------------------------------------------------------------

