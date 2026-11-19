// lib/features/usb_tools/usb_stream_mode.dart
//
// Per-DAC clock architecture selection for the direct USB path.
//
//   * bitPerfectPull — the decoder/reader fills a multi-second reservoir and
//     the USB worker pulls PCM at the DAC clock. Only usable with
//     `usb_pull_renderer`; the app must never label this bit-perfect when a
//     source/format precondition fails (see BIT_PERFECT_CLAIMS.md).
//   * clockSyncAsrc — polyphase ASRC follows the DAC feedback ratio. This is
//     explicitly a `resampled` mode and is never bit-perfect.
//   * bestEffort — today's real-time producer path with ±1% steering and
//     underrun/overrun counters.
//
// The selection is persisted per `vid:pid` so a DAC the user configured does not
// change behaviour when another device is attached.

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/feature_flags.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/utils/error_logger.dart';
import '../../data/services/usb_exclusive_service.dart';

/// Clock architecture requested for a direct-USB stream.
enum UsbStreamMode {
  /// Pull-based renderer; the only mode that may claim bit-perfect output.
  bitPerfectPull(
    wireName: 'bitPerfectPull',
    featureFlag: PrefsKeys.usbPullRenderer,
  ),

  /// Polyphase ASRC clock sync. Always reported as `resampled`.
  clockSyncAsrc(
    wireName: 'clockSyncAsrc',
    featureFlag: PrefsKeys.usbClockSyncAsrc,
  ),

  /// Real-time producer with feedback/steering. Never bit-perfect.
  bestEffort(
    wireName: 'bestEffort',
    featureFlag: null,
  );

  const UsbStreamMode({
    required this.wireName,
    required this.featureFlag,
  });

  /// Stable name persisted in preferences and echoed by native status.
  final String wireName;

  /// Value sent to Kotlin/native. Must match `UsbRenderMode` in C++.
  int get nativeCode => renderMode.nativeCode;

  /// Transport enum used by [UsbExclusiveService.startStreaming].
  UsbRenderMode get renderMode => switch (this) {
        UsbStreamMode.bitPerfectPull => UsbRenderMode.bitPerfectPull,
        UsbStreamMode.clockSyncAsrc => UsbRenderMode.clockSyncAsrc,
        UsbStreamMode.bestEffort => UsbRenderMode.bestEffort,
      };

  /// Flag that must be enabled for this mode, or null when always available.
  final String? featureFlag;

  /// Whether this mode may ever be presented as bit-perfect.
  bool get claimsBitPerfect => this == UsbStreamMode.bitPerfectPull;

  /// Whether this mode resamples by design.
  bool get isResampled => this == UsbStreamMode.clockSyncAsrc;

  /// Parses a stored/wire name; unknown values fall back to [bestEffort].
  static UsbStreamMode fromWireName(Object? value) {
    for (final mode in UsbStreamMode.values) {
      if (mode.wireName == value) return mode;
    }
    return UsbStreamMode.bestEffort;
  }
}

/// Why a requested mode was not used.
class UsbStreamModeResolution {
  const UsbStreamModeResolution({
    required this.requested,
    required this.effective,
    this.downgradeReason,
  });

  final UsbStreamMode requested;
  final UsbStreamMode effective;

  /// Null when the requested mode is usable; otherwise one of
  /// `flag_disabled`, `unknown_flag`, `feedback_required`.
  final String? downgradeReason;

  bool get wasDowngraded => effective != requested;
}

/// Pure policy that keeps unsupported modes from reaching the platform.
class UsbStreamModePolicy {
  const UsbStreamModePolicy._();

  /// Resolves [requested] against the rollout flags and device feedback
  /// capability.
  ///
  /// Bit-perfect pull is allowed without a feedback endpoint: bit-perfect is a
  /// statement about sample values, not about clock ownership. ASRC, on the
  /// other hand, exists only to follow a feedback ratio, so it is downgraded
  /// when the DAC reports no feedback endpoint.
  static UsbStreamModeResolution resolve({
    required UsbStreamMode requested,
    required bool Function(String flag) isFlagEnabled,
    required bool feedbackPresent,
  }) {
    if (requested == UsbStreamMode.bestEffort) {
      return UsbStreamModeResolution(
        requested: requested,
        effective: UsbStreamMode.bestEffort,
      );
    }
    final flag = requested.featureFlag;
    if (flag == null) {
      return UsbStreamModeResolution(
        requested: requested,
        effective: UsbStreamMode.bestEffort,
      );
    }
    if (!isFlagEnabled(flag)) {
      return UsbStreamModeResolution(
        requested: requested,
        effective: UsbStreamMode.bestEffort,
        downgradeReason: 'flag_disabled',
      );
    }
    if (requested == UsbStreamMode.clockSyncAsrc && !feedbackPresent) {
      return UsbStreamModeResolution(
        requested: requested,
        effective: UsbStreamMode.bestEffort,
        downgradeReason: 'feedback_required',
      );
    }
    return UsbStreamModeResolution(requested: requested, effective: requested);
  }
}

/// SharedPreferences-backed per-device mode selection.
class UsbStreamModeStore {
  /// Creates a store over [prefs]; tests pass a mock-backed instance.
  UsbStreamModeStore({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;

  /// The mode stored for `vid:pid`, defaulting to [UsbStreamMode.bestEffort].
  UsbStreamMode read(int vid, int pid) =>
      UsbStreamMode.fromWireName(_prefs.getString(_key(vid, pid)));

  /// Persists [mode] for `vid:pid`. Returns false when the write is rejected.
  Future<bool> write(int vid, int pid, UsbStreamMode mode) async {
    try {
      return await _prefs.setString(_key(vid, pid), mode.wireName);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to persist the USB stream mode for $vid:$pid',
        error: e,
        stackTrace: st,
        category: 'UsbStreamModeStore',
      );
      return false;
    }
  }

  /// Clears the stored mode so the device returns to best effort.
  Future<bool> clear(int vid, int pid) async {
    try {
      return await _prefs.remove(_key(vid, pid));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to clear the USB stream mode for $vid:$pid',
        error: e,
        stackTrace: st,
        category: 'UsbStreamModeStore',
      );
      return false;
    }
  }

  static String _key(int vid, int pid) => PrefsKeys.usbStreamModeKey(vid, pid);
}

/// Resolves the mode that should actually be sent to the platform for the
/// attached DAC, honouring the rollout flags and the feedback capability.
///
/// Returns [UsbRenderMode.bestEffort] when the device ids are unknown or the
/// preferences cannot be read: a missing preference must never opt a user into
/// an experimental clock path.
Future<UsbRenderMode> resolveEffectiveRenderMode({
  required int? vid,
  required int? pid,
  required bool feedbackPresent,
}) async {
  if (vid == null || pid == null) return UsbRenderMode.bestEffort;
  try {
    final prefs = await SharedPreferences.getInstance();
    final requested = UsbStreamModeStore(prefs: prefs).read(vid, pid);
    await FeatureFlags.instance.init();
    final resolved = UsbStreamModePolicy.resolve(
      requested: requested,
      isFlagEnabled: FeatureFlags.instance.isEnabled,
      feedbackPresent: feedbackPresent,
    );
    if (resolved.wasDowngraded) {
      ErrorLogger.addBreadcrumb(
        'USB stream mode ${requested.wireName} downgraded to '
        '${resolved.effective.wireName}: ${resolved.downgradeReason}',
        category: 'UsbStreamMode',
      );
    }
    return resolved.effective.renderMode;
  } catch (e, st) {
    ErrorLogger.log(
      'Failed to resolve the USB stream mode; using best effort',
      error: e,
      stackTrace: st,
      category: 'UsbStreamMode',
    );
    return UsbRenderMode.bestEffort;
  }
}
