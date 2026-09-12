// lib/features/player/presentation/themes/waveform_player_theme.dart
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
import '../widgets/equalizer_sheet.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import '../widgets/advanced_playback_bar.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import '../widgets/quran_mode_button.dart';
import '../widgets/speed_picker_sheet.dart';
import 'player_theme.dart';

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
    if (widget.props.state.isPlaying) {
      _waveController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant WaveformPlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.state.isPlaying && !_waveController.isAnimating) {
      _waveController.repeat();
    } else if (!widget.props.state.isPlaying && _waveController.isAnimating) {
      _waveController.stop();
    }
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
    final settingsState = context.watch<SettingsCubit>().state;
    final isTablet = context.isTablet;

    final bool hasDownload = song != null &&
        (song.source == SongSource.youtube ||
            (song.remoteId != null && song.remoteId!.isNotEmpty));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
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
                                  const EdgeInsets.symmetric(horizontal: 10),
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
                              color: Colors.white.withValues(alpha: 0.06),
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

                      // Symmetrical Audio Quality Badge & Waveform Indicator
                      if (song != null) ...[
                        const SizedBox(height: 6),
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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: activeColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.graphic_eq_rounded,
                                      size: 11, color: activeColor),
                                  const SizedBox(width: 3),
                                  Text(
                                    'WAVEFORM',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
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
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              );
            }

            return Column(
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
                      // Dismiss Button
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

                      // More Options Button
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

                // Center: Waveform Hero Stage / Lyrics / Queue
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: (state.isLyricsVisible || state.isQueueVisible)
                            ? (isTablet ? 560.0 : double.infinity)
                            : (isTablet ? 560.0 : double.infinity),
                        maxHeight: double.infinity,
                      ),
                      child: centerDisplay,
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                // Bottom Controls Section
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: controlsColumn,
                ),
              ],
            );
          },
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
                      icon: Icons.album_rounded,
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

// ---------------------------------------------------------------------------
// Waveform Hero Stage: Concentric Sonic Pulse + Floating Art + Neon Waves
// ---------------------------------------------------------------------------
class _WaveformHeroStage extends StatelessWidget {
  final dynamic song;
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
                  return CustomPaint(
                    painter: _SonicRipplesPainter(
                      color: activeColor,
                      progress: waveController.value,
                      isPlaying: isPlaying,
                      baseRadius: artSize * 0.52,
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
                  return CustomPaint(
                    painter: _FluidAudioWavesPainter(
                      color: activeColor,
                      progress: waveController.value,
                      isPlaying: isPlaying,
                      baselineY: waveBaselineY,
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
                  borderRadius: BorderRadius.circular(28),
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
    this.isActive = false,
    required this.activeColor,
    required this.inactiveColor,
    this.badgeText,
    this.isTablet = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isActive
                      ? activeColor.withValues(alpha: 0.18)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: isTablet ? 22 : 19,
                  color: isActive ? activeColor : inactiveColor,
                ),
              ),
              if (badgeText != null)
                Positioned(
                  top: -2,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 3.5, vertical: 1),
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText!,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
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
