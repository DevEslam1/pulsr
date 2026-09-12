// test/dop_dsd_test.dart
//
// Hermetic DoP (DSD over PCM) tests. No platform channels, no native code:
// only the pure framing math in DopEncoder and the capability math in
// DsdDacCapabilities are exercised.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dop_encoder.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';

const int dopMarkerA = DopEncoder.dopMarkerA; // 0x05
const int dopMarkerB = DopEncoder.dopMarkerB; // 0xFA

/// 6 bytes per channel => 3 16-bit DSD pairs. Interleaved so an L/R swap or a
/// marker misplacement cannot pass by coincidence.
final Uint8List _dsdL =
    Uint8List.fromList([0x11, 0x22, 0x33, 0x44, 0x55, 0x66]);
final Uint8List _dsdR =
    Uint8List.fromList([0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6]);

void main() {
  group('DopEncoder 24-bit framing', () {
    test('stereo interleave + alternating 0x05/0xFA markers', () {
      final dop = DopEncoder.encodeToDopPcm24(dsdLeft: _dsdL, dsdRight: _dsdR);

      // 3 frames per channel * (2 DSD bytes + 1 marker) * 2 channels = 18.
      expect(dop.length, 18);

      for (int i = 0; i < 3; i++) {
        final base = i * 6;
        final marker = i.isEven ? dopMarkerA : dopMarkerB;

        // Left: DSD0, DSD1, marker (little-endian 24-bit).
        expect(dop[base + 0], _dsdL[i * 2], reason: 'L byte 0 frame $i');
        expect(dop[base + 1], _dsdL[i * 2 + 1], reason: 'L byte 1 frame $i');
        expect(dop[base + 2], marker, reason: 'L marker frame $i');

        // Right: DSD0, DSD1, marker.
        expect(dop[base + 3], _dsdR[i * 2], reason: 'R byte 0 frame $i');
        expect(dop[base + 4], _dsdR[i * 2 + 1], reason: 'R byte 1 frame $i');
        expect(dop[base + 5], marker, reason: 'R marker frame $i');
      }
    });

    test('marker alternation starts on 0x05 and toggles every frame', () {
      final dop = DopEncoder.encodeToDopPcm24(dsdLeft: _dsdL, dsdRight: _dsdR);
      expect([dop[2], dop[8], dop[14]], [dopMarkerA, dopMarkerB, dopMarkerA]);
      expect([dop[5], dop[11], dop[17]], [dopMarkerA, dopMarkerB, dopMarkerA]);
    });
  });

  group('DopEncoder 32-bit framing', () {
    test('zero-padded 32-bit containers + alternating markers', () {
      final dop = DopEncoder.encodeToDopPcm32(dsdLeft: _dsdL, dsdRight: _dsdR);

      // 3 frames per channel * 4 bytes * 2 channels = 24.
      expect(dop.length, 24);

      for (int i = 0; i < 3; i++) {
        final base = i * 8;
        final marker = i.isEven ? dopMarkerA : dopMarkerB;

        // Left: pad, DSD0, DSD1, marker.
        expect(dop[base + 0], 0x00, reason: 'L pad frame $i');
        expect(dop[base + 1], _dsdL[i * 2], reason: 'L byte 0 frame $i');
        expect(dop[base + 2], _dsdL[i * 2 + 1], reason: 'L byte 1 frame $i');
        expect(dop[base + 3], marker, reason: 'L marker frame $i');

        // Right: pad, DSD0, DSD1, marker.
        expect(dop[base + 4], 0x00, reason: 'R pad frame $i');
        expect(dop[base + 5], _dsdR[i * 2], reason: 'R byte 0 frame $i');
        expect(dop[base + 6], _dsdR[i * 2 + 1], reason: 'R byte 1 frame $i');
        expect(dop[base + 7], marker, reason: 'R marker frame $i');
      }
    });
  });

  group('DoP length / carrier-rate math', () {
    test('DSD64/128/256 map to their carrier PCM rates', () {
      expect(DopEncoder.dopPcmSampleRate(64), 176400);
      expect(DopEncoder.dopPcmSampleRate(128), 352800);
      expect(DopEncoder.dopPcmSampleRate(256), 705600);
    });

    test('unsupported rates are rejected instead of fabricated', () {
      expect(DopEncoder.dopPcmSampleRate(512), 0);
      expect(DopEncoder.dopPcmSampleRate(0), 0);
      expect(DopEncoder.dopPcmSampleRate(-64), 0);
    });

    test('24-bit output is 3x the DSD byte count (stereo, 2:1 packing)', () {
      final four = Uint8List(4);
      final eight = Uint8List(8);
      expect(
        DopEncoder.encodeToDopPcm24(dsdLeft: four, dsdRight: four).length,
        12,
      );
      expect(
        DopEncoder.encodeToDopPcm24(dsdLeft: eight, dsdRight: eight).length,
        24,
      );
    });

    test('32-bit output is 4x the DSD byte count', () {
      final four = Uint8List(4);
      final eight = Uint8List(8);
      expect(
        DopEncoder.encodeToDopPcm32(dsdLeft: four, dsdRight: four).length,
        16,
      );
      expect(
        DopEncoder.encodeToDopPcm32(dsdLeft: eight, dsdRight: eight).length,
        32,
      );
    });
  });

  group('DopEncoder invalid input', () {
    test('24-bit rejects an odd DSD byte length', () {
      expect(
        () => DopEncoder.encodeToDopPcm24(
          dsdLeft: Uint8List(3),
          dsdRight: Uint8List(3),
        ),
        throwsArgumentError,
      );
    });

    test('24-bit rejects mismatched channel lengths', () {
      expect(
        () => DopEncoder.encodeToDopPcm24(
          dsdLeft: Uint8List(4),
          dsdRight: Uint8List(2),
        ),
        throwsArgumentError,
      );
    });

    test('32-bit rejects an odd DSD byte length', () {
      expect(
        () => DopEncoder.encodeToDopPcm32(
          dsdLeft: Uint8List(5),
          dsdRight: Uint8List(5),
        ),
        throwsArgumentError,
      );
    });

    test('32-bit rejects mismatched channel lengths', () {
      expect(
        () => DopEncoder.encodeToDopPcm32(
          dsdLeft: Uint8List(2),
          dsdRight: Uint8List(6),
        ),
        throwsArgumentError,
      );
    });
  });

  group('DsdDacCapabilities honesty gates', () {
    test('empty probe result cannot enable DoP', () {
      expect(DsdDacCapabilities.none.dop, isFalse);
      expect(DsdDacCapabilities.none.canUseDop, isFalse);
      expect(DsdDacCapabilities.none.supportsRate(64), isFalse);
      expect(DsdDacCapabilities.none.supportsRate(128), isFalse);
      expect(DsdDacCapabilities.none.supportsRate(256), isFalse);
    });

    test('DoP requires a DAC and at least one advertised carrier rate', () {
      const dopButNoRates = DsdDacCapabilities(
        dsd64: false,
        dsd128: false,
        dsd256: false,
        dop: true,
        nativeDac: true,
      );
      expect(dopButNoRates.canUseDop, isFalse);

      const dsd64Only = DsdDacCapabilities(
        dsd64: true,
        dsd128: false,
        dsd256: false,
        dop: true,
        nativeDac: true,
      );
      expect(dsd64Only.canUseDop, isTrue);
      expect(dsd64Only.supportsRate(64), isTrue);
      expect(dsd64Only.supportsRate(128), isFalse);
      expect(dsd64Only.supportsRate(256), isFalse);
      expect(dsd64Only.supportsRate(512), isFalse);
    });
  });
}
