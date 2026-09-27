// lib/core/theme/focus_tokens.dart
import 'package:flutter/material.dart';

/// Focus ring styles conforming to WCAG 2.4.7 for desktop, web, and hardware keyboard navigation.
abstract class FocusTokens {
  /// 2dp outer focus border outline with accent color.
  static BorderSide ringSide(Color accentColor) => BorderSide(
        color: accentColor,
        width: 2.0,
      );

  /// Outer glow decoration for focused elements.
  static List<BoxShadow> focusRingShadow(Color accentColor) => [
        BoxShadow(
          color: accentColor.withValues(alpha: 0.40),
          blurRadius: 6,
          spreadRadius: 2,
        ),
      ];
}
