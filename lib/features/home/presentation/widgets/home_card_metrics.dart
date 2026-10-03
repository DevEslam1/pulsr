import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive_values.dart';
import '../../../../core/utils/adaptive.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

/// Scales a fixed two-line card title box (34px at the default text size) with
/// the user's Dynamic Type setting so large text never clips. Pixel-identical
/// at the 1.0x scale.
double scaledTitleBoxHeight(BuildContext context) {
  final base = Adaptive.isTablet(context) ? AppSpacing.s38 : 34.0;
  return MediaQuery.textScalerOf(context).scale(base).clamp(base, 78.0);
}

/// Dynamically calculates the carousel height to comfortably fit card artwork,
/// dynamic text-scaled title box, artist line, and padding without overflowing.
double scaledCarouselHeight(BuildContext context, bool isTablet) {
  final cardWidth =
      context.responsive.value(compact: 138.0, medium: 150.0, expanded: 158.0);
  final titleHeight = scaledTitleBoxHeight(context);
  final textScale = MediaQuery.textScalerOf(context).scale(14.0);
  final artistHeight = textScale * 1.35;
  return cardWidth +
      AppSpacing.xs +
      titleHeight +
      AppSpacing.s2 +
      artistHeight +
      12.0;
}
