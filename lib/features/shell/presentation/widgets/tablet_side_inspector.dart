// lib/features/shell/presentation/widgets/tablet_side_inspector.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/performance/gpu_budget.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';
import '../../../player/presentation/widgets/lyrics_view.dart';
import '../../../player/presentation/widgets/now_playing_queue_view.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

@immutable
class _TabletLyricsData {
  final int? songId;
  final String? remoteId;
  final LyricsSlice lyricsSlice;

  const _TabletLyricsData({
    required this.songId,
    required this.remoteId,
    required this.lyricsSlice,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TabletLyricsData &&
          songId == other.songId &&
          remoteId == other.remoteId &&
          lyricsSlice == other.lyricsSlice;

  @override
  int get hashCode => Object.hash(songId, remoteId, lyricsSlice);
}

class TabletSideInspector extends StatefulWidget {
  final VoidCallback onClose;

  const TabletSideInspector({
    super.key,
    required this.onClose,
  });

  @override
  State<TabletSideInspector> createState() => TabletSideInspectorState();
}

class TabletSideInspectorState extends State<TabletSideInspector> {
  int _selectedTabIndex = 0; // 0: Queue, 1: Lyrics
  double? _customWidth;
  bool _isDragging = false;
  double? _lastScreenWidth;
  double _dragDeltaAccumulator = 0.0;

  @visibleForTesting
  double? get customWidth => _customWidth;

  @visibleForTesting
  set customWidth(double? value) => setState(() => _customWidth = value);

  @visibleForTesting
  double get dragDeltaAccumulator => _dragDeltaAccumulator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentWidth = Adaptive.widthOf(context);
    if (_lastScreenWidth != null &&
        _lastScreenWidth != currentWidth &&
        _lastScreenWidth! > 0) {
      if (_customWidth != null) {
        // Proportionally scale _customWidth so rotation doesn't cause a visual jump
        final ratio = _customWidth! / _lastScreenWidth!;
        _customWidth = (ratio * currentWidth).clamp(280.0, 400.0);
      }
    }
    _lastScreenWidth = currentWidth;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final activeColor = p.accent;
    final defaultWidth = (Adaptive.widthOf(context) * 0.35).clamp(280.0, 400.0);
    final inspectorWidth = (_customWidth ?? defaultWidth).clamp(280.0, 400.0);

    return Container(
      width: inspectorWidth,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            GpuBudget.isGpuSaverActive
                ? p.surface
                : p.surface.withValues(alpha: p.isDark ? 0.78 : 0.88),
            GpuBudget.isGpuSaverActive
                ? p.surfaceContainer
                : p.surfaceContainer.withValues(alpha: p.isDark ? 0.72 : 0.84),
          ],
        ),
        border: BorderDirectional(
          start: BorderSide(
            color: _isDragging
                ? p.accent.withValues(alpha: 0.6)
                : (p.isDark
                    ? AppColors.specularStrong
                    : AppColors.scrimAt(0.08)),
            width: _isDragging ? 1.5 : 1.2,
          ),
        ),
      ),
      child: ClipRect(
        child: Builder(
          builder: (context) {
            final inspectorContent = Stack(
              children: [
                Column(
                  children: [
                    // Header with Tabs & Close Button
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s14, vertical: AppSpacing.s10),
                      child: Row(
                        children: [
                          // Segmented Selector
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: p.surfaceContainer,
                                borderRadius:
                                    BorderRadius.circular(AppRadii.r12),
                                border: Border.all(color: p.hairline),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Semantics(
                                      button: true,
                                      selected: _selectedTabIndex == 0,
                                      label: context.l10n.queue,
                                      child: GestureDetector(
                                        onTap: () => setState(
                                            () => _selectedTabIndex = 0),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: AppSpacing.s6),
                                          decoration: BoxDecoration(
                                            color: _selectedTabIndex == 0
                                                ? p.accent
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                                AppRadii.r8),
                                          ),
                                          alignment: Alignment.center,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.queue_music_rounded,
                                                size: 15,
                                                color: _selectedTabIndex == 0
                                                    ? p.onAccent
                                                    : p.textSecondary,
                                              ),
                                              const SizedBox(
                                                  width: AppSpacing.s6),
                                              Flexible(
                                                child: BlocSelector<PlayerCubit,
                                                    PlayerState, int>(
                                                  selector: (state) =>
                                                      state.queue.length,
                                                  builder:
                                                      (context, queueCount) =>
                                                          Text(
                                                    'Queue ($queueCount)',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize:
                                                          AppFontSize.label,
                                                      fontWeight:
                                                          _selectedTabIndex == 0
                                                              ? FontWeight.w800
                                                              : FontWeight.w600,
                                                      color:
                                                          _selectedTabIndex == 0
                                                              ? p.onAccent
                                                              : p.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xxs),
                                  Expanded(
                                    child: Semantics(
                                      button: true,
                                      selected: _selectedTabIndex == 1,
                                      label: context.l10n.lyricsLabel,
                                      child: GestureDetector(
                                        onTap: () => setState(
                                            () => _selectedTabIndex = 1),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: AppSpacing.s6),
                                          decoration: BoxDecoration(
                                            color: _selectedTabIndex == 1
                                                ? p.accent
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                                AppRadii.r8),
                                          ),
                                          alignment: Alignment.center,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.lyrics_rounded,
                                                size: 15,
                                                color: _selectedTabIndex == 1
                                                    ? p.onAccent
                                                    : p.textSecondary,
                                              ),
                                              const SizedBox(
                                                  width: AppSpacing.s6),
                                              Flexible(
                                                child: Text(
                                                  context.l10n.lyricsLabel,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: AppFontSize.label,
                                                    fontWeight:
                                                        _selectedTabIndex == 1
                                                            ? FontWeight.w800
                                                            : FontWeight.w600,
                                                    color:
                                                        _selectedTabIndex == 1
                                                            ? p.onAccent
                                                            : p.textSecondary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            tooltip: context.l10n.close,
                            onPressed: widget.onClose,
                            constraints: const BoxConstraints(
                              minWidth: AppSpacing.minTouchTarget,
                              minHeight: AppSpacing.minTouchTarget,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: 1, color: p.hairline),

                    // Content Area
                    Expanded(
                      child: _selectedTabIndex == 0
                          ? const Padding(
                              padding: EdgeInsets.all(AppSpacing.xs),
                              child: NowPlayingQueueView(),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              child: BlocSelector<PlayerCubit, PlayerState,
                                  _TabletLyricsData>(
                                selector: (state) => _TabletLyricsData(
                                  songId: state.currentSong?.id,
                                  remoteId: state.currentSong?.remoteId,
                                  lyricsSlice: state.lyricsSlice,
                                ),
                                builder: (context, lyricsData) => LyricsView(
                                  key: (lyricsData.songId != null ||
                                          lyricsData.remoteId != null)
                                      ? ValueKey(
                                          'lyrics_${lyricsData.songId}_${lyricsData.remoteId}')
                                      : const ValueKey('lyrics_empty'),
                                  lyrics: lyricsData.lyricsSlice.lyrics,
                                  isLoading:
                                      lyricsData.lyricsSlice.isLoadingLyrics,
                                  activeColor: activeColor,
                                  source: lyricsData.lyricsSlice.lyricsSource,
                                  onLineTapped: (pos) =>
                                      context.read<PlayerCubit>().seek(pos),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
                // Left edge drag-to-resize handle
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: 14,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (_) {
                        _dragDeltaAccumulator = 0.0;
                        setState(() => _isDragging = true);
                      },
                      onHorizontalDragUpdate: (details) {
                        final isRtl =
                            Directionality.of(context) == TextDirection.rtl;
                        final delta =
                            isRtl ? details.delta.dx : -details.delta.dx;
                        _dragDeltaAccumulator += delta;
                        if (_dragDeltaAccumulator.abs() >= 1.0) {
                          final current = _customWidth ?? defaultWidth;
                          final newWidth = (current + _dragDeltaAccumulator)
                              .clamp(280.0, 400.0);
                          _dragDeltaAccumulator = 0.0;
                          if (newWidth != _customWidth) {
                            setState(() {
                              _customWidth = newWidth;
                            });
                          }
                        }
                      },
                      onHorizontalDragEnd: (_) {
                        _dragDeltaAccumulator = 0.0;
                        setState(() => _isDragging = false);
                      },
                      onHorizontalDragCancel: () {
                        _dragDeltaAccumulator = 0.0;
                        setState(() => _isDragging = false);
                      },
                      child: Center(
                        child: AnimatedContainer(
                          duration: context.motionMs(150),
                          width: _isDragging ? 4 : 3,
                          height: _isDragging ? 48 : 32,
                          decoration: BoxDecoration(
                            color: _isDragging
                                ? p.accent
                                : p.textTertiary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(AppRadii.r4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );

            if (GpuBudget.isGpuSaverActive) {
              return inspectorContent;
            }
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: inspectorContent,
            );
          },
        ),
      ),
    );
  }
}
