// lib/features/player/presentation/widgets/player_controls.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../cubit/player_state.dart';

class PlayerControls extends StatelessWidget {
  final bool isPlaying;
  final bool isShuffle;
  final PlayerRepeatMode repeatMode;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;
  final double mainButtonSize;
  final Color primaryColor;

  const PlayerControls({
    super.key,
    required this.isPlaying,
    required this.isShuffle,
    required this.repeatMode,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
    this.mainButtonSize = 64.0,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final onPrimaryColor = primaryColor.computeLuminance() > 0.5 ? const Color(0xFF101223) : Colors.white;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Semantics(
            label: isShuffle ? 'Disable shuffle' : 'Enable shuffle',
            button: true,
            child: IconButton(
              tooltip: isShuffle ? 'Disable shuffle' : 'Enable shuffle',
              onPressed: () {
                HapticFeedback.selectionClick();
                onToggleShuffle();
              },
              icon: Icon(
                Icons.shuffle_rounded,
                color: isShuffle ? primaryColor : p.textSecondary,
                size: 24,
              ),
            ),
          ),
          Semantics(
            label: 'Previous track',
            button: true,
            child: IconButton(
              tooltip: 'Previous track',
              onPressed: () {
                HapticFeedback.lightImpact();
                onPrevious();
              },
              icon: Icon(
                Icons.skip_previous_rounded,
                color: p.textPrimary,
                size: 38,
              ),
            ),
          ),
          Semantics(
            label: isPlaying ? 'Pause' : 'Play',
            button: true,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                onPlayPause();
              },
              child: Container(
                width: mainButtonSize,
                height: mainButtonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryColor,
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: onPrimaryColor,
                  size: mainButtonSize * 0.55,
                ),
              )
                  .animate(target: isPlaying ? 1 : 0)
                  .scale(duration: 120.ms, begin: const Offset(0.92, 0.92), end: const Offset(1.0, 1.0)),
            ),
          ),
          Semantics(
            label: 'Next track',
            button: true,
            child: IconButton(
              tooltip: 'Next track',
              onPressed: () {
                HapticFeedback.lightImpact();
                onNext();
              },
              icon: Icon(
                Icons.skip_next_rounded,
                color: p.textPrimary,
                size: 38,
              ),
            ),
          ),
          Semantics(
            label: repeatMode == PlayerRepeatMode.one
                ? 'Repeat one'
                : repeatMode == PlayerRepeatMode.all
                    ? 'Repeat all'
                    : 'Repeat off',
            button: true,
            child: IconButton(
              tooltip: repeatMode == PlayerRepeatMode.one
                  ? 'Repeat one'
                  : repeatMode == PlayerRepeatMode.all
                      ? 'Repeat all'
                      : 'Repeat off',
              onPressed: () {
                HapticFeedback.selectionClick();
                onToggleRepeat();
              },
              icon: Icon(
                repeatMode == PlayerRepeatMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                color: repeatMode != PlayerRepeatMode.off
                    ? primaryColor
                    : p.textSecondary,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
