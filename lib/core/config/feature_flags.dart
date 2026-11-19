// lib/core/config/feature_flags.dart
//
// Staged rollout for the USB Audio Class production-readiness program.
//
// Two engineering flags gate the new clock-domain work:
//   * `usb_pull_renderer`     — pull-based direct-USB renderer
//   * `usb_clock_sync_asrc`   — polyphase ASRC clock-sync fallback
//
// Both are OFF by default and are never enabled by a settings screen. A build
// can be rolled out in 5% / 25% / 100% cohorts; the cohort is derived from a
// stable per-install id and a deterministic hash, so the same device always
// lands in the same bucket for a given flag. A kill switch is simply the
// `off` stage: it disables both flags regardless of any manual override.
//
// The class is deliberately small and dependency-free (no codegen) so it can be
// unit-tested without the Flutter binding.

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/prefs_keys.dart';
import '../utils/error_logger.dart';

/// Rollout cohort for the USB engineering flags.
enum UsbRolloutStage {
  off(0),
  fivePercent(5),
  twentyFivePercent(25),
  hundredPercent(100);

  const UsbRolloutStage(this.percent);

  /// Percentage of installs that receive the flag in this stage.
  final int percent;

  /// Maps a stored percentage back to a stage. Unknown values are treated as
  /// [off] — a corrupt preference must never widen a rollout.
  static UsbRolloutStage fromPercent(int? value) {
    switch (value) {
      case 5:
        return UsbRolloutStage.fivePercent;
      case 25:
        return UsbRolloutStage.twentyFivePercent;
      case 100:
        return UsbRolloutStage.hundredPercent;
      default:
        return UsbRolloutStage.off;
    }
  }
}

/// Reads feature-flag state from [SharedPreferences].
class FeatureFlags {
  /// Creates a reader over [prefs]. Production uses [instance]; tests inject a
  /// mock-backed instance through `SharedPreferences.setMockInitialValues`.
  FeatureFlags({SharedPreferences? prefs}) : _prefs = prefs;

  /// Process-wide reader used by the USB UI/services.
  static final FeatureFlags instance = FeatureFlags();

  /// The engineering flags this class understands. An unknown flag is always
  /// disabled, so a typo can never silently enable work.
  static const Set<String> knownFlags = <String>{
    PrefsKeys.usbPullRenderer,
    PrefsKeys.usbClockSyncAsrc,
  };

  SharedPreferences? _prefs;

  /// Loads (or reloads) the backing preferences.
  Future<void> init() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _ensureInstallId();
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to initialize feature flags',
        error: e,
        stackTrace: st,
        category: 'FeatureFlags',
      );
    }
  }

  /// Whether [flag] is enabled for this install right now.
  ///
  /// Rules, in order:
  /// 1. an unknown flag is off;
  /// 2. the rollout stage is [UsbRolloutStage.off] (kill switch) => off;
  /// 3. an explicit manual override wins (used by internal/debug builds);
  /// 4. otherwise the install's deterministic bucket must be below the stage.
  bool isEnabled(String flag) {
    if (!knownFlags.contains(flag)) return false;
    final prefs = _prefs;
    if (prefs == null) return false;
    final stage = UsbRolloutStage.fromPercent(
      prefs.getInt(PrefsKeys.usbRolloutPercent),
    );
    if (stage == UsbRolloutStage.off) return false;
    final override = prefs.getBool(_overrideKey(flag));
    if (override != null) return override;
    if (stage == UsbRolloutStage.hundredPercent) return true;
    final installId = prefs.getString(PrefsKeys.usbRolloutInstallId);
    if (installId == null || installId.isEmpty) return false;
    return _bucket(flag, installId) < stage.percent;
  }

  /// Sets or clears (`null`) the manual override for [flag].
  ///
  /// Returns false for an unknown flag or a rejected write.
  Future<bool> setOverride(String flag, bool? enabled) async {
    if (!knownFlags.contains(flag)) return false;
    final prefs = await _requirePrefs();
    if (prefs == null) return false;
    try {
      final ok = enabled == null
          ? await prefs.remove(_overrideKey(flag))
          : await prefs.setBool(_overrideKey(flag), enabled);
      return ok;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set feature-flag override for $flag',
        error: e,
        stackTrace: st,
        category: 'FeatureFlags',
      );
      return false;
    }
  }

  /// The manual override for [flag], or null when the rollout bucket decides.
  bool? overrideFor(String flag) {
    if (!knownFlags.contains(flag)) return null;
    return _prefs?.getBool(_overrideKey(flag));
  }

  /// Current rollout stage (kill switch = [UsbRolloutStage.off]).
  UsbRolloutStage get rolloutStage =>
      UsbRolloutStage.fromPercent(_prefs?.getInt(PrefsKeys.usbRolloutPercent));

  /// Advances or rolls back the rollout stage. Returns false when the write is
  /// rejected. The caller is responsible for the 5 -> 25 -> 100 progression;
  /// this setter only persists the value so an operator can also kill-switch.
  Future<bool> setRolloutStage(UsbRolloutStage stage) async {
    final prefs = await _requirePrefs();
    if (prefs == null) return false;
    try {
      return await prefs.setInt(PrefsKeys.usbRolloutPercent, stage.percent);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to persist the USB rollout stage',
        error: e,
        stackTrace: st,
        category: 'FeatureFlags',
      );
      return false;
    }
  }

  /// True when at least one USB read flag is enabled. Diagnostics uses this to
  /// label the build without exposing individual flag values in UI copy.
  bool get anyUsbRendererFlagEnabled =>
      isEnabled(PrefsKeys.usbPullRenderer) ||
      isEnabled(PrefsKeys.usbClockSyncAsrc);

  Future<SharedPreferences?> _requirePrefs() async {
    if (_prefs == null) await init();
    return _prefs;
  }

  Future<void> _ensureInstallId() async {
    final prefs = _prefs;
    if (prefs == null) return;
    if ((prefs.getString(PrefsKeys.usbRolloutInstallId) ?? '').isNotEmpty) {
      return;
    }
    final id = _randomId();
    try {
      await prefs.setString(PrefsKeys.usbRolloutInstallId, id);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to persist the feature-flag install id',
        error: e,
        stackTrace: st,
        category: 'FeatureFlags',
      );
    }
  }

  static String _randomId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _overrideKey(String flag) => '${flag}_override';

  /// FNV-1a over `flag|installId`, folded into 0..99. Stable across launches
  /// and independent per flag, so enabling one does not correlate the other.
  static int _bucket(String flag, String installId) {
    var hash = 0x811C9DC5;
    for (final unit in '$flag|$installId'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash % 100;
  }
}
