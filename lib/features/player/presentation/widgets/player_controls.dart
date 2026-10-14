// lib/features/player/presentation/widgets/player_controls.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../cubit/player_state.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_colors.dart';

class PlayerControls extends StatefulWidget {
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

  /// Shows a progress spinner on the main button while the engine is
  /// loading/buffering. Tapping still toggles play/pause.
  final bool isBuffering;

  /// Whether a neighbouring queue entry exists in each direction. Defaults to
  /// true so standalone usages keep the pre-existing always-enabled behavior.
  final bool hasPrevious;
  final bool hasNext;
  final bool abLoopActive;

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
    this.isBuffering = false,
    this.hasPrevious = true,
    this.hasNext = true,
    this.abLoopActive = false,
  });

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  bool _isPlayPressed = false;
  double _prevNudgeX = 0.0;
  double _nextNudgeX = 0.0;
  Timer? _prevNudgeTimer;
  Timer? _nextNudgeTimer;

  @override
  void dispose() {
    _prevNudgeTimer?.cancel();
    _nextNudgeTimer?.cancel();
    super.dispose();
  }

  void _triggerPrevNudge() {
    _prevNudgeTimer?.cancel();
    setState(() => _prevNudgeX = -4.0);
    _prevNudgeTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted) {
        setState(() => _prevNudgeX = 0.0);
      }
    });
  }

  void _triggerNextNudge() {
    _nextNudgeTimer?.cancel();
    setState(() => _nextNudgeX = 4.0);
    _nextNudgeTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted) {
        setState(() => _nextNudgeX = 0.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final onPrimaryColor = widget.primaryColor.computeLuminance() > 0.5
        ? const Color(0xFF101223)
        : Colors.white;

    final shuffleLabel = widget.isShuffle ? l10n.disableShuffle : l10n.enableShuffle;
    final repeatLabel = widget.repeatMode == PlayerRepeatMode.one
        ? l10n.repeatOne
        : widget.repeatMode == PlayerRepeatMode.all
            ? l10n.repeatAll
            : l10n.repeatOff;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Shuffle Button with active indicator
              Semantics(
                label: shuffleLabel,
                button: true,
                child: _ControlButton(
                  tooltip: shuffleLabel,
                  isActive: widget.isShuffle,
                  activeColor: widget.primaryColor,
                  inactiveColor: p.textSecondary,
                  onPressed: () {
                    PulsrHaptics.selection();
                    widget.onToggleShuffle();
                  },
                  icon: Icons.shuffle_rounded,
                  iconSize: 22,
                ),
              ),

              const SizedBox(width: AppSpacing.md),

              // Previous Button
              Semantics(
                label: l10n.previous,
                button: true,
                enabled: widget.hasPrevious,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: _prevNudgeX),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  builder: (context, dx, child) => Transform.translate(
                    offset: Offset(dx, 0),
                    child: child,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: Tooltip(
                      message: l10n.previous,
                      excludeFromSemantics: true,
                      child: InkWell(
                        onTap: widget.hasPrevious
                            ? () {
                                PulsrHaptics.light();
                                _triggerPrevNudge();
                                widget.onPrevious();
                              }
                            : null,
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          width: (widget.mainButtonSize * 0.72).clamp(42.0, 52.0),
                          height: (widget.mainButtonSize * 0.72).clamp(42.0, 52.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.hasPrevious
                                ? p.textPrimary.withValues(alpha: 0.08)
                                : p.textPrimary.withValues(alpha: 0.03),
                            border: Border.all(
                              color: widget.hasPrevious
                                  ? p.textPrimary.withValues(alpha: 0.14)
                                  : p.textPrimary.withValues(alpha: 0.05),
                              width: 1.0,
                            ),
                            boxShadow: widget.hasPrevious
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Icon(
                              Icons.skip_previous_rounded,
                              color: widget.hasPrevious
                                  ? p.textPrimary
                                  : p.textTertiary.withValues(alpha: 0.3),
                              size: (widget.mainButtonSize * 0.44).clamp(24.0, 32.0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: AppSpacing.s18),

              // Main Play / Pause Button
              Semantics(
                label: widget.isPlaying ? l10n.pause : l10n.play,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => setState(() => _isPlayPressed = true),
                  onTapUp: (_) => setState(() => _isPlayPressed = false),
                  onTapCancel: () => setState(() => _isPlayPressed = false),
                  onTap: () {
                    PulsrHaptics.confirm();
                    widget.onPlayPause();
                  },
                  child: AnimatedScale(
                    scale: _isPlayPressed ? 0.92 : 1.0,
                    duration: Duration(milliseconds: _isPlayPressed ? 90 : 280),
                    curve: _isPlayPressed ? Curves.easeOutCubic : Curves.easeOutBack,
                    child: AnimatedContainer(
                      duration: context.motionMs(200),
                      width: widget.mainButtonSize,
                      height: widget.mainButtonSize,
                      decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(widget.primaryColor, Colors.white, 0.18) ??
                              widget.primaryColor,
                          widget.primaryColor,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.primaryColor.withValues(
                              alpha: widget.isPlaying ? 0.45 : 0.25),
                          blurRadius: widget.isPlaying ? 24 : 16,
                          spreadRadius: widget.isPlaying ? 2 : 0,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: AppColors.scrimAt(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                      border: Border.all(
                        color: widget.abLoopActive
                            ? p.accent
                            : AppColors.specularAt(0.25),
                        width: widget.abLoopActive ? 2.2 : 1.2,
                      ),
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: context.motionMs(260),
                        transitionBuilder: (child, anim) {
                          final curved = CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOutBack,
                          );
                          return FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.80, end: 1.0).animate(curved),
                              child: RotationTransition(
                                turns: Tween<double>(begin: -0.06, end: 0.0).animate(curved),
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: widget.isBuffering
                            ? SizedBox(
                                key: const ValueKey<String>('buffering'),
                                width: widget.mainButtonSize * 0.42,
                                height: widget.mainButtonSize * 0.42,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: onPrimaryColor,
                                ),
                              )
                            : Icon(
                                widget.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                key: ValueKey(widget.isPlaying),
                                color: onPrimaryColor,
                                size: widget.mainButtonSize * 0.52,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              ),

              const SizedBox(width: AppSpacing.s18),

              // Next Button
              Semantics(
                label: l10n.next,
                button: true,
                enabled: widget.hasNext,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: _nextNudgeX),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  builder: (context, dx, child) => Transform.translate(
                    offset: Offset(dx, 0),
                    child: child,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: Tooltip(
                      message: l10n.next,
                      excludeFromSemantics: true,
                      child: InkWell(
                        onTap: widget.hasNext
                            ? () {
                                PulsrHaptics.light();
                                _triggerNextNudge();
                                widget.onNext();
                              }
                            : null,
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          width: (widget.mainButtonSize * 0.72).clamp(42.0, 52.0),
                          height: (widget.mainButtonSize * 0.72).clamp(42.0, 52.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.hasNext
                                ? p.textPrimary.withValues(alpha: 0.08)
                                : p.textPrimary.withValues(alpha: 0.03),
                            border: Border.all(
                              color: widget.hasNext
                                  ? p.textPrimary.withValues(alpha: 0.14)
                                  : p.textPrimary.withValues(alpha: 0.05),
                              width: 1.0,
                            ),
                            boxShadow: widget.hasNext
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Icon(
                              Icons.skip_next_rounded,
                              color: widget.hasNext
                                  ? p.textPrimary
                                  : p.textTertiary.withValues(alpha: 0.3),
                              size: (widget.mainButtonSize * 0.44).clamp(24.0, 32.0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: AppSpacing.md),

              // Repeat Button with active indicator
              Semantics(
                label: repeatLabel,
                button: true,
                child: _ControlButton(
                  tooltip: repeatLabel,
                  isActive: widget.repeatMode != PlayerRepeatMode.off,
                  activeColor: widget.primaryColor,
                  inactiveColor: p.textSecondary,
                  onPressed: () {
                    PulsrHaptics.selection();
                    widget.onToggleRepeat();
                    final nextMode = switch (widget.repeatMode) {
                      PlayerRepeatMode.off => PlayerRepeatMode.all,
                      PlayerRepeatMode.all => PlayerRepeatMode.one,
                      PlayerRepeatMode.one => PlayerRepeatMode.off,
                    };
                    final nextLabel = switch (nextMode) {
                      PlayerRepeatMode.one => l10n.repeatOne,
                      PlayerRepeatMode.all => l10n.repeatAll,
                      PlayerRepeatMode.off => l10n.repeatOff,
                    };
                    final nextIcon = switch (nextMode) {
                      PlayerRepeatMode.one => Icons.repeat_one_rounded,
                      PlayerRepeatMode.all => Icons.repeat_rounded,
                      PlayerRepeatMode.off => Icons.repeat_rounded,
                    };
                    PulsrToast.show(
                      context,
                      message: nextLabel,
                      icon: nextIcon,
                      duration: const Duration(milliseconds: 1200),
                    );
                  },
                  icon: widget.repeatMode == PlayerRepeatMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  iconSize: 22,
                ),
              ),
            ],
          ),
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
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadii.r20All,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10, vertical: AppSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: context.motionMs(200),
                  padding: const EdgeInsets.all(AppSpacing.s6),
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
                const SizedBox(height: AppSpacing.s2),
                AnimatedContainer(
                  duration: context.motionMs(200),
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
      ),
    );
  }
}
