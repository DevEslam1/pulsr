// lib/core/services/device_profile_service.dart
import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/audio_output_info.dart';
import '../../core/utils/error_logger.dart';
import 'settings_profiles_service.dart';

/// A persisted "output device -> settings profile" link.
class DeviceProfileLink {
  final String deviceKey;
  final String profileId;
  final String deviceLabel;

  const DeviceProfileLink({
    required this.deviceKey,
    required this.profileId,
    required this.deviceLabel,
  });

  Map<String, dynamic> toJson() => {
        'deviceKey': deviceKey,
        'profileId': profileId,
        'deviceLabel': deviceLabel,
      };

  factory DeviceProfileLink.fromJson(Map<String, dynamic> json) =>
      DeviceProfileLink(
        deviceKey: json['deviceKey'] as String? ?? '',
        profileId: json['profileId'] as String? ?? '',
        deviceLabel: json['deviceLabel'] as String? ?? '',
      );
}

/// A remembered output device (for the per-device profile UI list).
class DeviceProfileEntry {
  final String deviceKey;
  final String deviceLabel;

  const DeviceProfileEntry(
      {required this.deviceKey, required this.deviceLabel});
}

/// Auto per-output-device profiles: links devices to [SettingsProfile]s and
/// resolves which profile should be applied when a device becomes active.
///
/// This service only *decides* - applying the profile is the caller's job
/// (PlayerCubit) so handler/state/UI stay consistent through the cubit's own
/// guarded setters (bit-perfect conflict rules included).
@lazySingleton
class DeviceProfileService {
  static const String _keyLinks = 'setting_device_profile_links';
  static const String _keyEnabled = 'setting_auto_device_profiles_enabled';
  static const String _keyRegistry = 'setting_device_registry';
  static const int _maxRegistryEntries = 30;

  /// Serializes every read-modify-write of the persisted link/registry JSON.
  /// Two concurrent [rememberLink]/[rememberDevice] calls would otherwise each
  /// read the same snapshot and the later write would drop the other's entry.
  final Mutex _prefsMutex = Mutex();

  /// Stable identity for an output device. Bluetooth/wired/USB/HDMI devices
  /// are keyed by "type:normalized name"; the built-in speaker collapses to
  /// one key so the phone speaker always maps to the same profile.
  static String deviceKeyFromInfo(AudioOutputInfo info) =>
      deviceKeyFor(info.deviceName,
          deviceType: info.activeDeviceType, isBluetooth: info.isBluetooth);

  static String deviceKeyFor(
    String deviceName, {
    required String deviceType,
    required bool isBluetooth,
  }) {
    // Every Bluetooth transport shares one namespace: the same earbuds report
    // activeDeviceType 'ble' over LE Audio and 'bluetooth' over A2DP, and the
    // user's profile has to follow them across that renegotiation.
    final type = isBluetooth ? 'bluetooth' : deviceType.trim().toLowerCase();
    if (type.isEmpty || type == 'builtin') return 'builtin:speaker';
    final name =
        deviceName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) return '$type:unknown';
    return '$type:$name';
  }

  Future<bool> isAutoSwitchEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyEnabled) ?? true;
    } catch (e, st) {
      ErrorLogger.log('Failed to read auto device-profile switch flag',
          error: e, stackTrace: st, category: 'DeviceProfileService');
      return true;
    }
  }

  Future<void> setAutoSwitchEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
  }

  /// Internal loader distinguishing missing key (returns empty map) from
  /// corrupt storage (returns null) so writes never wipe corrupt data.
  Future<Map<String, DeviceProfileLink>?> _loadLinksRaw() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyLinks);
      if (raw == null) return {};
      final dynamic decoded = json.decode(raw);
      if (decoded is! Map) {
        throw FormatException('Device profile links JSON is not a Map: $raw');
      }
      final result = <String, DeviceProfileLink>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          result[entry.key.toString()] = DeviceProfileLink.fromJson(
              Map<String, dynamic>.from(entry.value as Map));
        }
      }
      return result;
    } catch (e, st) {
      ErrorLogger.log('Failed to load device profile links',
          error: e, stackTrace: st, category: 'DeviceProfileService');
      return null;
    }
  }

  Future<Map<String, DeviceProfileLink>> getLinks() async {
    final links = await _loadLinksRaw();
    return links ?? {};
  }

  Future<DeviceProfileLink?> linkForDeviceKey(String deviceKey) async {
    final links = await getLinks();
    return links[deviceKey];
  }

  Future<void> rememberLink({
    required String deviceKey,
    required String deviceLabel,
    required String profileId,
  }) =>
      _prefsMutex.protect(() async {
        final links = await _loadLinksRaw();
        if (links == null) {
          ErrorLogger.log(
            'Refusing to overwrite corrupt device profile links storage',
            category: 'DeviceProfileService',
          );
          return;
        }
        links[deviceKey] = DeviceProfileLink(
          deviceKey: deviceKey,
          profileId: profileId,
          deviceLabel: deviceLabel,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyLinks,
            json.encode(links.map((k, v) => MapEntry(k, v.toJson()))));
      });

  Future<void> forgetLink(String deviceKey) => _prefsMutex.protect(() async {
        final links = await _loadLinksRaw();
        if (links == null) {
          ErrorLogger.log(
            'Refusing to overwrite corrupt device profile links storage',
            category: 'DeviceProfileService',
          );
          return;
        }
        if (links.remove(deviceKey) == null) return;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyLinks,
            json.encode(links.map((k, v) => MapEntry(k, v.toJson()))));
      });

  /// Remembers a seen device for the UI list (bounded, most recent kept).
  Future<void> rememberDevice(String deviceKey, String deviceLabel) =>
      _prefsMutex.protect(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString(_keyRegistry);
          final entries = <DeviceProfileEntry>[];
          if (raw != null) {
            final dynamic decoded = json.decode(raw);
            if (decoded is! List) {
              throw FormatException('Device registry JSON is not a List: $raw');
            }
            for (final e in decoded) {
              if (e is Map) {
                final map = Map<String, dynamic>.from(e);
                entries.add(DeviceProfileEntry(
                  deviceKey: map['deviceKey'] as String? ?? '',
                  deviceLabel: map['deviceLabel'] as String? ?? '',
                ));
              }
            }
          }
          entries.removeWhere((e) => e.deviceKey == deviceKey);
          entries.insert(
            0,
            DeviceProfileEntry(deviceKey: deviceKey, deviceLabel: deviceLabel),
          );
          final capped = entries.take(_maxRegistryEntries).toList();
          await prefs.setString(
            _keyRegistry,
            json.encode(capped
                .map((e) => {
                      'deviceKey': e.deviceKey,
                      'deviceLabel': e.deviceLabel,
                    })
                .toList()),
          );
        } catch (e, st) {
          ErrorLogger.log('Failed to remember output device',
              error: e, stackTrace: st, category: 'DeviceProfileService');
        }
      });

  Future<List<DeviceProfileEntry>> registryDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyRegistry);
      if (raw == null) return const [];
      final dynamic decoded = json.decode(raw);
      if (decoded is! List) {
        throw FormatException('Device registry JSON is not a List: $raw');
      }
      return decoded
          .whereType<Map>()
          .map((e) => DeviceProfileEntry(
                deviceKey:
                    Map<String, dynamic>.from(e)['deviceKey'] as String? ?? '',
                deviceLabel: e['deviceLabel'] as String? ?? '',
              ))
          .toList();
    } catch (e, st) {
      ErrorLogger.log('Failed to load device registry',
          error: e, stackTrace: st, category: 'DeviceProfileService');
      return const [];
    }
  }

  /// Exports all device-profile links as JSON for backup or sync across devices (Pillar 2).
  Future<String> exportLinksJson() async {
    final links = await getLinks();
    return json.encode(links.map((k, v) => MapEntry(k, v.toJson())));
  }

  /// Imports device-profile links from JSON (merging with existing links).
  Future<bool> importLinksJson(String jsonStr) => _prefsMutex.protect(() async {
        try {
          if (jsonStr.trim().isEmpty) return false;
          final dynamic decoded = json.decode(jsonStr);
          if (decoded is! Map) return false;
          final links = await _loadLinksRaw();
          if (links == null) {
            ErrorLogger.log(
              'Refusing to import into corrupt device profile links storage',
              category: 'DeviceProfileService',
            );
            return false;
          }
          var importedCount = 0;
          for (final entry in decoded.entries) {
            final key = entry.key?.toString() ?? '';
            if (key.isEmpty) continue;
            if (entry.value is Map) {
              final valMap = Map<String, dynamic>.from(entry.value as Map);
              final link = DeviceProfileLink.fromJson(valMap);
              if (link.deviceKey.isNotEmpty && link.profileId.isNotEmpty) {
                links[key] = link;
                importedCount++;
              }
            }
          }
          if (importedCount == 0 && decoded.isNotEmpty) return false;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyLinks,
              json.encode(links.map((k, v) => MapEntry(k, v.toJson()))));
          return true;
        } catch (e, st) {
          ErrorLogger.log('Failed to import device profile links from JSON',
              error: e, stackTrace: st, category: 'DeviceProfileService');
          return false;
        }
      });

  static const String _keyBtLatency = 'setting_bt_latency_by_device';

  /// Per-device Bluetooth latency offset (ms), or null when never calibrated.
  /// Earbuds differ wildly (80-300 ms), so one global value is always wrong
  /// for somebody's second pair.
  Future<int?> btLatencyFor(String deviceKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyBtLatency);
      if (raw == null) return null;
      final dynamic decoded = json.decode(raw);
      if (decoded is! Map) {
        throw FormatException('BT latency JSON is not a Map: $raw');
      }
      final val = (decoded[deviceKey] as num?)?.toInt();
      return val?.clamp(0, 1500);
    } catch (e, st) {
      ErrorLogger.log('Failed to read per-device BT latency',
          error: e, stackTrace: st, category: 'DeviceProfileService');
      return null;
    }
  }

  Future<void> rememberBtLatency(String deviceKey, int offsetMs) =>
      _prefsMutex.protect(() async {
        try {
          final clamped = offsetMs.clamp(0, 1500);
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString(_keyBtLatency);
          Map<String, dynamic> map;
          if (raw == null) {
            map = <String, dynamic>{};
          } else {
            final dynamic decoded = json.decode(raw);
            if (decoded is! Map) {
              throw FormatException('BT latency JSON is not a Map: $raw');
            }
            map = Map<String, dynamic>.from(decoded);
          }
          map[deviceKey] = clamped;
          await prefs.setString(_keyBtLatency, json.encode(map));
        } catch (e, st) {
          ErrorLogger.log('Failed to save per-device BT latency',
              error: e, stackTrace: st, category: 'DeviceProfileService');
        }
      });
}
