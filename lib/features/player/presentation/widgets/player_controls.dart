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
    final onPrimaryColor = primaryColor.computeLuminance() > 0.5
        ? const Color(0xFF101223)
        : Colors.white;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Shuffle Button with active indicator
            Semantics(
              label: isShuffle ? 'Disable shuffle' : 'Enable shuffle',
              button: true,
              child: _ControlButton(
                tooltip: isShuffle ? 'Disable shuffle' : 'Enable shuffle',
                isActive: isShuffle,
                activeColor: primaryColor,
                inactiveColor: p.textSecondary,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onToggleShuffle();
                },
                icon: Icons.shuffle_rounded,
                iconSize: 22,
              ),
            ),

            // Previous Button
            Semantics(
              label: 'Previous track',
              button: true,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  tooltip: 'Previous track',
                  splashRadius: 28,
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
            ),

            // Main Play / Pause Button
            Semantics(
              label: isPlaying ? 'Pause' : 'Play',
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onPlayPause();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: mainButtonSize,
                  height: mainButtonSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(primaryColor, Colors.white, 0.18) ?? primaryColor,
                        primaryColor,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: isPlaying ? 0.45 : 0.25),
                        blurRadius: isPlaying ? 24 : 16,
                        spreadRadius: isPlaying ? 2 : 0,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1.2,
                    ),
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: child,
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        key: ValueKey(isPlaying),
                        color: onPrimaryColor,
                        size: mainButtonSize * 0.52,
                      ),
                    ),
                  ),
                ).animate(target: isPlaying ? 1 : 0).scale(
                      duration: 140.ms,
                      curve: Curves.easeOutBack,
                      begin: const Offset(0.94, 0.94),
                      end: const Offset(1.0, 1.0),
                    ),
              ),
            ),

            // Next Button
            Semantics(
              label: 'Next track',
              button: true,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  tooltip: 'Next track',
                  splashRadius: 28,
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
            ),

            // Repeat Button with active indicator
            Semantics(
              label: repeatMode == PlayerRepeatMode.one
                  ? 'Repeat one'
                  : repeatMode == PlayerRepeatMode.all
                      ? 'Repeat all'
                      : 'Repeat off',
              button: true,
              child: _ControlButton(
                tooltip: repeatMode == PlayerRepeatMode.one
                    ? 'Repeat one'
                    : repeatMode == PlayerRepeatMode.all
                        ? 'Repeat all'
                        : 'Repeat off',
                isActive: repeatMode != PlayerRepeatMode.off,
                activeColor: primaryColor,
                inactiveColor: p.textSecondary,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onToggleRepeat();
                },
                icon: repeatMode == PlayerRepeatMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                iconSize: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onPressed;
  final String tooltip;

  const _ControlButton({
    required this.icon,
    this.iconSize = 22,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? activeColor.withValues(alpha: 0.15)
                      : Colors.transparent,
                ),
                child: Icon(
                  icon,
                  color: isActive ? activeColor : inactiveColor,
                  size: iconSize,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isActive ? 4 : 0,
                height: isActive ? 4 : 0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: activeColor,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.6),
                            blurRadius: 4,
                            spreadRadius: 0.5,
                          )
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
