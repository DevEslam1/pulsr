// lib/domain/models/reverb_preset.dart

/// Room shapes the native convolution reverb can synthesize.
///
/// The ordinals are the wire format for `setReverbPreset` and MUST match
/// `ReverbPreset` in `android/app/src/main/cpp/ConvolutionReverb.h`. The RT60
/// values in the labels come from `PreparedIr::createSynthetic`.
///
/// [custom] is not synthesizable — it means "an impulse response the user
/// loaded", so `createSynthetic` returns null for it and the previously loaded
/// IR is kept. Never send a synthesizable ordinal after loading a custom IR or
/// the synthetic one replaces it.
enum ReverbPreset {
  studio('Studio', 0.35),
  room('Room', 0.85),
  chamber('Chamber', 1.40),
  hall('Hall', 2.20),
  concertHall('Concert Hall', 3.20),
  cathedral('Cathedral', 5.00),
  plate('Plate', 1.80),
  spring('Spring', 1.10),
  custom('Custom IR', 0.0);

  const ReverbPreset(this.label, this.rt60Seconds);

  /// Chip label shown in the reverb card.
  final String label;

  /// Decay time of the synthetic IR, 0 for [custom].
  final double rt60Seconds;

  /// The ordinal sent across the method channel.
  int get wireValue => index;

  static ReverbPreset fromWireValue(int value) =>
      (value >= 0 && value < ReverbPreset.values.length)
          ? ReverbPreset.values[value]
          : ReverbPreset.studio;
}
