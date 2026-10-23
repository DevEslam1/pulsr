// test/domain/models/audio_quality_info_test.dart
//
// Regression coverage for the sample-rate/bit-depth presentation gate: a
// computed DSD carrier rate must not be masked as "Unknown" just because no
// PCM header value exists.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_quality_info.dart';

SongsTableData _song({
  String path = '/music/track.mp3',
  String source = SongSource.local,
  String? codec,
  int? sampleRate,
  int? bitDepth,
  int? bitrateKbps,
}) =>
    SongsTableData(
      id: 1,
      title: 'T',
      artist: 'A',
      album: 'Al',
      durationMs: 1000,
      path: path,
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
      source: source,
      codec: codec,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      bitrateKbps: bitrateKbps,
      isDownloaded: false,
    );

void main() {
  group('AudioQualityInfo.fromSong sample rate gating', () {
    test('DSD without a PCM header rate reports the DSD carrier rate', () {
      final info = AudioQualityInfo.fromSong(_song(path: '/m/master.dsf'));

      expect(info.format, 'DSD');
      expect(info.sampleRate, '2.8 MHz / 5.6 MHz');
      expect(info.bitDepth, '1-bit DSD');
    });

    test('DSD with an explicit PCM rate reports that measured rate', () {
      final info = AudioQualityInfo.fromSong(
        _song(path: '/m/master.dsf'),
        explicitSampleRate: 176400,
      );

      expect(info.sampleRate, '176.4 kHz');
    });

    test('DSD detected from a real codec string keeps the computed rate', () {
      final info = AudioQualityInfo.fromSong(
        _song(path: '/m/unknown.bin', codec: 'DSD'),
      );

      expect(info.sampleRate, '2.8 MHz / 5.6 MHz');
    });

    test('non-DSD without a header rate still reports Unknown', () {
      final info = AudioQualityInfo.fromSong(_song(path: '/m/a.mp3'));

      expect(info.sampleRate, 'Unknown');
      expect(info.bitDepth, 'Unknown');
    });

    test('non-DSD with a real header rate reports it', () {
      final info = AudioQualityInfo.fromSong(
        _song(
            path: '/m/a.flac', codec: 'flac', sampleRate: 96000, bitDepth: 24),
      );

      expect(info.sampleRate, '96.0 kHz');
      expect(info.bitDepth, '24-bit');
    });

    test('Opus track with webm.oga extension reports 48.0 kHz real rate even without explicit header rate', () {
      final info = AudioQualityInfo.fromSong(
        _song(path: '/storage/emulated/0/Music/Track.webm.oga'),
      );

      expect(info.format, 'OPUS');
      expect(info.sampleRate, '48.0 kHz');
    });

    test('Opus track with explicit header rate reports measured rate', () {
      final info = AudioQualityInfo.fromSong(
        _song(path: '/storage/emulated/0/Music/Track.webm.oga', sampleRate: 48000),
      );

      expect(info.format, 'OPUS');
      expect(info.sampleRate, '48.0 kHz');
    });
  });
}
