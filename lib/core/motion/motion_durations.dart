// lib/core/motion/motion_durations.dart

/// Canonical numeric duration spec for Pulsr.
///
/// This is the single source of truth for *how long* motion lasts. Every
/// animated widget should resolve its duration through one of these named
/// tokens (never a raw millisecond literal) so the entire app shares one
/// motion rhythm:
///
/// | token | ms | used for |
/// |---|---|---|
/// | [tap] | 120 | press/selection feedback, ink, toggles |
/// | [state] | 200 | small state changes, fades, chips |
/// | [layout] | 260 | reflows, dock/positioned moves, expanders |
/// | [page] | 320 | route transitions, sheets, large surfaces |
/// | [ambient] | 400 | hero/artwork, ambient decorative loops |
///
/// Durations are *desired* values; they must always be resolved through
/// `context.motion(...)` / `PulsrMotion.resolve(...)` so Reduce Motion can
/// collapse them to [Duration.zero].
abstract class PulsrDurations {
  PulsrDurations._();

  /// 120ms — direct manipulation feedback (tap, press, selection).
  static const Duration tap = Duration(milliseconds: 120);

  /// 200ms — small state changes (fades, chips, status swaps).
  static const Duration state = Duration(milliseconds: 200);

  /// 260ms — layout changes (reflows, positioned moves, size changes).
  static const Duration layout = Duration(milliseconds: 260);

  /// 320ms — page/surface transitions (routes, sheets, dock mode changes).
  static const Duration page = Duration(milliseconds: 320);

  /// 400ms — ambient/expressive motion (hero artwork, decorative loops).
  static const Duration ambient = Duration(milliseconds: 400);
}
