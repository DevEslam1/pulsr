// lib/features/player/presentation/widgets/lyrics_view.dart
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../domain/models/lyrics_line.dart';

class LyricsView extends StatefulWidget {
  final List<LyricsLine> lyrics;
  final Duration currentPosition;
  final bool isLoading;
  final Color activeColor;

  const LyricsView({
    super.key,
    required this.lyrics,
    required this.currentPosition,
    this.isLoading = false,
    this.activeColor = AppColors.primary,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lyrics.isEmpty) return;

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
    const itemHeight = 44.0;
    final targetOffset = (index * itemHeight) - 100;
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (widget.lyrics.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lyrics_outlined, size: 48, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              const Text(
                'No Lyrics Found',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Place a .lrc file in the same folder as your audio track for offline synced lyrics.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final currentMs = widget.currentPosition.inMilliseconds;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: AppRadii.cardRadius,
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        itemCount: widget.lyrics.length,
        itemBuilder: (context, index) {
          final line = widget.lyrics[index];
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
        },
      ),
    );
  }
}
