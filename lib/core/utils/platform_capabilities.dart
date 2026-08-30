// lib/core/utils/platform_capabilities.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/channels.dart';

class PlatformCapabilities {
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get hasEqualizer => isAndroid;
  static bool get hasAudioEffects => isAndroid;
  static bool get hasTagEditor => isAndroid;
  static bool get hasRingtoneManager => isAndroid;
  static bool get hasAppWidget => isAndroid;
  static bool get hasHardwareVisualizer => isAndroid;
  // Downloads are Android-only (native downloader + MediaStore + FGS dataSync)
  static bool get hasDownloads => isAndroid;
  static bool get hasYtm => isAndroid;

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
      const channel = MethodChannel(PulsrChannels.audioEffects);
      final caps = await channel
          .invokeMapMethod<String, dynamic>('getCapabilities')
          .timeout(const Duration(seconds: 2));
      if (caps != null) {
        return caps.map((k, v) => MapEntry(k, v == true || v == 1));
      }
    } catch (_) {}

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
}
