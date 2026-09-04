// lib/features/player/presentation/widgets/lyrics_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

class LyricsView extends StatefulWidget {
  /// Playback position used to highlight the active line.
  ///
  /// Optional for backwards compatibility: when null (the preferred usage from
  /// the player themes), the view derives the highlighted line from
  /// `PlayerCubit` itself via a [BlocSelector], so position ticks only
  /// rebuild the subtree when the active line actually changes. When
  /// non-null, the given value drives highlighting as before.
  final Duration? currentPosition;
  final List<LyricsLine> lyrics;
  final bool isLoading;
  final Color activeColor;
  final LyricsSource source;
  final ValueChanged<Duration>? onLineTapped;

  const LyricsView({
    super.key,
    this.currentPosition,
    required this.lyrics,
    this.isLoading = false,
    this.activeColor = Colors.white,
    this.source = LyricsSource.none,
    this.onLineTapped,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  // `_isSynced` is an O(n) scan; cache it keyed by lyrics list identity.
  List<LyricsLine>? _syncedCheckSource;
  bool _syncedCache = false;

  bool get _isSynced {
    if (!identical(_syncedCheckSource, widget.lyrics)) {
      _syncedCheckSource = widget.lyrics;
      _syncedCache = widget.lyrics.any((line) => line.timestamp > Duration.zero);
    }
    return _syncedCache;
  }

  LyricsSource get _effectiveSource {
    if (widget.source != LyricsSource.none) return widget.source;
    if (widget.lyrics.isNotEmpty) return widget.lyrics.first.source;
    return LyricsSource.none;
  }

  /// O(n) scan mapping a position to the index of the active lyric line
  /// (last line whose timestamp is <= position). Returns -1 before the first
  /// line's timestamp.
  int _activeIndexOf(Duration position) {
    final currentMs = position.inMilliseconds;
    int activeIndex = -1;
    for (int i = 0; i < widget.lyrics.length; i++) {
      if (widget.lyrics[i].timestamp.inMilliseconds <= currentMs) {
        activeIndex = i;
      } else {
        break;
      }
    }
    return activeIndex;
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Provided-position path: react to parent-driven position updates.
    if (widget.currentPosition == null || widget.lyrics.isEmpty || !_isSynced) {
      return;
    }
    _handleActiveLine(_activeIndexOf(widget.currentPosition!));
  }

  void _handleActiveLine(int activeIndex) {
    if (activeIndex != -1 && activeIndex != _lastActiveIndex) {
      _lastActiveIndex = activeIndex;
      _scrollToActive(activeIndex);
    }
  }

  void _scrollToActive(int index) {
    if (!_scrollController.hasClients || widget.lyrics.isEmpty) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final viewportHeight = _scrollController.position.viewportDimension;
    final denom = widget.lyrics.length > 1 ? (widget.lyrics.length - 1) : 1;
    final rawProgress = (index / denom);
    // Interpolate offset so early lines are at top and late lines reveal bottom fully
    final targetOffset =
        rawProgress * maxScroll - (1.0 - rawProgress) * (viewportHeight * 0.25);
    _scrollController.animateTo(
      targetOffset.clamp(0.0, maxScroll),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildSourceBadge(LyricsSource source) {
    if (source == LyricsSource.none) return const SizedBox.shrink();

    final String label = switch (source) {
      LyricsSource.embedded => 'Embedded',
      LyricsSource.externalLrc => 'LRC File',
      LyricsSource.lrclib => 'LRCLIB Synced',
      LyricsSource.ytmusic => 'YouTube Music',
      LyricsSource.none => '',
    };
    final IconData icon = switch (source) {
      LyricsSource.embedded => Icons.music_note,
      LyricsSource.externalLrc => Icons.subtitles_outlined,
      LyricsSource.lrclib => Icons.cloud_done_rounded,
      LyricsSource.ytmusic => Icons.lyrics_rounded,
      LyricsSource.none => Icons.music_note,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: widget.activeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.activeColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: widget.activeColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: widget.activeColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// The [BlocSelector] maps position -> active line index, so its subtree
  /// (the lyrics list) only rebuilds when the active line actually changes,
  /// not on every ~200 ms position tick.
  Widget _buildSyncedList() {
    return BlocSelector<PlayerCubit, PlayerState, int>(
      // Unsynced (plain-text) lyrics must not drive highlight/auto-scroll:
      // map them to -1 (no active line) exactly like the provided-position
      // path, so _lastActiveIndex is never polluted with a bogus index.
      selector: (s) => _isSynced ? _activeIndexOf(s.position) : -1,
      builder: (context, activeIndex) {
        _handleActiveLine(activeIndex);
        return _buildLyricsList(activeIndex: activeIndex);
      },
    );
  }

  Widget _buildLyricsList({required int activeIndex}) {
    final source = _effectiveSource;
    final isSynced = _isSynced;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: AppRadii.cardRadius,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              itemCount: widget.lyrics.length,
              itemBuilder: (context, index) {
                final line = widget.lyrics[index];
                if (isSynced) {
                  final isCurrent = index == activeIndex;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (widget.onLineTapped != null) {
                            widget.onLineTapped!(line.timestamp);
                          } else {
                            try {
                              context.read<PlayerCubit>().seek(line.timestamp);
                            } catch (_) {}
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        splashColor: widget.activeColor.withValues(alpha: 0.15),
                        highlightColor:
                            widget.activeColor.withValues(alpha: 0.08),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 12),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: isCurrent ? 20 : 15,
                              fontWeight:
                                  isCurrent ? FontWeight.w800 : FontWeight.w500,
                              color: isCurrent
                                  ? widget.activeColor
                                  : Colors.white.withValues(alpha: 0.45),
                              height: 1.3,
                            ),
                            textAlign: TextAlign.center,
                            child:
                                Text(line.text.isNotEmpty ? line.text : '•••'),
                          ),
                        ),
                      ),
                    ),
                  );
                } else {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      line.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.4,
                      ),
                    ),
                  );
                }
              },
            ),
          ),
          if (source != LyricsSource.none)
            Positioned(
              top: 12,
              right: 12,
              child: _buildSourceBadge(source),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (widget.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: widget.activeColor),
      );
    }

    if (widget.lyrics.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lyrics_outlined, size: 48, color: p.textTertiary),
              const SizedBox(height: 12),
              Text(
                context.l10n.noLyricsFound,
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Place a .lrc file in the same folder as your audio track or embed lyrics into file tags.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: p.textSecondary, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    // Self-subscribing path (preferred): highlight + auto-scroll react to the
    // cubit without the parent theme rebuilding per tick.
    if (widget.currentPosition == null) {
      return _buildSyncedList();
    }

    // Provided-position path (backwards compatible).
    final activeIndex =
        _isSynced ? _activeIndexOf(widget.currentPosition!) : -1;
    return _buildLyricsList(activeIndex: activeIndex);
  }
}
