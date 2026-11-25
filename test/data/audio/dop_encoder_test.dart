// test/data/audio/dop_encoder_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dop_encoder.dart';

String? _findHostDopTestLib() {
  final candidates = <String>[
    'android/app/build/testNative/Release/pulsr_dop_test.dll',
    'android/app/build/testNative/Release/libpulsr_dop_test.so',
    'android/app/build/testNative/Release/libpulsr_dop_test.dylib',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

void main() {
  group('DopEncoder tests', () {
    test('encodeToDopPcm24 alternates markers 0x05 and 0xFA correctly', () {
      // 4 bytes of DSD per channel = 2 24-bit samples per channel = 12 output bytes
      final dsdL = Uint8List.fromList([0xAA, 0x55, 0x11, 0x22]);
      final dsdR = Uint8List.fromList([0x33, 0x44, 0x66, 0x77]);

      final dop24 = DopEncoder.encodeToDopPcm24(dsdLeft: dsdL, dsdRight: dsdR);
      expect(dop24.length, equals(12));

      // Sample 0: Left [newer 0x55, older 0xAA, Marker 0x05],
      // Right [newer 0x44, older 0x33, Marker 0x05]. DoP 1.1 stores the
      // 24-bit word [marker | older | newer] little-endian, so the later DSD
      // byte precedes the earlier one on disk.
      expect(dop24[0], equals(0x55));
      expect(dop24[1], equals(0xAA));
      expect(dop24[2], equals(0x05));

      expect(dop24[3], equals(0x44));
      expect(dop24[4], equals(0x33));
      expect(dop24[5], equals(0x05));

      // Sample 1: Left [0x22, 0x11, Marker 0xFA], Right [0x77, 0x66, 0xFA]
      expect(dop24[6], equals(0x22));
      expect(dop24[7], equals(0x11));
      expect(dop24[8], equals(0xFA));

      expect(dop24[9], equals(0x77));
      expect(dop24[10], equals(0x66));
      expect(dop24[11], equals(0xFA));
    });

    test(
        'encodeToDopPcm32 outputs 32-bit zero-padded containers with DoP markers',
        () {
      final dsdL = Uint8List.fromList([0xAA, 0x55]);
      final dsdR = Uint8List.fromList([0x33, 0x44]);

      final dop32 = DopEncoder.encodeToDopPcm32(dsdLeft: dsdL, dsdRight: dsdR);
      expect(dop32.length, equals(8));

      // Left: 0x00, 0x55, 0xAA, 0x05
      expect(dop32[0], equals(0x00));
      expect(dop32[1], equals(0x55));
      expect(dop32[2], equals(0xAA));
      expect(dop32[3], equals(0x05));

      // Right: 0x00, 0x44, 0x33, 0x05
      expect(dop32[4], equals(0x00));
      expect(dop32[5], equals(0x44));
      expect(dop32[6], equals(0x33));
      expect(dop32[7], equals(0x05));
    });

    test('reverseBits converts LSB-first bytes to MSB-first inline', () {
      // 0x80 reversed = 0x01, 0x01 reversed = 0x80, 0xB4 reversed = 0x2D, 0x0F reversed = 0xF0
      final dsdL = Uint8List.fromList([0x80, 0x01, 0xB4, 0x0F]);
      final dsdR = Uint8List.fromList([0x02, 0x40, 0xC3, 0x5A]);

      final dop24 = DopEncoder.encodeToDopPcm24(
        dsdLeft: dsdL,
        dsdRight: dsdR,
        reverseBits: true,
      );
      expect(
        dop24,
        equals(Uint8List.fromList([
          0x80,
          0x01,
          0x05,
          0x02,
          0x40,
          0x05,
          0xF0,
          0x2D,
          0xFA,
          0x5A,
          0xC3,
          0xFA,
        ])),
      );

      final dop32 = DopEncoder.encodeToDopPcm32(
        dsdLeft: dsdL,
        dsdRight: dsdR,
        reverseBits: true,
        firstMarker: DopEncoder.dopMarkerB,
      );
      expect(
        dop32,
        equals(Uint8List.fromList([
          0x00,
          0x80,
          0x01,
          0xFA,
          0x00,
          0x02,
          0x40,
          0xFA,
          0x00,
          0xF0,
          0x2D,
          0x05,
          0x00,
          0x5A,
          0xC3,
          0x05,
        ])),
      );
    });

    test('handles empty input and rejects invalid firstMarker', () {
      expect(
        DopEncoder.encodeToDopPcm24(
          dsdLeft: Uint8List(0),
          dsdRight: Uint8List(0),
        ),
        isEmpty,
      );
      expect(
        () => DopEncoder.encodeToDopPcm24(
          dsdLeft: Uint8List(2),
          dsdRight: Uint8List(2),
          firstMarker: 0x00,
        ),
        throwsArgumentError,
      );
    });

    test('native C++ DopFramer and Dart fallback produce identical bytes', () {
      final libPath = _findHostDopTestLib();
      if (libPath == null) {
        return;
      }

      addTearDown(() {
        DopEncoder.forceDartFallbackForTesting = false;
        DopEncoder.setNativeLibraryPathForTesting(null);
      });

      final rng = Random(42);
      // > 2 MiB per channel forces multi-chunk FFI transfer and nextMarker carry.
      const largeBytes = 2 * 1024 * 1024 + 6;
      final largeL = Uint8List.fromList(
        List<int>.generate(largeBytes, (_) => rng.nextInt(256)),
      );
      final largeR = Uint8List.fromList(
        List<int>.generate(largeBytes, (_) => rng.nextInt(256)),
      );
      final smallL = Uint8List.fromList([0xAA, 0x55, 0x11, 0x22, 0x80, 0x01]);
      final smallR = Uint8List.fromList([0x33, 0x44, 0x66, 0x77, 0x02, 0x40]);

      for (final bits in [24, 32]) {
        for (final rev in [false, true]) {
          for (final marker in [DopEncoder.dopMarkerA, DopEncoder.dopMarkerB]) {
            for (final pair in [(smallL, smallR), (largeL, largeR)]) {
              DopEncoder.setNativeLibraryPathForTesting(libPath);
              DopEncoder.forceDartFallbackForTesting = false;
              final nativeOut = bits == 24
                  ? DopEncoder.encodeToDopPcm24(
                      dsdLeft: pair.$1,
                      dsdRight: pair.$2,
                      reverseBits: rev,
                      firstMarker: marker,
                    )
                  : DopEncoder.encodeToDopPcm32(
                      dsdLeft: pair.$1,
                      dsdRight: pair.$2,
                      reverseBits: rev,
                      firstMarker: marker,
                    );

              DopEncoder.forceDartFallbackForTesting = true;
              final dartOut = bits == 24
                  ? DopEncoder.encodeToDopPcm24(
                      dsdLeft: pair.$1,
                      dsdRight: pair.$2,
                      reverseBits: rev,
                      firstMarker: marker,
                    )
                  : DopEncoder.encodeToDopPcm32(
                      dsdLeft: pair.$1,
                      dsdRight: pair.$2,
                      reverseBits: rev,
                      firstMarker: marker,
                    );

              expect(
                nativeOut,
                equals(dartOut),
                reason:
                    'Mismatch for bits=$bits rev=$rev marker=$marker len=${pair.$1.length}',
              );
            }
          }
        }
      }
    });
  });
}
