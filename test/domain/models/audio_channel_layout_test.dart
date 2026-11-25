// test/domain/models/audio_channel_layout_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/audio_channel_layout.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';

void main() {
  group('AudioChannelLayout', () {
    test('matches Android channel masks and LFE indices', () {
      expect(AudioChannelLayout.stereo.channelCount, 2);
      expect(AudioChannelLayout.threeZero.channelCount, 3);
      expect(AudioChannelLayout.threeZero.labels, ['FL', 'FR', 'FC']);
      expect(AudioChannelLayout.threeZero.hasLfe, isFalse);
      expect(AudioChannelLayout.quad.labels, ['FL', 'FR', 'BL', 'BR']);
      expect(AudioChannelLayout.quad.hasLfe, isFalse);
      expect(AudioChannelLayout.fiveOne.channelCount, 6);
      expect(AudioChannelLayout.fiveOne.lfeIndex, 3);
      expect(AudioChannelLayout.fiveOne.labels,
          ['FL', 'FR', 'FC', 'LFE', 'BL', 'BR']);
      expect(AudioChannelLayout.sevenOne.channelCount, 8);
      expect(AudioChannelLayout.sevenOne.lfeIndex, 3);
      expect(AudioChannelLayout.sevenOne.labels,
          ['FL', 'FR', 'FC', 'LFE', 'BL', 'BR', 'SL', 'SR']);
    });

    test('offers 3.0/4.0/5.1/7.1 and never claims 2.1 on 3 channels', () {
      expect(AudioChannelLayout.offered, [
        AudioChannelLayout.threeZero,
        AudioChannelLayout.quad,
        AudioChannelLayout.fiveOne,
        AudioChannelLayout.sevenOne,
      ]);
      expect(AudioChannelLayout.twoOnePlatformNote, contains('3.0'));
      expect(AudioChannelLayout.fromChannelCount(3)!.displayName, '3.0');
      expect(AudioChannelLayout.fromChannelCount(4)!.displayName, '4.0');
      expect(AudioChannelLayout.fromChannelCount(6)!.displayName, '5.1');
      expect(AudioChannelLayout.fromChannelCount(8)!.displayName, '7.1');
      expect(AudioChannelLayout.fromChannelCount(5), isNull);
    });

    test('full names follow the layout, not a fixed 7.1 list', () {
      expect(AudioChannelLayout.quad.fullNameAt(2), 'Back Left (BL)');
      expect(AudioChannelLayout.quad.fullNameAt(3), 'Back Right (BR)');
      expect(AudioChannelLayout.sevenOne.fullNameAt(6), 'Side Left (SL)');
      expect(AudioChannelLayout.sevenOne.fullNameAt(7), 'Side Right (SR)');
    });
  });

  group('AudioOutputInfo multichannel gating', () {
    AudioOutputInfo info({
      int decodedChannels = 2,
      int outputChannels = 0,
      List<int> supported = const [2],
    }) =>
        AudioOutputInfo(
          deviceName: 'Test',
          isUsbDac: false,
          sampleRate: 48000,
          bitDepth: 24,
          isBitPerfectActive: false,
          decodedChannelCount: decodedChannels,
          outputChannels: outputChannels,
          supportedChannelCounts: supported,
        );

    test('the sink channel count is the truth', () {
      expect(info(outputChannels: 6).hasMultichannelOutput, isTrue);
      expect(
          info(outputChannels: 2, decodedChannels: 6, supported: [6])
              .hasMultichannelOutput,
          isFalse);
    });

    test(
        'falls back to a proven device + decoded count when the sink is unprobed',
        () {
      expect(info(decodedChannels: 6, supported: [2, 6]).hasMultichannelOutput,
          isTrue);
      expect(info(decodedChannels: 6, supported: [2]).hasMultichannelOutput,
          isFalse);
      expect(info(decodedChannels: 2, supported: [6]).hasMultichannelOutput,
          isFalse);
    });
  });
}
