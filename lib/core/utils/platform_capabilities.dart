// lib/core/utils/platform_capabilities.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/channels.dart';

@immutable
class AudioCapabilities {
  final bool hasEqualizer;
  final bool hasAudioEffects;
  final bool hasTagEditor;
  final bool hasRingtoneManager;
  final bool hasAppWidget;
  final bool hasHardwareVisualizer;
  final bool isVolumeBoostSupported;
  final bool isBassBoostSupported;
  final bool isDynamicsSupported;
  final bool isVirtualizerSupported;

  const AudioCapabilities({
    this.hasEqualizer = false,
    this.hasAudioEffects = false,
    this.hasTagEditor = false,
    this.hasRingtoneManager = false,
    this.hasAppWidget = false,
    this.hasHardwareVisualizer = false,
    this.isVolumeBoostSupported = false,
    this.isBassBoostSupported = false,
    this.isDynamicsSupported = false,
    this.isVirtualizerSupported = false,
  });

  factory AudioCapabilities.fromMap(Map<String, dynamic> map) {
    return AudioCapabilities(
      hasEqualizer: map['hasEqualizer'] == true || map['hasEqualizer'] == 1,
      hasAudioEffects: map['hasAudioEffects'] == true || map['hasAudioEffects'] == 1,
      hasTagEditor: map['hasTagEditor'] == true || map['hasTagEditor'] == 1,
      hasRingtoneManager: map['hasRingtoneManager'] == true || map['hasRingtoneManager'] == 1,
      hasAppWidget: map['hasAppWidget'] == true || map['hasAppWidget'] == 1,
      hasHardwareVisualizer: map['hasHardwareVisualizer'] == true || map['hasHardwareVisualizer'] == 1,
      isVolumeBoostSupported: map['isVolumeBoostSupported'] == true || map['isVolumeBoostSupported'] == 1,
      isBassBoostSupported: map['isBassBoostSupported'] == true || map['isBassBoostSupported'] == 1,
      isDynamicsSupported: map['isDynamicsSupported'] == true || map['isDynamicsSupported'] == 1,
      isVirtualizerSupported: map['isVirtualizerSupported'] == true || map['isVirtualizerSupported'] == 1,
    );
  }

  Map<String, bool> toMap() => {
        'hasEqualizer': hasEqualizer,
        'hasAudioEffects': hasAudioEffects,
        'hasTagEditor': hasTagEditor,
        'hasRingtoneManager': hasRingtoneManager,
        'hasAppWidget': hasAppWidget,
        'hasHardwareVisualizer': hasHardwareVisualizer,
        'isVolumeBoostSupported': isVolumeBoostSupported,
        'isBassBoostSupported': isBassBoostSupported,
        'isDynamicsSupported': isDynamicsSupported,
        'isVirtualizerSupported': isVirtualizerSupported,
      };
}

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

  static Future<AudioCapabilities> queryCapabilities() async {
    if (!isAndroid) {
      return const AudioCapabilities();
    }

    try {
      const channel = MethodChannel(PulsrChannels.audioEffects);
      final caps =
          await channel.invokeMapMethod<String, dynamic>('getCapabilities');
      if (caps != null) {
        return AudioCapabilities.fromMap(caps);
      }
    } catch (_) {}

    return const AudioCapabilities();
  }

  static Future<Map<String, bool>> queryNativeCapabilities() async {
    final caps = await queryCapabilities();
    return caps.toMap();
  }
}
