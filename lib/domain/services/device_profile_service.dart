// lib/core/services/device_profile_service.dart
import 'dart:convert';

import 'package:injectable/injectable.dart';
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

  const DeviceProfileEntry({required this.deviceKey, required this.deviceLabel});
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
    final type =
        isBluetooth ? 'bluetooth' : deviceType.trim().toLowerCase();
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

  Future<Map<String, DeviceProfileLink>> getLinks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyLinks);
      if (raw == null) return {};
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) =>
          MapEntry(k, DeviceProfileLink.fromJson(v as Map<String, dynamic>)));
    } catch (e, st) {
      ErrorLogger.log('Failed to load device profile links',
          error: e, stackTrace: st, category: 'DeviceProfileService');
      return {};
    }
  }

  Future<DeviceProfileLink?> linkForDeviceKey(String deviceKey) async {
    final links = await getLinks();
    return links[deviceKey];
  }

  Future<void> rememberLink({
    required String deviceKey,
    required String deviceLabel,
    required String profileId,
  }) async {
    final links = await getLinks();
    links[deviceKey] = DeviceProfileLink(
      deviceKey: deviceKey,
      profileId: profileId,
      deviceLabel: deviceLabel,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLinks,
        json.encode(links.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Future<void> forgetLink(String deviceKey) async {
    final links = await getLinks();
    if (links.remove(deviceKey) == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLinks,
        json.encode(links.map((k, v) => MapEntry(k, v.toJson()))));
  }

  /// Remembers a seen device for the UI list (bounded, most recent kept).
  Future<void> rememberDevice(String deviceKey, String deviceLabel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyRegistry);
      final entries = <DeviceProfileEntry>[];
      if (raw != null) {
        final decoded = json.decode(raw) as List<dynamic>;
        for (final e in decoded) {
          final map = e as Map<String, dynamic>;
          entries.add(DeviceProfileEntry(
            deviceKey: map['deviceKey'] as String? ?? '',
            deviceLabel: map['deviceLabel'] as String? ?? '',
          ));
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
            .map((e) => {'deviceKey': e.deviceKey, 'deviceLabel': e.deviceLabel})
            .toList()),
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to remember output device',
          error: e, stackTrace: st, category: 'DeviceProfileService');
    }
  }

  Future<List<DeviceProfileEntry>> registryDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyRegistry);
      if (raw == null) return const [];
      final decoded = json.decode(raw) as List<dynamic>;
      return decoded
          .map((e) => DeviceProfileEntry(
                deviceKey: (e as Map<String, dynamic>)['deviceKey'] as String? ?? '',
                deviceLabel: e['deviceLabel'] as String? ?? '',
              ))
          .toList();
    } catch (e, st) {
      ErrorLogger.log('Failed to load device registry',
          error: e, stackTrace: st, category: 'DeviceProfileService');
      return const [];
    }
  }
}
