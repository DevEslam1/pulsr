// lib/features/player/presentation/themes/card_player_theme.dart
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
import '../../../../core/widgets/glass_container.dart';
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
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import '../widgets/speed_picker_sheet.dart';
import 'player_theme.dart';

class CardPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const CardPlayerTheme({super.key, required this.props});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final settingsState = context.watch<SettingsCubit>().state;
    final isTablet = context.isTablet;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBgColor = isDark
        ? const Color(0xFF141828).withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.92);
    final cardBorderColor =
        isDark ? Colors.white.withValues(alpha: 0.15) : p.hairline;
    final textTitleColor = isDark ? Colors.white : p.textPrimary;
    final textSubtitleColor = isDark ? Colors.white70 : p.textSecondary;

    final bool hasDownload = song != null &&
        (song.source == SongSource.youtube ||
            (song.remoteId != null && song.remoteId!.isNotEmpty));

    return Stack(
      children: [
        // 1. Full-bleed Artwork Background
        Positioned.fill(
          child: song != null
              ? CachedArtwork(
                  id: song.id,
                  remoteUrl: song.remoteArtworkUrl,
                  type: ArtworkType.AUDIO,
                  size: double.infinity,
                  highQuality: true,
                )
              : Container(color: p.bg),
        ),

        // 2. Adaptive Gradient & Blur Overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.black.withValues(alpha: 0.75),
                        Colors.black.withValues(alpha: 0.95),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.35),
                        Colors.white.withValues(alpha: 0.65),
                        Colors.white.withValues(alpha: 0.92),
                      ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),

        // 3. Foreground Content
        SafeArea(
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
                props: props,
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
                          key: ValueKey(
                              'lyrics_${song?.id}_${song?.remoteId}'),
                          lyrics: state.lyrics,
                          isLoading: state.isLoadingLyrics,
                          activeColor: activeColor,
                          source: state.lyricsSource,
                        )
                      : state.isQueueVisible
                          ? const NowPlayingQueueView(
                              key: ValueKey('queue_view'))
                          : Center(
                              key: const ValueKey('artwork_card'),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: isLandscape ? 260 : 310,
                                  maxWidth: isLandscape ? 260 : 310,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 1.0,
                                  child: Hero(
                                    tag: 'now_playing_art_full',
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(28),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                                alpha: isDark ? 0.6 : 0.2),
                                            blurRadius: 30,
                                            spreadRadius: 4,
                                            offset: const Offset(0, 12),
                                          ),
                                          BoxShadow(
                                            color: activeColor.withValues(
                                                alpha: 0.3),
                                            blurRadius: 24,
                                            spreadRadius: -2,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: song != null
                                          ? CachedArtwork(
                                              id: song.id,
                                              remoteUrl: song.remoteArtworkUrl,
                                              type: ArtworkType.AUDIO,
                                              size: 310,
                                              borderRadius: 28,
                                              highQuality: true,
                                            )
                                          : Container(
                                              decoration: BoxDecoration(
                                                color: p.surfaceContainer,
                                                borderRadius:
                                                    BorderRadius.circular(28),
                                              ),
                                              child: Icon(
                                                Icons.music_note_rounded,
                                                size: 96,
                                                color: textSubtitleColor
                                                    .withValues(alpha: 0.4),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                ),
              );

              final visualizer =
                  (settingsState.visualizerStyle != VisualizerStyle.off &&
                          !state.isLyricsVisible &&
                          !state.isQueueVisible)
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 2),
                          child: AudioVisualizer(
                            style: settingsState.visualizerStyle,
                            color: activeColor,
                            height: settingsState.visualizerStyle ==
                                    VisualizerStyle.circular
                                ? 64
                                : 40,
                            isPlaying: state.isPlaying,
                            audioSessionId: state.audioSessionId,
                          ),
                        )
                      : const SizedBox.shrink();

              final bottomGlassCard = GlassContainer(
                borderRadius: BorderRadius.circular(28),
                blur: 24,
                color: cardBgColor,
                border: Border.all(
                  color: cardBorderColor,
                  width: 1,
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Symmetrical Track Header: [Download/Playlist] Title/Artist [Favorite]
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left Action: Download or Playlist Add
                        SizedBox(
                          width: isTablet ? 46 : 40,
                          height: isTablet ? 46 : 40,
                          child: hasDownload
                              ? Center(
                                  child: YtmDownloadButton(
                                    song: song,
                                    activeColor: activeColor,
                                    iconColor: textSubtitleColor,
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
                                        color: textSubtitleColor,
                                      ),
                                    ),
                                  ),
                                ),
                        ),

                        // Center: Title & Artist
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
                                    color: textTitleColor,
                                    height: 1.22,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                MarqueeText(
                                  text: song?.artist ?? context.l10n.unknownArtist,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: isTablet ? 15 : 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: textSubtitleColor,
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
                              inactiveColor: textSubtitleColor,
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

                    SizedBox(height: spacingTrackToSeek),

                    // Seek Bar
                    PlayerSeekBar(
                      duration: state.duration,
                      activeColor: activeColor,
                      songId: state.currentSong?.id,
                      filePath: state.currentSong?.path,
                      onSeek: (pos) => cubit.seek(pos),
                    ),

                    SizedBox(height: spacingSeekToControls),

                    // Player Controls
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
                  ],
                ),
              );

              if (isLandscape) {
                return Padding(
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
                          child: bottomGlassCard,
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
                                  color: textTitleColor,
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
                                          : textSubtitleColor,
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
                                            color: textSubtitleColor
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
                                        color: textTitleColor,
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
                                  color: textTitleColor,
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

                  // Center Artwork Card / Lyrics / Queue
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: (state.isLyricsVisible || state.isQueueVisible)
                              ? (isTablet ? 560.0 : double.infinity)
                              : 340.0,
                          maxHeight: (state.isLyricsVisible || state.isQueueVisible)
                              ? double.infinity
                              : 310.0,
                        ),
                        child: centerDisplay,
                      ),
                    ),
                  ),

                  if (visualizer != const SizedBox.shrink()) visualizer,

                  const SizedBox(height: 6),

                  // Bottom Card with Controls and EQ Action Dock
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: bottomGlassCard,
                  ),
                ],
              );
            },
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
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
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
                      icon: Icons.layers_rounded,
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

                  // 5. Add to Playlist
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
