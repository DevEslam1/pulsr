// lib/features/player/presentation/themes/vinyl_player_theme.dart
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
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import '../widgets/advanced_playback_bar.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';

class VinylPlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const VinylPlayerTheme({super.key, required this.props});

  @override
  State<VinylPlayerTheme> createState() => _VinylPlayerThemeState();
}

class _VinylPlayerThemeState extends State<VinylPlayerTheme>
    with TickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final AnimationController _tonearmController;
  late final Animation<double> _tonearmAnimation;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    _tonearmController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      value: widget.props.state.isPlaying ? 1.0 : 0.0,
    );

    _tonearmAnimation = CurvedAnimation(
      parent: _tonearmController,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tonearmController.duration = context.motionMs(850);
    _syncRotation();
  }

  void _syncRotation() {
    final shouldSpin = widget.props.state.isPlaying && context.motionEnabled;
    if (shouldSpin) {
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
  void didUpdateWidget(covariant VinylPlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.state.isPlaying != oldWidget.props.state.isPlaying) {
      if (widget.props.state.isPlaying) {
        _tonearmController.forward();
      } else {
        _tonearmController.reverse();
      }
    }
    _syncRotation();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _tonearmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.props.state;
    final cubit = widget.props.cubit;
    final p = context.palette;
    final song = state.currentSong;
    final activeColor = widget.props.activeColor;
    final settingsState = context.watch<SettingsCubit>().state;
    final isTablet = context.isTablet;

    final bool hasDownload = song != null &&
        (song.source == SongSource.youtube ||
            (song.remoteId != null && song.remoteId!.isNotEmpty));

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = context.isLandscape &&
            (context.isTwoPane || constraints.maxWidth >= 680);

        // Dynamic vertical spacing ratio for balanced, centered content distribution
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

        final viewSwitcher = _buildViewSwitcher(
          context: context,
          state: state,
          cubit: cubit,
          activeColor: activeColor,
          isTablet: isTablet,
          barWidth: pillBarWidth,
          barHeight: pillBarHeight,
        );

        final bottomDock = _buildBottomActionDock(
          context: context,
          props: widget.props,
          settingsState: settingsState,
          isTablet: isTablet,
          barWidth: pillBarWidth,
          barHeight: pillBarHeight,
        );

        final turntableDeck = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: isLandscape ? 300 : (isTablet ? 480 : 390),
              maxWidth: isLandscape ? 320 : (isTablet ? 500 : 410),
            ),
            child: AspectRatio(
              aspectRatio: 1.04,
              child: LayoutBuilder(
                builder: (context, deckConstraints) {
                  final w = deckConstraints.maxWidth;
                  final h = deckConstraints.maxHeight;

                  // Vinyl record geometry
                  final vinylSize = w * 0.70;
                  final vinylLeft = w * 0.05;
                  final vinylTop = (h - vinylSize) / 2;

                  // Tonearm geometry
                  final pivotOffset = Offset(w * 0.81, h * 0.19);
                  final armLength = w * 0.46;


                  return Semantics(
                    button: true,
                    label: state.isPlaying
                        ? context.l10n.pause
                        : context.l10n.play,
                    excludeSemantics: true,
                    child: GestureDetector(
                    onTap: () => cubit.togglePlayPause(),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF14151C),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: const Color(0xFF282B37),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.65),
                            blurRadius: 28,
                            spreadRadius: 2,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.08),
                            blurRadius: 32,
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 1. Plinth Studio Branding & Active Status
                          Positioned(
                            top: 14,
                            left: 16,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: state.isPlaying
                                        ? activeColor
                                        : Colors.white24,
                                    boxShadow: state.isPlaying
                                        ? [
                                            BoxShadow(
                                              color: activeColor
                                                  .withValues(alpha: 0.8),
                                              blurRadius: 6,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'STUDIO • DIRECT DRIVE',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: Colors.white38,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 2. Platter Strobe Rim
                          Positioned(
                            left: vinylLeft - 4,
                            top: vinylTop - 4,
                            width: vinylSize + 8,
                            height: vinylSize + 8,
                            child: CustomPaint(
                              painter: _PlatterStrobePainter(),
                            ),
                          ),

                          // 3. Spinning Vinyl Record
                          Positioned(
                            left: vinylLeft,
                            top: vinylTop,
                            width: vinylSize,
                            height: vinylSize,
                            child: RotationTransition(
                              turns: _rotationController,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF0C0D11),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: CustomPaint(
                                  painter: _VinylGroovesPainter(
                                    activeColor: activeColor,
                                  ),
                                  child: Center(
                                    // Center Album Artwork
                                    child: Container(
                                      width: vinylSize * 0.44,
                                      height: vinylSize * 0.44,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.3),
                                          width: 1.5,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          if (song != null)
                                            CachedArtwork(
                                              id: song.id,
                                              remoteUrl: song.remoteArtworkUrl,
                                              type: ArtworkType.AUDIO,
                                              size: vinylSize * 0.44,
                                              borderRadius: 999,
                                              highQuality: true,
                                              fallbackIcon:
                                                  Icons.music_note_rounded,
                                            ),
                                          // Center Spindle Hole
                                          Container(
                                            width: 18,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: RadialGradient(
                                                colors: [
                                                  Colors.grey.shade400,
                                                  Colors.grey.shade800,
                                                  const Color(0xFF14172B),
                                                ],
                                                stops: const [0.0, 0.6, 1.0],
                                              ),
                                              border: Border.all(
                                                color: Colors.white30,
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 4. Animated Tonearm Assembly Layer
                          Positioned.fill(
                            child: IgnorePointer(
                              child: BlocSelector<PlayerCubit, PlayerState, Duration>(
                                selector: (s) => s.position,
                                builder: (context, position) {
                                  final progress = state.duration.inMilliseconds > 0
                                      ? (position.inMilliseconds /
                                              state.duration.inMilliseconds)
                                          .clamp(0.0, 1.0)
                                      : 0.0;
                                  final playAngle = 0.35 + (progress * 0.14);
                                  return AnimatedBuilder(
                                    animation: _tonearmAnimation,
                                    builder: (context, child) {
                                      final currentAngle = -0.06 +
                                          ((playAngle - (-0.06)) *
                                              _tonearmAnimation.value);

                                      return CustomPaint(
                                        painter: _TonearmPainter(
                                          pivot: pivotOffset,
                                          angle: currentAngle,
                                          activeColor: activeColor,
                                          armLength: armLength,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),

                          // 5. Bottom Plinth RPM Badge (33⅓ RPM / Standby)
                          Positioned(
                            bottom: 12,
                            left: 14,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: state.isPlaying
                                        ? activeColor.withValues(alpha: 0.15)
                                        : const Color(0xFF181A22),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: state.isPlaying
                                          ? activeColor.withValues(alpha: 0.5)
                                          : const Color(0xFF2B2E3C),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        state.isPlaying
                                            ? Icons.speed_rounded
                                            : Icons.pause_circle_outline_rounded,
                                        size: 11,
                                        color: state.isPlaying
                                            ? activeColor
                                            : Colors.white38,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        state.isPlaying
                                            ? '33⅓ RPM'
                                            : context.l10n.dspStandby,
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                          color: state.isPlaying
                                              ? activeColor
                                              : Colors.white38,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        final centerDisplay = AnimatedSwitcher(
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
                      key: const ValueKey('turntable_view'),
                      child: turntableDeck,
                    ),
        );

        final controlsColumn = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Symmetrical Track Header: [Download/Playlist] Title/Artist [Favorite]
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 28 : 16,
                vertical: 2,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left Action: Download (stream) or Add to Playlist (local)
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
                                color: Colors.white.withValues(alpha: 0.06),
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
                                        backgroundColor: Colors.transparent,
                                        builder: (_) =>
                                            AddToPlaylistSheet(song: song),
                                      );
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
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MarqueeText(
                                text: song?.title ?? context.l10n.noTrackSelected,
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
                                text: song?.artist ?? context.l10n.unknownArtist,
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
                    const SizedBox(height: 6),
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

            // Seek Bar
            PlayerSeekBar(
              duration: state.duration,
              activeColor: activeColor,
              songId: song?.id,
              filePath: song?.path,
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
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 6,
                    child: SingleChildScrollView(
                      child: controlsColumn,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Column(
            children: [
              // Top Pull-down Handle Indicator
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
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

              // Top App Bar - Symmetrical Left/Right Targets & Centered Header
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 28 : 20,
                  vertical: 2,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Dismiss Button (40x40 circle)
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

                    // Center: "PLAYING FROM" / Album Header
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

                    // More Options Button (40x40 circle)
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

              // Top View Switcher (lyrics bar: Track | Lyrics | Queue)
              Padding(
                padding: EdgeInsets.only(
                  top: switcherTopPad,
                  bottom: switcherBottomPad,
                ),
                child: viewSwitcher,
              ),

              // Center: Turntable / Lyrics / Queue
              Expanded(
                child: LayoutBuilder(
                  builder: (context, artConstraints) {
                    final double availableWidth =
                        artConstraints.maxWidth - (isTablet ? 64.0 : 28.0);
                    final double availableHeight =
                        artConstraints.maxHeight - (isTablet ? 24.0 : 12.0);
                    final double maxAllowed = isTablet ? 560.0 : 420.0;
                    final double deckSize = math.min(
                      math.min(availableWidth, availableHeight),
                      maxAllowed,
                    ).clamp(200.0, double.infinity);

                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: (state.isLyricsVisible ||
                                  state.isQueueVisible)
                              ? (isTablet ? 560.0 : double.infinity)
                              : deckSize,
                          maxHeight: (state.isLyricsVisible ||
                                  state.isQueueVisible)
                              ? double.infinity
                              : deckSize,
                        ),
                        child: centerDisplay,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 4),

              // Bottom Controls Section
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: controlsColumn,
              ),
            ],
          ),
        );
      },
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
    // Extracted to player_theme_chrome.dart (A-13); only the tokens this theme
    // actually differed on are passed through.
    return PlayerViewSwitcher(
      state: state,
      cubit: cubit,
      activeColor: activeColor,
      isTablet: isTablet,
      barWidth: barWidth,
      barHeight: barHeight,
      trackIcon: Icons.album_rounded,
      surfaceFillAlpha: 0.06,
      borderAlpha: 0.12,
    );
  }
  Widget _buildBottomActionDock({
    required BuildContext context,
    required PlayerThemeProps props,
    required SettingsState settingsState,
    required bool isTablet,
    required double barWidth,
    required double barHeight,
  }) {
    // Extracted to player_theme_chrome.dart (A-13).
    return PlayerBottomActionDock(
      props: props,
      settingsState: settingsState,
      isTablet: isTablet,
      barWidth: barWidth,
      barHeight: barHeight,
      dockIconStyle: PlayerDockIconStyle.common,
    );
  }
}

// -----------------------------------------------------------------------------
// Sub-widgets
// -----------------------------------------------------------------------------

class _VinylGroovesPainter extends CustomPainter {
  final Color activeColor;

  _VinylGroovesPainter({required this.activeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Vinyl base sheen (radial gradient from center to rim)
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFF181A22),
          Color(0xFF101116),
          Color(0xFF090A0D),
          Color(0xFF14151C),
        ],
        stops: const [0.3, 0.65, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, basePaint);

    // 2. Bilateral specular reflection (the classic vinyl "butterfly" sheen)
    final sheenPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.22, 0.44, 0.50, 0.72, 0.94],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..blendMode = BlendMode.screen;
    canvas.drawCircle(center, radius - 4, sheenPaint);

    // 3. Concentric microgrooves in bands
    final labelRadius = radius * 0.36;
    final leadInRadius = radius - 6;

    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;

    for (double r = labelRadius + 14; r < leadInRadius; r += 2.5) {
      final isBandGap = (r > labelRadius + 38 && r < labelRadius + 42) ||
          (r > labelRadius + 74 && r < labelRadius + 78);
      if (isBandGap) {
        groovePaint.color = Colors.black.withValues(alpha: 0.4);
        groovePaint.strokeWidth = 1.2;
      } else {
        final opacity =
            ((math.sin(r * 0.8) + 1.0) * 0.025 + 0.02).clamp(0.015, 0.055);
        groovePaint.color = Colors.white.withValues(alpha: opacity);
        groovePaint.strokeWidth = 0.6;
      }
      canvas.drawCircle(center, r, groovePaint);
    }

    // 4. Run-out dead wax groove
    final deadWaxPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(center, labelRadius + 5, deadWaxPaint);
    canvas.drawCircle(center, labelRadius + 9, deadWaxPaint);

    // Outer rim bead
    final rimPaint = Paint()
      ..color = const Color(0xFF2B2E3C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 1, rimPaint);
  }

  @override
  bool shouldRepaint(covariant _VinylGroovesPainter oldDelegate) => false;
}

class _PlatterStrobePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer aluminum platter bevel ring
    final bevelPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.grey.shade600,
          Colors.grey.shade400,
          Colors.grey.shade700,
          Colors.grey.shade500,
          Colors.grey.shade600,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawCircle(center, radius - 2, bevelPaint);

    // Strobe dots (like Technics SL-1200)
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    const numDots = 48;
    for (int i = 0; i < numDots; i++) {
      final angle = (i * 2 * math.pi) / numDots;
      final x = center.dx + (radius - 2) * math.cos(angle);
      final y = center.dy + (radius - 2) * math.sin(angle);
      canvas.drawCircle(Offset(x, y), 0.9, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TonearmPainter extends CustomPainter {
  final Offset pivot;
  final double angle;
  final Color activeColor;
  final double armLength;

  _TonearmPainter({
    required this.pivot,
    required this.angle,
    required this.activeColor,
    required this.armLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Arm Rest / Cradle at fixed position
    final restBase = pivot + const Offset(-6, 44);
    _drawArmRest(canvas, restBase);

    // 2. Gimbal Base Mounting Plate (below the pivot)
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFF2C2F3C),
          Color(0xFF1B1D26),
          Color(0xFF0F1015),
        ],
      ).createShader(Rect.fromCircle(center: pivot, radius: 22));
    canvas.drawCircle(pivot, 22, basePaint);

    final baseRimPaint = Paint()
      ..color = const Color(0xFF424658)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(pivot, 22, baseRimPaint);

    // Bearing ring screws (4 small silver dots)
    final screwPaint = Paint()..color = Colors.grey.shade400;
    for (int i = 0; i < 4; i++) {
      final a = (i * math.pi) / 2 + 0.4;
      final sx = pivot.dx + 16 * math.cos(a);
      final sy = pivot.dy + 16 * math.sin(a);
      canvas.drawCircle(Offset(sx, sy), 1.2, screwPaint);
    }

    // Save canvas to rotate the tonearm around the pivot
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);

    // --- EVERYTHING BELOW IS IN LOCAL TONEARM COORDINATES (pivot at 0,0) ---

    // 3. Counterweight (behind the pivot: y < 0)
    final stemPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF8B8E9B), Color(0xFF535664)],
      ).createShader(const Rect.fromLTWH(-2.5, -34, 5, 34))
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-2.5, -34, 5, 34),
        const Radius.circular(2),
      ),
      stemPaint,
    );

    // Counterweight cylinder
    final weightRect = const Rect.fromLTWH(-10, -28, 20, 16);
    final weightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFF9EA2B2),
          Color(0xFFE2E4EB),
          Color(0xFF5A5D6C),
          Color(0xFF383A46),
        ],
        stops: [0.0, 0.35, 0.75, 1.0],
      ).createShader(weightRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(weightRect, const Radius.circular(3)),
      weightPaint,
    );

    // Black calibration ring on counterweight
    final calibRect = const Rect.fromLTWH(-10, -18, 20, 4);
    final calibPaint = Paint()..color = const Color(0xFF14151B);
    canvas.drawRect(calibRect, calibPaint);

    // White calibration tick marks
    final tickPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 0.8;
    for (double tx = -7; tx <= 7; tx += 3.5) {
      canvas.drawLine(Offset(tx, -18), Offset(tx, -14), tickPaint);
    }

    // 4. Drop Shadow of the Tonearm onto the Platter/Record
    final shadowPath = Path();
    final l = armLength;
    shadowPath.moveTo(0, 8);
    shadowPath.cubicTo(
      6,
      l * 0.30,
      -8,
      l * 0.65,
      -3,
      l * 0.90,
    );
    shadowPath.lineTo(-6, l);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);

    canvas.save();
    canvas.translate(7, 7); // shadow offset
    canvas.drawPath(shadowPath, shadowPaint);
    canvas.restore();

    // 5. Tonearm Tube (Polished Chrome S-Curve)
    final tubePath = Path();
    tubePath.moveTo(0, 6);
    tubePath.cubicTo(
      6,
      l * 0.30,
      -8,
      l * 0.65,
      -3,
      l * 0.90,
    );

    final tubePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.grey.shade400,
          Colors.white,
          Colors.grey.shade600,
          Colors.grey.shade800,
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(-10, 0, 20, l))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(tubePath, tubePaint);

    // 6. Headshell Collar (Connector Ring at l * 0.90)
    final collarPaint = Paint()
      ..color = const Color(0xFFC0C3D0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(-3, l * 0.90), 3.2, collarPaint);

    // 7. Headshell & Cartridge
    final headshellStart = Offset(-3, l * 0.90);
    final headshellEnd = Offset(-7, l);

    // Headshell Body (Angled studio cartridge)
    final headshellPath = Path();
    headshellPath.moveTo(headshellStart.dx - 4, headshellStart.dy);
    headshellPath.lineTo(headshellStart.dx + 4, headshellStart.dy);
    headshellPath.lineTo(headshellEnd.dx + 5, headshellEnd.dy + 8);
    headshellPath.lineTo(headshellEnd.dx - 5, headshellEnd.dy + 8);
    headshellPath.close();

    final headshellPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF323544), Color(0xFF161820)],
      ).createShader(
          Rect.fromLTWH(headshellEnd.dx - 6, headshellStart.dy, 12, 22));
    canvas.drawPath(headshellPath, headshellPaint);

    // Cartridge Tip / Stylus Housing (with activeColor accent)
    final stylusHousingRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(headshellEnd.dx - 3.5, headshellEnd.dy + 3, 7, 6),
      const Radius.circular(1.5),
    );
    final stylusHousingPaint = Paint()..color = activeColor;
    canvas.drawRRect(stylusHousingRect, stylusHousingPaint);

    // Stylus Needle Point
    final needlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(headshellEnd.dx, headshellEnd.dy + 9),
      Offset(headshellEnd.dx, headshellEnd.dy + 12),
      needlePaint,
    );

    // Finger Lift (slender curved lever on the right of headshell)
    final fingerLiftPath = Path();
    fingerLiftPath.moveTo(headshellEnd.dx + 4, headshellEnd.dy + 2);
    fingerLiftPath.cubicTo(
      headshellEnd.dx + 12,
      headshellEnd.dy + 1,
      headshellEnd.dx + 14,
      headshellEnd.dy - 6,
      headshellEnd.dx + 11,
      headshellEnd.dy - 10,
    );
    final fingerLiftPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(fingerLiftPath, fingerLiftPaint);

    // 8. Pivot Bearing Cap (on top of gimbal)
    final bearingPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.grey.shade400,
          Colors.grey.shade800,
        ],
      ).createShader(const Rect.fromLTWH(-7, -7, 14, 14));
    canvas.drawCircle(Offset.zero, 6.5, bearingPaint);

    final centerScrewPaint = Paint()..color = const Color(0xFF1A1C24);
    canvas.drawCircle(Offset.zero, 2.5, centerScrewPaint);

    canvas.restore();
  }

  void _drawArmRest(Canvas canvas, Offset pos) {
    // Rest post
    final postPaint = Paint()
      ..color = const Color(0xFF282B36)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: pos, width: 8, height: 14),
        const Radius.circular(2),
      ),
      postPaint,
    );

    // Rest cradle clip (small curved fork)
    final clipPaint = Paint()
      ..color = const Color(0xFF4A4E60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawArc(
      Rect.fromCenter(center: pos + const Offset(0, -3), width: 10, height: 6),
      0,
      math.pi,
      false,
      clipPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TonearmPainter oldDelegate) {
    return oldDelegate.angle != angle ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.armLength != armLength ||
        oldDelegate.pivot != pivot;
  }
}
