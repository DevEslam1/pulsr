// lib/core/motion/pulsr_motion.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/settings/cubit/settings_cubit.dart';
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

  // ── Canonical Curves ────────────────────────────────────────────────────
  /// Elements appearing / entering the viewport.
  static const Curve enter = Curves.easeOutCubic;

  /// Elements disappearing / exiting the viewport.
  static const Curve exit = Curves.easeInCubic;

  /// Positional and geometry layout transitions.
  static const Curve move = Curves.easeInOutCubic;

  /// Playful spring bounce / button release.
  static const Curve spring = Curves.easeOutBack;

  /// Deceleration for scroll-linked or settling motion.
  static const Curve decelerate = Curves.easeOutQuart;

  // ── Canonical tokens (see [PulsrDurations]) ──────────────────────────────
  // There is exactly one duration scale. Legacy aliases (instant/fast/
  // standard/slow/expressive) were removed so a stray literal cannot bypass
  // Reduce Motion through a const that never collapses.
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

  /// Whether animations should play for [context].
  ///
  /// Combines the OS "Reduce motion" / "Remove animations" accessibility flag
  /// ([MediaQuery.disableAnimationsOf]) with the user's in-app
  /// `SettingsState.reduceMotion` preference. When [SettingsCubit] is not in
  /// the widget tree (such as isolated widget tests), safely falls back to
  /// `!MediaQuery.disableAnimationsOf(context)` without throwing.
  static bool shouldAnimate(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return false;
    return !_isInAppReduceMotionEnabled(context);
  }

  static bool _isInAppReduceMotionEnabled(BuildContext context) {
    try {
      return context.select<SettingsCubit, bool>((c) => c.state.reduceMotion);
    } on ProviderNotFoundException {
      return false;
    } catch (_) {
      // Called outside build (e.g. callback or listener): read without listening.
      try {
        return context.read<SettingsCubit>().state.reduceMotion;
      } catch (_) {
        return false;
      }
    }
  }

  /// Whether animations should play at all for the given context.
  ///
  /// Returns `false` when the OS reports Reduce Motion / Remove animations,
  /// when the user's in-app reduce-motion toggle is enabled, or when the user
  /// is navigating with an accessibility service.
  static bool isEnabled(BuildContext context) =>
      shouldAnimate(context) && !MediaQuery.accessibleNavigationOf(context);

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
  /// `true` when animations should play (see [PulsrMotion.shouldAnimate]).
  bool get shouldAnimate => PulsrMotion.shouldAnimate(this);

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
