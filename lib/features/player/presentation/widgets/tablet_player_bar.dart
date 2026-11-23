// lib/features/player/presentation/widgets/tablet_player_bar.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'audio_quality_badge.dart';
import 'audio_quality_sheet.dart';
import 'equalizer_sheet.dart';
import '../themes/player_theme.dart';
import '../../../../core/widgets/pulsr_modal_tracker.dart';
import '../../../../core/widgets/pulsr_dock_tracker.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

import '../../../../core/utils/pulsr_haptics.dart';

part 'tablet_player_bar_sections.dart';

class TabletPlayerBar extends StatefulWidget {
  final VoidCallback onOpenNowPlaying;
  final VoidCallback? onToggleSideInspector;
  final bool isInspectorOpen;

  const TabletPlayerBar({
    super.key,
    required this.onOpenNowPlaying,
    this.onToggleSideInspector,
    this.isInspectorOpen = false,
  });

  @override
  State<TabletPlayerBar> createState() => _TabletPlayerBarState();
}

class _TabletPlayerBarState extends State<TabletPlayerBar> {
  final ValueNotifier<double?> _dragVolumeNotifier =
      ValueNotifier<double?>(null);
  final ValueNotifier<double?> _dragSeekNotifier = ValueNotifier<double?>(null);
  double? _lastDockHeight;
  bool? _lastMiniPlayer;

  @override
  void initState() {
    super.initState();
    PulsrModalTracker.isModalOpen.addListener(_onModalChanged);
  }

  void _onModalChanged() {
    _syncDock();
  }

  void _syncDock() {
    if (!mounted) return;
    if (PulsrModalTracker.isModalOpen.value) {
      _maybeUpdateDock(0.0, false);
      return;
    }
    final playerCubit = context.read<PlayerCubit?>();
    final playerState = playerCubit?.state;
    if (playerState?.currentSong == null) {
      _maybeUpdateDock(0.0, false);
      return;
    }
    final mq = MediaQuery.of(context);
    final bottomInset = mq.padding.bottom;
    final isShortHeight =
        mq.size.height < 500 && mq.orientation == Orientation.landscape;
    final cardHeight = isShortHeight ? 64.0 : 80.0;
    final bottomMargin = isShortHeight
        ? (bottomInset > 0 ? bottomInset : AppSpacing.xxs)
        : (bottomInset > 0 ? bottomInset + AppSpacing.xxs : AppSpacing.s10);
    _maybeUpdateDock(cardHeight + bottomMargin + 6.0, true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDock();
  }

  void _maybeUpdateDock(double height, bool miniPlayer) {
    if (_lastDockHeight == height && _lastMiniPlayer == miniPlayer) return;
    _lastDockHeight = height;
    _lastMiniPlayer = miniPlayer;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PulsrDockTracker.updateDock(height: height, miniPlayer: miniPlayer);
      }
    });
  }

  @override
  void dispose() {
    PulsrModalTracker.isModalOpen.removeListener(_onModalChanged);
    _dragVolumeNotifier.value = null;
    _dragSeekNotifier.value = null;
    _dragVolumeNotifier.dispose();
    _dragSeekNotifier.dispose();
    // Reset synchronously: the deferred post-frame callback in _maybeUpdateDock
    // is skipped once the widget is unmounted, leaving a stale dock reservation.
    _lastDockHeight = null;
    _lastMiniPlayer = null;
    PulsrDockTracker.updateDock(height: 0.0, miniPlayer: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (playerSliderStyle, currentOutputDevice, playerThemeMode) =
        context.select<SettingsCubit,
            (PlayerSliderStyle, AudioOutputInfo?, PlayerThemeMode)>(
      (c) => (
        c.state.playerSliderStyle,
        c.state.currentOutputDevice,
        c.state.playerThemeMode,
      ),
    );
    final mq = MediaQuery.of(context);
    final bottomInset = mq.padding.bottom;
    final isShortHeight =
        mq.size.height < 500 && mq.orientation == Orientation.landscape;
    final cardHeight = isShortHeight ? 64.0 : 80.0;
    final bottomMargin = isShortHeight
        ? (bottomInset > 0 ? bottomInset : AppSpacing.xxs)
        : (bottomInset > 0 ? bottomInset + AppSpacing.xxs : AppSpacing.s10);

    return BlocListener<PlayerCubit, PlayerState>(
      listenWhen: (prev, curr) =>
          (prev.currentSong != null) != (curr.currentSong != null),
      listener: (context, state) => _syncDock(),
      child: ValueListenableBuilder<bool>(
        valueListenable: PulsrModalTracker.isModalOpen,
        builder: (context, modalOpen, _) {
          if (modalOpen) {
            return const SizedBox.shrink();
          }
          return BlocBuilder<PlayerCubit, PlayerState>(
            buildWhen: (prev, curr) =>
                prev.currentSong?.id != curr.currentSong?.id ||
                prev.currentSong?.title != curr.currentSong?.title ||
                prev.currentSong?.artist != curr.currentSong?.artist ||
                prev.currentSong?.isFavorite != curr.currentSong?.isFavorite ||
                prev.isPlaying != curr.isPlaying ||
                prev.isBuffering != curr.isBuffering ||
                prev.hasPreviousNeighbour != curr.hasPreviousNeighbour ||
                prev.hasNextNeighbour != curr.hasNextNeighbour ||
                prev.duration != curr.duration ||
                prev.isShuffle != curr.isShuffle ||
                prev.repeatMode != curr.repeatMode ||
                prev.isLyricsVisible != curr.isLyricsVisible ||
                prev.isQueueVisible != curr.isQueueVisible ||
                prev.isEqEnabled != curr.isEqEnabled,
            builder: (context, state) {
              if (state.currentSong == null) {
                return const SizedBox.shrink();
              }

              final cubit = context.read<PlayerCubit>();
              final activeColor = p.accent;

              return LayoutBuilder(
                builder: (context, outerConstraints) {
                  final availableHeight = outerConstraints.maxHeight.isFinite
                      ? outerConstraints.maxHeight
                      : double.infinity;
                  final effectiveBottomMargin =
                      availableHeight < 64.0 ? 0.0 : bottomMargin;
                  final maxAllowedHeight = availableHeight.isFinite
                      ? (availableHeight - effectiveBottomMargin)
                          .clamp(44.0, cardHeight)
                      : cardHeight;
                  final barRadius =
                      isShortHeight ? AppRadii.r16All : AppRadii.r20All;

                  return RepaintBoundary(
                    child: Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.xs,
                        0,
                        AppSpacing.sm,
                        effectiveBottomMargin,
                      ),
                      child: Container(
                        height: maxAllowedHeight,
                        decoration: BoxDecoration(
                          borderRadius: barRadius,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.scrimAt(p.isDark ? 0.35 : 0.08),
                              blurRadius: 18,
                              spreadRadius: 0,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color:
                                  AppColors.scrimAt(p.isDark ? 0.15 : 0.04),
                              blurRadius: 6,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: barRadius,
                          child: Container(
                            height: maxAllowedHeight,
                            decoration: BoxDecoration(
                              color: p.surfaceContainer,
                              border: Border.all(
                                color: p.hairline,
                                width: 1.0,
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: isShortHeight
                                    ? AppSpacing.xxs
                                    : AppSpacing.s6,
                              ),
                              child: LayoutBuilder(
                                builder: (context, barConstraints) {
                                  final totalWidth = barConstraints.maxWidth;
                                  final isCompactBar = totalWidth < 600;
                                  final leftMaxWidth = isShortHeight
                                      ? (totalWidth * 0.38).clamp(140.0, 240.0)
                                      : (isCompactBar
                                          ? (totalWidth * 0.28)
                                              .clamp(60.0, 160.0)
                                          : (totalWidth * 0.27)
                                              .clamp(120.0, 300.0));
                                  final rightMaxWidth = isShortHeight
                                      ? (totalWidth * 0.20).clamp(60.0, 110.0)
                                      : (isCompactBar
                                          ? (totalWidth * 0.32)
                                              .clamp(70.0, 200.0)
                                          : (totalWidth * 0.34)
                                              .clamp(140.0, 360.0));
                                  final showVolumeSlider = !isShortHeight &&
                                      totalWidth >= 680 &&
                                      rightMaxWidth >= 160;
                                  final showSecondaryBadges = !isShortHeight &&
                                      totalWidth >= 600 &&
                                      leftMaxWidth >= 140;
                                  final showFavoriteButton = isShortHeight
                                      ? leftMaxWidth >= 140
                                      : (!isCompactBar && leftMaxWidth >= 130);

                                  return Row(
                                    children: [
                                      _buildLeftTrackSection(
                                        context: context,
                                        cubit: cubit,
                                        state: state,
                                        p: p,
                                        activeColor: activeColor,
                                        playerThemeMode: playerThemeMode,
                                        leftMaxWidth: leftMaxWidth,
                                        isShortHeight: isShortHeight,
                                        isCompactBar: isCompactBar,
                                        showSecondaryBadges:
                                            showSecondaryBadges,
                                        showFavoriteButton: showFavoriteButton,
                                      ),
                                      SizedBox(
                                        width: isCompactBar
                                            ? AppSpacing.xs
                                            : AppSpacing.sm,
                                      ),
                                      _buildCenterTransportSection(
                                        context: context,
                                        cubit: cubit,
                                        state: state,
                                        p: p,
                                        activeColor: activeColor,
                                        playerSliderStyle: playerSliderStyle,
                                        isShortHeight: isShortHeight,
                                      ),
                                      SizedBox(
                                        width: isCompactBar
                                            ? AppSpacing.xs
                                            : AppSpacing.sm,
                                      ),
                                      _buildRightActionsSection(
                                        context: context,
                                        cubit: cubit,
                                        state: state,
                                        p: p,
                                        activeColor: activeColor,
                                        playerSliderStyle: playerSliderStyle,
                                        currentOutputDevice:
                                            currentOutputDevice,
                                        rightMaxWidth: rightMaxWidth,
                                        isShortHeight: isShortHeight,
                                        showVolumeSlider: showVolumeSlider,
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
