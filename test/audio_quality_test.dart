// test/audio_quality_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_quality_info.dart';

void main() {
  group('AudioQualityInfo Unit Tests', () {
    test('Calculates FLAC Hi-Res Lossless quality correctly', () {
      const song = SongsTableData(
        id: 1,
        title: 'Hi-Res Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000, // 3 minutes = 180s
        path: '/storage/emulated/0/Music/track_24bit_96k.flac',
        fileSize: 40 * 1024 * 1024, // 40MB
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      final info = AudioQualityInfo.fromSong(song);
      expect(info.format, 'FLAC');
      expect(info.tier, AudioQualityTier.hiResLossless);
      expect(info.bitDepth, '24-bit');
      expect(info.bitrateKbps, greaterThan(1411));
      expect(info.shortBadgeLabel, contains('FLAC'));
    });

    test('Calculates CD Quality Lossless FLAC correctly', () {
      const song = SongsTableData(
        id: 2,
        title: 'CD Quality Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 200000, // 200s
        path: '/storage/emulated/0/Music/track.flac',
        fileSize: 20 * 1024 * 1024, // 20MB -> ~838 kbps
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      final info = AudioQualityInfo.fromSong(song);
      expect(info.format, 'FLAC');
      expect(info.tier, AudioQualityTier.lossless);
      expect(info.bitDepth, '16-bit');
      expect(info.sampleRate, '44.1 kHz');
      expect(info.shortBadgeLabel, contains('FLAC'));
    });

    test('Calculates 320 kbps High Quality MP3 correctly', () {
      const song = SongsTableData(
        id: 3,
        title: 'MP3 Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 240000, // 240s (4 mins)
        path: '/storage/emulated/0/Music/track.mp3',
        fileSize: 9600000, // 9.6MB -> 320 kbps
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      final info = AudioQualityInfo.fromSong(song);
      expect(info.format, 'MP3');
      expect(info.tier, AudioQualityTier.highQuality);
      expect(info.bitrateKbps, 320);
      expect(info.shortBadgeLabel, 'MP3 • 320k');
    });

    test('Handles missing song gracefully', () {
      final info = AudioQualityInfo.fromSong(null);
      expect(info.format, 'AUDIO');
      expect(info.tier, AudioQualityTier.standardQuality);
      expect(info.shortBadgeLabel, 'STANDARD');
    });

    test('Calculates Hi-Res with explicit sampleRate and bitDepth metadata', () {
      const song = SongsTableData(
        id: 4,
        title: 'Explicit HiRes',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        path: '/storage/emulated/0/Music/track.flac',
        fileSize: 35000000,
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      final info = AudioQualityInfo.fromSong(
        song,
        explicitSampleRate: 96000,
        explicitBitDepth: 24,
        explicitBitrateKbps: 2304,
      );

      expect(info.format, 'FLAC');
      expect(info.tier, AudioQualityTier.hiResLossless);
      expect(info.bitDepth, '24-bit');
      expect(info.sampleRate, '96.0 kHz');
      expect(info.bitrateKbps, 2304);
      expect(info.shortBadgeLabel, 'FLAC • 2304k');
    });

    test('Calculates DSD Ultra Hi-Res quality correctly', () {
      const song = SongsTableData(
        id: 5,
        title: 'DSD Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 200000,
        path: '/storage/emulated/0/Music/track.dsf',
        fileSize: 100000000,
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      final info = AudioQualityInfo.fromSong(song);
      expect(info.format, 'DSD');
      expect(info.tier, AudioQualityTier.hiResLossless);
      expect(info.bitDepth, '1-bit DSD');
      expect(info.shortBadgeLabel, 'DSD • HI-RES');
    });

    test('Provides accurate renderEngineDescription for lossless vs compressed streams', () {
      const flacSong = SongsTableData(
        id: 10,
        title: 'Lossless Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        path: '/storage/emulated/0/Music/track.flac',
        fileSize: 30000000,
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );
      final flacInfo = AudioQualityInfo.fromSong(flacSong);
      expect(flacInfo.renderEngineDescription, 'ExoPlayer Media3 • 32-bit Float PCM');

      const ytmSong = SongsTableData(
        id: 11,
        title: 'YTM Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 210000,
        path: 'ytmusic://abc12345',
        source: SongSource.youtube,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );
      final ytmInfo = AudioQualityInfo.fromSong(ytmSong);
      expect(ytmInfo.renderEngineDescription, contains('Hardware Offload (AAC / DSP)'));

      const mp3Song = SongsTableData(
        id: 12,
        title: 'MP3 Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 200000,
        path: '/storage/emulated/0/Music/track.mp3',
        fileSize: 8000000,
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );
      final mp3Info = AudioQualityInfo.fromSong(mp3Song);
      expect(mp3Info.renderEngineDescription, contains('Hardware Offload (MP3 / DSP)'));
    });
  });
}
