// lib/features/usb_tools/usb_quirk_profile.dart
//
// Value type for one USB DAC quirk profile.
//
// Two groups of knobs live here:
//   * ergonomics — claim the device's HID consumer-control interfaces and map
//     its media buttons;
//   * audio transport — the knobs a problem DAC forces on the direct USB path
//     (pre-open silence, forced 16-bit, alt-setting reset, transfer sizing,
//     explicit-feedback suppression, UAC2 selector pin, UAC1 re-assert, clock
//     switch suppression).
//
// Every audio knob has a real consumer: the profile is pushed to
// `UsbExclusivePlugin.setQuirkProfile`, validated again by
// `UsbQuirkResolver.kt`, and applied by the exclusive start path. A knob that
// would change bit-perfect semantics (`force16Bit`, `disableUac2ClockSwitch`)
// is surfaced as `bitPerfectAffected` instead of being applied silently.
//
// The type is immutable and validates in the factory, so an out-of-range value
// can never reach the native side. `fromJson` is strict about the transport
// shape (a stored profile that no longer parses is reported, never guessed) and
// tolerant of unknown keys so a newer build can write a superset.

import '../../core/errors/app_error.dart';

/// A quirk profile field that failed validation.
///
/// Extends [AppError] so the UI can surface [userMessage] verbatim and crash
/// reports carry a stable [code]. [field] names the offending profile field
/// (`vid`, `pid`, ...) for diagnostics.
class QuirkValidationError extends AppError {
  const QuirkValidationError({
    required super.code,
    required super.userMessage,
    this.field,
    super.cause,
    super.stackTrace,
  });

  /// Profile field the error belongs to, when it is about a single field.
  final String? field;

  @override
  String toString() =>
      'QuirkValidationError($code, field: $field): $userMessage';
}

/// One per-device (or default) set of USB ergonomics and transport knobs.
///
/// Every field is validated on construction:
/// * [vid] / [pid] must be USB 16-bit ids.
/// * [label] must be non-empty and at most [maxLabelLength] characters.
/// * numeric transport knobs must be inside the ranges documented on each
///   field; 0 means "automatic" for [transferSizeBytes] and [bufferMs].
class UsbQuirkProfile {
  /// Builds a validated profile.
  ///
  /// Throws [QuirkValidationError] when a field is out of range, so callers
  /// never have to re-check a profile they already hold.
  factory UsbQuirkProfile({
    required int vid,
    required int pid,
    required String label,
    bool hidEnabled = false,
    int silenceMs = 0,
    bool force16Bit = false,
    bool altResetOnStop = false,
    int transferSizeBytes = 0,
    int bufferMs = 0,
    bool disableExplicitFeedback = false,
    int? preferredSelectorPin,
    double volumeCalibrationDb = 0.0,
    bool uac1ReassertAfterAlt = false,
    bool disableUac2ClockSwitch = false,
  }) {
    final error = _fieldError(
      vid: vid,
      pid: pid,
      label: label,
      silenceMs: silenceMs,
      transferSizeBytes: transferSizeBytes,
      bufferMs: bufferMs,
      preferredSelectorPin: preferredSelectorPin,
      volumeCalibrationDb: volumeCalibrationDb,
    );
    if (error != null) throw error;
    return UsbQuirkProfile._(
      vid: vid,
      pid: pid,
      label: label.trim(),
      hidEnabled: hidEnabled,
      silenceMs: silenceMs,
      force16Bit: force16Bit,
      altResetOnStop: altResetOnStop,
      transferSizeBytes: transferSizeBytes,
      bufferMs: bufferMs,
      disableExplicitFeedback: disableExplicitFeedback,
      preferredSelectorPin: preferredSelectorPin,
      volumeCalibrationDb: volumeCalibrationDb,
      uac1ReassertAfterAlt: uac1ReassertAfterAlt,
      disableUac2ClockSwitch: disableUac2ClockSwitch,
    );
  }

  const UsbQuirkProfile._({
    required this.vid,
    required this.pid,
    required this.label,
    required this.hidEnabled,
    required this.silenceMs,
    required this.force16Bit,
    required this.altResetOnStop,
    required this.transferSizeBytes,
    required this.bufferMs,
    required this.disableExplicitFeedback,
    required this.preferredSelectorPin,
    required this.volumeCalibrationDb,
    required this.uac1ReassertAfterAlt,
    required this.disableUac2ClockSwitch,
  });

  /// Highest USB vendor/product id (16-bit field).
  static const int maxUsbId = 0xFFFF;

  /// Longest accepted [label].
  static const int maxLabelLength = 64;

  /// Highest accepted pre-open silence.
  static const int maxSilenceMs = 2000;

  /// Highest accepted reservoir target.
  static const int maxBufferMs = 10000;

  /// Highest accepted isochronous transfer size.
  static const int maxTransferSizeBytes = 65536;

  /// USB vendor id.
  final int vid;

  /// USB product id.
  final int pid;

  /// Human label shown in the editor and in diagnostics.
  final String label;

  /// Claim the device's HID consumer-control interfaces and map media keys.
  final bool hidEnabled;

  /// Delay between selecting the alt setting and submitting the first URB.
  final int silenceMs;

  /// Force a 16-bit wire format. Visible because it changes bit-perfect
  /// semantics (a 24-bit source is truncated).
  final bool force16Bit;

  /// Issue SET_INTERFACE(alt 0) before releasing the claim on stop.
  final bool altResetOnStop;

  /// Isochronous transfer size in bytes; 0 selects the automatic sizing.
  final int transferSizeBytes;

  /// Pull-renderer reservoir target in ms; 0 selects the automatic size.
  final int bufferMs;

  /// Ignore an advertised asynchronous feedback endpoint.
  final bool disableExplicitFeedback;

  /// Preferred UAC2 clock-selector pin, or null for the device default.
  final int? preferredSelectorPin;

  /// Extra attenuation applied to the hardware-volume scale.
  final double volumeCalibrationDb;

  /// Re-assert the UAC1 sample rate after selecting the alt setting.
  final bool uac1ReassertAfterAlt;

  /// Do not program the UAC2 clock source/selector (device keeps its own).
  final bool disableUac2ClockSwitch;

  /// A profile with every knob at its neutral value.
  ///
  /// Used as the fallback when neither a per-device entry nor the global
  /// defaults exist, and as the seed for a brand-new device editor. The ids are
  /// zero and are always replaced by the real device ids before being applied.
  static const UsbQuirkProfile defaults = UsbQuirkProfile._(
    vid: 0,
    pid: 0,
    label: 'Default',
    hidEnabled: false,
    silenceMs: 0,
    force16Bit: false,
    altResetOnStop: false,
    transferSizeBytes: 0,
    bufferMs: 0,
    disableExplicitFeedback: false,
    preferredSelectorPin: null,
    volumeCalibrationDb: 0.0,
    uac1ReassertAfterAlt: false,
    disableUac2ClockSwitch: false,
  );

  /// Storage key of this device: `vid:pid`, lowercase, zero-padded to 4 hex
  /// digits each (`0a12:0001`).
  String get key => deviceKey(vid, pid);

  /// Whether this profile carries a real device identity (nonzero ids).
  bool get isDeviceSpecific => vid > 0 && pid > 0;

  /// Whether every knob is at its neutral value.
  bool get isNeutral =>
      !hidEnabled &&
      silenceMs == 0 &&
      !force16Bit &&
      !altResetOnStop &&
      transferSizeBytes == 0 &&
      bufferMs == 0 &&
      !disableExplicitFeedback &&
      preferredSelectorPin == null &&
      volumeCalibrationDb == 0.0 &&
      !uac1ReassertAfterAlt &&
      !disableUac2ClockSwitch;

  /// Whether this profile changes bit-perfect semantics if applied.
  ///
  /// Forced 16-bit truncates a wider source; suppressing the UAC2 clock switch
  /// leaves the DAC on a clock the app cannot verify. Both must be visible.
  bool get affectsBitPerfect => force16Bit || disableUac2ClockSwitch;

  /// Lowercase `vid:pid` storage key, zero-padded to four hex digits each.
  static String deviceKey(int vid, int pid) => '${_hex4(vid)}:${_hex4(pid)}';

  /// Copy with selected fields replaced; re-validates through the factory.
  UsbQuirkProfile copyWith({
    int? vid,
    int? pid,
    String? label,
    bool? hidEnabled,
    int? silenceMs,
    bool? force16Bit,
    bool? altResetOnStop,
    int? transferSizeBytes,
    int? bufferMs,
    bool? disableExplicitFeedback,
    Object? preferredSelectorPin = _unset,
    double? volumeCalibrationDb,
    bool? uac1ReassertAfterAlt,
    bool? disableUac2ClockSwitch,
  }) {
    return UsbQuirkProfile(
      vid: vid ?? this.vid,
      pid: pid ?? this.pid,
      label: label ?? this.label,
      hidEnabled: hidEnabled ?? this.hidEnabled,
      silenceMs: silenceMs ?? this.silenceMs,
      force16Bit: force16Bit ?? this.force16Bit,
      altResetOnStop: altResetOnStop ?? this.altResetOnStop,
      transferSizeBytes: transferSizeBytes ?? this.transferSizeBytes,
      bufferMs: bufferMs ?? this.bufferMs,
      disableExplicitFeedback:
          disableExplicitFeedback ?? this.disableExplicitFeedback,
      preferredSelectorPin: identical(preferredSelectorPin, _unset)
          ? this.preferredSelectorPin
          : preferredSelectorPin as int?,
      volumeCalibrationDb:
          volumeCalibrationDb ?? this.volumeCalibrationDb,
      uac1ReassertAfterAlt:
          uac1ReassertAfterAlt ?? this.uac1ReassertAfterAlt,
      disableUac2ClockSwitch:
          disableUac2ClockSwitch ?? this.disableUac2ClockSwitch,
    );
  }

  /// Serializable form stored in preferences and shown in the JSON preview.
  ///
  /// Neutral audio knobs are omitted so an HID-only profile keeps the compact
  /// shape older builds understand; a non-neutral one is a full superset that
  /// older builds ignore key by key.
  Map<String, Object?> toJson() => <String, Object?>{
        'vid': vid,
        'pid': pid,
        'label': label,
        'hidEnabled': hidEnabled,
        if (silenceMs != 0) 'silenceMs': silenceMs,
        if (force16Bit) 'force16Bit': true,
        if (altResetOnStop) 'altResetOnStop': true,
        if (transferSizeBytes != 0) 'transferSizeBytes': transferSizeBytes,
        if (bufferMs != 0) 'bufferMs': bufferMs,
        if (disableExplicitFeedback) 'disableExplicitFeedback': true,
        if (preferredSelectorPin != null)
          'preferredSelectorPin': preferredSelectorPin,
        if (volumeCalibrationDb != 0.0)
          'volumeCalibrationDb': volumeCalibrationDb,
        if (uac1ReassertAfterAlt) 'uac1ReassertAfterAlt': true,
        if (disableUac2ClockSwitch) 'disableUac2ClockSwitch': true,
      };

  /// Reads a profile from an already-decoded JSON object.
  ///
  /// Unknown keys are ignored. A missing or wrong-typed `vid`/`pid` throws
  /// [QuirkValidationError]; a missing `label` falls back to the default.
  factory UsbQuirkProfile.fromJson(Map<String, Object?> json) {
    final vid = _readInt(json, 'vid');
    if (vid == null) {
      throw const QuirkValidationError(
        code: 'usb-quirk-vid-missing',
        userMessage: 'The profile has no USB vendor id.',
        field: 'vid',
      );
    }
    final pid = _readInt(json, 'pid');
    if (pid == null) {
      throw const QuirkValidationError(
        code: 'usb-quirk-pid-missing',
        userMessage: 'The profile has no USB product id.',
        field: 'pid',
      );
    }
    final label = _readString(json, 'label') ?? defaults.label;
    return UsbQuirkProfile(
      vid: vid,
      pid: pid,
      label: label,
      hidEnabled: _readBool(json, 'hidEnabled') ?? false,
      silenceMs: _readInt(json, 'silenceMs') ?? 0,
      force16Bit: _readBool(json, 'force16Bit') ?? false,
      altResetOnStop: _readBool(json, 'altResetOnStop') ?? false,
      transferSizeBytes: _readInt(json, 'transferSizeBytes') ?? 0,
      bufferMs: _readInt(json, 'bufferMs') ?? 0,
      disableExplicitFeedback:
          _readBool(json, 'disableExplicitFeedback') ?? false,
      preferredSelectorPin: _readInt(json, 'preferredSelectorPin'),
      volumeCalibrationDb:
          _readDouble(json, 'volumeCalibrationDb') ?? 0.0,
      uac1ReassertAfterAlt: _readBool(json, 'uac1ReassertAfterAlt') ?? false,
      disableUac2ClockSwitch:
          _readBool(json, 'disableUac2ClockSwitch') ?? false,
    );
  }

  /// Tolerant [fromJson]: returns null instead of throwing.
  ///
  /// Used when reading the store, where one unreadable entry must not hide the
  /// rest. Non-map input is rejected as well.
  static UsbQuirkProfile? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final map = <String, Object?>{};
    for (final entry in json.entries) {
      final key = entry.key;
      if (key is String) map[key] = entry.value;
    }
    try {
      return UsbQuirkProfile.fromJson(map);
    } on QuirkValidationError {
      return null;
    }
  }

  /// One-line summary for the diagnostics sheet and for logs.
  ///
  /// Neutral profiles collapse to `defaults` so the line stays short:
  /// `1d6b:0104 "Melo DAC": defaults`.
  String describe() {
    final parts = <String>[
      if (hidEnabled) 'HID consumer keys',
      if (force16Bit) '16-bit forced',
      if (altResetOnStop) 'alt reset on stop',
      if (silenceMs != 0) '${silenceMs}ms silence',
      if (transferSizeBytes != 0) '${transferSizeBytes}B transfers',
      if (bufferMs != 0) '${bufferMs}ms buffer',
      if (disableExplicitFeedback) 'feedback ignored',
      if (preferredSelectorPin != null) 'selector pin $preferredSelectorPin',
      if (volumeCalibrationDb != 0.0)
        '${volumeCalibrationDb.toStringAsFixed(1)}dB cal',
      if (uac1ReassertAfterAlt) 'UAC1 rate re-assert',
      if (disableUac2ClockSwitch) 'UAC2 clock switch disabled',
    ];
    if (parts.isEmpty) return '$key "$label": defaults';
    return '$key "$label": ${parts.join(", ")}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsbQuirkProfile &&
          other.vid == vid &&
          other.pid == pid &&
          other.label == label &&
          other.hidEnabled == hidEnabled &&
          other.silenceMs == silenceMs &&
          other.force16Bit == force16Bit &&
          other.altResetOnStop == altResetOnStop &&
          other.transferSizeBytes == transferSizeBytes &&
          other.bufferMs == bufferMs &&
          other.disableExplicitFeedback == disableExplicitFeedback &&
          other.preferredSelectorPin == preferredSelectorPin &&
          other.volumeCalibrationDb == volumeCalibrationDb &&
          other.uac1ReassertAfterAlt == uac1ReassertAfterAlt &&
          other.disableUac2ClockSwitch == disableUac2ClockSwitch;

  @override
  int get hashCode => Object.hash(
        vid,
        pid,
        label,
        hidEnabled,
        silenceMs,
        force16Bit,
        altResetOnStop,
        transferSizeBytes,
        bufferMs,
        disableExplicitFeedback,
        preferredSelectorPin,
        volumeCalibrationDb,
        uac1ReassertAfterAlt,
        disableUac2ClockSwitch,
      );

  @override
  String toString() => 'UsbQuirkProfile(${describe()})';

  static const Object _unset = Object();

  static String _hex4(int value) =>
      value.toRadixString(16).padLeft(4, '0').toLowerCase();

  static QuirkValidationError? _fieldError({
    required int vid,
    required int pid,
    required String label,
    required int silenceMs,
    required int transferSizeBytes,
    required int bufferMs,
    required int? preferredSelectorPin,
    required double volumeCalibrationDb,
  }) {
    if (vid < 0 || vid > maxUsbId) {
      return const QuirkValidationError(
        code: 'usb-quirk-vid-range',
        userMessage: 'Vendor id must be a USB 16-bit id (0-65535).',
        field: 'vid',
      );
    }
    if (pid < 0 || pid > maxUsbId) {
      return const QuirkValidationError(
        code: 'usb-quirk-pid-range',
        userMessage: 'Product id must be a USB 16-bit id (0-65535).',
        field: 'pid',
      );
    }
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return const QuirkValidationError(
        code: 'usb-quirk-label-empty',
        userMessage: 'Give this device a name.',
        field: 'label',
      );
    }
    if (trimmed.length > maxLabelLength) {
      return const QuirkValidationError(
        code: 'usb-quirk-label-too-long',
        userMessage: 'Name must be at most 64 characters.',
        field: 'label',
      );
    }
    if (silenceMs < 0 || silenceMs > maxSilenceMs) {
      return const QuirkValidationError(
        code: 'usb-quirk-silence-range',
        userMessage: 'Pre-open silence must be between 0 and 2000 ms.',
        field: 'silenceMs',
      );
    }
    if (transferSizeBytes != 0 &&
        (transferSizeBytes < 64 || transferSizeBytes > maxTransferSizeBytes)) {
      return const QuirkValidationError(
        code: 'usb-quirk-transfer-range',
        userMessage: 'Transfer size must be 0 (auto) or 64-65536 bytes.',
        field: 'transferSizeBytes',
      );
    }
    if (bufferMs < 0 || bufferMs > maxBufferMs) {
      return const QuirkValidationError(
        code: 'usb-quirk-buffer-range',
        userMessage: 'Reservoir target must be between 0 and 10000 ms.',
        field: 'bufferMs',
      );
    }
    if (preferredSelectorPin != null &&
        (preferredSelectorPin < 0 || preferredSelectorPin > 255)) {
      return const QuirkValidationError(
        code: 'usb-quirk-pin-range',
        userMessage: 'Clock selector pin must be between 0 and 255.',
        field: 'preferredSelectorPin',
      );
    }
    if (volumeCalibrationDb < -24.0 || volumeCalibrationDb > 24.0) {
      return const QuirkValidationError(
        code: 'usb-quirk-calibration-range',
        userMessage: 'Volume calibration must be between -24 and +24 dB.',
        field: 'volumeCalibrationDb',
      );
    }
    return null;
  }

  static int? _readInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw QuirkValidationError(
      code: 'usb-quirk-field-type',
      userMessage: 'The profile field "$key" must be a number.',
      field: key,
    );
  }

  static double? _readDouble(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    throw QuirkValidationError(
      code: 'usb-quirk-field-type',
      userMessage: 'The profile field "$key" must be a number.',
      field: key,
    );
  }

  static bool? _readBool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is bool) return value;
    throw QuirkValidationError(
      code: 'usb-quirk-field-type',
      userMessage: 'The profile field "$key" must be true or false.',
      field: key,
    );
  }

  static String? _readString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw QuirkValidationError(
      code: 'usb-quirk-field-type',
      userMessage: 'The profile field "$key" must be text.',
      field: key,
    );
  }
}
