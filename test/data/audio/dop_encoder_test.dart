// test/data/audio/dop_encoder_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dop_encoder.dart';

void main() {
  group('DopEncoder tests', () {
    test('encodeToDopPcm24 alternates markers 0x05 and 0xFA correctly', () {
      // 4 bytes of DSD per channel = 2 24-bit samples per channel = 12 output bytes
      final dsdL = Uint8List.fromList([0xAA, 0x55, 0x11, 0x22]);
      final dsdR = Uint8List.fromList([0x33, 0x44, 0x66, 0x77]);

      final dop24 = DopEncoder.encodeToDopPcm24(dsdLeft: dsdL, dsdRight: dsdR);
      expect(dop24.length, equals(12));

      // Sample 0: Left [0xAA, 0x55, Marker 0x05], Right [0x33, 0x44, Marker 0x05]
      expect(dop24[0], equals(0xAA));
      expect(dop24[1], equals(0x55));
      expect(dop24[2], equals(0x05));

      expect(dop24[3], equals(0x33));
      expect(dop24[4], equals(0x44));
      expect(dop24[5], equals(0x05));

      // Sample 1: Left [0x11, 0x22, Marker 0xFA], Right [0x66, 0x77, Marker 0xFA]
      expect(dop24[6], equals(0x11));
      expect(dop24[7], equals(0x22));
      expect(dop24[8], equals(0xFA));

      expect(dop24[9], equals(0x66));
      expect(dop24[10], equals(0x77));
      expect(dop24[11], equals(0xFA));
    });

    test(
        'encodeToDopPcm32 outputs 32-bit zero-padded containers with DoP markers',
        () {
      final dsdL = Uint8List.fromList([0xAA, 0x55]);
      final dsdR = Uint8List.fromList([0x33, 0x44]);

      final dop32 = DopEncoder.encodeToDopPcm32(dsdLeft: dsdL, dsdRight: dsdR);
      expect(dop32.length, equals(8));

      // Left: 0x00, 0xAA, 0x55, 0x05
      expect(dop32[0], equals(0x00));
      expect(dop32[1], equals(0xAA));
      expect(dop32[2], equals(0x55));
      expect(dop32[3], equals(0x05));

      // Right: 0x00, 0x33, 0x44, 0x05
      expect(dop32[4], equals(0x00));
      expect(dop32[5], equals(0x33));
      expect(dop32[6], equals(0x44));
      expect(dop32[7], equals(0x05));
    });
  });
}
