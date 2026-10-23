// lib/core/widgets/pulsr_pressable.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_radii.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';

/// {@category DesignSystem}
enum PulsrHapticStyle {
  light,
  medium,
  selection,
  heavy,
}

/// A premium, Apple/M3 tactile pressable wrapper.
///
/// Compresses slightly on press down (scale 0.96) and springs back with an organic
/// curve when released. Automatically provides subtle haptic feedback and respects
/// global Reduce Motion accessibility settings.
class PulsrPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final Duration duration;
  final bool enableHaptics;
  final PulsrHapticStyle hapticStyle;
  final HitTestBehavior behavior;

  /// Shape of the keyboard focus ring. Match the child's silhouette (for
  /// example [AppRadii.full] for circular icon buttons) so focus stays legible
  /// without drawing a rounded square around a round control.
  final BorderRadius focusBorderRadius;

  const PulsrPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.duration = const Duration(milliseconds: 120),
    this.enableHaptics = true,
    this.hapticStyle = PulsrHapticStyle.light,
    this.behavior = HitTestBehavior.opaque,
    this.focusBorderRadius = AppRadii.r12All,
  });

  @override
  State<PulsrPressable> createState() => _PulsrPressableState();
}

class _PulsrPressableState extends State<PulsrPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: const Duration(milliseconds: 180),
    );
    _configureScaleAnimation();
  }

  void _configureScaleAnimation() {
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressedScale,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutQuad,
      reverseCurve: Curves.easeOutBack,
    ));
  }

  @override
  void didUpdateWidget(covariant PulsrPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.pressedScale != widget.pressedScale) {
      _configureScaleAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    if (context.motionEnabled) {
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails _) {
    _activate();
  }

  void _activate() {
    // Release the pressed scale before the early return: a pressable that only
    // exposes onLongPress never calls _release() from the tap path, so without
    // this the widget stayed visually stuck at pressedScale after a long press.
    _release();
    if (widget.onTap == null) return;
    if (widget.enableHaptics) {
      switch (widget.hapticStyle) {
        case PulsrHapticStyle.light:
          HapticFeedback.lightImpact();
          break;
        case PulsrHapticStyle.medium:
          HapticFeedback.mediumImpact();
          break;
        case PulsrHapticStyle.selection:
          HapticFeedback.selectionClick();
          break;
        case PulsrHapticStyle.heavy:
          HapticFeedback.heavyImpact();
          break;
      }
    }
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _release();
  }

  void _release() {
    if (context.motionEnabled &&
        (_controller.isAnimating || _controller.value > 0)) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) {
      return widget.child;
    }

    return FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (value) {
        if (mounted && value != _focused) setState(() => _focused = value);
      },
      child: Semantics(
        button: widget.onTap != null,
        onTap: widget.onTap == null ? null : _activate,
        onLongPress: widget.onLongPress,
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: widget.behavior,
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          onLongPress: widget.onLongPress != null
              ? () {
                  if (widget.enableHaptics) {
                    switch (widget.hapticStyle) {
                      case PulsrHapticStyle.heavy:
                        HapticFeedback.heavyImpact();
                        break;
                      default:
                        HapticFeedback.mediumImpact();
                        break;
                    }
                  }
                  widget.onLongPress?.call();
                }
              : null,
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  if (!context.motionEnabled) return child!;
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: child,
                  );
                },
                child: widget.child,
              ),
              // Keyboard / switch-navigation focus ring.
              if (_focused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: context.palette.accent, width: 2),
                        borderRadius: widget.focusBorderRadius,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
