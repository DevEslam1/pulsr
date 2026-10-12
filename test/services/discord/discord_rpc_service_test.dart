import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/services/discord/discord_rpc_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

SongsTableData _createTestSong({
  required int id,
  required String title,
  required String artist,
  String album = 'Test Album',
  required int durationMs,
  required String path,
  String? codec,
  int? sampleRate,
  int? bitDepth,
  int? bitrateKbps,
  String? remoteId,
  String source = 'local',
}) {
  return SongsTableData(
    id: id,
    title: title,
    artist: artist,
    album: album,
    durationMs: durationMs,
    path: path,
    isFavorite: false,
    isMissing: false,
    playCount: 0,
    lastPositionMs: 0,
    source: source,
    isDownloaded: false,
    codec: codec,
    sampleRate: sampleRate,
    bitDepth: bitDepth,
    bitrateKbps: bitrateKbps,
    remoteId: remoteId,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiscordSuperProperties', () {
    test('mimics Discord Android client', () {
      final props = DiscordSuperProperties.createProperties();
      expect(props['os'], 'Android');
      expect(props['browser'], 'Discord Android');
      expect(props['client_version'], '314.13 - Stable');
      expect(props['client_build_number'], 314013);
      expect(props['release_channel'], 'googleRelease');
    });

    test('generates valid base64 super properties', () {
      final b64 = DiscordSuperProperties.getBase64();
      final decodedJson = utf8.decode(base64.decode(b64));
      final map = jsonDecode(decodedJson) as Map<String, dynamic>;
      expect(map['os'], 'Android');
      expect(map['browser'], 'Discord Android');
    });
  });

  group('DiscordUser', () {
    test('parses json with avatar correctly', () {
      final json = {
        'id': '123456789',
        'username': 'pulsr_listener',
        'global_name': 'Pulsr Listener',
        'avatar': 'abcdef123456',
      };
      final user = DiscordUser.fromJson(json);
      expect(user.id, '123456789');
      expect(user.username, 'pulsr_listener');
      expect(user.globalName, 'Pulsr Listener');
      expect(user.avatarUrl,
          'https://cdn.discordapp.com/avatars/123456789/abcdef123456.png');
    });

    test('parses json without avatar correctly', () {
      final json = {
        'id': '987654321',
        'username': 'local_user',
        'avatar': null,
      };
      final user = DiscordUser.fromJson(json);
      expect(user.id, '987654321');
      expect(user.username, 'local_user');
      expect(user.globalName, 'local_user');
      expect(user.avatarUrl, isNull);
    });
  });

  group('DiscordRpcService - Audio Quality Formatting', () {
    test('formats Hi-Res Lossless FLAC with sample rate and bit depth', () {
      final song = _createTestSong(
        id: 1,
        title: 'Hi-Res Track',
        artist: 'Audiophile Artist',
        album: 'Studio Master',
        durationMs: 240000,
        path: '/storage/music/track.flac',
        codec: 'flac',
        sampleRate: 96000,
        bitDepth: 24,
        bitrateKbps: 4608,
      );

      final line = DiscordRpcService.formatAudioQuality(song);
      expect(line, isNotNull);
      expect(line, contains('Hi-Res Lossless'));
      expect(line, contains('FLAC'));
      expect(line, contains('24-bit'));
      expect(line, contains('96.0 kHz'));
    });

    test('formats Lossless WAV audio', () {
      final song = _createTestSong(
        id: 2,
        title: 'CD Quality Track',
        artist: 'Artist',
        durationMs: 180000,
        path: '/storage/music/track.wav',
        codec: 'wav',
        sampleRate: 44100,
        bitDepth: 16,
        bitrateKbps: 1411,
      );

      final line = DiscordRpcService.formatAudioQuality(song);
      expect(line, isNotNull);
      expect(line, contains('Lossless'));
      expect(line, contains('WAV'));
      expect(line, contains('16-bit'));
      expect(line, contains('44.1 kHz'));
    });

    test('formats Dolby Atmos track', () {
      final song = _createTestSong(
        id: 3,
        title: 'Spatial Experience (Dolby Atmos)',
        artist: 'Spatial Artist',
        durationMs: 200000,
        path: '/storage/music/atmos.m4a',
        codec: 'atmos',
      );

      final line = DiscordRpcService.formatAudioQuality(song);
      expect(line, isNotNull);
      expect(line, contains('Dolby Atmos'));
    });

    test('returns null for standard lossy MP3', () {
      final song = _createTestSong(
        id: 4,
        title: 'Standard Track',
        artist: 'Artist',
        durationMs: 150000,
        path: '/storage/music/track.mp3',
        codec: 'mp3',
        bitrateKbps: 320,
        sampleRate: 44100,
        bitDepth: 16,
      );

      final line = DiscordRpcService.formatAudioQuality(song);
      expect(line, isNull);
    });
  });

  group('DiscordRpcService - Watch URL Generation', () {
    test('returns YouTube Music watch url when remoteId present', () {
      final song = _createTestSong(
        id: 5,
        title: 'Online Song',
        artist: 'Online Artist',
        durationMs: 210000,
        path: 'ytmusic://abcdef',
        remoteId: 'dQw4w9WgXcQ',
      );

      final url = DiscordRpcService.getWatchUrl(song);
      expect(url, 'https://music.youtube.com/watch?v=dQw4w9WgXcQ');
    });

    test('falls back to search query URL for local track', () {
      final song = _createTestSong(
        id: 6,
        title: 'Local Master',
        artist: 'Daft Punk',
        durationMs: 300000,
        path: '/storage/music/song.flac',
      );

      final url = DiscordRpcService.getWatchUrl(song);
      expect(url, contains('https://music.youtube.com/search?q='));
      expect(url, contains('Daft%20Punk'));
    });
  });

  group('DiscordRpcService - Preferences persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initializes and saves token and enabled flags', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = DiscordRpcService.instance;

      await service.init(prefs);
      expect(service.isEnabled, isFalse);
      expect(service.token, isEmpty);

      await service.setToken('test_discord_token_123');
      expect(service.token, 'test_discord_token_123');
      expect(prefs.getString(PrefsKeys.discordRpcToken), 'test_discord_token_123');

      await service.setEnabled(true);
      expect(service.isEnabled, isTrue);
      expect(prefs.getBool(PrefsKeys.discordRpcEnabled), isTrue);

      await service.clearAccount();
      expect(service.token, isEmpty);
      expect(prefs.getString(PrefsKeys.discordRpcToken), isNull);
    });
  });
}
