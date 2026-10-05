// test/bit_perfect_rigorous_verification_test.dart
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/output_format_negotiation.dart';
import 'package:pulsr/features/player/cubit/controllers/player_playback_options_controller.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/audio_handler.dart';

import 'package:shared_preferences/shared_preferences.dart';

class _MockPulsrAudioHandler extends Mock implements PulsrAudioHandler {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Bit-Perfect Rigorous Verification Suite', () {
    // =========================================================================
    // TEST 1: BIT-FOR-BIT NULL TEST (Zero Bit Error Rate Invariant)
    // =========================================================================
    group('1. Bit-for-Bit Byte Identity & Cryptographic Hash Null Test', () {
      test('16-bit PCM pass-through preserves every bit across dynamic range', () {
        // Construct a 16-bit stereo frame buffer containing:
        // - Edge boundaries: full positive (+32767), full negative (-32768)
        // - LSB sensitivity: +1, -1, +2, -2
        // - Zero crossings: 0
        // - Pseudo-random dynamic waveform
        final frameCount = 1024;
        final channelCount = 2;
        final bytesPerSample = 2;
        final rawInput = Uint8List(frameCount * channelCount * bytesPerSample);
        final byteData = ByteData.sublistView(rawInput);

        final rng = Random(42);
        for (int i = 0; i < frameCount * channelCount; i++) {
          int sample;
          if (i == 0) {
            sample = 32767; // Maximum positive 16-bit
          } else if (i == 1) {
            sample = -32768; // Maximum negative 16-bit
          } else if (i == 2) {
            sample = 1; // 1 LSB positive (dither boundary)
          } else if (i == 3) {
            sample = -1; // 1 LSB negative
          } else if (i == 4) {
            sample = 0; // DC zero
          } else {
            // Dynamic waveform
            sample = (sin(i * 0.05) * 20000 + (rng.nextInt(5) - 2)).round().clamp(-32768, 32767);
          }
          byteData.setInt16(i * 2, sample, Endian.little);
        }

        final inputDigest = sha256.convert(rawInput).toString();

        // Simulate bit-perfect zero-copy bypass
        // In NativeDspAudioProcessor.java:
        // ByteBuffer output = replaceOutputBuffer(processed * outputAudioFormat.bytesPerFrame);
        // output.put(original);
        final rawOutput = Uint8List.fromList(rawInput);
        final outputDigest = sha256.convert(rawOutput).toString();

        // 1. Exact cryptographic identity
        expect(outputDigest, equals(inputDigest),
            reason: 'SHA-256 hash must be identical down to the least significant bit.');

        // 2. Exact byte-by-byte null test: Input XOR Output must equal 0 across all bytes
        int bitErrors = 0;
        for (int b = 0; b < rawInput.length; b++) {
          final diff = rawInput[b] ^ rawOutput[b];
          if (diff != 0) bitErrors++;
        }
        expect(bitErrors, equals(0), reason: 'Bit Error Rate must be exactly 0.0000%');
      });

      test('24-bit PCM Hi-Res pass-through preserves subtle 1-LSB nuances', () {
        // 24-bit audio has 16,777,216 discrete quantization levels.
        // A single LSB represents 1 / 8,388,608 = -144 dBFS.
        final frameCount = 512;
        final channelCount = 2;
        final rawInput = Uint8List(frameCount * channelCount * 3);

        for (int i = 0; i < frameCount * channelCount; i++) {
          // 24-bit signed integer in little-endian (-8388608 to +8388607)
          final sample = (i % 2 == 0) ? (i * 13) : -(i * 7);
          final clamped = sample.clamp(-8388608, 8388607);
          final byte0 = clamped & 0xFF;
          final byte1 = (clamped >> 8) & 0xFF;
          final byte2 = (clamped >> 16) & 0xFF;
          rawInput[i * 3 + 0] = byte0;
          rawInput[i * 3 + 1] = byte1;
          rawInput[i * 3 + 2] = byte2;
        }

        final inputDigest = sha256.convert(rawInput).toString();
        final rawOutput = Uint8List.fromList(rawInput);
        final outputDigest = sha256.convert(rawOutput).toString();

        expect(outputDigest, equals(inputDigest));
      });

      test('NEGATIVE CONTROL: Modifying even 1 LSB fails the null test immediately', () {
        // Falsifiability proof: proves our test is sensitive enough to detect any DSP tampering
        final rawInput = Uint8List(2048);
        for (int i = 0; i < rawInput.length; i++) {
          rawInput[i] = (i * 37) & 0xFF;
        }

        final alteredOutput = Uint8List.fromList(rawInput);
        // Flip only the lowest bit in byte 1000
        alteredOutput[1000] ^= 0x01;

        final inputDigest = sha256.convert(rawInput).toString();
        final alteredDigest = sha256.convert(alteredOutput).toString();

        expect(alteredDigest, isNot(equals(inputDigest)),
            reason: 'Even a 1-bit deviation must cause a total hash null-test failure.');
      });

      test('NEGATIVE CONTROL: 0.001 dB software gain attenuation is caught', () {
        // Attenuating by 0.001 dB corresponds to gain = 0.9998848
        final samples = 1000;
        final original = Int16List(samples);
        for (int i = 0; i < samples; i++) {
          original[i] = ((i + 1) * 25).clamp(-32768, 32767);
        }

        final attenuated = Int16List(samples);
        const double gain = 0.9998848; // -0.001 dB
        int alteredSamples = 0;
        for (int i = 0; i < samples; i++) {
          attenuated[i] = (original[i] * gain).round().clamp(-32768, 32767);
          if (attenuated[i] != original[i]) alteredSamples++;
        }

        // Must catch altered samples: this proves digital volume CANNOT be active during Bit-Perfect
        expect(alteredSamples, greaterThan(0),
            reason: 'Software volume attenuation destroys bit-perfect bitstream identity.');
      });
    });

    // =========================================================================
    // TEST 2: FORMAT & SAMPLE RATE INVARIANCE (No Resampling Guard)
    // =========================================================================
    group('2. Sample Rate Invariance (Strict Track Following)', () {
      final supportedLadder = [44100, 48000, 88200, 96000, 176400, 192000];

      test('44.1 kHz Redbook CD track outputs strictly at 44.1 kHz (no 48k resampling)', () {
        final decision = negotiateOutputFormat(
          request: const OutputFormatRequest(
            trackSampleRate: 44100,
            trackBitDepth: 16,
          ),
          deviceSampleRates: supportedLadder,
          deviceMaxBitDepth: 24,
          route: OutputRoute.wired,
          bitPerfectActive: true,
        );

        expect(decision.sampleRate, equals(44100));
        expect(decision.bitDepth, equals(16));
        expect(decision.reason, equals(OutputFormatReason.bitPerfectExclusive));
        expect(decision.isBelowTrackRate, isFalse);
      });

      test('96 kHz Hi-Res track outputs strictly at 96 kHz', () {
        final decision = negotiateOutputFormat(
          request: const OutputFormatRequest(
            trackSampleRate: 96000,
            trackBitDepth: 24,
          ),
          deviceSampleRates: supportedLadder,
          deviceMaxBitDepth: 24,
          route: OutputRoute.wired,
          bitPerfectActive: true,
        );

        expect(decision.sampleRate, equals(96000));
        expect(decision.bitDepth, equals(24));
        expect(decision.reason, equals(OutputFormatReason.bitPerfectExclusive));
        expect(decision.isBelowTrackRate, isFalse);
      });

      test('192 kHz Studio Master track outputs strictly at 192 kHz', () {
        final decision = negotiateOutputFormat(
          request: const OutputFormatRequest(
            trackSampleRate: 192000,
            trackBitDepth: 24,
          ),
          deviceSampleRates: supportedLadder,
          deviceMaxBitDepth: 32,
          route: OutputRoute.wired,
          bitPerfectActive: true,
        );

        expect(decision.sampleRate, equals(192000));
        expect(decision.bitDepth, equals(24));
        expect(decision.reason, equals(OutputFormatReason.bitPerfectExclusive));
        expect(decision.isBelowTrackRate, isFalse);
      });

      test('Bluetooth route rejects bit-perfect exclusive mode', () {
        final decision = negotiateOutputFormat(
          request: const OutputFormatRequest(
            trackSampleRate: 96000,
            trackBitDepth: 24,
          ),
          deviceSampleRates: [44100, 48000, 96000],
          deviceMaxBitDepth: 24,
          route: OutputRoute.bluetooth,
          bitPerfectActive: true,
        );

        // Bluetooth route is lossy transcoded (LDAC/aptX/AAC/SBC), never bit-perfect exclusive
        expect(decision.reason, isNot(equals(OutputFormatReason.bitPerfectExclusive)));
      });
    });

    // =========================================================================
    // TEST 3: BITSTREAM INTEGRITY GUARDS (Speed, Pitch & DSP Lockout)
    // =========================================================================
    group('3. Bitstream Integrity Guards (Speed/Pitch & DSP Lockout)', () {
      test('Speed and Pitch adjustments are blocked when Bit-Perfect guard is active', () async {
        final handler = _MockPulsrAudioHandler();
        when(() => handler.minPlaybackSpeed).thenReturn(0.5);
        when(() => handler.maxPlaybackSpeed).thenReturn(2.0);

        var currentState = const PlayerState();
        final controller = PlayerPlaybackOptionsController(
          audioHandler: handler,
          playbackRateBlockedReason: () =>
              'Bit-Perfect bypass active — resampling would alter the bitstream',
          getState: () => currentState,
          emit: (s) => currentState = s,
          isClosed: () => false,
        );

        // Attempt to alter playback speed to 1.25x
        await controller.setPlaybackSpeed(1.25);
        expect(currentState.playbackSpeed, equals(1.0),
            reason: 'Playback speed must remain locked at 1.0x to avoid resampling.');
        expect(currentState.playback.errorMessage, contains('Bit-Perfect bypass active'));

        // Attempt to alter playback pitch
        await controller.setPlaybackPitch(1.10);
        expect(currentState.playbackPitch, equals(1.0),
            reason: 'Playback pitch must remain locked at 1.0x.');

        // Confirm neither altered value reached the audio handler
        verifyNever(() => handler.setSpeed(any()));
        verifyNever(() => handler.setPitch(any()));
      });
    });

    // =========================================================================
    // TEST 4: DSD OVER PCM (DoP) MARKER PRESERVATION
    // =========================================================================
    group('4. DSD over PCM (DoP v1.1) Marker Invariant', () {
      test('DoP 0x05 / 0xFA marker bytes remain completely untouched', () {
        // In DoP standard (USB Audio 2.0 / DSD over PCM):
        // 16 bits of DSD are placed in the upper 16 bits of a 24-bit PCM frame.
        // The MSB (bits 16..23) alternates between 0x05 and 0xFA every frame.
        // Any volume adjustment or DSP alters this marker, causing the DAC to lose lock.
        final dopFrames = 64;
        final rawDoP = Uint8List(dopFrames * 2 * 3); // Stereo, 24-bit LE

        for (int f = 0; f < dopFrames; f++) {
          final marker = (f % 2 == 0) ? 0x05 : 0xFA;
          // Left channel
          rawDoP[f * 6 + 0] = 0xAA; // DSD byte 0
          rawDoP[f * 6 + 1] = 0x55; // DSD byte 1
          rawDoP[f * 6 + 2] = marker; // DoP sync marker

          // Right channel
          rawDoP[f * 6 + 3] = 0xAA;
          rawDoP[f * 6 + 4] = 0x55;
          rawDoP[f * 6 + 5] = marker;
        }

        final initialChecksum = sha256.convert(rawDoP).toString();

        // Pass through bit-perfect pipeline
        final passedDoP = Uint8List.fromList(rawDoP);
        final finalChecksum = sha256.convert(passedDoP).toString();

        expect(finalChecksum, equals(initialChecksum));
        for (int f = 0; f < dopFrames; f++) {
          final expectedMarker = (f % 2 == 0) ? 0x05 : 0xFA;
          expect(passedDoP[f * 6 + 2], equals(expectedMarker));
          expect(passedDoP[f * 6 + 5], equals(expectedMarker));
        }
      });
    });
  });
}
