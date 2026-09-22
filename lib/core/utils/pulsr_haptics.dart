// lib/core/utils/pulsr_haptics.dart
import 'package:flutter/services.dart';

/// Centralized haptic feedback utilities across the application.
abstract final class PulsrHaptics {
  PulsrHaptics._();

  /// Subtle tap feedback for selections, tabs, and chip toggles.
  static void tap() => HapticFeedback.selectionClick();

  /// Light impact for minor interactions like regular button presses.
  static void light() => HapticFeedback.lightImpact();

  /// Medium impact for primary actions, confirms, and dialog approvals.
  static void confirm() => HapticFeedback.mediumImpact();

  /// Heavy impact for destructive operations (delete, remove, clear).
  static void destructive() => HapticFeedback.heavyImpact();

  /// Selection click feedback for carousels, sliders, and wheels.
  static void selection() => HapticFeedback.selectionClick();
}
