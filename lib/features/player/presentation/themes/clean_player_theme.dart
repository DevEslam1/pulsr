// lib/features/player/presentation/themes/clean_player_theme.dart
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
import '../widgets/audio_visualizer.dart';
import '../widgets/canvas_backdrop.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/player_gesture_scope.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import '../widgets/player_volume_bar.dart';
import '../widgets/quran_mode_sheet.dart';
import '../widgets/radio_now_playing_recommendations.dart';
import '../widgets/speed_picker_sheet.dart';
import '../widgets/waveform_seek_bar.dart';
import '../../../../core/services/waveform_service.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart';

part 'parts/clean_player_theme_deck_colors.dart';
part 'parts/clean_player_theme_header.dart';
part 'parts/clean_player_theme_stage.dart';
part 'parts/clean_player_theme_seek_bar.dart';
part 'parts/clean_player_theme_transport.dart';
part 'parts/clean_player_theme_dock.dart';

/// Clean Apple Music-inspired Player Theme.
///
/// Features:
/// 1. Full-bleed edge-to-edge artwork at the top that dissolves smoothly into
///    the album's ambient background color via a vertical gradient mask.
/// 2. Left-aligned track title and artist with frosted action circles (Favorite
///    & More).
/// 3. Minimal seek bar with tabular timestamps and centered "Lossless" badge
///    pill.
/// 4. Bare, prominent transport controls (no circular background on
///    Play/Pause).
/// 5. Clean bottom actions dock (Lyrics, AirPlay/Audio Output, Queue).
///
/// This file holds the public theme plus the layout composition only; the
/// private widgets live in `parts/clean_player_theme_*.dart`. That split is not
/// cosmetic: the deck used to hardcode `Colors.white` in six different widgets,
/// which is exactly how it drifted into white-on-light in `AuraTheme.lightTheme`.
/// One [_CleanDeckColors] resolution per widget keeps the foreground palette in
/// a single, brightness-aware place.
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
      :playerSliderStyle,
      :canvasEnabled,
      :canvasAsBackdrop,
      :themeMode,
      :visualizerStyle,
    ) = context.select<
        SettingsCubit,
        ({
          PlayerSliderStyle playerSliderStyle,
          bool canvasEnabled,
          bool canvasAsBackdrop,
          AppThemeMode themeMode,
          VisualizerStyle visualizerStyle,
        })>((c) => (
          playerSliderStyle: c.state.playerSliderStyle,
          canvasEnabled: c.state.canvasEnabled,
          canvasAsBackdrop: c.state.canvasAsBackdrop,
          themeMode: c.state.themeMode,
          visualizerStyle: c.state.visualizerStyle,
        ));

    final isInSplitView = PlayerSplitViewScope.of(context);
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

        // 1. Upper stage: full-bleed artwork with gradient fade, lyrics, or
        // queue.
        final animatedUpperStage = ClipRect(
          child: AnimatedSwitcher(
            duration: context.motionMs(320),
            transitionBuilder: (child, animation) =>
                playerOverlayTransitionBuilder(context, child, animation),
            child: _CleanUpperStage(
              props: props,
              isInSplitView: isInSplitView,
              isLandscape: isLandscape,
              canvasEnabled: canvasEnabled,
              canvasAsBackdrop: canvasAsBackdrop,
              fadeColor: bottomBg,
              fallbackWidth: constraints.maxWidth,
            ),
          ),
        );

        final isShort = metrics.isShortHeight ||
            (isInSplitView && constraints.maxHeight < 540);
        final isVeryShort = metrics.isVeryShortHeight ||
            (isInSplitView && constraints.maxHeight < 460);

        final spacingTrackToSeek = isVeryShort ? 4.0 : (isShort ? 8.0 : 18.0);
        final spacingSeekToControls =
            isVeryShort ? 6.0 : (isShort ? 10.0 : 22.0);
        final spacingControlsToDock =
            isVeryShort ? 6.0 : (isShort ? 12.0 : 26.0);
        final paddingBottom = isVeryShort ? 4.0 : (isShort ? 8.0 : 12.0);

        final horizontalPadding =
            (constraints.maxWidth * 0.06).clamp(12.0, 24.0);

        // 2. Track header: title and artist with Download/Add to Playlist,
        // Star (Favorite) & More (...) circles.
        final trackHeader = _CleanTrackHeader(
          props: props,
          metrics: metrics,
          horizontalPadding: horizontalPadding,
          hasDownload: hasDownload,
        );

        final showVisualizer = visualizerStyle != VisualizerStyle.off &&
            !state.isLyricsVisible &&
            !state.isQueueVisible &&
            !isInSplitView;

        final visualizer = showVisualizer
            ? Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: AppSpacing.xxs,
                ),
                child: AudioVisualizer(
                  style: visualizerStyle,
                  color: activeColor,
                  height: visualizerStyle == VisualizerStyle.circular ? 60 : 34,
                  isPlaying: state.isPlaying,
                  audioSessionId: state.audioSessionId,
                  trackSeed: song?.id,
                ),
              )
            : null;

        // 3. Apple-style seek bar with Lossless badge & timestamps.
        final cleanSeekBar = _CleanSeekBar(
          props: props,
          duration: state.duration,
          song: song,
          activeColor: activeColor,
          sliderStyle: playerSliderStyle,
          horizontalPadding: horizontalPadding,
          isCompact: isShort,
        );

        // Bookmark prompt banner (resume playback from saved position).
        final Widget? bookmarkBanner = state.bookmarkPosition != null
            ? Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: PlayerBookmarkPromptBanner(
                  cubit: cubit,
                  position: state.bookmarkPosition!,
                ),
              )
            : null;

        // 4. Playback controls (Shuffle, Previous, Play/Pause, Next, Repeat).
        final transportControls = _CleanTransportControls(
          props: props,
          activeColor: activeColor,
          isCompact: isShort,
        );

        // Volume bar for tablet / split-view.
        final Widget? volumeBar =
            ((isInSplitView || context.isTablet) && !isVeryShort)
                ? Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: PlayerVolumeBar(
                      cubit: cubit,
                      activeColor: activeColor,
                    ),
                  )
                : null;

        // 5. Down bar (Lyrics, EQ, Speed, Audio Output/Cast, Quran, Ambient,
        // Timer, Queue).
        final downBar = _CleanDownBar(
          props: props,
          activeColor: activeColor,
          horizontalPadding: horizontalPadding,
        );

        // Lower deck shared by the portrait and landscape compositions.
        final Widget lowerDeck = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            trackHeader,
            if (visualizer != null) visualizer,
            SizedBox(height: spacingTrackToSeek),
            cleanSeekBar,
            if (song?.source == SongSource.radio) ...[
              const SizedBox(height: AppSpacing.xs),
              RadioNowPlayingRecommendations(
                props: props,
                cubit: cubit,
              ),
              const SizedBox(height: AppSpacing.xs),
            ] else if (bookmarkBanner != null) ...[
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
        );

        final Widget content;
        if (isLandscape && !isInSplitView) {
          final isRtl = Directionality.of(context) == TextDirection.rtl;
          content = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: animatedUpperStage,
              ),
              Expanded(
                flex: 5,
                child: SafeArea(
                  left: isRtl,
                  right: !isRtl,
                  top: true,
                  bottom: true,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: lowerDeck,
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
              // Upper stage: full-bleed artwork reaching to the top.
              Expanded(
                child: animatedUpperStage,
              ),
              // Lower deck: metadata, seek bar, transport and the down bar.
              SafeArea(
                top: false,
                bottom: true,
                child: Padding(
                  padding: EdgeInsets.only(bottom: paddingBottom),
                  child: RepaintBoundary(child: lowerDeck),
                ),
              ),
            ],
          );
        }

        if (isInSplitView) {
          return content;
        }

        // Rich, dynamic ambient backdrop matching the artwork palette.
        return Stack(
          fit: StackFit.expand,
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
            // Top bar affordance: grab handle (center).
            const PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              child: SafeArea(
                top: true,
                bottom: false,
                left: false,
                right: false,
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
