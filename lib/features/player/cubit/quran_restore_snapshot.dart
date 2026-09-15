import '../../../domain/models/audio_effects_config.dart';
import '../../../domain/models/eq_preset.dart';
import '../../../domain/models/headphone_profile.dart';

/// Captures the DSP settings that Quran Mode overrides so they can be restored
/// verbatim when the mode is switched off.
class QuranRestoreSnapshot {
  final EqPreset eqPreset;
  final bool isEqEnabled;
  final HeadphoneProfile? headphoneProfile;
  final bool isReverbEnabled;
  final int reverbPreset;
  final double reverbWetDry;
  final bool isDynamicsEnabled;
  final DynamicsPreset dynamicsPreset;
  final bool isSaturationEnabled;
  final double saturationDrive;
  final double saturationMix;
  final double saturationTilt;
  final double playbackSpeed;
  final bool isShuffle;
  final double preampDb;

  const QuranRestoreSnapshot({
    required this.eqPreset,
    required this.isEqEnabled,
    required this.headphoneProfile,
    required this.isReverbEnabled,
    required this.reverbPreset,
    required this.reverbWetDry,
    required this.isDynamicsEnabled,
    required this.dynamicsPreset,
    required this.isSaturationEnabled,
    required this.saturationDrive,
    required this.saturationMix,
    required this.saturationTilt,
    required this.playbackSpeed,
    required this.isShuffle,
    required this.preampDb,
  });

  Map<String, dynamic> toJson() => {
        'eqPreset': eqPreset.toJson(),
        'isEqEnabled': isEqEnabled,
        'headphoneProfile': headphoneProfile?.toJson(),
        'isReverbEnabled': isReverbEnabled,
        'reverbPreset': reverbPreset,
        'reverbWetDry': reverbWetDry,
        'isDynamicsEnabled': isDynamicsEnabled,
        'dynamicsPreset': dynamicsPreset.name,
        'isSaturationEnabled': isSaturationEnabled,
        'saturationDrive': saturationDrive,
        'saturationMix': saturationMix,
        'saturationTilt': saturationTilt,
        'playbackSpeed': playbackSpeed,
        'isShuffle': isShuffle,
        'preampDb': preampDb,
      };

  factory QuranRestoreSnapshot.fromJson(Map<String, dynamic> json) {
    final rawEq = json['eqPreset'];
    final rawProfile = json['headphoneProfile'];
    return QuranRestoreSnapshot(
      eqPreset: EqPreset.fromJson(
          rawEq is Map ? Map<String, dynamic>.from(rawEq) : const {}),
      isEqEnabled: json['isEqEnabled'] as bool? ?? false,
      headphoneProfile: rawProfile is Map
          ? HeadphoneProfile.fromJson(Map<String, dynamic>.from(rawProfile))
          : null,
      isReverbEnabled: json['isReverbEnabled'] as bool? ?? false,
      reverbPreset: (json['reverbPreset'] as num?)?.toInt() ?? 0,
      reverbWetDry: (json['reverbWetDry'] as num?)?.toDouble() ?? 0.20,
      isDynamicsEnabled: json['isDynamicsEnabled'] as bool? ?? false,
      dynamicsPreset: DynamicsPreset.values.firstWhere(
          (e) => e.name == json['dynamicsPreset'],
          orElse: () => DynamicsPreset.off),
      isSaturationEnabled: json['isSaturationEnabled'] as bool? ?? false,
      saturationDrive: (json['saturationDrive'] as num?)?.toDouble() ?? 0.3,
      saturationMix: (json['saturationMix'] as num?)?.toDouble() ?? 0.5,
      saturationTilt: (json['saturationTilt'] as num?)?.toDouble() ?? 0.3,
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      isShuffle: json['isShuffle'] as bool? ?? false,
      preampDb: (json['preampDb'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
