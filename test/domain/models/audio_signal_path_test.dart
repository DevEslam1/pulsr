// test/domain/models/audio_signal_path_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/telemetry/audio_session_log.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/audio_signal_path.dart';
import 'package:pulsr/domain/models/bit_perfect_state.dart';

/// A USB route capable of a verified chain; each test supplies the state that
/// decides whether it is one.
const _usbDacOutput = AudioOutputInfo(
  deviceName: 'FiiO KA17',
  isUsbDac: true,
  sampleRate: 96000,
  bitDepth: 24,
  decodedSampleRate: 96000,
  decodedBitDepth: 24,
  isBitPerfectActive: true,
  activeDeviceType: 'usb',
  usbAudioClass: 2,
);

void main() {
  group('AudioOutputInfo device capability serialization', () {
    test('round-trips supportedEncodings, channelCounts, and channelMasks', () {
      const entry = AudioDeviceEntry(
        id: 7,
        name: 'USB-C Adapter',
        type: 22,
        typeName: 'USB Headset',
        isCurrent: true,
        sampleRates: [44100, 48000, 96000, 192000, 384000],
        maxBitDepth: 32,
        supportedEncodings: ['16', '24', '32', 'float'],
        channelCounts: [2],
        channelMasks: [12],
      );
      final info = AudioOutputInfo(
        deviceName: 'USB-C Adapter',
        isUsbDac: true,
        sampleRate: 384000,
        bitDepth: 32,
        isBitPerfectActive: true,
        isDirectSupported: true,
        activeDeviceType: 'usb',
        usbAudioClass: 2,
        availableDevices: const [entry],
        supportedEncodings: const ['16', '24', '32', 'float'],
        supportedChannelCounts: const [2],
        supportedChannelMasks: const [12],
      );

      final roundTripped = AudioOutputInfo.fromMap(info.toMap());
      expect(roundTripped, equals(info));
      expect(roundTripped.supportedEncodings, ['16', '24', '32', 'float']);
      expect(roundTripped.supportedChannelCounts, [2]);
      expect(roundTripped.supportedChannelMasks, [12]);
      expect(roundTripped.availableDevices.single.supportedEncodings,
          ['16', '24', '32', 'float']);
    });
  });

  group('AudioOutputInfo integer-bypass observation', () {
    test('round-trips the flag, keeps it through copyWith and defaults it off',
        () {
      const info = AudioOutputInfo(
        deviceName: 'USB DAC',
        isUsbDac: true,
        sampleRate: 96000,
        bitDepth: 24,
        isBitPerfectActive: true,
        integerBypassActive: true,
      );

      expect(info.toMap()['integerBypassActive'], isTrue);
      expect(AudioOutputInfo.fromMap(info.toMap()).integerBypassActive, isTrue);
      expect(info.copyWith(bitDepth: 16).integerBypassActive, isTrue);
      expect(info.copyWith(integerBypassActive: false).integerBypassActive,
          isFalse);

      // A payload from a platform build that never observed the bypass must not
      // read as one: absence of evidence is not an integer path.
      final legacy = Map<String, dynamic>.from(info.toMap())
        ..remove('integerBypassActive');
      expect(AudioOutputInfo.fromMap(legacy).integerBypassActive, isFalse);
    });
  });

  group('AudioSignalPath across all 4 hardware output paths', () {
    test('1. 3.5mm Wired Headphone Jack path shows AAudio Direct PCM', () {
      final path = AudioSignalPath.fromOutputInfo(
        sourceCodec: 'FLAC',
        sourceSampleRate: 192000,
        sourceBitDepth: 24,
        aaudioEnabled: true,
        output: const AudioOutputInfo(
          deviceName: 'Wired Headphones',
          isUsbDac: false,
          sampleRate: 192000,
          bitDepth: 24,
          decodedSampleRate: 192000,
          decodedBitDepth: 24,
          decodedPcmEncoding: 21,
          isBitPerfectActive: false,
          isDirectSupported: true,
          activeDeviceType: 'wired',
          supportedEncodings: ['16', '24', 'float'],
          supportedChannelCounts: [2],
        ),
      );

      expect(path.routeCategory, 'wired');
      expect(path.routeLabel, '3.5mm Wired DAC');
      expect(path.decoderSummary, 'PCM 24-bit Packed (24-bit / 192 kHz)');
      expect(path.driverPath, 'AAudio Direct');
      expect(path.isDirectPath, isTrue);
      expect(path.toChainString(), contains('-> PCM 24-bit Packed'));
    });

    test('2. External USB-C DAC is UAC2 Isochronous but unverified without a state', () {
      final path = AudioSignalPath.fromOutputInfo(
        sourceCodec: 'WAV',
        sourceSampleRate: 384000,
        sourceBitDepth: 32,
        uac2DirectActive: true,
        output: const AudioOutputInfo(
          deviceName: 'FiiO KA17',
          isUsbDac: true,
          sampleRate: 384000,
          bitDepth: 32,
          decodedSampleRate: 384000,
          decodedBitDepth: 32,
          decodedPcmEncoding: 22,
          isBitPerfectActive: true,
          activeDeviceType: 'usb',
          usbAudioClass: 2,
        ),
      );

      expect(path.routeCategory, 'usb');
      expect(path.driverPath, 'Pulsr UAC2 Isochronous');
      // A direct route is not evidence that the bytes reached the DAC
      // unaltered: only a supplied BitPerfectState may say Bit-Perfect.
      expect(path.isBitPerfect, isFalse);
      expect(path.hardwareSummary, contains('384 kHz'));
      expect(path.hardwareSummary, contains('Direct PCM'));
      expect(path.hardwareSummary, isNot(contains('Bit-Perfect')));
    });

    test('3. USB-C Digital Audio adapter preserves encodings & channel caps', () {
      final path = AudioSignalPath.fromOutputInfo(
        sourceCodec: 'ALAC',
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        floatOutputEnabled: true,
        output: const AudioOutputInfo(
          deviceName: 'Apple USB-C Adapter',
          isUsbDac: true,
          sampleRate: 96000,
          bitDepth: 24,
          decodedSampleRate: 96000,
          decodedBitDepth: 24,
          decodedPcmEncoding: 4,
          isBitPerfectActive: false,
          isDirectSupported: true,
          activeDeviceType: 'usb',
          usbAudioClass: 0,
          supportedEncodings: ['16', '24', 'float'],
          supportedChannelCounts: [2],
        ),
      );

      expect(path.routeCategory, 'type_c');
      expect(path.deviceEncodings, ['16', '24', 'float']);
      expect(path.deviceChannelCounts, [2]);
      expect(path.decoderSummary, 'PCM Float 32 (24-bit / 96 kHz)');
      expect(path.driverPath, 'Media3 Float DSP');
    });

    test('4. Bluetooth Hi-Res path reports LDAC bitrate, sample rate, and depth', () {
      final path = AudioSignalPath.fromOutputInfo(
        sourceCodec: 'FLAC',
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        floatOutputEnabled: true,
        output: const AudioOutputInfo(
          deviceName: 'WH-1000XM5',
          isUsbDac: false,
          sampleRate: 96000,
          bitDepth: 24,
          decodedSampleRate: 96000,
          decodedBitDepth: 24,
          decodedPcmEncoding: 4,
          isBitPerfectActive: false,
          isBluetooth: true,
          activeDeviceType: 'bluetooth',
          btCodecName: 'LDAC',
          btSampleRateHz: 96000,
          btBitDepth: 24,
          btEstimatedBitrateKbps: 990,
        ),
      );

      expect(path.routeCategory, 'bluetooth');
      expect(path.routeLabel, 'Bluetooth (LDAC • 990 kbps)');
      expect(path.hardwareSampleRate, 96000);
      expect(path.hardwareBitDepth, 24);
      expect(path.hardwareSummary, contains('Lossy A2DP/LE'));
    });
  });

  group('AudioSignalPath status tag follows the supplied BitPerfectState', () {
    test('a verified state tags the endpoint Bit-Perfect', () {
      final state = resolveBitPerfectState(
        requested: true,
        sinkActive: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        sinkSampleRate: 96000,
        sinkBitDepth: 24,
        exclusive: true,
        integerBypass: true,
        halClean: true,
        unityGain: true,
      );
      expect(state.tier, BitPerfectTier.active);

      final path = AudioSignalPath.fromOutputInfo(
        sourceCodec: 'FLAC',
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        output: _usbDacOutput,
        bitPerfectState: state,
      );

      expect(path.isBitPerfect, isTrue);
      expect(path.hardwareSummary, contains('Bit-Perfect'));
      expect(path.driverPath, 'USB Exclusive Mixer');
    });

    test('a degraded state tags the endpoint Exclusive / Unverified', () {
      final state = resolveBitPerfectState(
        requested: true,
        sinkActive: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        sinkSampleRate: 96000,
        sinkBitDepth: 24,
        // Exclusive, but no observed integer bypass: the samples were
        // re-quantised somewhere ahead of the sink.
        integerBypass: false,
        halClean: true,
        unityGain: true,
      );
      expect(state.tier, BitPerfectTier.degraded);

      final path = AudioSignalPath.fromOutputInfo(
        sourceCodec: 'FLAC',
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        output: _usbDacOutput,
        bitPerfectState: state,
      );

      expect(path.isBitPerfect, isFalse);
      expect(path.hardwareSummary, contains('Exclusive / Unverified'));
      expect(path.hardwareSummary, isNot(contains('Bit-Perfect')));
    });

    test('without a state no route claims Bit-Perfect', () {
      // AudioOutputInfo.isBitPerfectActive echoes the request, so it cannot
      // stand in for evidence when no state was supplied.
      final flagOnly = AudioSignalPath.fromOutputInfo(
        sourceCodec: 'FLAC',
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        output: _usbDacOutput,
      );
      expect(flagOnly.isBitPerfect, isFalse);
      expect(flagOnly.hardwareSummary, isNot(contains('Bit-Perfect')));

      final directRoute = AudioSignalPath.fromOutputInfo(
        sourceCodec: 'FLAC',
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        uac2DirectActive: true,
        output: _usbDacOutput,
      );
      // A direct route is a routing fact, not a measurement. Without a
      // supplied state the honest tag is Direct PCM, never Bit-Perfect.
      expect(directRoute.isBitPerfect, isFalse);
      expect(directRoute.hardwareSummary, contains('Direct PCM'));
      expect(directRoute.hardwareSummary, isNot(contains('Bit-Perfect')));
    });
  });

  group('AudioSessionRecord signal-path serialization', () {
    test('serializes and deserializes signal-path fields cleanly', () {
      final record = AudioSessionRecord(
        sessionId: 'sess_1',
        trackId: 't1',
        trackTitle: 'Track',
        startedAt: '2026-11-15T18:00:00Z',
        routeType: AudioRouteType.wired,
        sampleRate: 192000,
        bitDepth: 24,
        sourceCodec: 'FLAC',
        sourceSampleRate: 192000,
        sourceBitDepth: 24,
        decoderSampleRate: 192000,
        decoderBitDepth: 24,
        decoderEncoding: 'PCM Float 32',
        driverPath: 'AAudio Direct',
        isBitPerfect: false,
        signalPathSummary: 'A -> B -> C -> D',
      );
      final parsed = AudioSessionRecord.fromJson(record.toJson());
      expect(parsed.sourceCodec, 'FLAC');
      expect(parsed.decoderEncoding, 'PCM Float 32');
      expect(parsed.driverPath, 'AAudio Direct');
      expect(parsed.signalPathSummary, 'A -> B -> C -> D');
      expect(parsed.isBitPerfect, isFalse);
    });
  });
}
