// lib/features/player/presentation/widgets/tablet_player_bar.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/performance/gpu_budget.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'audio_quality_badge.dart';
import 'audio_quality_sheet.dart';
import 'equalizer_sheet.dart';
import '../../../../core/widgets/pulsr_modal_tracker.dart';
import '../../../../core/widgets/pulsr_dock_tracker.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

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
    final cardHeight = isShortHeight ? 72.0 : 80.0;
    final bottomMargin =
        bottomInset > 0 ? bottomInset + AppSpacing.xxs : AppSpacing.s10;
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
    final settingsState = context.watch<SettingsCubit>().state;
    final mq = MediaQuery.of(context);
    final bottomInset = mq.padding.bottom;
    final isShortHeight =
        mq.size.height < 500 && mq.orientation == Orientation.landscape;
    final cardHeight = isShortHeight ? 72.0 : 80.0;
    final bottomMargin =
        bottomInset > 0 ? bottomInset + AppSpacing.xxs : AppSpacing.s10;

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
                prev.duration != curr.duration ||
                prev.isShuffle != curr.isShuffle ||
                prev.repeatMode != curr.repeatMode ||
                prev.isLyricsVisible != curr.isLyricsVisible ||
                prev.isQueueVisible != curr.isQueueVisible ||
                prev.isEqEnabled != curr.isEqEnabled,
            builder: (context, state) {
              final song = state.currentSong;
              if (song == null) {
                return const SizedBox.shrink();
              }

              final cubit = context.read<PlayerCubit>();
              final activeColor = p.accent;
              // A-3: the handler owns the master volume (no PlayerState.volume by
              // design). Read it as the single source of truth, keeping the local
              // drag override only while the user is scrubbing.
              final handlerVolume =
                  context.read<PulsrAudioHandler>().volume.clamp(0.0, 1.0);
              final l10n = context.l10n;

              return LayoutBuilder(
                builder: (context, outerConstraints) {
                  final availableHeight = outerConstraints.maxHeight.isFinite
                      ? outerConstraints.maxHeight
                      : double.infinity;
                  final effectiveBottomMargin =
                      availableHeight < 80.0 ? 0.0 : bottomMargin;
                  final maxAllowedHeight = availableHeight.isFinite
                      ? (availableHeight - effectiveBottomMargin)
                          .clamp(48.0, cardHeight)
                      : cardHeight;

                  final barRadius = AppRadii.r20All;

                  return Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.sm,
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
                            color: Colors.black
                                .withValues(alpha: p.isDark ? 0.40 : 0.12),
                            blurRadius: 24,
                            spreadRadius: 0,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: p.accent
                                .withValues(alpha: p.isDark ? 0.10 : 0.05),
                            blurRadius: 18,
                            spreadRadius: -2,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: barRadius,
                        child: Builder(
                          builder: (context) {
                            final barContainer = Container(
                              height: maxAllowedHeight,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    GpuBudget.isGpuSaverActive
                                        ? p.surface
                                        : p.surface.withValues(
                                            alpha: p.isDark ? 0.76 : 0.86),
                                    GpuBudget.isGpuSaverActive
                                        ? p.surfaceContainer
                                        : p.surfaceContainer.withValues(
                                            alpha: p.isDark ? 0.70 : 0.82),
                                  ],
                                ),
                                border: Border.all(
                                  color: p.isDark
                                      ? AppColors.specularStrong
                                      : AppColors.scrimAt(0.08),
                                  width: 1.2,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  // Specular refraction highlight along top edge
                                  PositionedDirectional(
                                    top: 0,
                                    start: 16,
                                    end: 16,
                                    height: 1.2,
                                    child: IgnorePointer(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              AppColors.specularAt(0.0),
                                              AppColors.specularAt(
                                                  p.isDark ? 0.35 : 0.65),
                                              AppColors.specularAt(0.0),
                                            ],
                                            stops: const [0.0, 0.5, 1.0],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                      vertical: isShortHeight
                                          ? AppSpacing.xxs
                                          : AppSpacing.s6,
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, barConstraints) {
                                        final totalWidth =
                                            barConstraints.maxWidth;
                                        final isCompactBar = totalWidth < 600;
                                        final leftMaxWidth = isCompactBar
                                            ? (totalWidth * 0.28)
                                                .clamp(60.0, 160.0)
                                            : (totalWidth * 0.25)
                                                .clamp(120.0, 260.0);
                                        final rightMaxWidth = isCompactBar
                                            ? (totalWidth * 0.32)
                                                .clamp(70.0, 200.0)
                                            : (totalWidth * 0.35)
                                                .clamp(140.0, 360.0);

                                        return Row(
                                          children: [
                                            // ── Left: Track Info & Artwork ──────────────────────────
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                minWidth: 0,
                                                maxWidth: leftMaxWidth,
                                              ),
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: AlignmentDirectional
                                                    .centerStart,
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    GestureDetector(
                                                      onTap: widget
                                                          .onOpenNowPlaying,
                                                      child: ClipRRect(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                                    AppRadii
                                                                        .r10),
                                                        child: CachedArtwork(
                                                          id: song.id,
                                                          albumId: song.albumId,
                                                          remoteUrl: song
                                                                  .remoteArtworkUrl ??
                                                              song.artworkUri,
                                                          type:
                                                              ArtworkType.AUDIO,
                                                          size: isCompactBar
                                                              ? 42
                                                              : (isShortHeight
                                                                  ? 48
                                                                  : 54),
                                                          borderRadius: 12,
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                        width: isCompactBar
                                                            ? AppSpacing.xs
                                                            : AppSpacing.s10),
                                                    ConstrainedBox(
                                                      constraints:
                                                          BoxConstraints(
                                                        maxWidth:
                                                            (leftMaxWidth - 90)
                                                                .clamp(60.0,
                                                                    160.0),
                                                      ),
                                                      child: GestureDetector(
                                                        onTap: widget
                                                            .onOpenNowPlaying,
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              song.title,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                color: p
                                                                    .textPrimary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                fontSize:
                                                                    AppFontSize
                                                                        .bodySmall,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height:
                                                                    AppSpacing
                                                                        .s2),
                                                            Text(
                                                              song.artist,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                color: p
                                                                    .textSecondary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                fontSize:
                                                                    AppFontSize
                                                                        .label,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height:
                                                                    AppSpacing
                                                                        .xxs),
                                                            AudioQualityBadge(
                                                              song: song,
                                                              activeColor:
                                                                  activeColor,
                                                              compact: true,
                                                              showDevice: false,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    if (!isCompactBar ||
                                                        leftMaxWidth >= 110)
                                                      IconButton(
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints: const BoxConstraints(
                                                            minWidth: AppSpacing
                                                                .minTouchTarget,
                                                            minHeight: AppSpacing
                                                                .minTouchTarget),
                                                        icon: Icon(
                                                          song.isFavorite
                                                              ? Icons
                                                                  .favorite_rounded
                                                              : Icons
                                                                  .favorite_border_rounded,
                                                          color: song.isFavorite
                                                              ? p.favorite
                                                              : p.textSecondary,
                                                          size: 20,
                                                        ),
                                                        tooltip: song.isFavorite
                                                            ? l10n.unlike
                                                            : l10n.like,
                                                        onPressed: () => cubit
                                                            .toggleFavorite(
                                                                song.id),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),

                                            SizedBox(
                                                width: isCompactBar
                                                    ? AppSpacing.xs
                                                    : AppSpacing.sm),

                                            // ── Center: Transport Controls & Seekbar ─────────────────
                                            Expanded(
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal:
                                                            AppSpacing.xs),
                                                child: LayoutBuilder(
                                                  builder:
                                                      (context, constraints) {
                                                    return FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment:
                                                          Alignment.center,
                                                      child: SizedBox(
                                                        width: constraints
                                                            .maxWidth
                                                            .clamp(
                                                                180.0, 500.0),
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            // Controls Row
                                                            SingleChildScrollView(
                                                              scrollDirection:
                                                                  Axis.horizontal,
                                                              child: Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  IconButton(
                                                                    visualDensity:
                                                                        VisualDensity
                                                                            .compact,
                                                                    padding:
                                                                        EdgeInsets
                                                                            .zero,
                                                                    constraints: const BoxConstraints(
                                                                        minWidth:
                                                                            AppSpacing
                                                                                .minTouchTarget,
                                                                        minHeight:
                                                                            AppSpacing.minTouchTarget),
                                                                    icon: Icon(
                                                                      Icons
                                                                          .shuffle_rounded,
                                                                      size: 19,
                                                                      color: state
                                                                              .isShuffle
                                                                          ? activeColor
                                                                          : p.textSecondary,
                                                                    ),
                                                                    tooltip: state
                                                                            .isShuffle
                                                                        ? l10n
                                                                            .disableShuffle
                                                                        : l10n
                                                                            .enableShuffle,
                                                                    onPressed:
                                                                        () {
                                                                      HapticFeedback
                                                                          .selectionClick();
                                                                      cubit
                                                                          .toggleShuffle();
                                                                    },
                                                                  ),
                                                                  const SizedBox(
                                                                      width: AppSpacing
                                                                          .s2),
                                                                  IconButton(
                                                                    visualDensity:
                                                                        VisualDensity
                                                                            .compact,
                                                                    padding:
                                                                        EdgeInsets
                                                                            .zero,
                                                                    constraints: const BoxConstraints(
                                                                        minWidth:
                                                                            AppSpacing
                                                                                .minTouchTarget,
                                                                        minHeight:
                                                                            AppSpacing.minTouchTarget),
                                                                    icon: Icon(
                                                                      Icons
                                                                          .skip_previous_rounded,
                                                                      size: 24,
                                                                      color: p
                                                                          .textPrimary,
                                                                    ),
                                                                    tooltip: l10n
                                                                        .previous,
                                                                    onPressed:
                                                                        () {
                                                                      HapticFeedback
                                                                          .selectionClick();
                                                                      cubit
                                                                          .previous();
                                                                    },
                                                                  ),
                                                                  const SizedBox(
                                                                      width: AppSpacing
                                                                          .xxs),
                                                                  Semantics(
                                                                    label: state
                                                                            .isPlaying
                                                                        ? l10n
                                                                            .pause
                                                                        : l10n
                                                                            .play,
                                                                    button:
                                                                        true,
                                                                    child:
                                                                        GestureDetector(
                                                                      onTap:
                                                                          () {
                                                                        HapticFeedback
                                                                            .mediumImpact();
                                                                        cubit
                                                                            .togglePlayPause();
                                                                      },
                                                                      child:
                                                                          SizedBox(
                                                                        width:
                                                                            44,
                                                                        height:
                                                                            44,
                                                                        child:
                                                                            Center(
                                                                          child:
                                                                              Container(
                                                                            width:
                                                                                38,
                                                                            height:
                                                                                38,
                                                                            decoration:
                                                                                BoxDecoration(
                                                                              color: activeColor,
                                                                              shape: BoxShape.circle,
                                                                              boxShadow: [
                                                                                BoxShadow(
                                                                                  color: p.glow.withValues(alpha: 0.4),
                                                                                  blurRadius: 10,
                                                                                  spreadRadius: 1,
                                                                                ),
                                                                              ],
                                                                            ),
                                                                            child:
                                                                                Icon(
                                                                              state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                                                              color: p.onAccent,
                                                                              size: 24,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                      width: AppSpacing
                                                                          .xxs),
                                                                  IconButton(
                                                                    visualDensity:
                                                                        VisualDensity
                                                                            .compact,
                                                                    padding:
                                                                        EdgeInsets
                                                                            .zero,
                                                                    constraints: const BoxConstraints(
                                                                        minWidth:
                                                                            AppSpacing
                                                                                .minTouchTarget,
                                                                        minHeight:
                                                                            AppSpacing.minTouchTarget),
                                                                    icon: Icon(
                                                                      Icons
                                                                          .skip_next_rounded,
                                                                      size: 24,
                                                                      color: p
                                                                          .textPrimary,
                                                                    ),
                                                                    tooltip: l10n
                                                                        .next,
                                                                    onPressed:
                                                                        () {
                                                                      HapticFeedback
                                                                          .selectionClick();
                                                                      cubit
                                                                          .next();
                                                                    },
                                                                  ),
                                                                  const SizedBox(
                                                                      width: AppSpacing
                                                                          .s2),
                                                                  IconButton(
                                                                    visualDensity:
                                                                        VisualDensity
                                                                            .compact,
                                                                    padding:
                                                                        EdgeInsets
                                                                            .zero,
                                                                    constraints: const BoxConstraints(
                                                                        minWidth:
                                                                            AppSpacing
                                                                                .minTouchTarget,
                                                                        minHeight:
                                                                            AppSpacing.minTouchTarget),
                                                                    icon: Icon(
                                                                      state.repeatMode ==
                                                                              PlayerRepeatMode
                                                                                  .one
                                                                          ? Icons
                                                                              .repeat_one_rounded
                                                                          : Icons
                                                                              .repeat_rounded,
                                                                      size: 19,
                                                                      color: state.repeatMode !=
                                                                              PlayerRepeatMode.off
                                                                          ? activeColor
                                                                          : p.textSecondary,
                                                                    ),
                                                                    tooltip: state.repeatMode ==
                                                                            PlayerRepeatMode
                                                                                .one
                                                                        ? l10n
                                                                            .repeatOne
                                                                        : state.repeatMode ==
                                                                                PlayerRepeatMode.all
                                                                            ? l10n.repeatAll
                                                                            : l10n.repeatOff,
                                                                    onPressed:
                                                                        () {
                                                                      HapticFeedback
                                                                          .selectionClick();
                                                                      cubit
                                                                          .toggleRepeat();
                                                                    },
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height:
                                                                    AppSpacing
                                                                        .xxs),
                                                            // Seekbar Row
                                                            BlocSelector<
                                                                PlayerCubit,
                                                                PlayerState,
                                                                Duration>(
                                                              selector: (s) =>
                                                                  s.position,
                                                              builder: (context,
                                                                  position) {
                                                                return ValueListenableBuilder<
                                                                    double?>(
                                                                  valueListenable:
                                                                      _dragSeekNotifier,
                                                                  builder: (context,
                                                                      dragSeekValue,
                                                                      _) {
                                                                    final currentDuration = dragSeekValue !=
                                                                            null
                                                                        ? Duration(
                                                                            milliseconds:
                                                                                dragSeekValue.toInt())
                                                                        : position;
                                                                    final valueLabel =
                                                                        '${Formatters.formatDuration(currentDuration)} / ${Formatters.formatDuration(state.duration)}';
                                                                    return Row(
                                                                      children: [
                                                                        Text(
                                                                          Formatters.formatDuration(
                                                                              currentDuration),
                                                                          style:
                                                                              TextStyle(
                                                                            color:
                                                                                p.textSecondary,
                                                                            fontSize:
                                                                                AppFontSize.caption,
                                                                            fontFeatures: const [
                                                                              FontFeature.tabularFigures()
                                                                            ],
                                                                          ),
                                                                        ),
                                                                        const SizedBox(
                                                                            width:
                                                                                AppSpacing.xs),
                                                                        Expanded(
                                                                          child:
                                                                              Semantics(
                                                                            value:
                                                                                valueLabel,
                                                                            child:
                                                                                PulsrSlider(
                                                                              height: 24,
                                                                              min: 0.0,
                                                                              max: state.duration.inMilliseconds.toDouble() > 0 ? state.duration.inMilliseconds.toDouble() : 1.0,
                                                                              value: (dragSeekValue ?? position.inMilliseconds.toDouble()).clamp(
                                                                                0.0,
                                                                                state.duration.inMilliseconds.toDouble() > 0 ? state.duration.inMilliseconds.toDouble() : 1.0,
                                                                              ),
                                                                              semanticLabel: context.l10n.seekLabel,
                                                                              activeColor: activeColor,
                                                                              onChangeStart: (val) {
                                                                                _dragSeekNotifier.value = val;
                                                                              },
                                                                              onChanged: (val) {
                                                                                _dragSeekNotifier.value = val;
                                                                              },
                                                                              onChangeEnd: (val) {
                                                                                cubit.seek(Duration(milliseconds: val.toInt()));
                                                                                _dragSeekNotifier.value = null;
                                                                              },
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        const SizedBox(
                                                                            width:
                                                                                AppSpacing.xs),
                                                                        Text(
                                                                          Formatters.formatDuration(
                                                                              state.duration),
                                                                          style:
                                                                              TextStyle(
                                                                            color:
                                                                                p.textSecondary,
                                                                            fontSize:
                                                                                AppFontSize.caption,
                                                                            fontFeatures: const [
                                                                              FontFeature.tabularFigures()
                                                                            ],
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    );
                                                                  },
                                                                );
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),

                                            SizedBox(
                                                width: isCompactBar
                                                    ? AppSpacing.xs
                                                    : AppSpacing.sm),

                                            // ── Right: Volume & Quick Actions ───────────────────────
                                            Flexible(
                                              flex: 0,
                                              child: ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  maxWidth: rightMaxWidth,
                                                ),
                                                child: SingleChildScrollView(
                                                  scrollDirection:
                                                      Axis.horizontal,
                                                  reverse: true,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.end,
                                                    children: [
                                                      // Volume Mute / Slider
                                                      ValueListenableBuilder<
                                                          double?>(
                                                        valueListenable:
                                                            _dragVolumeNotifier,
                                                        builder: (context,
                                                            dragVolume, _) {
                                                          final effectiveVolume =
                                                              (dragVolume ??
                                                                      handlerVolume)
                                                                  .clamp(
                                                                      0.0, 1.0);
                                                          final isMuted = cubit
                                                                  .isMuted ||
                                                              effectiveVolume <=
                                                                  0.0;
                                                          return Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              IconButton(
                                                                visualDensity:
                                                                    VisualDensity
                                                                        .compact,
                                                                padding:
                                                                    EdgeInsets
                                                                        .zero,
                                                                constraints:
                                                                    const BoxConstraints(
                                                                        minWidth:
                                                                            48,
                                                                        minHeight:
                                                                            48),
                                                                icon: Icon(
                                                                  isMuted
                                                                      ? Icons
                                                                          .volume_off_rounded
                                                                      : (effectiveVolume <
                                                                              0.5
                                                                          ? Icons
                                                                              .volume_down_rounded
                                                                          : Icons
                                                                              .volume_up_rounded),
                                                                  color: p
                                                                      .textSecondary,
                                                                  size: 19,
                                                                ),
                                                                tooltip: isMuted
                                                                    ? l10n
                                                                        .unmute
                                                                    : l10n.mute,
                                                                onPressed: () {
                                                                  _dragVolumeNotifier
                                                                          .value =
                                                                      null;
                                                                  cubit
                                                                      .toggleMute();
                                                                },
                                                              ),
                                                              SizedBox(
                                                                width: 80,
                                                                child:
                                                                    Semantics(
                                                                  label: l10n
                                                                      .volume,
                                                                  value:
                                                                      '${(effectiveVolume * 100).round()}%',
                                                                  child:
                                                                      PulsrSlider(
                                                                    min: 0.0,
                                                                    max: 1.0,
                                                                    value:
                                                                        effectiveVolume,
                                                                    activeColor:
                                                                        p.textPrimary,
                                                                    onChangeStart: (v) =>
                                                                        _dragVolumeNotifier
                                                                            .value = v,
                                                                    onChanged:
                                                                        (v) {
                                                                      _dragVolumeNotifier
                                                                          .value = v;
                                                                      cubit.setVolume(
                                                                          v);
                                                                    },
                                                                    onChangeEnd:
                                                                        (v) {
                                                                      _dragVolumeNotifier
                                                                              .value =
                                                                          null;
                                                                      cubit.setVolume(
                                                                          v);
                                                                    },
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          );
                                                        },
                                                      ),
                                                      const SizedBox(
                                                          width: AppSpacing.s2),

                                                      // DAC / Output
                                                      IconButton(
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(
                                                                minWidth: 48,
                                                                minHeight: 48),
                                                        icon: Icon(
                                                          Icons
                                                              .settings_input_component_rounded,
                                                          size: 19,
                                                          color: settingsState
                                                                      .currentOutputDevice
                                                                      ?.isUsbDac ==
                                                                  true
                                                              ? AppColors
                                                                  .dacGold
                                                              : p.textSecondary,
                                                        ),
                                                        tooltip: l10n
                                                            .audioOutputAndDac,
                                                        onPressed: () =>
                                                            AudioQualitySheet
                                                                .show(
                                                                    context,
                                                                    song,
                                                                    activeColor),
                                                      ),

                                                      // Equalizer
                                                      IconButton(
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(
                                                                minWidth: 48,
                                                                minHeight: 48),
                                                        icon: Icon(
                                                          Icons
                                                              .equalizer_rounded,
                                                          size: 19,
                                                          color: state
                                                                  .isEqEnabled
                                                              ? activeColor
                                                              : p.textSecondary,
                                                        ),
                                                        tooltip: l10n.equalizer,
                                                        onPressed: () =>
                                                            EqualizerSheet.show(
                                                                context),
                                                      ),

                                                      // Queue inspector toggle
                                                      if (widget
                                                              .onToggleSideInspector !=
                                                          null)
                                                        IconButton(
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          padding:
                                                              EdgeInsets.zero,
                                                          constraints:
                                                              const BoxConstraints(
                                                                  minWidth: 48,
                                                                  minHeight:
                                                                      48),
                                                          icon: Icon(
                                                            Icons
                                                                .queue_music_rounded,
                                                            size: 19,
                                                            color: widget
                                                                    .isInspectorOpen
                                                                ? activeColor
                                                                : p.textSecondary,
                                                          ),
                                                          tooltip: l10n
                                                              .toggleSideQueue,
                                                          onPressed: widget
                                                              .onToggleSideInspector,
                                                        ),

                                                      // Expand Fullscreen
                                                      IconButton(
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(
                                                                minWidth: 48,
                                                                minHeight: 48),
                                                        icon: Icon(
                                                          Icons
                                                              .open_in_full_rounded,
                                                          size: 18,
                                                          color:
                                                              p.textSecondary,
                                                        ),
                                                        tooltip: l10n
                                                            .fullscreenPlayer,
                                                        onPressed: widget
                                                            .onOpenNowPlaying,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            )
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (GpuBudget.isGpuSaverActive) {
                              return barContainer;
                            }
                            return BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                              child: barContainer,
                            );
                          },
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
