// lib/core/constants/app_blur.dart
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../performance/gpu_budget.dart';

/// {@category DesignSystem}
/// Canonical blur sigma tokens and GPU/accessibility gating for glass surfaces.
///
/// Every `BackdropFilter` or `ImageFilter.blur` in Pulsr must resolve its sigma
/// and eligibility through [AppBlur] so that:
/// 1. GPU Saver ([GpuBudget.isGpuSaverActive]) disables expensive blur passes.
/// 2. High Contrast — both the OS flag and Pulsr's own accessibility mode,
///    which `main.dart` mirrors into `MediaQuery.highContrast` — falls back to
///    solid, high-contrast surfaces for maximum legibility.
/// 3. Blur radius is strictly capped at [maxSigma] to bound per-frame raster cost.
abstract class AppBlur {
  AppBlur._();

  /// 0.0 — solid surface (no blur).
  static const double none = 0.0;

  /// 8.0 — subtle blur for compact floating chips and badges.
  static const double chip = 8.0;

  /// 12.0 — standard glass container blur.
  static const double standard = 12.0;

  /// 14.0 — floating bottom navigation pill blur.
  static const double nav = 14.0;

  /// 16.0 — modal dialog glass blur.
  static const double dialog = 16.0;

  /// 18.0 — hard ceiling on BackdropFilter sigma to prevent GPU frame spikes.
  static const double maxSigma = 18.0;

  /// 18.0 — bottom sheet preset. Declared at the ceiling (not above it) so the
  /// token a designer reads is the sigma the GPU actually rasterises.
  static const double sheet = maxSigma;

  /// 18.0 — floating dock preset, also at the ceiling for the same reason.
  static const double dock = maxSigma;

  /// Minimum surface alpha used when blur is disabled or High Contrast is active
  /// so text over arbitrary artwork maintains WCAG AA (>= 4.5:1) contrast.
  static const double solidFallbackMinAlpha = 0.94;

  /// Returns `true` when backdrop/image blur is allowed for the current frame.
  static bool canBlur(BuildContext context, {bool enableBlur = true}) {
    if (!enableBlur || GpuBudget.isGpuSaverActive) return false;
    final media = MediaQuery.maybeOf(context);
    if (media != null && media.highContrast) return false;
    return true;
  }

  /// Clamps a desired [sigma] to `[0.0, maxSigma]`.
  static double clampSigma(double sigma) {
    if (sigma <= 0.0) return 0.0;
    return math.min(sigma, maxSigma);
  }
}
