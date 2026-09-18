// test/data/audio/non_android_degradation_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';

/// iOS-style degradation: every bool-returning native setter must report the
/// truth (unsupported / false) instead of falsely claiming the effect applied,
/// and DSD must fail with a handled, typed exception rather than a raw
/// UnsupportedError.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final channel = AudioEffectsChannel();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('AudioEffectsChannel non-Android bool setters', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    test('all bool-returning effect setters return false (not "applied")',
        () async {
      expect(await channel.setVolumeBoost(350), isFalse);
      expect(await channel.setBassBoost(500), isFalse);
      expect(await channel.setVirtualizerEnabled(true), isFalse);
      expect(await channel.setVirtualizerStrength(0.7), isFalse);
      expect(await channel.setDynamicsPreset(DynamicsPreset.studioPunch, true),
          isFalse);
      expect(await channel.setSpatializerEnabled(true), isFalse);
      expect(
          await channel.setReplayGainParams(
            mode: 1,
            trackGainDb: -3.0,
            albumGainDb: -2.0,
            trackPeak: 0.9,
            albumPeak: 0.95,
            preAmpDb: 0.0,
            enabled: true,
          ),
          isFalse);
      expect(await channel.setReplayGainEnabled(true), isFalse);
      expect(
          await channel.setDitherParams(
            enabled: true,
            targetBitDepth: 16,
            isBluetooth: false,
          ),
          isFalse);
    });

    test('non-bool probes are also honest on non-Android', () async {
      expect(await channel.hasActiveEffects(), isFalse);
      expect(await channel.loadImpulseResponse(const [1.0, 0.0, -1.0]), isFalse);
      expect(
          await channel.decodeDsd(
            Uint8List.fromList([1, 2, 3]),
            Uint8List.fromList([4, 5, 6]),
          ),
          isNull);
    });
  });

  group('DSD decode graceful failure on non-Android', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      DsdDecoderHelper.testDecoder = null;
    });

    tearDown(() {
      DsdDecoderHelper.testDecoder = null;
    });

    test('a null native decode surfaces DsdUnsupportedException, not a crash',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('dsd_non_android');
      addTearDown(() => tempDir.delete(recursive: true));
      final tempFile = File('${tempDir.path}/album_track.dsf');
      await tempFile.writeAsBytes(_minimalDsfBytes());

      final song = SongsTableData(
        id: 909,
        title: 'DSD on iOS',
        artist: 'Artist',
        album: 'Album',
        durationMs: 1000,
        path: tempFile.path,
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        isDownloaded: false,
      );

      // Must be a catchable Exception subtype — never an Error/UnsupportedError.
      final error = await _captureError(
        () => DsdDecoderHelper.decodeDsdFile(
          song,
          MediaItem(id: '909', title: 'DSD on iOS'),
        ),
      );
      expect(error, isA<DsdUnsupportedException>());
      expect(error, isNot(isA<UnsupportedError>()));
      expect((error as DsdUnsupportedException).message, isNotEmpty);
    });
  });
}

Future<Object> _captureError(Future<void> Function() body) async {
  try {
    await body();
  } catch (e) {
    return e;
  }
  fail('Expected the body to throw, but it completed normally');
}

/// Minimal but structurally valid DSF payload (header + 16 L / 16 R frames).
Uint8List _minimalDsfBytes() {
  final builder = BytesBuilder();
  builder.add(Uint8List.fromList([0x44, 0x53, 0x44, 0x20])); // 'DSD '
  final dsdHeader = ByteData(24);
  dsdHeader.setUint64(0, 28, Endian.little);
  dsdHeader.setUint64(8, 200, Endian.little);
  dsdHeader.setUint64(16, 0, Endian.little);
  builder.add(dsdHeader.buffer.asUint8List());

  builder.add(Uint8List.fromList([0x66, 0x6D, 0x74, 0x20])); // 'fmt '
  final fmtHeader = ByteData(48);
  fmtHeader.setUint64(0, 52, Endian.little);
  fmtHeader.setUint32(8, 1, Endian.little);
  fmtHeader.setUint32(12, 0, Endian.little);
  fmtHeader.setUint32(16, 2, Endian.little);
  fmtHeader.setUint32(20, 2, Endian.little);
  fmtHeader.setUint32(24, 2822400, Endian.little); // DSD64
  fmtHeader.setUint32(28, 1, Endian.little);
  fmtHeader.setUint64(32, 1000, Endian.little);
  fmtHeader.setUint32(40, 16, Endian.little);
  builder.add(fmtHeader.buffer.asUint8List());

  builder.add(Uint8List.fromList([0x64, 0x61, 0x74, 0x61])); // 'data'
  final dataHeader = ByteData(8);
  dataHeader.setUint64(0, 44, Endian.little);
  builder.add(dataHeader.buffer.asUint8List());
  builder.add(Uint8List(32)); // 16 L + 16 R
  return builder.takeBytes();
}
