// lib/features/player/presentation/widgets/player_controls.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../cubit/player_state.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/utils/formatters.dart';
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

  /// AB loop inline affordances flanking Back (A) and Next (B) buttons.
  final bool showAbControls;
  final Duration? abPointA;
  final Duration? abPointB;
  final VoidCallback? onSetAbPointA;
  final VoidCallback? onSetAbPointB;
  final VoidCallback? onToggleAbLoop;
  final VoidCallback? onClearAbLoop;

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
    this.sideButtonSize,
    required this.primaryColor,
    this.isBuffering = false,
    this.hasPrevious = true,
    this.hasNext = true,
    this.abLoopActive = false,
    this.showAbControls = false,
    this.abPointA,
    this.abPointB,
    this.onSetAbPointA,
    this.onSetAbPointB,
    this.onToggleAbLoop,
    this.onClearAbLoop,
  });

  final double? sideButtonSize;

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

    final shuffleLabel =
        widget.isShuffle ? l10n.disableShuffle : l10n.enableShuffle;
    final repeatLabel = widget.repeatMode == PlayerRepeatMode.one
        ? l10n.repeatOne
        : widget.repeatMode == PlayerRepeatMode.all
            ? l10n.repeatAll
            : l10n.repeatOff;

    final resolvedSideSize = widget.sideButtonSize ??
        (widget.mainButtonSize * 0.72).clamp(38.0, 52.0);
    final prevNextIconSize = (resolvedSideSize * 0.54).clamp(20.0, 30.0);
    final buttonSpacing = widget.showAbControls
        ? (widget.mainButtonSize * 0.12).clamp(4.0, 10.0)
        : (widget.mainButtonSize * 0.22).clamp(8.0, 18.0);
    final shuffleRepeatIconSize = (resolvedSideSize * 0.48).clamp(18.0, 24.0);
    final abButtonSize = (resolvedSideSize * 0.78).clamp(32.0, 42.0);

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
                  iconSize: shuffleRepeatIconSize,
                ),
              ),

              if (widget.showAbControls) ...[
                SizedBox(width: buttonSpacing),
                // Point A Button (next to Back/Previous)
                Semantics(
                  label: widget.abPointA != null
                      ? 'Loop point A ${Formatters.formatDuration(widget.abPointA!)}'
                      : 'Set loop point A',
                  button: true,
                  child: _AbPointButton(
                    label: 'A',
                    point: widget.abPointA,
                    isActive: widget.abPointA != null,
                    isLoopActive: widget.abLoopActive,
                    activeColor: widget.primaryColor,
                    inactiveColor: p.textSecondary,
                    onPressed: () {
                      PulsrHaptics.selection();
                      widget.onSetAbPointA?.call();
                    },
                    onLongPress: () {
                      if (widget.abPointA != null || widget.abPointB != null) {
                        PulsrHaptics.confirm();
                        widget.onClearAbLoop?.call();
                        PulsrToast.show(
                          context,
                          message: l10n.clearAbLoop,
                          icon: Icons.clear_rounded,
                          duration: const Duration(milliseconds: 1200),
                        );
                      }
                    },
                    tooltip: widget.abPointA != null
                        ? 'Point A: ${Formatters.formatDuration(widget.abPointA!)} (${l10n.clearAbLoop})'
                        : 'Set loop point A',
                    buttonSize: abButtonSize,
                  ),
                ),
              ],

              SizedBox(width: buttonSpacing),

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
                          width: resolvedSideSize,
                          height: resolvedSideSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: widget.hasPrevious
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      p.textPrimary.withValues(alpha: 0.12),
                                      p.textPrimary.withValues(alpha: 0.05),
                                    ],
                                  )
                                : null,
                            color: widget.hasPrevious
                                ? null
                                : p.textPrimary.withValues(alpha: 0.03),
                            border: Border.all(
                              color: widget.hasPrevious
                                  ? p.textPrimary.withValues(alpha: 0.16)
                                  : p.textPrimary.withValues(alpha: 0.05),
                              width: 1.0,
                            ),
                            boxShadow: widget.hasPrevious
                                ? [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.22),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
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
                              size: prevNextIconSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              SizedBox(width: buttonSpacing),

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
                    curve: _isPlayPressed
                        ? Curves.easeOutCubic
                        : Curves.easeOutBack,
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
                            Color.lerp(
                                    widget.primaryColor, Colors.white, 0.22) ??
                                widget.primaryColor,
                            widget.primaryColor,
                            Color.lerp(
                                    widget.primaryColor, Colors.black, 0.14) ??
                                widget.primaryColor,
                          ],
                          stops: const [0.0, 0.58, 1.0],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.primaryColor.withValues(
                                alpha: widget.isPlaying ? 0.48 : 0.28),
                            blurRadius: widget.isPlaying ? 26 : 18,
                            spreadRadius: widget.isPlaying ? 2 : 0,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: AppColors.scrimAt(0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: widget.abLoopActive
                              ? p.accent
                              : AppColors.specularAt(0.32),
                          width: widget.abLoopActive ? 2.2 : 1.4,
                        ),
                      ),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: context.motionMs(260),
                          transitionBuilder: (child, anim) {
                            final curve = CurveTween(
                              curve: Curves.easeOutBack,
                            );
                            return FadeTransition(
                              opacity: anim,
                              child: ScaleTransition(
                                scale: anim.drive(
                                  Tween<double>(begin: 0.80, end: 1.0)
                                      .chain(curve),
                                ),
                                child: RotationTransition(
                                  turns: anim.drive(
                                    Tween<double>(begin: -0.06, end: 0.0)
                                        .chain(curve),
                                  ),
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

              SizedBox(width: buttonSpacing),

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
                          width: resolvedSideSize,
                          height: resolvedSideSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: widget.hasNext
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      p.textPrimary.withValues(alpha: 0.12),
                                      p.textPrimary.withValues(alpha: 0.05),
                                    ],
                                  )
                                : null,
                            color: widget.hasNext
                                ? null
                                : p.textPrimary.withValues(alpha: 0.03),
                            border: Border.all(
                              color: widget.hasNext
                                  ? p.textPrimary.withValues(alpha: 0.16)
                                  : p.textPrimary.withValues(alpha: 0.05),
                              width: 1.0,
                            ),
                            boxShadow: widget.hasNext
                                ? [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.22),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
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
                              size: prevNextIconSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              if (widget.showAbControls) ...[
                SizedBox(width: buttonSpacing),
                // Point B Button (next to Next)
                Semantics(
                  label: widget.abPointB != null
                      ? 'Loop point B ${Formatters.formatDuration(widget.abPointB!)}'
                      : 'Set loop point B',
                  button: true,
                  child: _AbPointButton(
                    label: 'B',
                    point: widget.abPointB,
                    isActive: widget.abPointB != null,
                    isLoopActive: widget.abLoopActive,
                    activeColor: widget.primaryColor,
                    inactiveColor: p.textSecondary,
                    onPressed: () {
                      PulsrHaptics.selection();
                      widget.onSetAbPointB?.call();
                    },
                    onLongPress: () {
                      if (widget.abPointA != null || widget.abPointB != null) {
                        PulsrHaptics.confirm();
                        widget.onClearAbLoop?.call();
                        PulsrToast.show(
                          context,
                          message: l10n.clearAbLoop,
                          icon: Icons.clear_rounded,
                          duration: const Duration(milliseconds: 1200),
                        );
                      }
                    },
                    tooltip: widget.abPointB != null
                        ? 'Point B: ${Formatters.formatDuration(widget.abPointB!)} (${l10n.clearAbLoop})'
                        : 'Set loop point B',
                    buttonSize: abButtonSize,
                  ),
                ),
              ],

              SizedBox(width: buttonSpacing),

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
                  iconSize: shuffleRepeatIconSize,
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
                        ? activeColor.withValues(alpha: 0.16)
                        : Colors.transparent,
                    border: isActive
                        ? Border.all(
                            color: activeColor.withValues(alpha: 0.35),
                            width: 1.0,
                          )
                        : null,
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

class _AbPointButton extends StatelessWidget {
  final String label;
  final Duration? point;
  final bool isActive;
  final bool isLoopActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String tooltip;
  final double buttonSize;

  const _AbPointButton({
    required this.label,
    this.point,
    required this.isActive,
    this.isLoopActive = false,
    required this.activeColor,
    required this.inactiveColor,
    this.onPressed,
    this.onLongPress,
    required this.tooltip,
    this.buttonSize = 34.0,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final Color effectiveColor = isLoopActive
        ? context.palette.success
        : (isActive ? activeColor : inactiveColor);

    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          onLongPress: onLongPress,
          borderRadius: AppRadii.r20All,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxs, vertical: AppSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: context.motionMs(200),
                  width: buttonSize,
                  height: buttonSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? effectiveColor.withValues(alpha: 0.16)
                        : (p.isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.05),
                    border: Border.all(
                      color: isActive
                          ? effectiveColor.withValues(alpha: 0.50)
                          : (p.isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.12),
                      width: isActive ? 1.4 : 1.0,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: effectiveColor.withValues(alpha: 0.25),
                              blurRadius: 8,
                              spreadRadius: 0.5,
                            )
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: (buttonSize * 0.44).clamp(11.0, 15.0),
                      fontWeight: FontWeight.w800,
                      color: effectiveColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                AnimatedContainer(
                  duration: context.motionMs(200),
                  width: isActive ? 4 : 0,
                  height: isActive ? 4 : 0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: effectiveColor,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: effectiveColor.withValues(alpha: 0.6),
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
