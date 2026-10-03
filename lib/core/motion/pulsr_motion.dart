// lib/core/motion/pulsr_motion.dart
import 'package:flutter/material.dart';

import 'motion_durations.dart';

/// {@category DesignSystem}
export 'motion_durations.dart';

/// Centralized motion tokens.
///
/// Every animation in the app should resolve its duration through
/// [PulsrMotion.of] / [PulsrMotionX.motion] so that the platform "reduce
/// motion" accessibility switch is honoured globally:
///
/// * Android — Settings ▸ Accessibility ▸ Remove animations
/// * iOS — Settings ▸ Accessibility ▸ Motion ▸ Reduce Motion
///
/// When motion is reduced we collapse durations to [Duration.zero] and swap
/// easing for [Curves.linear], which makes implicitly animated widgets snap to
/// their end state instead of tweening. Infinite/repeating decorations should
/// be skipped entirely by checking [PulsrMotionX.motionEnabled].
abstract class PulsrMotion {
  PulsrMotion._();

  /// 90ms — icon tint / selection feedback.
  static const Duration instant = Duration(milliseconds: 90);

  /// 150ms — press states, small fades.
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration snappy = fast;

  /// 250ms — standard transitions (nav indicator, switches).
  static const Duration standard = Duration(milliseconds: 250);

  /// 400ms — larger surface changes (sheet, hero, artwork).
  static const Duration slow = Duration(milliseconds: 400);

  /// 600ms — expressive entrance choreography.
  static const Duration expressive = Duration(milliseconds: 600);

  // ── Canonical semantic tokens (see [PulsrDurations]) ─────────────────────
  // Prefer these five in new code; they map the whole app onto one rhythm.
  /// 120ms — direct-manipulation feedback (tap, press, selection).
  static const Duration tap = PulsrDurations.tap;

  /// 200ms — small state changes (fades, chips, status swaps).
  static const Duration state = PulsrDurations.state;

  /// 260ms — layout changes (reflows, positioned moves, size changes).
  static const Duration layout = PulsrDurations.layout;

  /// 320ms — page/surface transitions (routes, sheets, dock mode changes).
  static const Duration page = PulsrDurations.page;

  /// 400ms — ambient/expressive motion (hero artwork, decorative loops).
  static const Duration ambient = PulsrDurations.ambient;

  /// Whether animations should play at all for the given context.
  ///
  /// Returns `false` when the OS reports Reduce Motion / Remove animations, or
  /// when the user is navigating with an accessibility service.
  static bool isEnabled(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context) &&
      !MediaQuery.accessibleNavigationOf(context);

  /// Clamps a desired [duration] to zero when motion is disabled.
  static Duration resolve(BuildContext context, Duration duration) =>
      isEnabled(context) ? duration : Duration.zero;

  /// Resolves an easing curve, flattening it when motion is disabled.
  static Curve resolveCurve(BuildContext context, Curve curve) =>
      isEnabled(context) ? curve : Curves.linear;

  /// Scales a duration instead of collapsing it (useful for long, non-essential
  /// loops that should merely run faster under reduced motion).
  static Duration scale(BuildContext context, Duration duration,
          {double factor = 0.0}) =>
      isEnabled(context) ? duration : duration * factor;
}

extension PulsrMotionX on BuildContext {
  /// `true` when animations may play (see [PulsrMotion.isEnabled]).
  bool get motionEnabled => PulsrMotion.isEnabled(this);

  /// Reduce-motion-aware duration for ad-hoc call sites.
  Duration motion(Duration duration) => PulsrMotion.resolve(this, duration);

  /// Convenience wrapper for millisecond literals.
  Duration motionMs(int milliseconds) =>
      PulsrMotion.resolve(this, Duration(milliseconds: milliseconds));

  /// Reduce-motion-aware easing curve.
  Curve motionCurve(Curve curve) => PulsrMotion.resolveCurve(this, curve);
}

/// Convenience alias for [PulsrMotion].
typedef AppMotion = PulsrMotion;
