// lib/features/audio_profiles/audio_profile.dart
//
// Value type and versioned JSON codec for a portable Pulsr audio profile.
// Decoding is deliberately strict: unknown top-level keys are ignored so an
// older build can read a newer field set, but every setting value must be one
// of the five SharedPreferences scalar types and a payload may never exceed
// 512 KB or carry more than 200 settings.

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../../core/errors/app_error.dart';
import 'audio_profile_strings.dart';

/// A profile file that is unreadable, newer than this build supports, or
/// violates the value, key-count or size limits of [AudioProfile].
class ProfileFormatError extends AppError {
  const ProfileFormatError({
    required super.code,
    required super.userMessage,
    super.cause,
    super.stackTrace,
  });
}

/// One shareable audio setup: the whitelisted audio preferences captured on a
/// device, stamped with the app version and the output device they came from.
class AudioProfile {
  AudioProfile({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.appVersion,
    this.formatVersion = currentFormatVersion,
    this.deviceVid,
    this.devicePid,
    this.deviceName,
    Map<String, Object?> values = const <String, Object?>{},
  }) : _values = _normalizeValues(values);

  /// Format this build writes and the newest format it accepts.
  static const int currentFormatVersion = 1;

  /// Hard ceiling on a profile file, enforced before parsing.
  static const int maxFileBytes = 512 * 1024;

  /// Hard ceiling on the number of settings one profile may carry.
  static const int maxValueCount = 200;

  /// Format version declared by this profile.
  final int formatVersion;

  /// Stable identifier; also the on-disk file name.
  final String id;

  /// Human name chosen by the user.
  final String name;

  /// When the profile was captured or imported.
  final DateTime createdAt;

  /// App version that produced the profile.
  final String appVersion;

  /// USB vendor id of the output device, when known.
  final int? deviceVid;

  /// USB product id of the output device, when known.
  final int? devicePid;

  /// Human label of the output device, when known.
  final String? deviceName;

  final Map<String, Object?> _values;

  /// Whitelisted preference values, normalized and unmodifiable.
  Map<String, Object?> get values =>
      UnmodifiableMapView<String, Object?>(_values);

  /// Number of settings in [values].
  int get valueCount => _values.length;

  /// Same profile under a different [newId] (used when an import collides).
  AudioProfile withId(String newId) => AudioProfile(
        formatVersion: formatVersion,
        id: newId,
        name: name,
        createdAt: createdAt,
        appVersion: appVersion,
        deviceVid: deviceVid,
        devicePid: devicePid,
        deviceName: deviceName,
        values: _values,
      );

  /// Serializable form written to disk and to the share sheet.
  Map<String, Object?> toJson() => <String, Object?>{
        'formatVersion': formatVersion,
        'id': id,
        'name': name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'appVersion': appVersion,
        if (deviceVid != null) 'deviceVid': deviceVid,
        if (devicePid != null) 'devicePid': devicePid,
        if (deviceName != null) 'deviceName': deviceName,
        'values': Map<String, Object?>.of(_values),
      };

  /// Pretty-free JSON string used by the service when writing files.
  String toJsonString() => jsonEncode(toJson());

  /// UTF-8 bytes of [toJsonString].
  Uint8List encode() => Uint8List.fromList(utf8.encode(toJsonString()));

  /// Reads a profile from an already-decoded JSON [json] object.
  ///
  /// Unknown keys are ignored, `formatVersion` above [currentFormatVersion] is
  /// rejected with [ProfileFormatError], and every value in `values` is checked
  /// against the supported scalar types.
  factory AudioProfile.fromJson(Map<String, Object?> json) {
    final version = json['formatVersion'];
    if (version is! int) {
      throw const ProfileFormatError(
        code: 'audio-profile-version-missing',
        userMessage: AudioProfileStrings.formatMissingVersion,
      );
    }
    if (version > currentFormatVersion) {
      throw ProfileFormatError(
        code: 'audio-profile-version-newer',
        userMessage: AudioProfileStrings.formatNewerVersion(version),
      );
    }
    if (version < 1) {
      throw ProfileFormatError(
        code: 'audio-profile-version-invalid',
        userMessage: AudioProfileStrings.formatInvalidVersionNumber(version),
      );
    }

    final rawValues = json['values'];
    if (rawValues != null && rawValues is! Map) {
      throw const ProfileFormatError(
        code: 'audio-profile-values-invalid',
        userMessage: AudioProfileStrings.formatCorrupt,
      );
    }
    final values = <String, Object?>{};
    if (rawValues is Map) {
      for (final entry in rawValues.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const ProfileFormatError(
            code: 'audio-profile-key-invalid',
            userMessage: AudioProfileStrings.formatCorrupt,
          );
        }
        values[key] = entry.value;
      }
    }

    final createdAt = DateTime.tryParse(_readString(json, 'createdAt') ?? '');
    if (createdAt == null) {
      throw const ProfileFormatError(
        code: 'audio-profile-created-at-invalid',
        userMessage: AudioProfileStrings.formatCorrupt,
      );
    }

    return AudioProfile(
      formatVersion: version,
      id: _readRequiredString(json, 'id'),
      name: _readRequiredString(json, 'name'),
      createdAt: createdAt,
      appVersion: _readString(json, 'appVersion') ?? 'unknown',
      deviceVid: _readOptionalInt(json, 'deviceVid'),
      devicePid: _readOptionalInt(json, 'devicePid'),
      deviceName: _readString(json, 'deviceName'),
      values: values,
    );
  }

  /// Decodes a profile from raw file [bytes], enforcing the size ceiling.
  static AudioProfile decodeBytes(List<int> bytes) {
    if (bytes.length > maxFileBytes) {
      throw const ProfileFormatError(
        code: 'audio-profile-too-large',
        userMessage: AudioProfileStrings.formatTooLarge,
      );
    }
    late final String source;
    try {
      source = utf8.decode(bytes);
    } on FormatException catch (e, st) {
      throw ProfileFormatError(
        code: 'audio-profile-invalid-utf8',
        userMessage: AudioProfileStrings.formatCorrupt,
        cause: e,
        stackTrace: st,
      );
    }
    return decodeString(source);
  }

  /// Decodes a profile from a JSON [source] string, enforcing the size ceiling.
  static AudioProfile decodeString(String source) {
    if (utf8.encode(source).length > maxFileBytes) {
      throw const ProfileFormatError(
        code: 'audio-profile-too-large',
        userMessage: AudioProfileStrings.formatTooLarge,
      );
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e, st) {
      throw ProfileFormatError(
        code: 'audio-profile-invalid-json',
        userMessage: AudioProfileStrings.formatCorrupt,
        cause: e,
        stackTrace: st,
      );
    }
    if (decoded is! Map) {
      throw const ProfileFormatError(
        code: 'audio-profile-not-an-object',
        userMessage: AudioProfileStrings.formatCorrupt,
      );
    }
    final json = <String, Object?>{};
    for (final entry in decoded.entries) {
      final key = entry.key;
      if (key is String) json[key] = entry.value;
    }
    return AudioProfile.fromJson(json);
  }

  static Map<String, Object?> _normalizeValues(Map<String, Object?> source) {
    if (source.length > maxValueCount) {
      throw const ProfileFormatError(
        code: 'audio-profile-too-many-values',
        userMessage: AudioProfileStrings.formatTooManyValues,
      );
    }
    final normalized = <String, Object?>{};
    for (final entry in source.entries) {
      if (entry.key.isEmpty) {
        throw const ProfileFormatError(
          code: 'audio-profile-empty-key',
          userMessage: AudioProfileStrings.formatEmptyKey,
        );
      }
      normalized[entry.key] = _normalizeValue(entry.key, entry.value);
    }
    return normalized;
  }

  static Object? _normalizeValue(String key, Object? value) {
    if (value is bool || value is int || value is String) return value;
    if (value is double) {
      if (!value.isFinite) {
        throw ProfileFormatError(
          code: 'audio-profile-non-finite-double',
          userMessage: AudioProfileStrings.formatInvalidValue(key),
        );
      }
      return value;
    }
    if (value is List) {
      final strings = <String>[];
      for (final item in value) {
        if (item is! String) {
          throw ProfileFormatError(
            code: 'audio-profile-invalid-list',
            userMessage: AudioProfileStrings.formatInvalidValue(key),
          );
        }
        strings.add(item);
      }
      return List<String>.unmodifiable(strings);
    }
    throw ProfileFormatError(
      code: 'audio-profile-invalid-type',
      userMessage: AudioProfileStrings.formatInvalidValue(key),
    );
  }

  static String _readRequiredString(Map<String, Object?> json, String key) {
    final value = _readString(json, key);
    if (value == null || value.trim().isEmpty) {
      throw const ProfileFormatError(
        code: 'audio-profile-missing-field',
        userMessage: AudioProfileStrings.formatCorrupt,
      );
    }
    return value;
  }

  static String? _readString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw ProfileFormatError(
      code: 'audio-profile-field-type',
      userMessage: AudioProfileStrings.formatInvalidValue(key),
    );
  }

  static int? _readOptionalInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw ProfileFormatError(
      code: 'audio-profile-field-type',
      userMessage: AudioProfileStrings.formatInvalidValue(key),
    );
  }
}
