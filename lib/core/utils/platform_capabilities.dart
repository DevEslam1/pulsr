// lib/core/utils/platform_capabilities.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/channels.dart';

class AudioCapabilityMatrix {
  final int sdkInt;
  const AudioCapabilityMatrix(this.sdkInt);

  /// API 28+: DynamicsProcessing 10-band EQ (floor for Graphic EQ).
  bool get supportsDynamicsProcessing => sdkInt >= 28;

  /// API 29+: AudioTrack hardware offload (optional battery mode).
  /// NOTE: Offloaded tracks bypass AudioFlinger effects, which naturally bypasses
  /// device Dolby Atmos processing on vendors where Dolby sits in the HAL effect chain.
  bool get supportsHardwareOffload => sdkInt >= 29;

  /// API 31+: ENCODING_PCM_24BIT_PACKED / ENCODING_PCM_32BIT and LE Audio presence.
  bool get supportsExtendedPcmBitDepth => sdkInt >= 31;
  bool get hasLeAudioPresence => sdkInt >= 31;

  /// API 33+: Public BluetoothLeAudio / LC3 codec APIs and Spatializer APIs.
  bool get supportsLeAudioPublicApis => sdkInt >= 33;
  bool get supportsSpatializerApis => sdkInt >= 33;

  /// API 34: FGS dataSync 6h timeout cap (download resumption handled via SQLite).
  bool get usesFgsDataSync => sdkInt == 34;

  /// API 35+: FGS mediaProcessing for background transcoding and tagging.
  bool get usesFgsMediaProcessing => sdkInt >= 35;

  /// API 36 (Android 16): Modern track open, float path, effect session routing.
  bool get isAndroid16OrHigher => sdkInt >= 36;
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

  static AudioCapabilityMatrix getAudioCapabilities([int? sdkInt]) {
    return AudioCapabilityMatrix(sdkInt ?? 33);
  }

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
