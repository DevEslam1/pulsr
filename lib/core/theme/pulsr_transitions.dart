import 'package:flutter/material.dart';

/// {@category DesignSystem}
/// Standardized transition builders for page routes and surface reveals.
class PulsrTransitions {
  PulsrTransitions._();

  /// Fade in with a subtle upward slide (standard entrance).
  static Widget fadeSlideUp(Widget child, Animation<double> anim) {
    final curved = CurvedAnimation(
      parent: anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final offsetTween = Tween<Offset>(
      begin: const Offset(0.0, 0.08),
      end: Offset.zero,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: offsetTween.animate(curved),
        child: child,
      ),
    );
  }

  /// Fade in with a subtle downward slide.
  static Widget fadeSlideDown(Widget child, Animation<double> anim) {
    final curved = CurvedAnimation(
      parent: anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final offsetTween = Tween<Offset>(
      begin: const Offset(0.0, -0.08),
      end: Offset.zero,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: offsetTween.animate(curved),
        child: child,
      ),
    );
  }

  /// Fade in with a subtle scale-up from 96% to 100%.
  static Widget fadeScale(Widget child, Animation<double> anim) {
    final curved = CurvedAnimation(
      parent: anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final scaleTween = Tween<double>(begin: 0.96, end: 1.0);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: scaleTween.animate(curved),
        child: child,
      ),
    );
  }

  /// Horizontal slide transition with subtle fade.
  static Widget slideHorizontal(Widget child, Animation<double> anim) {
    final curved = CurvedAnimation(
      parent: anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final offsetTween = Tween<Offset>(
      begin: const Offset(0.12, 0.0),
      end: Offset.zero,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: offsetTween.animate(curved),
        child: child,
      ),
    );
  }
}
