// lib/features/usb_tools/usb_quirk_profile.dart
//
// Value type for one USB DAC quirk profile. A profile answers the ergonomics
// questions a problem DAC forces on the user: how long to stay silent while the
// device settles, whether to drop to 16-bit, whether to reset the alternate
// setting on stop, whether to claim the HID consumer-control interfaces, and
// how the isochronous transfers should be sized.
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
/// (`silenceMs`, `vid`, ...) for diagnostics.
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

/// One per-device (or default) set of USB ergonomics knobs.
///
/// Every field is validated on construction:
/// * [vid] / [pid] must be USB 16-bit ids.
/// * [label] must be non-empty and at most [maxLabelLength] characters.
/// * [silenceMs] must be 0..[maxSilenceMs].
/// * [bufferMs] must be 0..[maxBufferMs].
/// * [transferSizeBytes] must be 0 (auto) or [minTransferSizeBytes]..
///   [maxTransferSizeBytes].
class UsbQuirkProfile {
  /// Builds a validated profile.
  ///
  /// Throws [QuirkValidationError] when any field is out of range, so callers
  /// never have to re-check a profile they already hold.
  factory UsbQuirkProfile({
    required int vid,
    required int pid,
    required String label,
    int silenceMs = 0,
    bool altResetOnStop = false,
    bool force16Bit = false,
    bool hidEnabled = false,
    int transferSizeBytes = 0,
    int bufferMs = 0,
  }) {
    final error = _fieldError(
      vid: vid,
      pid: pid,
      label: label,
      silenceMs: silenceMs,
      transferSizeBytes: transferSizeBytes,
      bufferMs: bufferMs,
    );
    if (error != null) throw error;
    return UsbQuirkProfile._(
      vid: vid,
      pid: pid,
      label: label.trim(),
      silenceMs: silenceMs,
      altResetOnStop: altResetOnStop,
      force16Bit: force16Bit,
      hidEnabled: hidEnabled,
      transferSizeBytes: transferSizeBytes,
      bufferMs: bufferMs,
    );
  }

  const UsbQuirkProfile._({
    required this.vid,
    required this.pid,
    required this.label,
    required this.silenceMs,
    required this.altResetOnStop,
    required this.force16Bit,
    required this.hidEnabled,
    required this.transferSizeBytes,
    required this.bufferMs,
  });

  /// Highest USB vendor/product id (16-bit field).
  static const int maxUsbId = 0xFFFF;

  /// Longest accepted [label].
  static const int maxLabelLength = 64;

  /// Longest accepted [silenceMs]; longer than this and the user hears a gap.
  static const int maxSilenceMs = 2500;

  /// Longest accepted [bufferMs].
  static const int maxBufferMs = 500;

  /// Smallest non-auto [transferSizeBytes].
  static const int minTransferSizeBytes = 512;

  /// Largest accepted [transferSizeBytes].
  static const int maxTransferSizeBytes = 65536;

  /// USB vendor id.
  final int vid;

  /// USB product id.
  final int pid;

  /// Human label shown in the editor and in diagnostics.
  final String label;

  /// Silence written before the first real frame, in milliseconds.
  final int silenceMs;

  /// Return the streaming interface to alternate setting 0 on stop.
  final bool altResetOnStop;

  /// Force a 16-bit wire format even when the source is deeper.
  final bool force16Bit;

  /// Claim the device's HID consumer-control interfaces and map media keys.
  final bool hidEnabled;

  /// Requested isochronous transfer size in bytes; 0 means "let the sink pick".
  final int transferSizeBytes;

  /// Requested sink buffer depth in milliseconds; 0 means "sink default".
  final int bufferMs;

  /// A profile with every knob at its neutral value.
  ///
  /// Used as the fallback when neither a per-device entry nor the global
  /// defaults exist, and as the seed for a brand-new device editor. The ids are
  /// zero and are always replaced by the real device ids before being applied.
  static const UsbQuirkProfile defaults = UsbQuirkProfile._(
    vid: 0,
    pid: 0,
    label: 'Default',
    silenceMs: 0,
    altResetOnStop: false,
    force16Bit: false,
    hidEnabled: false,
    transferSizeBytes: 0,
    bufferMs: 0,
  );

  /// Storage key of this device: `vid:pid`, lowercase, zero-padded to 4 hex
  /// digits each (`0a12:0001`).
  String get key => deviceKey(vid, pid);

  /// Whether this profile carries a real device identity (nonzero ids).
  bool get isDeviceSpecific => vid > 0 && pid > 0;

  /// Whether every knob is at its neutral value.
  bool get isNeutral =>
      silenceMs == 0 &&
      bufferMs == 0 &&
      transferSizeBytes == 0 &&
      !altResetOnStop &&
      !force16Bit &&
      !hidEnabled;

  /// Lowercase `vid:pid` storage key, zero-padded to four hex digits each.
  static String deviceKey(int vid, int pid) => '${_hex4(vid)}:${_hex4(pid)}';

  /// Copy with selected fields replaced; re-validates through the factory.
  UsbQuirkProfile copyWith({
    int? vid,
    int? pid,
    String? label,
    int? silenceMs,
    bool? altResetOnStop,
    bool? force16Bit,
    bool? hidEnabled,
    int? transferSizeBytes,
    int? bufferMs,
  }) {
    return UsbQuirkProfile(
      vid: vid ?? this.vid,
      pid: pid ?? this.pid,
      label: label ?? this.label,
      silenceMs: silenceMs ?? this.silenceMs,
      altResetOnStop: altResetOnStop ?? this.altResetOnStop,
      force16Bit: force16Bit ?? this.force16Bit,
      hidEnabled: hidEnabled ?? this.hidEnabled,
      transferSizeBytes: transferSizeBytes ?? this.transferSizeBytes,
      bufferMs: bufferMs ?? this.bufferMs,
    );
  }

  /// Serializable form stored in preferences and shown in the JSON preview.
  Map<String, Object?> toJson() => <String, Object?>{
        'vid': vid,
        'pid': pid,
        'label': label,
        'silenceMs': silenceMs,
        'altResetOnStop': altResetOnStop,
        'force16Bit': force16Bit,
        'hidEnabled': hidEnabled,
        'transferSizeBytes': transferSizeBytes,
        'bufferMs': bufferMs,
      };

  /// Reads a profile from an already-decoded JSON object.
  ///
  /// Unknown keys are ignored. Missing optional knobs fall back to their
  /// neutral value; a missing or wrong-typed `vid`/`pid`/`label` (or any knob
  /// outside its range) throws [QuirkValidationError].
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
      silenceMs: _readInt(json, 'silenceMs') ?? 0,
      altResetOnStop: _readBool(json, 'altResetOnStop') ?? false,
      force16Bit: _readBool(json, 'force16Bit') ?? false,
      hidEnabled: _readBool(json, 'hidEnabled') ?? false,
      transferSizeBytes: _readInt(json, 'transferSizeBytes') ?? 0,
      bufferMs: _readInt(json, 'bufferMs') ?? 0,
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
    if (isNeutral) return '$key "$label": defaults';
    final knobs = <String>[
      if (silenceMs > 0) 'silence ${silenceMs}ms',
      if (bufferMs > 0) 'buffer ${bufferMs}ms',
      if (transferSizeBytes > 0)
        'transfer ${transferSizeBytes}B'
      else
        'transfer auto',
      if (force16Bit) 'force 16-bit',
      if (altResetOnStop) 'alt-reset on stop',
      if (hidEnabled) 'HID consumer keys',
    ];
    return '$key "$label": ${knobs.join(', ')}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsbQuirkProfile &&
          other.vid == vid &&
          other.pid == pid &&
          other.label == label &&
          other.silenceMs == silenceMs &&
          other.altResetOnStop == altResetOnStop &&
          other.force16Bit == force16Bit &&
          other.hidEnabled == hidEnabled &&
          other.transferSizeBytes == transferSizeBytes &&
          other.bufferMs == bufferMs;

  @override
  int get hashCode => Object.hash(
        vid,
        pid,
        label,
        silenceMs,
        altResetOnStop,
        force16Bit,
        hidEnabled,
        transferSizeBytes,
        bufferMs,
      );

  @override
  String toString() => 'UsbQuirkProfile(${describe()})';

  static String _hex4(int value) =>
      value.toRadixString(16).padLeft(4, '0').toLowerCase();

  static QuirkValidationError? _fieldError({
    required int vid,
    required int pid,
    required String label,
    required int silenceMs,
    required int transferSizeBytes,
    required int bufferMs,
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
        userMessage: 'Silence must be between 0 and 2500 ms.',
        field: 'silenceMs',
      );
    }
    if (bufferMs < 0 || bufferMs > maxBufferMs) {
      return const QuirkValidationError(
        code: 'usb-quirk-buffer-range',
        userMessage: 'Buffer must be between 0 and 500 ms.',
        field: 'bufferMs',
      );
    }
    if (transferSizeBytes != 0 &&
        (transferSizeBytes < minTransferSizeBytes ||
            transferSizeBytes > maxTransferSizeBytes)) {
      return const QuirkValidationError(
        code: 'usb-quirk-transfer-size-range',
        userMessage: 'Transfer size must be auto, or 512-65536 bytes.',
        field: 'transferSizeBytes',
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
