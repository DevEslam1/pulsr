// lib/features/audio_profiles/audio_profile.dart
//
// Value type and versioned JSON codec for a portable Pulsr audio profile.
// Decoding is strict about the document shape (format version, id, name and
// timestamps) so a malformed import is rejected, while a single corrupt
// setting is dropped and reported instead of discarding the whole profile.
// Unknown top-level keys are ignored so an older build can read a newer field
// set, and a payload may never exceed 512 KB or carry more than 200 settings.

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../../core/errors/app_error.dart';
import 'audio_profile_keys.dart';
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
  factory AudioProfile({
    required String id,
    required String name,
    required DateTime createdAt,
    required String appVersion,
    int formatVersion = currentFormatVersion,
    int? deviceVid,
    int? devicePid,
    String? deviceName,
    Map<String, Object?> values = const <String, Object?>{},
    List<String> ignoredKeys = const <String>[],
  }) {
    final (normalized, dropped) = _normalizeValues(values, ignoredKeys);
    return AudioProfile._(
      formatVersion: formatVersion,
      id: id,
      name: name,
      createdAt: createdAt,
      appVersion: appVersion,
      deviceVid: deviceVid,
      devicePid: devicePid,
      deviceName: deviceName,
      values: normalized,
      ignoredKeys: dropped,
    );
  }

  AudioProfile._({
    required this.formatVersion,
    required this.id,
    required this.name,
    required this.createdAt,
    required this.appVersion,
    required this.deviceVid,
    required this.devicePid,
    required this.deviceName,
    required Map<String, Object?> values,
    required List<String> ignoredKeys,
  })  : _values = values,
        ignoredKeys = List<String>.unmodifiable(ignoredKeys);

  /// Format this build writes and the newest format it accepts.
  static const int currentFormatVersion = 1;

  /// Hard ceiling on a profile file, enforced before parsing.
  static const int maxFileBytes = 512 * 1024;

  /// Hard ceiling on the number of settings one profile may carry.
  static const int maxValueCount = 200;

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,80}$');

  /// Whether [id] is a safe on-disk profile identifier.
  static bool isValidId(String id) => _idPattern.hasMatch(id);

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

  /// Keys dropped while building the profile because they are not on
  /// [AudioProfileKeys.whitelist] or carried a corrupt value. An import still
  /// succeeds; the affected settings simply keep their current/default value.
  final List<String> ignoredKeys;

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
        ignoredKeys: ignoredKeys,
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
  /// Unknown top-level keys are ignored and only settings on
  /// [AudioProfileKeys.whitelist] are kept; `formatVersion` above
  /// [currentFormatVersion] is rejected with [ProfileFormatError]. A corrupt
  /// individual setting is dropped (and reported through [ignoredKeys]) so the
  /// rest of the profile still imports and the affected preference keeps its
  /// current/default value.
  factory AudioProfile.fromJson(Map<String, Object?> json) {
    final version = json['formatVersion'];
    if (version is! int) {
      throw ProfileFormatError(
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
      throw ProfileFormatError(
        code: 'audio-profile-values-invalid',
        userMessage: AudioProfileStrings.formatCorrupt,
      );
    }
    if (rawValues is Map && rawValues.length > maxValueCount) {
      throw ProfileFormatError(
        code: 'audio-profile-too-many-values',
        userMessage: AudioProfileStrings.formatTooManyValues,
      );
    }
    final values = <String, Object?>{};
    final ignored = <String>[];
    if (rawValues is Map) {
      for (final entry in rawValues.entries) {
        final key = entry.key;
        if (key is! String) {
          ignored.add('$key');
          continue;
        }
        if (key.isEmpty) {
          throw ProfileFormatError(
            code: 'audio-profile-empty-key',
            userMessage: AudioProfileStrings.formatEmptyKey,
          );
        }
        if (!AudioProfileKeys.isWhitelisted(key)) {
          ignored.add(key);
          continue;
        }
        values[key] = entry.value;
      }
    }

    final id = _readRequiredString(json, 'id');
    if (!isValidId(id)) {
      throw ProfileFormatError(
        code: 'audio-profile-id-invalid',
        userMessage: AudioProfileStrings.formatInvalidId,
      );
    }

    final createdAt = DateTime.tryParse(_readString(json, 'createdAt') ?? '');
    if (createdAt == null) {
      throw ProfileFormatError(
        code: 'audio-profile-created-at-invalid',
        userMessage: AudioProfileStrings.formatCorrupt,
      );
    }

    return AudioProfile(
      formatVersion: version,
      id: id,
      name: _readRequiredString(json, 'name'),
      createdAt: createdAt,
      appVersion: _readLenientString(json, 'appVersion') ?? 'unknown',
      deviceVid: _readOptionalInt(json, 'deviceVid'),
      devicePid: _readOptionalInt(json, 'devicePid'),
      deviceName: _readLenientString(json, 'deviceName'),
      values: values,
      ignoredKeys: ignored,
    );
  }

  /// Decodes a profile from raw file [bytes], enforcing the size ceiling.
  static AudioProfile decodeBytes(List<int> bytes) {
    if (bytes.length > maxFileBytes) {
      throw ProfileFormatError(
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
      throw ProfileFormatError(
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
      throw ProfileFormatError(
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

  static (Map<String, Object?>, List<String>) _normalizeValues(
    Map<String, Object?> source,
    List<String> alreadyIgnored,
  ) {
    if (source.length > maxValueCount) {
      throw ProfileFormatError(
        code: 'audio-profile-too-many-values',
        userMessage: AudioProfileStrings.formatTooManyValues,
      );
    }
    final normalized = <String, Object?>{};
    final ignored = <String>[
      for (final key in alreadyIgnored)
        if (key.isNotEmpty) key,
    ];
    for (final entry in source.entries) {
      if (entry.key.isEmpty) {
        ignored.add(entry.key);
        continue;
      }
      try {
        normalized[entry.key] = _normalizeValue(entry.key, entry.value);
      } on ProfileFormatError {
        // A single corrupt setting must not make the whole profile unusable;
        // the preference simply keeps its current/default value.
        ignored.add(entry.key);
      }
    }
    return (normalized, ignored);
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
      throw ProfileFormatError(
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

  /// Like [_readString], but degrades a corrupt optional field to `null`.
  static String? _readLenientString(Map<String, Object?> json, String key) {
    final value = json[key];
    return value is String ? value : null;
  }

  static int? _readOptionalInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is int) return value >= 0 ? value : null;
    if (value is num) {
      final rounded = value.toInt();
      return rounded >= 0 ? rounded : null;
    }
    // A corrupt device field must not block the rest of the metadata.
    return null;
  }
}
