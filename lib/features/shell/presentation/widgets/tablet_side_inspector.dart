// lib/features/shell/presentation/widgets/tablet_side_inspector.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';
import '../../../player/presentation/widgets/lyrics_view.dart';
import '../../../player/presentation/widgets/now_playing_queue_view.dart';

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

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.queue.length != curr.queue.length ||
          prev.lyrics != curr.lyrics ||
          prev.isLoadingLyrics != curr.isLoadingLyrics ||
          prev.lyricsSource != curr.lyricsSource,
      builder: (context, state) {
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
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    // Segmented Selector
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
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
                                      const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _selectedTabIndex == 0
                                        ? p.accent
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(9),
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
                                      const SizedBox(width: 5),
                                      Text(
                                        'Queue (${state.queue.length})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: _selectedTabIndex == 0
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: _selectedTabIndex == 0
                                              ? p.onAccent
                                              : p.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedTabIndex = 1),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _selectedTabIndex == 1
                                        ? p.accent
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(9),
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
                                      const SizedBox(width: 5),
                                      Text(
                                        'Lyrics',
                                        style: TextStyle(
                                          fontSize: 12,
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
                    const SizedBox(width: 8),
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
                        padding: EdgeInsets.all(8.0),
                        child: NowPlayingQueueView(),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: LyricsView(
                          lyrics: state.lyrics,
                          isLoading: state.isLoadingLyrics,
                          activeColor: activeColor,
                          source: state.lyricsSource,
                          onLineTapped: (pos) =>
                              context.read<PlayerCubit>().seek(pos),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
