// lib/features/player/presentation/themes/card_player_theme.dart
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
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/waveform_logo.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../sheets/song_info_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/audio_visualizer.dart';
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

              final viewSwitcher = PlayerViewSwitcher(
                state: state,
                cubit: cubit,
                activeColor: activeColor,
                isTablet: isTablet,
                barWidth: pillBarWidth,
                barHeight: pillBarHeight,
                trackIcon: Icons.layers_rounded,
                surfaceFillAlpha: 0.08,
                borderAlpha: 0.15,
              );

              final bottomDock = PlayerBottomActionDock(
                props: props,
                settingsState: settingsState,
                isTablet: isTablet,
                barWidth: pillBarWidth,
                barHeight: pillBarHeight,
                dockIconStyle: PlayerDockIconStyle.common,
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
                  duration: context.motionMs(300),
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
                                  maxHeight: isLandscape ? 320 : double.infinity,
                                  maxWidth: isLandscape ? 320 : double.infinity,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 1.0,
                                  child: Hero(
                                    tag: 'now_playing_art_full',
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                          resolveCustomRadius(context, AppRadii.r28)),
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
                                              size: double.infinity,
                                              borderRadius: 28,
                                              highQuality: true,
                                            )
                                          : Container(
                                              decoration: BoxDecoration(
                                                color: p.surfaceContainer,
                                                borderRadius:
                                                    BorderRadius.circular(AppRadii.r28),
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

                              horizontal: AppSpacing.lg, vertical: AppSpacing.s2),
                          child: AudioVisualizer(
                            style: settingsState.visualizerStyle,
                            color: activeColor,
                            height: settingsState.visualizerStyle ==
                                    VisualizerStyle.circular
                                ? 64
                                : 40,
                            isPlaying: state.isPlaying,
                            audioSessionId: state.audioSessionId,
                            trackSeed: song?.id,
                          ),
                        )
                      : const SizedBox.shrink();

              final bottomGlassCard = GlassContainer(
                borderRadius: BorderRadius.circular(
                          resolveCustomRadius(context, AppRadii.r28)),
                blur: 24,
                color: cardBgColor,
                border: Border.all(
                  color: cardBorderColor,
                  width: 1,
                ),
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.s10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Symmetrical Track Header: [Download/Playlist] Title/Artist [Favorite]
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left Action: Download or Playlist Add
                        SizedBox(
                          width: isTablet ? 48 : 44,
                          height: isTablet ? 48 : 44,
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
                                        AddToPlaylistSheet.show(context, song: song);
                                      }
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.playlist_add_rounded,
                                        semanticLabel: context.l10n.addToPlaylist,
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
                                    color: textTitleColor,
                                    height: 1.22,
                                    letterSpacing: AppTracking.title,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s2),
                                MarqueeText(
                                  text: song?.artist ?? context.l10n.unknownArtist,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: isTablet ? AppFontSize.callout : AppFontSize.bodySmall,
                                    fontWeight: FontWeight.w600,
                                    color: textSubtitleColor,
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
                      const SizedBox(height: AppSpacing.s6),
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
                      loopPointA: state.abPointA,
                      loopPointB: state.abPointB,
                      onSeek: (pos) => cubit.seek(pos),
                    ),

                    SizedBox(height: spacingSeekToControls),

                    // F1/F2/F11 advanced playback (AB loop, delay, bookmark)
                    const AdvancedPlaybackBar(),

                    // Player Controls
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
                  ],
                ),
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
                                  color: textTitleColor,
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
                                          : textSubtitleColor,
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
                                            color: textSubtitleColor
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
                                        color: textTitleColor,
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

                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, artConstraints) {
                        final double availableWidth =
                            artConstraints.maxWidth - (isTablet ? 64.0 : 36.0);
                        final double availableHeight =
                            artConstraints.maxHeight - (isTablet ? 24.0 : 12.0);
                        final double maxAllowed = isTablet ? 560.0 : 420.0;
                        final double cardArtSize = math.min(
                          math.min(availableWidth, availableHeight),
                          maxAllowed,
                        ).clamp(180.0, double.infinity);

                        return Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: (state.isLyricsVisible ||
                                      state.isQueueVisible)
                                  ? (isTablet ? 560.0 : double.infinity)
                                  : cardArtSize,
                              maxHeight: (state.isLyricsVisible ||
                                      state.isQueueVisible)
                                  ? double.infinity
                                  : cardArtSize,
                            ),
                            child: centerDisplay,
                          ),
                        );
                      },
                    ),
                  ),

                  if (visualizer != const SizedBox.shrink()) visualizer,

                  const SizedBox(height: AppSpacing.s6),

                  // Bottom Card with Controls and EQ Action Dock
                  Padding(
                    padding: const EdgeInsets.symmetric(

                        horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
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

}

// -----------------------------------------------------------------------------
// Sub-widgets
// -----------------------------------------------------------------------------

