// lib/core/utils/haptics.dart
import 'package:flutter/services.dart';

/// Centralized haptic feedback controller for the Pulsr application.
///
/// Provides consistent tactile response across platforms with sensible semantic
/// patterns:
/// - [tap]: quick light feedback for standard button / control presses.
/// - [select]: subtle click for slider detents, tab switches, and pickers.
/// - [medium]: affirmative interactions such as queue inserts or favorites.
/// - [heavy]: destructive actions, long-press triggers, or reordering starts.
/// - [success]: double-pulse confirmation pattern.
/// - [error]: alerting double-pulse pattern for invalid operations.
abstract class Haptics {
  /// Standard button/tile tap feedback.
  static Future<void> tap() => HapticFeedback.lightImpact();

  /// Picker / scrubber / tab selection detent.
  static Future<void> select() => HapticFeedback.selectionClick();

  /// Affirmative interaction feedback (e.g. favorite, add to queue).
  static Future<void> medium() => HapticFeedback.mediumImpact();

  /// Strong tactile impact (destructive deletes, reorder pick).
  static Future<void> heavy() => HapticFeedback.heavyImpact();

  /// Success completion pattern.
  static Future<void> success() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.lightImpact();
  }

  /// Error/warning pattern.
  static Future<void> error() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.mediumImpact();
  }
}
