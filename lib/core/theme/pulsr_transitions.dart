import 'package:flutter/material.dart';

/// {@category DesignSystem}
/// Aurora motion. All builders use `animation.drive(CurveTween)` instead of
/// `CurvedAnimation` so repeated route/overlay builds never register listeners
/// that outlive the transition (same rationale as player_theme_chrome).
class PulsrTransitions {
  PulsrTransitions._();

  static const Curve _enter = Cubic(0.22, 1.0, 0.36, 1.0); // easeOutQuint-ish
  static const Curve _exit = Curves.easeInCubic;

  static Animatable<double> _curve(Animation<double> anim) => CurveTween(
        curve: anim.status == AnimationStatus.reverse ? _exit : _enter,
      );

  /// Fade + subtle upward slide (standard entrance).
  static Widget fadeSlideUp(Widget child, Animation<double> anim) {
    final c = _curve(anim);
    return FadeTransition(
      opacity: anim.drive(c),
      child: SlideTransition(
        position: anim.drive(
          Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
              .chain(c),
        ),
        child: child,
      ),
    );
  }

  /// Fade + subtle downward slide.
  static Widget fadeSlideDown(Widget child, Animation<double> anim) {
    final c = _curve(anim);
    return FadeTransition(
      opacity: anim.drive(c),
      child: SlideTransition(
        position: anim.drive(
          Tween<Offset>(begin: const Offset(0, -0.06), end: Offset.zero)
              .chain(c),
        ),
        child: child,
      ),
    );
  }

  /// Fade + scale from 96% (dialogs, artwork reveals).
  static Widget fadeScale(Widget child, Animation<double> anim) {
    final c = _curve(anim);
    return FadeTransition(
      opacity: anim.drive(c),
      child: ScaleTransition(
        scale: anim.drive(Tween<double>(begin: 0.96, end: 1.0).chain(c)),
        child: child,
      ),
    );
  }

  /// Horizontal slide + fade.
  static Widget slideHorizontal(Widget child, Animation<double> anim) {
    final c = _curve(anim);
    return FadeTransition(
      opacity: anim.drive(c),
      child: SlideTransition(
        position: anim.drive(
          Tween<Offset>(begin: const Offset(0.10, 0), end: Offset.zero)
              .chain(c),
        ),
        child: child,
      ),
    );
  }

  /// NEW: emphasized scale for hero surfaces (now-playing open).
  static Widget heroReveal(Widget child, Animation<double> anim) {
    final c = CurveTween(curve: _enter);
    return FadeTransition(
      opacity: anim.drive(CurveTween(curve: const Interval(0.0, 0.6))),
      child: ScaleTransition(
        scale: anim.drive(Tween<double>(begin: 0.92, end: 1.0).chain(c)),
        child: child,
      ),
    );
  }
}
