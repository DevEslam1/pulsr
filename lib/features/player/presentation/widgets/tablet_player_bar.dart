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
    final settingsState = context.watch<SettingsCubit>().state;
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
                      availableHeight < 64.0 ? 0.0 : bottomMargin;
                  final maxAllowedHeight = availableHeight.isFinite
                      ? (availableHeight - effectiveBottomMargin)
                          .clamp(44.0, cardHeight)
                      : cardHeight;

                  final barRadius =
                      isShortHeight ? AppRadii.r16All : AppRadii.r20All;

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
                                        final leftMaxWidth = isShortHeight
                                            ? (totalWidth * 0.38)
                                                .clamp(140.0, 240.0)
                                            : (isCompactBar
                                                ? (totalWidth * 0.28)
                                                    .clamp(60.0, 160.0)
                                                : (totalWidth * 0.25)
                                                    .clamp(120.0, 260.0));
                                        final rightMaxWidth = isShortHeight
                                            ? (totalWidth * 0.20)
                                                .clamp(60.0, 110.0)
                                            : (isCompactBar
                                                ? (totalWidth * 0.32)
                                                    .clamp(70.0, 200.0)
                                                : (totalWidth * 0.35)
                                                    .clamp(140.0, 360.0));

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
                                                                    isShortHeight
                                                                        ? AppRadii
                                                                            .r8
                                                                        : AppRadii
                                                                            .r10),
                                                        child: CachedArtwork(
                                                          id: song.id,
                                                          albumId: song.albumId,
                                                          remoteUrl: song
                                                                  .remoteArtworkUrl ??
                                                              song.artworkUri,
                                                          type:
                                                              ArtworkType.AUDIO,
                                                          size: isShortHeight
                                                              ? 40
                                                              : (isCompactBar
                                                                  ? 42
                                                                  : 54),
                                                          borderRadius:
                                                              isShortHeight
                                                                  ? 8
                                                                  : 12,
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                        width: (isCompactBar ||
                                                                isShortHeight)
                                                            ? AppSpacing.xs
                                                            : AppSpacing.s10),
                                                    ConstrainedBox(
                                                      constraints:
                                                          BoxConstraints(
                                                        maxWidth: isShortHeight
                                                            ? (leftMaxWidth - 78)
                                                                .clamp(80.0, 180.0)
                                                            : (leftMaxWidth - 90)
                                                                .clamp(60.0, 160.0),
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
                                                                    isShortHeight
                                                                        ? AppFontSize
                                                                            .label
                                                                        : AppFontSize
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
                                                                    isShortHeight
                                                                        ? AppFontSize
                                                                            .tiny
                                                                        : AppFontSize
                                                                            .label,
                                                              ),
                                                            ),
                                                            if (!isShortHeight) ...[
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
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    if (!isCompactBar ||
                                                        leftMaxWidth >= 110 ||
                                                        isShortHeight)
                                                      IconButton(
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints: BoxConstraints(
                                                            minWidth: isShortHeight
                                                                ? 32
                                                                : AppSpacing
                                                                    .minTouchTarget,
                                                            minHeight: isShortHeight
                                                                ? 32
                                                                : AppSpacing
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
                                                          size: isShortHeight
                                                              ? 18
                                                              : 20,
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
                                                                  // Shuffle
                                                                  Semantics(
                                                                    label: state.isShuffle
                                                                        ? l10n.disableShuffle
                                                                        : l10n.enableShuffle,
                                                                    button: true,
                                                                    child: Tooltip(
                                                                      message: state.isShuffle
                                                                          ? l10n.disableShuffle
                                                                          : l10n.enableShuffle,
                                                                      child: Material(
                                                                        color: Colors.transparent,
                                                                        shape: const CircleBorder(),
                                                                        clipBehavior: Clip.antiAlias,
                                                                        child: InkWell(
                                                                          onTap: () {
                                                                            HapticFeedback.selectionClick();
                                                                            cubit.toggleShuffle();
                                                                          },
                                                                          child: AnimatedContainer(
                                                                            duration: const Duration(milliseconds: 180),
                                                                            width: isShortHeight ? 30 : 36,
                                                                            height: isShortHeight ? 30 : 36,
                                                                            decoration: BoxDecoration(
                                                                              shape: BoxShape.circle,
                                                                              color: state.isShuffle
                                                                                  ? activeColor.withValues(alpha: 0.16)
                                                                                  : Colors.transparent,
                                                                              border: state.isShuffle
                                                                                  ? Border.all(
                                                                                      color: activeColor.withValues(alpha: 0.35),
                                                                                      width: 1.0,
                                                                                    )
                                                                                  : null,
                                                                            ),
                                                                            child: Center(
                                                                              child: Icon(
                                                                                Icons.shuffle_rounded,
                                                                                size: isShortHeight ? 17 : 20,
                                                                                color: state.isShuffle
                                                                                    ? activeColor
                                                                                    : p.textSecondary,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                      width: isShortHeight
                                                                          ? AppSpacing.s10
                                                                          : AppSpacing.s14),
                                                                  // Previous Button
                                                                  Semantics(
                                                                    label: l10n.previous,
                                                                    button: true,
                                                                    child: Tooltip(
                                                                      message: l10n.previous,
                                                                      child: Material(
                                                                        color: Colors.transparent,
                                                                        shape: const CircleBorder(),
                                                                        clipBehavior: Clip.antiAlias,
                                                                        child: InkWell(
                                                                          onTap: () {
                                                                            HapticFeedback.lightImpact();
                                                                            cubit.previous();
                                                                          },
                                                                          child: Container(
                                                                            width: isShortHeight ? 34 : 40,
                                                                            height: isShortHeight ? 34 : 40,
                                                                            decoration: BoxDecoration(
                                                                              shape: BoxShape.circle,
                                                                              color: p.textPrimary.withValues(alpha: 0.08),
                                                                              border: Border.all(
                                                                                color: p.textPrimary.withValues(alpha: 0.13),
                                                                                width: 1.0,
                                                                              ),
                                                                              boxShadow: [
                                                                                BoxShadow(
                                                                                  color: Colors.black.withValues(alpha: 0.18),
                                                                                  blurRadius: 4,
                                                                                  offset: const Offset(0, 1),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                            child: Center(
                                                                              child: Icon(
                                                                                Icons.skip_previous_rounded,
                                                                                size: isShortHeight ? 20 : 24,
                                                                                color: p.textPrimary,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                      width: isShortHeight
                                                                          ? AppSpacing.s10
                                                                          : AppSpacing.s14),
                                                                  // Main Play / Pause Button
                                                                  Semantics(
                                                                    label: state.isPlaying
                                                                        ? l10n.pause
                                                                        : l10n.play,
                                                                    button: true,
                                                                    child: Tooltip(
                                                                      message: state.isPlaying
                                                                          ? l10n.pause
                                                                          : l10n.play,
                                                                      child: GestureDetector(
                                                                        behavior: HitTestBehavior.opaque,
                                                                        onTap: () {
                                                                          HapticFeedback.mediumImpact();
                                                                          cubit.togglePlayPause();
                                                                        },
                                                                        child: AnimatedContainer(
                                                                          duration: const Duration(milliseconds: 180),
                                                                          width: isShortHeight ? 40 : 48,
                                                                          height: isShortHeight ? 40 : 48,
                                                                          decoration: BoxDecoration(
                                                                            shape: BoxShape.circle,
                                                                            gradient: LinearGradient(
                                                                              begin: Alignment.topLeft,
                                                                              end: Alignment.bottomRight,
                                                                              colors: [
                                                                                Color.lerp(activeColor, Colors.white, 0.22) ?? activeColor,
                                                                                activeColor,
                                                                              ],
                                                                            ),
                                                                            boxShadow: [
                                                                              BoxShadow(
                                                                                color: activeColor.withValues(
                                                                                    alpha: state.isPlaying ? 0.45 : 0.28),
                                                                                blurRadius: isShortHeight ? 12 : 18,
                                                                                spreadRadius: state.isPlaying ? 1.5 : 0.5,
                                                                                offset: const Offset(0, 2),
                                                                              ),
                                                                              BoxShadow(
                                                                                color: Colors.black.withValues(alpha: 0.25),
                                                                                blurRadius: 6,
                                                                                offset: const Offset(0, 2),
                                                                              ),
                                                                            ],
                                                                            border: Border.all(
                                                                              color: Colors.white.withValues(alpha: 0.30),
                                                                              width: 1.2,
                                                                            ),
                                                                          ),
                                                                          child: Center(
                                                                            child: AnimatedSwitcher(
                                                                              duration: const Duration(milliseconds: 160),
                                                                              transitionBuilder: (child, anim) => ScaleTransition(
                                                                                scale: anim,
                                                                                child: child,
                                                                              ),
                                                                              child: Icon(
                                                                                state.isPlaying
                                                                                    ? Icons.pause_rounded
                                                                                    : Icons.play_arrow_rounded,
                                                                                key: ValueKey<bool>(state.isPlaying),
                                                                                color: activeColor.computeLuminance() > 0.5
                                                                                    ? const Color(0xFF101223)
                                                                                    : Colors.white,
                                                                                size: isShortHeight ? 22 : 26,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                      width: isShortHeight
                                                                          ? AppSpacing.s10
                                                                          : AppSpacing.s14),
                                                                  // Next Button
                                                                  Semantics(
                                                                    label: l10n.next,
                                                                    button: true,
                                                                    child: Tooltip(
                                                                      message: l10n.next,
                                                                      child: Material(
                                                                        color: Colors.transparent,
                                                                        shape: const CircleBorder(),
                                                                        clipBehavior: Clip.antiAlias,
                                                                        child: InkWell(
                                                                          onTap: () {
                                                                            HapticFeedback.lightImpact();
                                                                            cubit.next();
                                                                          },
                                                                          child: Container(
                                                                            width: isShortHeight ? 34 : 40,
                                                                            height: isShortHeight ? 34 : 40,
                                                                            decoration: BoxDecoration(
                                                                              shape: BoxShape.circle,
                                                                              color: p.textPrimary.withValues(alpha: 0.08),
                                                                              border: Border.all(
                                                                                color: p.textPrimary.withValues(alpha: 0.13),
                                                                                width: 1.0,
                                                                              ),
                                                                              boxShadow: [
                                                                                BoxShadow(
                                                                                  color: Colors.black.withValues(alpha: 0.18),
                                                                                  blurRadius: 4,
                                                                                  offset: const Offset(0, 1),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                            child: Center(
                                                                              child: Icon(
                                                                                Icons.skip_next_rounded,
                                                                                size: isShortHeight ? 20 : 24,
                                                                                color: p.textPrimary,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                      width: isShortHeight
                                                                          ? AppSpacing.s10
                                                                          : AppSpacing.s14),
                                                                  // Repeat
                                                                  Semantics(
                                                                    label: state.repeatMode == PlayerRepeatMode.one
                                                                        ? l10n.repeatOne
                                                                        : state.repeatMode == PlayerRepeatMode.all
                                                                            ? l10n.repeatAll
                                                                            : l10n.repeatOff,
                                                                    button: true,
                                                                    child: Tooltip(
                                                                      message: state.repeatMode == PlayerRepeatMode.one
                                                                          ? l10n.repeatOne
                                                                          : state.repeatMode == PlayerRepeatMode.all
                                                                              ? l10n.repeatAll
                                                                              : l10n.repeatOff,
                                                                      child: Material(
                                                                        color: Colors.transparent,
                                                                        shape: const CircleBorder(),
                                                                        clipBehavior: Clip.antiAlias,
                                                                        child: InkWell(
                                                                          onTap: () {
                                                                            HapticFeedback.selectionClick();
                                                                            cubit.toggleRepeat();
                                                                          },
                                                                          child: AnimatedContainer(
                                                                            duration: const Duration(milliseconds: 180),
                                                                            width: isShortHeight ? 30 : 36,
                                                                            height: isShortHeight ? 30 : 36,
                                                                            decoration: BoxDecoration(
                                                                              shape: BoxShape.circle,
                                                                              color: state.repeatMode != PlayerRepeatMode.off
                                                                                  ? activeColor.withValues(alpha: 0.16)
                                                                                  : Colors.transparent,
                                                                              border: state.repeatMode != PlayerRepeatMode.off
                                                                                  ? Border.all(
                                                                                      color: activeColor.withValues(alpha: 0.35),
                                                                                      width: 1.0,
                                                                                    )
                                                                                  : null,
                                                                            ),
                                                                            child: Center(
                                                                              child: Icon(
                                                                                state.repeatMode == PlayerRepeatMode.one
                                                                                    ? Icons.repeat_one_rounded
                                                                                    : Icons.repeat_rounded,
                                                                                size: isShortHeight ? 17 : 20,
                                                                                color: state.repeatMode != PlayerRepeatMode.off
                                                                                    ? activeColor
                                                                                    : p.textSecondary,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            SizedBox(
                                                                height:
                                                                    isShortHeight
                                                                        ? 2
                                                                        : AppSpacing
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
                                                                              height: isShortHeight ? 16 : 24,
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
                                                      if (!isShortHeight) ...[
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

                                                      ],
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
                                                              BoxConstraints(
                                                                  minWidth: isShortHeight ? 36 : 48,
                                                                  minHeight:
                                                                      isShortHeight ? 36 : 48),
                                                          icon: Icon(
                                                            Icons
                                                                .queue_music_rounded,
                                                            size: isShortHeight ? 18 : 19,
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
                                                            BoxConstraints(
                                                                minWidth: isShortHeight ? 36 : 48,
                                                                minHeight: isShortHeight ? 36 : 48),
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
