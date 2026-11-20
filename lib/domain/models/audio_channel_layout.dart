// lib/domain/models/audio_channel_layout.dart
//
// Explicit multichannel speaker layouts. The channel order must match the
// Android/Media3 AudioTrack mask that the sink actually opens:
//   3 ch -> FL/FR/FC   (CHANNEL_OUT_STEREO | FRONT_CENTER)
//   4 ch -> FL/FR/BL/BR (CHANNEL_OUT_QUAD)
//   6 ch -> FL/FR/FC/LFE/BL/BR (CHANNEL_OUT_5POINT1)
//   8 ch -> FL/FR/FC/LFE/BL/BR/SL/SR (CHANNEL_OUT_7POINT1_SURROUND)
// A true 2.1 (FL/FR/LFE) is therefore not offered on the 3-channel AudioTrack
// mask; 3 ch is 3.0, not 2.1. LFE layouts are 5.1/7.1.
enum AudioChannelLayout {
  stereo(
    channelCount: 2,
    lfeIndex: -1,
    displayName: '2.0',
    labels: ['FL', 'FR'],
  ),
  threeZero(
    channelCount: 3,
    lfeIndex: -1,
    displayName: '3.0',
    labels: ['FL', 'FR', 'FC'],
  ),
  quad(
    channelCount: 4,
    lfeIndex: -1,
    displayName: '4.0',
    labels: ['FL', 'FR', 'BL', 'BR'],
  ),
  fiveOne(
    channelCount: 6,
    lfeIndex: 3,
    displayName: '5.1',
    labels: ['FL', 'FR', 'FC', 'LFE', 'BL', 'BR'],
  ),
  sevenOne(
    channelCount: 8,
    lfeIndex: 3,
    displayName: '7.1',
    labels: ['FL', 'FR', 'FC', 'LFE', 'BL', 'BR', 'SL', 'SR'],
  );

  const AudioChannelLayout({
    required this.channelCount,
    required this.lfeIndex,
    required this.displayName,
    required this.labels,
  });

  final int channelCount;

  /// -1 when the layout has no dedicated LFE channel.
  final int lfeIndex;
  final String displayName;
  final List<String> labels;

  bool get hasLfe => lfeIndex >= 0;

  /// Layouts the trim/delay/LFE card offers. 3 ch is 3.0, not 2.1.
  static const List<AudioChannelLayout> offered = [
    threeZero,
    quad,
    fiveOne,
    sevenOne,
  ];

  static AudioChannelLayout? fromChannelCount(int? channels) {
    switch (channels) {
      case 2:
        return stereo;
      case 3:
        return threeZero;
      case 4:
        return quad;
      case 6:
        return fiveOne;
      case 8:
        return sevenOne;
    }
    return null;
  }

  /// Full speaker name for the per-channel trim/delay row.
  String fullNameAt(int channel) {
    final label = channel < labels.length ? labels[channel] : 'CH $channel';
    switch (label) {
      case 'FL':
        return 'Front Left (FL)';
      case 'FR':
        return 'Front Right (FR)';
      case 'FC':
        return 'Front Center (FC)';
      case 'LFE':
        return 'Low-Frequency Effects (LFE)';
      case 'BL':
        return 'Back Left (BL)';
      case 'BR':
        return 'Back Right (BR)';
      case 'SL':
        return 'Side Left (SL)';
      case 'SR':
        return 'Side Right (SR)';
    }
    return label;
  }

  String labelAt(int channel) =>
      channel < labels.length ? labels[channel] : 'CH $channel';

  /// Why the 3-channel layout is 3.0 rather than 2.1.
  static const String twoOnePlatformNote =
      'Android routes 3-channel AudioTrack as FL/FR/FC (3.0), not FL/FR/LFE. '
      'Use 5.1 or 7.1 for a dedicated LFE channel.';
}
