// lib/features/player/presentation/themes/cassette_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
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

class CassettePlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const CassettePlayerTheme({super.key, required this.props});

  @override
  State<CassettePlayerTheme> createState() => _CassettePlayerThemeState();
}

class _CassettePlayerThemeState extends State<CassettePlayerTheme>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spoolController;

  @override
  void initState() {
    super.initState();
    _spoolController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spoolController.duration = context.motionMs(4000);
    _syncSpool();
  }

  void _syncSpool() {
    final shouldAnimate = widget.props.state.isPlaying && context.motionEnabled;
    if (shouldAnimate) {
      if (!_spoolController.isAnimating) {
        _spoolController.repeat();
      }
    } else {
      if (_spoolController.isAnimating) {
        _spoolController.stop();
      }
    }
  }

  @override
  void didUpdateWidget(covariant CassettePlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSpool();
  }

  @override
  void dispose() {
    _spoolController.dispose();
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

        final cassetteBody = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: isLandscape ? 260 : (isTablet ? 360 : 300),
              maxWidth: isLandscape ? 390 : (isTablet ? 540 : 440),
            ),
            child: AspectRatio(
              aspectRatio: 1.5,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2028),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF323646), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Cassette Label Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: activeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'SIDE A • TYPE II (CrO2)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            'PULSR TAPE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: activeColor,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Cassette Center Window with Spinning Spools
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1116),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Left Spool
                            _buildSpool(),
                            // Center Tape Window
                            Container(
                              width: 70,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Center(
                                child: Container(
                                  height: 12,
                                  width: 50,
                                  color: const Color(0xFF5A3825),
                                ),
                              ),
                            ),
                            // Right Spool
                            _buildSpool(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Track Title on Cassette Body
                    Text(
                      song?.title ?? context.l10n.dspTapeLoaded,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
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
                      key: const ValueKey('cassette_view'),
                      child: cassetteBody,
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

              // Center: Cassette / Lyrics / Queue
              Expanded(
                child: LayoutBuilder(
                  builder: (context, artConstraints) {
                    final double availableWidth =
                        artConstraints.maxWidth - (isTablet ? 64.0 : 28.0);
                    final double availableHeight =
                        artConstraints.maxHeight - (isTablet ? 24.0 : 12.0);
                    final double maxW = isTablet ? 560.0 : 440.0;
                    final double maxH = isTablet ? 360.0 : 300.0;
                    final double cassetteW =
                        math.min(availableWidth, maxW).clamp(240.0, double.infinity);
                    final double cassetteH =
                        math.min(availableHeight, maxH).clamp(160.0, double.infinity);

                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: (state.isLyricsVisible ||
                                  state.isQueueVisible)
                              ? (isTablet ? 560.0 : double.infinity)
                              : cassetteW,
                          maxHeight: (state.isLyricsVisible ||
                                  state.isQueueVisible)
                              ? double.infinity
                              : cassetteH,
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

  Widget _buildSpool() {
    return RotationTransition(
      turns: _spoolController,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade400, width: 3),
        ),
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Color(0xFF0F1116),
              shape: BoxShape.circle,
            ),
            child: CustomPaint(painter: _SpoolTeethPainter()),
          ),
        ),
      ),
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
      trackIcon: Icons.radio_rounded,
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

class _SpoolTeethPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0;

    for (int i = 0; i < 6; i++) {
      final angle = i * (math.pi / 3);
      final p1 = Offset(
        center.dx + 4 * math.cos(angle),
        center.dy + 4 * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + 10 * math.cos(angle),
        center.dy + 10 * math.sin(angle),
      );
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// Sub-widgets
// -----------------------------------------------------------------------------

