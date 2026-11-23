// lib/features/player/presentation/themes/clean_player_theme.dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_blur.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/services/waveform_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/services/cast_service.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../../domain/models/audio_quality_info.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/song_options_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/canvas_backdrop.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/player_gesture_scope.dart';
import '../widgets/player_volume_bar.dart';
import '../widgets/radio_now_playing_recommendations.dart';
import '../widgets/waveform_seek_bar.dart';
import 'player_shape.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart' show PlayerThemeMetrics;

part 'parts/clean_player_theme_deck_colors.dart';
part 'parts/clean_player_theme_header.dart';
part 'parts/clean_player_theme_stage.dart';
part 'parts/clean_player_theme_seek_bar.dart';
part 'parts/clean_player_theme_transport.dart';
part 'parts/clean_player_theme_dock.dart';

/// Clean Modern Flow — Apple Music-inspired Now Playing theme.
///
/// Decoupled from `PlayerThemeScaffold` via [PlayerSurfaceShell]:
/// 1. Full-bleed smooth mesh + blurred album-art ambient backdrop (never harsh
///    pure-black void; all blur gated by [AppBlur.canBlur] + [AppBlur.clampSigma]).
/// 2. Large rounded artwork (`resolveCustomRadius(context, 16)`) with smooth
///    play/pause `AnimatedScale` (`1.0` playing vs `0.90` paused) and elevation
///    shadow depth animation (disabled in preview / reduce-motion).
/// 3. Left-aligned bold title & artist with subtle marquee and frosted favorite
///    & options buttons.
/// 4. Thick translucent capsule scrubber (no thumb knob) that expands smoothly
///    on active scrub, scoped via `BlocSelector<PlayerCubit, PlayerState, ...>`.
/// 5. Clean borderless transport controls (no A/B loop clutter).
/// 6. Minimal 4-item bottom action row: Lyrics, Output/DSP, Queue, and
///    [PlayerToolsTriggerButton] (housing A/B loop & secondary tools).
class CleanPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const CleanPlayerTheme({super.key, required this.props});

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;

    final (
      :canvasEnabled,
      :canvasAsBackdrop,
      :themeMode,
      :visualizerStyle,
    ) = context.select<
        SettingsCubit,
        ({
          bool canvasEnabled,
          bool canvasAsBackdrop,
          AppThemeMode themeMode,
          VisualizerStyle visualizerStyle,
        })>((c) => (
          canvasEnabled: c.state.canvasEnabled,
          canvasAsBackdrop: c.state.canvasAsBackdrop,
          themeMode: c.state.themeMode,
          visualizerStyle: c.state.visualizerStyle,
        ));

    final hasDownload = song != null &&
        (song.source == SongSource.youtube ||
            (song.remoteId != null && song.remoteId!.isNotEmpty));

    final p = context.palette;
    final isAmoled =
        themeMode == AppThemeMode.amoled || (p.isDark && p.bg == Colors.black);
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);

    return PlayerSurfaceShell(
      props: props,
      background: _CleanAmbientBackdrop(
        song: song,
        activeColor: activeColor,
        bgColor: props.bgColor,
        isAmoled: isAmoled,
      ),
      topBarBuilder: (context, metrics) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s6),
        child: Center(child: PlayerPlayHandle()),
      ),
      builder: (context, metrics, isInSplitView, isPreview) {
        final constraints = metrics.constraints;
        final isLandscape = metrics.isLandscape && !isInSplitView;
        final isShort = metrics.isShortHeight ||
            isPreview ||
            (isInSplitView && constraints.maxHeight < 540);
        final isVeryShort = metrics.isVeryShortHeight ||
            (isInSplitView && constraints.maxHeight < 460);

        final double horizontalPadding =
            (constraints.maxWidth * 0.06).clamp(16.0, 28.0);
        final double spacingStageToHeader =
            isVeryShort ? AppSpacing.s8 : (isShort ? AppSpacing.s12 : AppSpacing.s20);
        final double spacingHeaderToSeek =
            isVeryShort ? AppSpacing.s6 : (isShort ? AppSpacing.s10 : AppSpacing.s16);
        final double spacingSeekToTransport =
            isVeryShort ? AppSpacing.s6 : (isShort ? AppSpacing.s10 : AppSpacing.s20);
        final double spacingTransportToDock =
            isVeryShort ? AppSpacing.s4 : (isShort ? AppSpacing.s10 : AppSpacing.lg);
        final double paddingBottom =
            isVeryShort || isPreview ? AppSpacing.s6 : (isShort ? AppSpacing.s8 : AppSpacing.s14);

        final artworkStage = _CleanArtworkStage(
          props: props,
          metrics: metrics,
          isInSplitView: isInSplitView,
          isPreview: isPreview,
          canvasEnabled: canvasEnabled,
          canvasAsBackdrop: canvasAsBackdrop,
          horizontalPadding: horizontalPadding,
        );

        final trackHeader = _CleanTrackHeader(
          props: props,
          metrics: metrics,
          horizontalPadding: horizontalPadding,
          hasDownload: hasDownload && !isPreview,
        );

        final showVisualizer = !isPreview &&
            visualizerStyle != VisualizerStyle.off &&
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
                  height: visualizerStyle == VisualizerStyle.circular ? 56 : 32,
                  isPlaying: state.isPlaying,
                  audioSessionId: state.audioSessionId,
                  trackSeed: song?.id,
                ),
              )
            : null;

        final cleanSeekBar = _CleanSeekBar(
          props: props,
          duration: state.duration,
          song: song,
          activeColor: activeColor,
          horizontalPadding: horizontalPadding,
          isCompact: isShort,
          isPreview: isPreview,
        );

        final Widget? bookmarkBanner =
            (!isPreview && state.bookmarkPosition != null)
                ? Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: PlayerBookmarkPromptBanner(
                      cubit: cubit,
                      position: state.bookmarkPosition!,
                    ),
                  )
                : null;

        final transportControls = _CleanTransportControls(
          props: props,
          activeColor: activeColor,
          isCompact: isShort,
          isPreview: isPreview,
        );

        final Widget? volumeBar = (!isPreview &&
                (isInSplitView || context.isTablet) &&
                !isVeryShort)
            ? Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: PlayerVolumeBar(
                  cubit: cubit,
                  activeColor: activeColor,
                ),
              )
            : null;

        final downBar = _CleanDownBar(
          props: props,
          activeColor: activeColor,
          horizontalPadding: horizontalPadding,
          isPreview: isPreview,
        );

        final Widget lowerDeck = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            trackHeader,
            if (visualizer != null) visualizer,
            SizedBox(height: spacingHeaderToSeek),
            cleanSeekBar,
            if (!isPreview && song?.source == SongSource.radio) ...[
              const SizedBox(height: AppSpacing.xs),
              RadioNowPlayingRecommendations(
                props: props,
                cubit: cubit,
                metrics: metrics,
              ),
              const SizedBox(height: AppSpacing.xs),
            ] else if (bookmarkBanner != null) ...[
              const SizedBox(height: AppSpacing.xs),
              bookmarkBanner,
              const SizedBox(height: AppSpacing.xs),
            ] else ...[
              SizedBox(height: spacingSeekToTransport),
            ],
            transportControls,
            if (volumeBar != null) ...[
              const SizedBox(height: AppSpacing.xs),
              volumeBar,
              const SizedBox(height: AppSpacing.xs),
            ] else ...[
              SizedBox(height: spacingTransportToDock),
            ],
            downBar,
          ],
        );

        // Landscape single-pane layout: artwork stage on start, scrollable
        // control deck on end.
        if (isLandscape) {
          final isRtl = Directionality.of(context) == TextDirection.rtl;
          return SafeArea(
            top: !isPreview,
            bottom: !isPreview,
            left: !isPreview,
            right: !isPreview,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: AppSpacing.md,
                      end: AppSpacing.xs,
                      top: isPreview ? AppSpacing.sm : AppSpacing.lg,
                      bottom: AppSpacing.sm,
                    ),
                    child: artworkStage,
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: isRtl ? AppSpacing.md : AppSpacing.xs,
                      end: isRtl ? AppSpacing.xs : AppSpacing.md,
                    ),
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          child: RepaintBoundary(child: lowerDeck),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Scroll fallback for very short portrait viewports or large
        // accessibility text scaling so no RenderFlex overflow can occur.
        final double portraitScrollThreshold =
            540.0 + (textScale - 1.0) * 120.0;
        if (!isPreview &&
            !isInSplitView &&
            constraints.maxHeight < portraitScrollThreshold) {
          final double boundedArt =
              (constraints.maxHeight * 0.38).clamp(160.0, 280.0);
          return SafeArea(
            top: true,
            bottom: true,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.only(
                  top: AppSpacing.xl,
                  bottom: paddingBottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: boundedArt,
                      width: constraints.maxWidth,
                      child: artworkStage,
                    ),
                    SizedBox(height: spacingStageToHeader),
                    RepaintBoundary(child: lowerDeck),
                  ],
                ),
              ),
            ),
          );
        }

        // Standard Portrait / Tablet Split-View / Theme Preview composition.
        return Column(
          children: [
            if (!isInSplitView && !isPreview)
              const SafeArea(
                top: true,
                bottom: false,
                child: SizedBox(height: AppSpacing.xl),
              )
            else
              const SizedBox(height: AppSpacing.sm),
            Expanded(child: artworkStage),
            SizedBox(height: spacingStageToHeader),
            SafeArea(
              top: false,
              bottom: !isPreview && !isInSplitView,
              child: Padding(
                padding: EdgeInsets.only(bottom: paddingBottom),
                child: RepaintBoundary(child: lowerDeck),
              ),
            ),
          ],
        );
      },
    );
  }
}
