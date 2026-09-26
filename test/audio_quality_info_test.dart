// Classification tests for the audio-quality badge model. The factory is pure
// and drives the quality sheet/badges, so its tiering must not regress.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_quality_info.dart';

SongsTableData _song({
  int id = 1,
  String path = '/music/track.mp3',
  String source = SongSource.local,
  String? codec,
  int? sampleRate,
  int? bitDepth,
  int? bitrateKbps,
  int? fileSize,
  int durationMs = 1000,
  String? remoteId,
}) =>
    SongsTableData(
      id: id,
      title: 'T',
      artist: 'A',
      album: 'Al',
      durationMs: durationMs,
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
      fileSize: fileSize,
      remoteId: remoteId,
      isDownloaded: false,
    );

void main() {
  group('AudioQualityInfo.fromSong', () {
    test('null song falls back to a standard stereo descriptor', () {
      final info = AudioQualityInfo.fromSong(null);
      expect(info.format, 'AUDIO');
      expect(info.tier, AudioQualityTier.standardQuality);
    });

    test('plain MP3 with no header defaults to a high-quality MP3 tier', () {
      final info = AudioQualityInfo.fromSong(_song(path: '/m/a.mp3'));
      expect(info.format, 'MP3');
      expect(info.tier, AudioQualityTier.highQuality);
    });

    test('FLAC with a 24/96 header is classified Hi-Res lossless', () {
      final info = AudioQualityInfo.fromSong(_song(
        path: '/m/a.flac',
        codec: 'flac',
        sampleRate: 96000,
        bitDepth: 24,
      ));
      expect(info.format, 'FLAC');
      expect(info.tier, AudioQualityTier.hiResLossless);
      expect(info.sampleRate, '96.0 kHz');
      expect(info.bitDepth, '24-bit');
    });

    test('FLAC with a 16/44.1 header is plain lossless, not Hi-Res', () {
      final info = AudioQualityInfo.fromSong(_song(
        path: '/m/a.flac',
        codec: 'flac',
        sampleRate: 44100,
        bitDepth: 16,
      ));
      expect(info.tier, AudioQualityTier.lossless);
    });

    test('a DSD file is classified ultra Hi-Res', () {
      final info = AudioQualityInfo.fromSong(_song(path: '/m/master.dsf'));
      expect(info.format, 'DSD');
      expect(info.tier, AudioQualityTier.hiResLossless);
    });

    test('an MQA-tagged path surfaces an MQA format label', () {
      final info = AudioQualityInfo.fromSong(_song(path: '/m/mqa/track.flac'));
      expect(info.format, 'MQA');
    });

    test('a YouTube stream defaults to a 256k AAC high-quality tier', () {
      final info = AudioQualityInfo.fromSong(_song(
        source: SongSource.youtube,
        path: 'ytmusic://abc',
      ));
      expect(info.format, 'AAC');
      expect(info.tier, AudioQualityTier.highQuality);
    });

    test('a YouTube stream with a low explicit bitrate is compact', () {
      final info = AudioQualityInfo.fromSong(_song(
        source: SongSource.youtube,
        path: 'ytmusic://abc',
        bitrateKbps: 64,
      ));
      expect(info.tier, AudioQualityTier.compact);
    });

    test('a low-bitrate MP3 is compact', () {
      final info = AudioQualityInfo.fromSong(_song(
        path: '/m/low.mp3',
        bitrateKbps: 96,
      ));
      expect(info.tier, AudioQualityTier.compact);
    });

    test('a downloaded Opus track with webm.oga or oga path is classified as OPUS not MP3', () {
      final info = AudioQualityInfo.fromSong(_song(
        path: '/storage/emulated/0/Music/Song.webm.oga',
        codec: 'OPUS',
        bitrateKbps: 160,
      ));
      expect(info.format, 'OPUS');
      expect(info.codecName, 'Opus Interactive Audio');
      expect(info.shortBadgeLabel, 'OPUS • 160k');
      expect(info.tier, AudioQualityTier.highQuality);
    });

    test('a downloaded Opus track without explicit codec but webm path is classified as OPUS', () {
      final info = AudioQualityInfo.fromSong(_song(
        path: '/storage/emulated/0/Music/Song.webm',
        bitrateKbps: 160,
      ));
      expect(info.format, 'OPUS');
      expect(info.shortBadgeLabel, 'OPUS • 160k');
    });

    test('a downloaded AAC track is classified as AAC', () {
      final info = AudioQualityInfo.fromSong(_song(
        path: '/storage/emulated/0/Music/Song.m4a',
        codec: 'AAC',
        bitrateKbps: 128,
      ));
      expect(info.format, 'AAC');
      expect(info.shortBadgeLabel, 'AAC • 128k');
      expect(info.tier, AudioQualityTier.highQuality);
    });
  });
}
