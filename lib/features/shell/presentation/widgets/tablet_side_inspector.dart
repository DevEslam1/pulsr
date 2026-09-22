// lib/features/shell/presentation/widgets/tablet_side_inspector.dart
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';
import '../../../player/presentation/widgets/lyrics_view.dart';
import '../../../player/presentation/widgets/now_playing_queue_view.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
  State<TabletSideInspector> createState() => _TabletSideInspectorState();
}

class _TabletSideInspectorState extends State<TabletSideInspector> {
  int _selectedTabIndex = 0; // 0: Queue, 1: Lyrics

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final activeColor = p.accent;

    return Container(
      width: 350,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(
          left: BorderSide(color: p.hairline, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header with Tabs & Close Button
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.s10),
            child: Row(
              children: [
                // Segmented Selector
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppRadii.r12),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedTabIndex = 0),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: AppSpacing.s6),
                              decoration: BoxDecoration(
                                color: _selectedTabIndex == 0
                                    ? p.accent
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(AppRadii.r8),
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
                                  const SizedBox(width: AppSpacing.s6),
                                  BlocSelector<PlayerCubit, PlayerState, int>(
                                    selector: (state) => state.queue.length,
                                    builder: (context, queueCount) => Text(
                                      'Queue ($queueCount)',
                                      style: TextStyle(
                                        fontSize: AppFontSize.label,
                                        fontWeight: _selectedTabIndex == 0
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: _selectedTabIndex == 0
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
                        const SizedBox(width: AppSpacing.xxs),
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedTabIndex = 1),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: AppSpacing.s6),
                              decoration: BoxDecoration(
                                color: _selectedTabIndex == 1
                                    ? p.accent
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(AppRadii.r8),
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
                                  const SizedBox(width: AppSpacing.s6),
                                  Text(
                                    context.l10n.lyricsLabel,
                                    style: TextStyle(
                                      fontSize: AppFontSize.label,
                                      fontWeight: _selectedTabIndex == 1
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: _selectedTabIndex == 1
                                          ? p.onAccent
                                          : p.textSecondary,
                                    ),
                                  ),
                                ],
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
                  tooltip: 'Close panel',
                  onPressed: widget.onClose,
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
                    child: BlocSelector<PlayerCubit, PlayerState, _TabletLyricsData>(
                      selector: (state) => _TabletLyricsData(
                        songId: state.currentSong?.id,
                        remoteId: state.currentSong?.remoteId,
                        lyricsSlice: state.lyricsSlice,
                      ),
                      builder: (context, lyricsData) => LyricsView(
                        key: ValueKey('lyrics_${lyricsData.songId}_${lyricsData.remoteId}'),
                        lyrics: lyricsData.lyricsSlice.lyrics,
                        isLoading: lyricsData.lyricsSlice.isLoadingLyrics,
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
    );
  }
}
