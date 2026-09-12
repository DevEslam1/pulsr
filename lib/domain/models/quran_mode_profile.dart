// lib/domain/models/quran_mode_profile.dart
import 'audio_effects_config.dart';
import 'eq_preset.dart';
import 'reverb_preset.dart';

/// The recitation "moods" Quran Mode can target.
///
/// Every style resolves to a [QuranModeProfile] whose fields map onto DSP
/// stages that actually exist in `libpulsr_dsp` (parametric EQ, convolution
/// reverb, harmonic saturation, dynamics/limiter). There is deliberately no
/// "noise reduction" or "breath reduction" field: the native engine has no
/// spectral denoiser / gate / de-esser stage. Sibilance control is expressed
/// through the EQ (a high-shelf cut on the 8 k / 16 k bands), which is the
/// honest approximation available today.
enum QuranReciterStyle {
  murattal(
    'Murattal',
    'Clear & measured',
    'Balanced presence for everyday recitation',
  ),
  mujawwad(
    'Mujawwad',
    'Melodic & ornamental',
    'Warmth and room for melodic phrasing',
  ),
  tarawih(
    'Tarawih',
    'Extended recitation',
    'Spacious, comfortable long sessions',
  ),
  memorization(
    'Memorization',
    'Slow & precise',
    'Maximum clarity at a slower pace',
  ),
  sleepMode(
    'Sleep',
    'Soft & warm',
    'Gentle, low-fatigue bedtime listening',
  ),
  studyMode(
    'Study & Tajweed',
    'Articulation',
    'Highlights makharij and consonants',
  );

  const QuranReciterStyle(this.label, this.tagline, this.description);

  final String label;
  final String tagline;
  final String description;
}

/// A fully-resolved Quran audio profile.
///
/// [eqGains] are 10-band gains in dB aligned to [EqPreset.centerFrequencies]
/// (32 Hz … 16 kHz), so they can be handed straight to [EqPreset].
class QuranModeProfile {
  final QuranReciterStyle style;
  final List<double> eqGains;

  final bool reverbEnabled;
  final ReverbPreset reverbPreset;
  final double reverbWetDry;

  final bool saturationEnabled;
  final double saturationDrive;
  final double saturationMix;
  final double saturationTilt;

  final bool dynamicsEnabled;
  final DynamicsPreset dynamicsPreset;

  /// Playback speed applied when the profile is activated.
  final double playbackSpeed;

  /// EQ preamp (dB) applied with the curve to leave headroom for boosts.
  final double preampDb;

  const QuranModeProfile({
    required this.style,
    required this.eqGains,
    this.reverbEnabled = true,
    this.reverbPreset = ReverbPreset.hall,
    this.reverbWetDry = 0.16,
    this.saturationEnabled = false,
    this.saturationDrive = 0.2,
    this.saturationMix = 0.3,
    this.saturationTilt = 0.3,
    this.dynamicsEnabled = true,
    this.dynamicsPreset = DynamicsPreset.vocalFocus,
    this.playbackSpeed = 1.0,
    this.preampDb = -1.0,
  });

  String get eqPresetName => 'Quran • ${style.label}';

  EqPreset toEqPreset([List<double>? gainsOverride]) => EqPreset(
        name: eqPresetName,
        gains: gainsOverride ?? eqGains,
      );

  static const Map<QuranReciterStyle, QuranModeProfile> presets = {
    QuranReciterStyle.murattal: QuranModeProfile(
      style: QuranReciterStyle.murattal,
      //             32    64    125   250   500   1k    2k    4k    8k    16k
      eqGains: [-2.0, -1.5, -1.0, 0.5, 1.5, 2.5, 3.5, 2.5, 0.5, -1.5],
      reverbEnabled: true,
      reverbPreset: ReverbPreset.room,
      reverbWetDry: 0.12,
      dynamicsPreset: DynamicsPreset.vocalFocus,
    ),
    QuranReciterStyle.mujawwad: QuranModeProfile(
      style: QuranReciterStyle.mujawwad,
      eqGains: [-1.5, -1.0, -0.5, 1.0, 2.0, 2.0, 2.5, 1.5, 0.0, -2.0],
      reverbEnabled: true,
      reverbPreset: ReverbPreset.hall,
      reverbWetDry: 0.22,
      saturationEnabled: true,
      saturationDrive: 0.22,
      saturationMix: 0.32,
      saturationTilt: 0.35,
      dynamicsPreset: DynamicsPreset.warmAnalog,
      preampDb: -1.5,
    ),
    QuranReciterStyle.tarawih: QuranModeProfile(
      style: QuranReciterStyle.tarawih,
      eqGains: [-1.5, -1.0, -0.5, 0.5, 1.5, 2.0, 2.5, 1.5, 0.0, -2.0],
      reverbEnabled: true,
      reverbPreset: ReverbPreset.cathedral,
      reverbWetDry: 0.26,
      saturationEnabled: true,
      saturationDrive: 0.18,
      saturationMix: 0.26,
      saturationTilt: 0.3,
      dynamicsPreset: DynamicsPreset.warmAnalog,
      preampDb: -1.5,
    ),
    QuranReciterStyle.memorization: QuranModeProfile(
      style: QuranReciterStyle.memorization,
      eqGains: [-2.5, -2.0, -1.5, 0.0, 1.5, 3.0, 4.0, 3.0, 0.5, -2.0],
      reverbEnabled: false,
      reverbPreset: ReverbPreset.room,
      reverbWetDry: 0.0,
      dynamicsPreset: DynamicsPreset.vocalFocus,
      playbackSpeed: 0.75,
      preampDb: -2.0,
    ),
    QuranReciterStyle.sleepMode: QuranModeProfile(
      style: QuranReciterStyle.sleepMode,
      eqGains: [-1.0, -0.5, 0.0, 1.0, 1.5, 1.0, 0.5, 0.0, -1.0, -2.5],
      reverbEnabled: true,
      reverbPreset: ReverbPreset.hall,
      reverbWetDry: 0.3,
      saturationEnabled: true,
      saturationDrive: 0.15,
      saturationMix: 0.22,
      saturationTilt: 0.25,
      dynamicsPreset: DynamicsPreset.nightLeveller,
      preampDb: -2.0,
    ),
    QuranReciterStyle.studyMode: QuranModeProfile(
      style: QuranReciterStyle.studyMode,
      eqGains: [-2.0, -1.5, -1.0, 0.5, 1.5, 3.0, 3.5, 2.5, 0.5, -1.0],
      reverbEnabled: false,
      reverbPreset: ReverbPreset.room,
      reverbWetDry: 0.0,
      dynamicsPreset: DynamicsPreset.vocalFocus,
      preampDb: -1.5,
    ),
  };

  static QuranModeProfile forStyle(QuranReciterStyle style) =>
      presets[style] ?? presets[QuranReciterStyle.murattal]!;
}
