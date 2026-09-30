// lib/features/player/presentation/themes/lyrics_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/responsive/pulsr_layout_metrics.dart';
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
import 'player_theme_metrics.dart';
import 'player_theme_chrome.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'player_shape.dart';

class LyricsPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const LyricsPlayerTheme({super.key, required this.props});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final bgColor = props.bgColor;
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
      color: bgColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape =
                PulsrLayoutMetrics.isPlayerSplitMode(context, constraints);

            final m = PlayerThemeMetrics.of(

              isTablet: isTablet,

              isLandscape: isLandscape,

              constraints: constraints,

            );

            final double spacingTrackToSeek = m.spacingTrackToSeek;
            final double spacingSeekToControls = m.spacingSeekToControls;
            final double spacingControlsToDock = m.spacingControlsToDock;
            final double spacingBelowDock = m.spacingBelowDock;
            final double switcherTopPad = m.switcherTopPad;
            final double switcherBottomPad = m.switcherBottomPad;

            final double pillBarWidth = math.min(
              constraints.maxWidth - (isTablet ? 64 : 28),
              isTablet ? 440.0 : 336.0,
            );
            final double pillBarHeight = m.pillBarHeight;

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
              props: props,
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
                    ? Container(
                        key: ValueKey('lyrics_${song?.id}_${song?.remoteId}'),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(AppRadii.r20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: LyricsView(
                          lyrics: state.lyrics,
                          isLoading: state.isLoadingLyrics,
                          activeColor: activeColor,
                          source: state.lyricsSource,
                        ),
                      )
                    : state.isQueueVisible
                        ? const NowPlayingQueueView(
                            key: ValueKey('queue_view_lyrics'),
                          )
                        : Center(
                            key: const ValueKey('track_art_lyrics_focus'),
                            child: LayoutBuilder(
                              builder: (context, artConstraints) {
                                final double availableWidth =
                                    artConstraints.maxWidth -
                                        (isTablet ? 64.0 : 36.0);
                                final double availableHeight =
                                    artConstraints.maxHeight -
                                        (isTablet ? 24.0 : 12.0);
                                final double maxAllowed =
                                    isTablet ? 560.0 : 420.0;
                                final double rawArtSize =
                                    math.min(availableWidth, availableHeight);
                                final double artSize = isLandscape
                                    ? 280.0
                                    : (rawArtSize <= 0
                                        ? 0.0
                                        : math.min(rawArtSize, maxAllowed));

                                return ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: artSize,
                                    maxWidth: artSize,
                                  ),
                                  child: AspectRatio(
                                    aspectRatio: 1.0,
                                    child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                        resolveCustomRadius(context, 20)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: activeColor
                                            .withValues(alpha: 0.35),
                                        blurRadius: 36,
                                        spreadRadius: 2,
                                        offset: const Offset(0, 12),
                                      ),
                                    ],
                                  ),
                                  child: song != null
                                      ? CachedArtwork(
                                          id: song.id,
                                          remoteUrl: song.remoteArtworkUrl,
                                          type: ArtworkType.AUDIO,
                                          size: double.infinity,
                                          borderRadius:
                                              resolveCustomRadius(context, 20),
                                          highQuality: true,
                                        )
                                      : const SizedBox.shrink(),
                                 ),
                               ),
                             );
                           },
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
                            width: 48,
                            height: 48,
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

                      // Symmetrical Audio Quality Badge & Karaoke indicator
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
                                color: activeColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(AppRadii.r6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.mic_rounded,
                                      size: 11, color: activeColor),
                                  const SizedBox(width: AppSpacing.xxs),
                                  Text(
                                    context.l10n.lyrics,
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

                // Playback Controls
                PlayerControls(
                  isPlaying: state.isPlaying,
                  isShuffle: state.isShuffle,
                  repeatMode: state.repeatMode,
                  hasPrevious: state.hasPreviousNeighbour,
                  hasNext: state.hasNextNeighbour,
                  primaryColor: activeColor,
                  mainButtonSize: m.mainButtonSize,
                  onPlayPause: () => cubit.togglePlayPause(),
                  onNext: () => cubit.next(),
                  onPrevious: () => cubit.previous(),
                  onToggleShuffle: () => cubit.toggleShuffle(),
                  onToggleRepeat: () => cubit.toggleRepeat(),
                ),

                if (!isLandscape || constraints.maxHeight >= 480) ...[
                  // F1/F2/F11 advanced playback (AB loop, delay, bookmark)
                  const AdvancedPlaybackBar(),
                ],

                SizedBox(height: spacingControlsToDock),

                // Floating Glass Bottom Action Dock (EQ bar)
                bottomDock,

                SizedBox(height: spacingBelowDock),
              ],
            );

            if (isLandscape) {
              final bool isSplitContentMode = state.isLyricsVisible || state.isQueueVisible;

              final Widget heroArtwork = Center(
                key: const ValueKey('track_art_lyrics_focus_landscape'),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                          resolveCustomRadius(context, 20)),
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.35),
                          blurRadius: 36,
                          spreadRadius: 2,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: song != null
                        ? CachedArtwork(
                            id: song.id,
                            remoteUrl: song.remoteArtworkUrl,
                            type: ArtworkType.AUDIO,
                            size: double.infinity,
                            borderRadius: resolveCustomRadius(context, 20),
                            highQuality: true,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              );

              final Widget leftPaneContent = isSplitContentMode
                  ? Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: m.paneMaxWidth,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: isTablet ? AppSpacing.lg : AppSpacing.md,
                              ),
                              child: viewSwitcher,
                            ),
                            controlsColumn,
                          ],
                        ),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                          child: viewSwitcher,
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: (constraints.maxHeight - 56).clamp(160.0, isTablet ? 520.0 : 310.0),
                            maxWidth: (constraints.maxHeight - 56).clamp(160.0, isTablet ? 520.0 : 310.0),
                          ),
                          child: heroArtwork,
                        ),
                      ],
                    );

              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 32 : 16,
                  vertical: 4,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: context.motionMs(260),
                          child: KeyedSubtree(
                            key: ValueKey('left_pane_${isSplitContentMode ? "split" : "art"}'),
                            child: leftPaneContent,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: isTablet ? 32 : 16),
                    Expanded(
                      flex: 6,
                      child: SizedBox.expand(
                        child: AnimatedSwitcher(
                          duration: context.motionMs(260),
                          layoutBuilder: (currentChild, previousChildren) {
                            return Stack(
                              fit: StackFit.expand,
                              alignment: Alignment.center,
                              children: <Widget>[
                                ...previousChildren,
                                if (currentChild != null) currentChild,
                              ],
                            );
                          },
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
                                      key: ValueKey('queue_view_lyrics'),
                                    )
                                  : Center(
                                      key: const ValueKey('track_controls_pane'),
                                      child: SingleChildScrollView(
                                        child: controlsColumn,
                                      ),
                                    ),
                        ),
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

                // Center: Lyrics Immersion / Artwork / Queue
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isTablet ? 580.0 : double.infinity,
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


