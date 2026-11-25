// lib/features/usb_tools/usb_quirk_store.dart
//
// SharedPreferences-backed storage for [UsbQuirkProfile]. Everything lives in
// one versioned key (`usb_quirks_v1`) holding a small JSON document, because a
// per-device preference key would multiply a key per DAC the user ever plugged
// in and cannot be enumerated cheaply.
//
// The store never throws: a corrupt document, a removed field or a preference
// write that the platform rejects is logged and reported as an empty result or
// a `false` return, so a bad stored profile can never block the settings UI.

import 'dart:convert';

import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/error_logger.dart';
import 'usb_quirk_profile.dart';

/// Reads and writes USB quirk profiles.
class UsbQuirkStore {
  /// Creates a store over [prefs]. The caller owns the [SharedPreferences]
  /// instance (dependency injection supplies it in production, tests use
  /// `SharedPreferences.setMockInitialValues`).
  UsbQuirkStore({required SharedPreferences prefs}) : _prefs = prefs;

  /// Versioned preference key that holds the whole document.
  static const String storageKey = 'usb_quirks_v1';

  /// Field holding the per-device map inside [storageKey].
  static const String devicesField = 'devices';

  /// Field holding the fallback profile inside [storageKey].
  static const String globalDefaultsField = 'globalDefaults';

  final SharedPreferences _prefs;
  final Mutex _writeMutex = Mutex();

  String? _cachedRaw;
  Map<String, UsbQuirkProfile> _cachedDevices = const {};
  UsbQuirkProfile? _cachedDefaults;

  /// Every stored device profile, ordered by label (then by key).
  ///
  /// Entries that no longer decode are logged and skipped; the rest still load.
  List<UsbQuirkProfile> all() {
    final snapshot = _read();
    final profiles = snapshot.devices.values.toList()
      ..sort((a, b) {
        final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
        return byLabel != 0 ? byLabel : a.key.compareTo(b.key);
      });
    return List<UsbQuirkProfile>.unmodifiable(profiles);
  }

  /// The stored profile for [vid]/[pid], or null when the device has none.
  UsbQuirkProfile? get(int vid, int pid) =>
      _read().devices[UsbQuirkProfile.deviceKey(vid, pid)];

  /// The fallback profile applied to devices without their own entry.
  UsbQuirkProfile? get globalDefaults => _read().defaults;

  /// Writes [profile] under its own `vid:pid` key.
  ///
  /// Returns false when the platform rejected the write or the document could
  /// not be serialized; the previous value is left in place.
  Future<bool> put(UsbQuirkProfile profile) {
    return _writeMutex.protect(() async {
      final snapshot = _read();
      final devices = Map<String, UsbQuirkProfile>.of(snapshot.devices)
        ..[profile.key] = profile;
      return _write(devices: devices, defaults: snapshot.defaults);
    });
  }

  /// Removes the entry for [vid]/[pid]. Returns false only on a failed write;
  /// removing a device that was never stored still returns true.
  Future<bool> remove(int vid, int pid) {
    return _writeMutex.protect(() async {
      final snapshot = _read();
      if (!snapshot.devices.containsKey(UsbQuirkProfile.deviceKey(vid, pid))) {
        return true;
      }
      final devices = Map<String, UsbQuirkProfile>.of(snapshot.devices)
        ..remove(UsbQuirkProfile.deviceKey(vid, pid));
      return _write(devices: devices, defaults: snapshot.defaults);
    });
  }

  /// Sets (or clears, with null) the fallback profile.
  Future<bool> setGlobalDefaults(UsbQuirkProfile? profile) {
    return _writeMutex.protect(() async {
      final snapshot = _read();
      return _write(devices: snapshot.devices, defaults: profile);
    });
  }

  /// The profile to apply for a device: its own entry, else the global
  /// defaults, else null.
  ///
  /// A null [vid] or [pid] (no DAC attached, or a device that reports no ids)
  /// resolves to the global defaults.
  UsbQuirkProfile? profileForDevice(int? vid, int? pid) {
    if (vid != null && pid != null) {
      final stored = get(vid, pid);
      if (stored != null) return stored;
    }
    return globalDefaults;
  }

  /// Decoded document for the current preference value, cached by raw string so
  /// repeated reads during a rebuild do not re-parse JSON.
  _Snapshot _read() {
    final raw = _prefs.getString(storageKey);
    if (raw == _cachedRaw) {
      return _Snapshot(devices: _cachedDevices, defaults: _cachedDefaults);
    }
    final snapshot = _decode(raw);
    _cachedRaw = raw;
    _cachedDevices = snapshot.devices;
    _cachedDefaults = snapshot.defaults;
    return snapshot;
  }

  _Snapshot _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const _Snapshot.empty();
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e, st) {
      ErrorLogger.log(
        'Stored USB quirk document is not valid JSON; ignoring it',
        error: e,
        stackTrace: st,
        category: 'UsbQuirkStore',
      );
      return const _Snapshot.empty();
    }
    if (decoded is! Map) {
      ErrorLogger.log(
        'Stored USB quirk document is not an object; ignoring it',
        category: 'UsbQuirkStore',
      );
      return const _Snapshot.empty();
    }
    final devices = <String, UsbQuirkProfile>{};
    final rawDevices = decoded[devicesField];
    if (rawDevices is Map) {
      for (final entry in rawDevices.entries) {
        final profile = UsbQuirkProfile.tryFromJson(entry.value);
        if (profile == null) {
          ErrorLogger.log(
            'Skipping an unreadable USB quirk entry',
            category: 'UsbQuirkStore',
            meta: <String, dynamic>{'entry': '${entry.key}'},
          );
          continue;
        }
        // Re-key from the profile's own ids so a hand-edited or upper-cased key
        // still resolves to the canonical lowercase `vid:pid`.
        devices[profile.key] = profile;
      }
    } else if (rawDevices != null) {
      ErrorLogger.log(
        'Stored USB quirk "devices" field is not an object; ignoring it',
        category: 'UsbQuirkStore',
      );
    }
    final defaults = UsbQuirkProfile.tryFromJson(decoded[globalDefaultsField]);
    return _Snapshot(devices: devices, defaults: defaults);
  }

  Future<bool> _write({
    required Map<String, UsbQuirkProfile> devices,
    required UsbQuirkProfile? defaults,
  }) async {
    final payload = <String, Object?>{
      devicesField: <String, Object?>{
        for (final entry in devices.entries) entry.key: entry.value.toJson(),
      },
      globalDefaultsField: defaults?.toJson(),
    };
    try {
      final ok = await _prefs.setString(storageKey, jsonEncode(payload));
      if (!ok) {
        ErrorLogger.log(
          'Writing the USB quirk document was rejected by preferences',
          category: 'UsbQuirkStore',
        );
        return false;
      }
      _cachedRaw = null;
      _cachedDevices = const {};
      _cachedDefaults = null;
      return true;
    } catch (e, st) {
      ErrorLogger.log(
        'Writing the USB quirk document failed',
        error: e,
        stackTrace: st,
        category: 'UsbQuirkStore',
      );
      return false;
    }
  }
}

/// Decoded form of the stored document.
class _Snapshot {
  const _Snapshot({required this.devices, required this.defaults});

  const _Snapshot.empty()
      : devices = const {},
        defaults = null;

  final Map<String, UsbQuirkProfile> devices;
  final UsbQuirkProfile? defaults;
}
