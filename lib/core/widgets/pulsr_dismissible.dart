// lib/core/widgets/pulsr_dismissible.dart
import 'package:flutter/material.dart';

/// Shared swipe-to-action configuration for song tiles.
///
/// The default Material [Dismissible] starts tracking horizontal drags
/// almost immediately, which makes accidental swipes common while the user
/// is scrolling vertically. These constants require a deliberate horizontal
/// pull (≥55 % of the tile width) before the action fires.
abstract class PulsrDismissible {
  static Map<DismissDirection, double> get thresholds => const {
        DismissDirection.startToEnd: 0.75,
        DismissDirection.endToStart: 0.75,
      };

  /// Only horizontal swipe gestures trigger the action.
  static const DismissDirection direction = DismissDirection.horizontal;

  /// Wraps a [Dismissible] with the safe configuration.
  static Widget wrap({
    required Key key,
    required Widget child,
    required Widget background,
    required Widget secondaryBackground,
    required Future<bool> Function(DismissDirection) confirm,
  }) {
    return Dismissible(
      key: key,
      direction: direction,
      dismissThresholds: thresholds,
      confirmDismiss: confirm,
      background: background,
      secondaryBackground: secondaryBackground,
      child: child,
    );
  }
}
