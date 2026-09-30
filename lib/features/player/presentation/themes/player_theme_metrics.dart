// lib/features/player/presentation/themes/player_theme_metrics.dart
import 'package:flutter/widgets.dart';

/// Shared layout metrics for the responsive player themes.
///
/// The audit found that all themes independently re-derived the same spacing,
/// pill-bar and control sizes from `(constraints.maxHeight / 720).clamp(...)`,
/// drifting subtly (classic used a different vertical rhythm; vinyl/cassette
/// intentionally diverge because they render a physical object). This class is
/// the single source of truth for the **canonical** rhythm.
///
/// Intentional per-theme divergences that are NOT captured here:
/// * **classic** — uses a roomier 14/10/8 dp vertical rhythm.
/// * **vinyl / cassette** — skeuomorphic artwork sizing and 500/410 pane width.
///
/// Spec table (canonical values, value at `heightRatio == 1.0`):
///
/// | metric | phone | tablet |
/// |---|---|---|
/// | spacingTrackToSeek | 6 | 10 |
/// | spacingSeekToControls | 8 | 12 |
/// | spacingControlsToDock | 8 | 12 |
/// | spacingBelowDock | 4 | 8 |
/// | switcherTopPad | 2 | 4 |
/// | switcherBottomPad | 3 | 6 |
/// | pillBarHeight (clamped 0.85–1.15) | 44 | 50 |
/// | mainButtonSize (clamped 0.85–1.10) | 64 (56 landscape) | 72 |
/// | paneMaxWidth | 380 | 440 |
class PlayerThemeMetrics {
  final bool isTablet;
  final bool isLandscape;

  /// `(maxHeight / 720).clamp(0.55, 1.25)` — the shared responsive scale.
  final double heightRatio;

  const PlayerThemeMetrics._({
    required this.isTablet,
    required this.isLandscape,
    required this.heightRatio,
  });

  factory PlayerThemeMetrics.of({
    required bool isTablet,
    required bool isLandscape,
    required BoxConstraints constraints,
  }) {
    return PlayerThemeMetrics._(
      isTablet: isTablet,
      isLandscape: isLandscape,
      heightRatio: (constraints.maxHeight / 720.0).clamp(0.55, 1.25),
    );
  }

  double get spacingTrackToSeek => (isTablet ? 10.0 : 6.0) * heightRatio;
  double get spacingSeekToControls => (isTablet ? 12.0 : 8.0) * heightRatio;
  double get spacingControlsToDock => (isTablet ? 12.0 : 8.0) * heightRatio;
  double get spacingBelowDock => (isTablet ? 8.0 : 4.0) * heightRatio;
  double get switcherTopPad => (isTablet ? 4.0 : 2.0) * heightRatio;
  double get switcherBottomPad => (isTablet ? 6.0 : 3.0) * heightRatio;
  double get pillBarHeight =>
      (isTablet ? 50.0 : 44.0) * heightRatio.clamp(0.85, 1.15);
  double get mainButtonSize =>
      (isTablet ? 72.0 : (isLandscape ? 56.0 : 64.0)) *
      heightRatio.clamp(0.85, 1.10);
  double get paneMaxWidth => isTablet ? 440.0 : 380.0;
}
