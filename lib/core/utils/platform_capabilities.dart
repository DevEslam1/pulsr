// lib/core/utils/platform_capabilities.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PlatformCapabilities {
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  static bool get hasEqualizer => isAndroid;
  static bool get hasAudioEffects => isAndroid;
  static bool get hasTagEditor => isAndroid;
  static bool get hasRingtoneManager => isAndroid;
  static bool get hasAppWidget => isAndroid;
  static bool get hasHardwareVisualizer => isAndroid;

  static Future<Map<String, bool>> queryNativeCapabilities() async {
    if (!isAndroid) {
      return {
        'hasEqualizer': false,
        'hasAudioEffects': false,
        'hasTagEditor': false,
        'hasRingtoneManager': false,
        'hasAppWidget': false,
        'hasHardwareVisualizer': false,
        'isVolumeBoostSupported': false,
        'isBassBoostSupported': false,
        'isDynamicsSupported': false,
        'isVirtualizerSupported': false,
      };
    }

    try {
      const channel = MethodChannel('com.pulsr.music/audio_effects');
      final caps = await channel.invokeMapMethod<String, dynamic>('getCapabilities');
      if (caps != null) {
        return caps.map((k, v) => MapEntry(k, v == true));
      }
    } catch (_) {}

    return {
      'hasEqualizer': true,
      'hasAudioEffects': true,
      'hasTagEditor': true,
      'hasRingtoneManager': true,
      'hasAppWidget': true,
      'hasHardwareVisualizer': true,
      'isVolumeBoostSupported': true,
      'isBassBoostSupported': true,
      'isDynamicsSupported': true,
      'isVirtualizerSupported': true,
    };
  }
}
