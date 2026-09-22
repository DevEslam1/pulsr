import 'package:flutter/services.dart';

/// Centralized haptic feedback patterns ensuring tactile consistency across Pulsr.
class HapticPatterns {
  const HapticPatterns._();

  /// Subtle light impact for standard button taps, item selections, and tabs.
  static void tap() => HapticFeedback.lightImpact();

  /// Medium impact for confirmations, toggles, and saving changes.
  static void confirm() => HapticFeedback.mediumImpact();

  /// Heavy impact for destructive actions (deletions, clears, resets).
  static void destructive() => HapticFeedback.heavyImpact();

  /// Selection click for scrubbers, sliders, and picker wheels.
  static void selection() => HapticFeedback.selectionClick();

  /// General alert vibration for errors or timeouts.
  static void vibrate() => HapticFeedback.vibrate();
}
