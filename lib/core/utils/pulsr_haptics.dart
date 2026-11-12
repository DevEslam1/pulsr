// lib/core/utils/pulsr_haptics.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Centralized haptic feedback utilities across the application.
///
/// Respects [enabled] so users or tests can silence tactile feedback globally.
abstract final class PulsrHaptics {
  PulsrHaptics._();

  /// Global master switch for haptic feedback (defaults to `true`).
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  /// Updates the global master switch for haptic feedback.
  static void setEnabled(bool value) {
    enabled.value = value;
  }

  /// Subtle tap feedback for selections, tabs, and chip toggles.
  static Future<void> tap() {
    if (!enabled.value) return Future<void>.value();
    return HapticFeedback.selectionClick();
  }

  /// Light impact for minor interactions like regular button presses.
  static Future<void> light() {
    if (!enabled.value) return Future<void>.value();
    return HapticFeedback.lightImpact();
  }

  /// Medium impact for primary actions, confirms, and dialog approvals.
  static Future<void> confirm() {
    if (!enabled.value) return Future<void>.value();
    return HapticFeedback.mediumImpact();
  }

  /// Heavy impact for destructive operations (delete, remove, clear).
  static Future<void> destructive() {
    if (!enabled.value) return Future<void>.value();
    return HapticFeedback.heavyImpact();
  }

  /// Selection click feedback for carousels, sliders, and wheels.
  static Future<void> selection() {
    if (!enabled.value) return Future<void>.value();
    return HapticFeedback.selectionClick();
  }

  /// Direct aliases to Flutter's HapticFeedback methods, routed through the enabled gate.
  static Future<void> selectionClick() => selection();
  static Future<void> lightImpact() => light();
  static Future<void> mediumImpact() => confirm();
  static Future<void> heavyImpact() => destructive();

  /// General alert vibration for errors or timeouts.
  static Future<void> vibrate() {
    if (!enabled.value) return Future<void>.value();
    return HapticFeedback.vibrate();
  }

  /// Double-pulse affirmative completion pattern.
  static Future<void> success() async {
    if (!enabled.value) return;
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!enabled.value) return;
    await HapticFeedback.lightImpact();
  }

  /// Double-pulse alerting pattern for invalid operations.
  static Future<void> error() async {
    if (!enabled.value) return;
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!enabled.value) return;
    await HapticFeedback.mediumImpact();
  }
}
