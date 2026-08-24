// lib/features/player/presentation/widgets/lyrics_view.dart
import 'package:flutter/material.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../domain/models/lyrics_line.dart';

class LyricsView extends StatefulWidget {
  final List<LyricsLine> lyrics;
  final Duration currentPosition;
  final bool isLoading;
  final Color activeColor;
  final LyricsSource source;

  const LyricsView({
    super.key,
    required this.lyrics,
    required this.currentPosition,
    this.isLoading = false,
    this.activeColor = Colors.white,
    this.source = LyricsSource.none,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  bool get _isSynced => widget.lyrics.any((line) => line.timestamp > Duration.zero);

  LyricsSource get _effectiveSource {
    if (widget.source != LyricsSource.none) return widget.source;
    if (widget.lyrics.isNotEmpty) return widget.lyrics.first.source;
    return LyricsSource.none;
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lyrics.isEmpty || !_isSynced) return;

    final currentMs = widget.currentPosition.inMilliseconds;
    int activeIndex = -1;

    for (int i = 0; i < widget.lyrics.length; i++) {
      if (widget.lyrics[i].timestamp.inMilliseconds <= currentMs) {
        activeIndex = i;
      } else {
        break;
      }
    }

    if (activeIndex != -1 && activeIndex != _lastActiveIndex) {
      _lastActiveIndex = activeIndex;
      _scrollToActive(activeIndex);
    }
  }

  void _scrollToActive(int index) {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final estimatedOffset = (index / widget.lyrics.length) * maxScroll - 100;
    _scrollController.animateTo(
      estimatedOffset.clamp(0.0, maxScroll),
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
                'No Lyrics Found',
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
                style: TextStyle(color: p.textSecondary, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    final currentMs = widget.currentPosition.inMilliseconds;
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
                  final nextLineMs = index + 1 < widget.lyrics.length
                      ? widget.lyrics[index + 1].timestamp.inMilliseconds
                      : double.infinity;
                  final isCurrent = currentMs >= line.timestamp.inMilliseconds && currentMs < nextLineMs;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: isCurrent ? 20 : 15,
                        fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                        color: isCurrent ? widget.activeColor : Colors.white.withValues(alpha: 0.45),
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                      child: Text(line.text.isNotEmpty ? line.text : '•••'),
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
}
