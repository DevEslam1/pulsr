// Classification tests for the audio-quality badge model. The factory is pure
// and drives the quality sheet/badges, so its tiering must not regress.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_quality_info.dart';
import 'package:pulsr/domain/models/ytm_audio_quality.dart';

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

    test('plain MP3 without metadata has unverified source quality', () {
      final info = AudioQualityInfo.fromSong(_song(path: '/m/a.mp3'));
      expect(info.format, 'MP3');
      expect(info.tier, AudioQualityTier.standardQuality);
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

    test(
        'a YouTube stream without metadata shows its source instead of '
        'inventing a codec or bitrate', () {
      final info = AudioQualityInfo.fromSong(_song(
        source: SongSource.youtube,
        path: 'ytmusic://abc',
      ));
      expect(info.format, 'YTM');
      expect(info.shortBadgeLabel, 'YTM • STREAM');
      expect(info.bitrateKbps, isNull);
      expect(info.sampleRate, 'Unknown');
      expect(info.bitDepth, 'Unknown');
      expect(info.tierLabel, 'Stream quality unverified');
    });

    test(
        'a YouTube stream without resolved metadata uses the selected '
        'streaming tier on the badge', () {
      final song = _song(
        source: SongSource.youtube,
        path: 'ytmusic://abc',
      );

      final high = AudioQualityInfo.fromSong(
        song,
        streamingQuality: YtmAudioQuality.high,
      );
      expect(high.format, 'YTM');
      expect(high.bitrateKbps, isNull);
      expect(high.shortBadgeLabel, 'YTM • HIGH');
      expect(high.tier, AudioQualityTier.highQuality);
      expect(high.tierLabel, 'High Quality Stream');

      final medium = AudioQualityInfo.fromSong(
        song,
        streamingQuality: YtmAudioQuality.medium,
      );
      expect(medium.shortBadgeLabel, 'YTM • MEDIUM');
      expect(medium.tier, AudioQualityTier.standardQuality);
      expect(medium.tierLabel, 'Medium Quality Stream');

      final low = AudioQualityInfo.fromSong(
        song,
        streamingQuality: YtmAudioQuality.low,
      );
      expect(low.shortBadgeLabel, 'YTM • LOW');
      expect(low.tier, AudioQualityTier.compact);
      expect(low.tierLabel, 'Data Saver Stream');
    });

    test('resolved stream metadata wins over the selected quality tier', () {
      final info = AudioQualityInfo.fromSong(
        _song(
          source: SongSource.youtube,
          path: 'ytmusic://abc',
          codec: 'OPUS',
          bitrateKbps: 256,
        ),
        streamingQuality: YtmAudioQuality.low,
      );
      expect(info.format, 'OPUS');
      expect(info.shortBadgeLabel, 'OPUS • 256k');
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

    test(
        'a downloaded Opus track with webm.oga or oga path is classified as OPUS not MP3',
        () {
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

    test(
        'a downloaded Opus track without explicit codec but webm path is classified as OPUS',
        () {
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

    test('a live radio station is classified as RADIO with clean badge label',
        () {
      final info = AudioQualityInfo.fromSong(_song(
        path:
            'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi_mojawwad',
        source: SongSource.radio,
      ));
      expect(info.format, 'RADIO');
      expect(info.shortBadgeLabel, 'Radio');
      expect(info.tierLabel, 'Live Radio');
      expect(info.codecName, 'Internet Radio Stream');
      expect(info.sampleRate, 'Live Stream');
      expect(info.bitDepth, 'Live');
    });

    test(
        'an http radio stream path without SongSource.radio is also detected as radio',
        () {
      final info = AudioQualityInfo.fromSong(_song(
        path: 'https://stream.radiojar.com/radio.mp3',
      ));
      expect(info.format, 'RADIO');
      expect(info.shortBadgeLabel, 'Radio');
    });
  });
}
