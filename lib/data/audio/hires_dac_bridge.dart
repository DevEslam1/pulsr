// lib/data/audio/hires_dac_bridge.dart
import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/constants/channels.dart';
import '../../core/utils/platform_capabilities.dart';

/// Bridge to the `pulsr/hires_dac` plugin: the DSD capability map and the
/// DAC's own UAC2 attenuator.
///
/// Every call fails closed (`null` / `false`) when the bridge is absent, the
/// platform is not Android, or the call times out. The UI therefore never
/// offers native DSD or a hardware-volume slider it cannot honour — the same
/// rule [AudioEffectsChannel] applies to the DSP setters.
class HiresDacBridge {
  const HiresDacBridge();

  static const MethodChannel _channel = MethodChannel(PulsrChannels.hiresDac);

  /// Capability map from `getDsdCapabilities`. A bridge that can prove the
  /// native path adds `nativeDsd`, `nativeDsdRates` and `nativeDsdAltSetting`
  /// to the legacy DoP fields; an absent key means "not proven", never
  /// "proven unsupported".
  Future<Map<String, dynamic>?> getDsdCapabilities() async {
    if (!PlatformCapabilities.isAndroid) return null;
    try {
      return await _channel
          .invokeMapMethod<String, dynamic>('getDopCapabilities')
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  /// The DAC's volume range in 1/256 dB (`minQ8`/`maxQ8`), or null when the
  /// device exposes no UAC2 Feature Unit volume control — the slider is hidden
  /// then rather than mapped onto an assumed 0…-60 dB scale.
  Future<({int minQ8, int maxQ8})?> getUac2VolumeRange() async {
    if (!PlatformCapabilities.isAndroid) return null;
    try {
      final map = await _channel
          .invokeMapMethod<String, dynamic>('getUac2VolumeRange')
          .timeout(const Duration(seconds: 2));
      final min = map?['minQ8'];
      final max = map?['maxQ8'];
      if (min is! num || max is! num || max <= min) return null;
      return (minQ8: min.toInt(), maxQ8: max.toInt());
    } catch (_) {
      return null;
    }
  }

  /// Current attenuator value as a 0..1 position, or null when it cannot be
  /// read.
  ///
  /// The Kotlin side answers a map (`q8`, `db`, `position`, `minQ8`, `maxQ8`,
  /// `resQ8`). Asking for a bare `num` here used to fail the platform type cast
  /// and return null, which silently fell back to the status snapshot. The map
  /// is parsed instead, with a bare-num path kept for older bridges.
  Future<num?> getUac2HardwareVolume() async {
    if (!PlatformCapabilities.isAndroid) return null;
    try {
      final result = await _channel
          .invokeMethod<dynamic>('getUac2HardwareVolume')
          .timeout(const Duration(seconds: 2));
      if (result is num) return result;
      if (result is! Map) return null;
      final position = result['position'];
      if (position is num && position.isFinite) return position;
      final q8 = result['q8'];
      final min = result['minQ8'];
      final max = result['maxQ8'];
      if (q8 is num && min is num && max is num && max > min) {
        return ((q8 - min) / (max - min)).clamp(0.0, 1.0);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Moves the DAC's own attenuator to [position] (0 = quietest, 1 = unity).
  /// Returns false on any bridge failure; it never throws at the slider.
  Future<bool> setUac2HardwareVolume(double position) async {
    if (!PlatformCapabilities.isAndroid) return false;
    if (!position.isFinite) return false;
    try {
      final res = await _channel.invokeMethod<dynamic>(
          'setUac2HardwareVolume', {
        'position': position.clamp(0.0, 1.0)
      }).timeout(const Duration(seconds: 3));
      return res != null &&
          res != false &&
          !(res is Map && res['error'] != null);
    } catch (_) {
      return false;
    }
  }

  /// Current hardware mute state, or null when unavailable.
  Future<bool?> getUac2HardwareMute() async {
    if (!PlatformCapabilities.isAndroid) return null;
    try {
      final res = await _channel
          .invokeMethod<dynamic>('getUac2HardwareMute')
          .timeout(const Duration(seconds: 2));
      if (res is bool) return res;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Sets hardware mute state (true = muted, false = unmuted).
  Future<bool> setUac2HardwareMute(bool muted) async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<dynamic>('setUac2HardwareMute',
          {'muted': muted}).timeout(const Duration(seconds: 3));
      return res == true;
    } catch (_) {
      return false;
    }
  }
}
