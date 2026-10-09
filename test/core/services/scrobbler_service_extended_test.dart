// test/core/services/scrobbler_service_extended_test.dart
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/scrobbler_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final methodCalls = <MethodCall>[];
  final httpRequests = <http.Request>[];
  late MockSecureStorage secure;
  final secureStore = <String, String>{};
  late int httpStatus;
  late ScrobblerService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    methodCalls.clear();
    httpRequests.clear();
    secureStore.clear();
    httpStatus = 200;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.pulsr.music/scrobbler'),
      (MethodCall call) async {
        methodCalls.add(call);
        return true;
      },
    );

    secure = MockSecureStorage();
    when(() => secure.read(key: any(named: 'key'))).thenAnswer(
        (inv) async => secureStore[inv.namedArguments[const Symbol('key')]]);
    when(() => secure.write(
            key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((inv) async {
      secureStore[inv.namedArguments[const Symbol('key')] as String] =
          inv.namedArguments[const Symbol('value')] as String;
    });

    final client = MockClient((request) async {
      httpRequests.add(request);
      return http.Response(jsonEncode({'status': 'ok'}), httpStatus);
    });
    service = ScrobblerService(client, secure);
    service.scrobbleThrottle = Duration.zero;
  });

  Future<void> enableLastFm() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ScrobblerService.keyLastFmEnabled, true);
    await prefs.setString(ScrobblerService.keyLastFmApiKey, 'api');
    await prefs.setString(ScrobblerService.keyLastFmSecret, 'secret');
    await prefs.setString(ScrobblerService.keyLastFmSessionKey, 'session');
  }

  Future<void> enableListenBrainz() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ScrobblerService.keyListenBrainzEnabled, true);
    await prefs.setString(ScrobblerService.keyListenBrainzToken, 'token');
  }

  group('notifyPlaybackState broadcast gating', () {
    test('always broadcasts and skips REST for Quran recitation', () async {
      await service.notifyPlaybackState(
        id: 1,
        artist: 'Reciter',
        track: 'Surah',
        album: 'Quran',
        durationMs: 600000,
        positionMs: 300000,
        isPlaying: true,
        isQuran: true,
      );
      expect(methodCalls.single.method, 'broadcastPlaybackState');
      expect(httpRequests, isEmpty);
    });

    test('skips REST for short tracks, empty artist or track', () async {
      await enableLastFm();
      await service.notifyPlaybackState(
        id: 1,
        artist: 'A',
        track: 'T',
        album: '',
        durationMs: 20000,
        positionMs: 15000,
        isPlaying: true,
      );
      expect(httpRequests, isEmpty);

      await service.notifyPlaybackState(
        id: 2,
        artist: '',
        track: '',
        album: '',
        durationMs: 200000,
        positionMs: 100000,
        isPlaying: true,
      );
      expect(httpRequests, isEmpty);
    });
  });

  group('now playing', () {
    test('posts Last.fm now-playing with a signature', () async {
      await enableLastFm();
      await service.notifyPlaybackState(
        id: 1,
        artist: 'Artist',
        track: 'Track',
        album: 'Album',
        durationMs: 200000,
        positionMs: 1000,
        isPlaying: true,
      );
      final lastfm = httpRequests
          .where((r) => r.url.host == 'ws.audioscrobbler.com')
          .toList();
      expect(lastfm.length, 1);
      expect(lastfm.single.body, contains('track.updateNowPlaying'));
      expect(lastfm.single.body, contains('api_sig='));
    });

    test('posts ListenBrainz now-playing', () async {
      await enableListenBrainz();
      await service.notifyPlaybackState(
        id: 1,
        artist: 'Artist',
        track: 'Track',
        album: 'Album',
        durationMs: 200000,
        positionMs: 1000,
        isPlaying: true,
      );
      final lb = httpRequests
          .where((r) => r.url.host == 'api.listenbrainz.org')
          .toList();
      expect(lb.length, 1);
      expect(lb.single.body, contains('playing_now'));
      expect(lb.single.headers['Authorization'], 'Token token');
    });
  });

  group('scrobbling', () {
    test('scrobbles after the threshold and records stats', () async {
      await enableLastFm();
      await service.notifyPlaybackState(
        id: 7,
        artist: 'Artist',
        track: 'Track',
        album: 'Album',
        durationMs: 200000,
        positionMs: 1000,
        isPlaying: true,
      );
      await service.notifyPlaybackState(
        id: 7,
        artist: 'Artist',
        track: 'Track',
        album: 'Album',
        durationMs: 200000,
        positionMs: 150000,
        isPlaying: true,
      );

      expect(
          httpRequests.any((r) => r.body.contains('track.scrobble')), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(ScrobblerService.keyTotalScrobbleCount), 1);
      expect(prefs.getString(ScrobblerService.keyDailyScrobbleLog), isNotNull);
    });

    test('a failed service post enqueues an offline scrobble', () async {
      httpStatus = 500;
      await enableLastFm();
      await service.notifyPlaybackState(
        id: 8,
        artist: 'Artist',
        track: 'Track',
        album: 'Album',
        durationMs: 200000,
        positionMs: 1000,
        isPlaying: true,
      );
      await service.notifyPlaybackState(
        id: 8,
        artist: 'Artist',
        track: 'Track',
        album: 'Album',
        durationMs: 200000,
        positionMs: 150000,
        isPlaying: true,
      );
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getString('scrobbler_offline_queue');
      expect(queue, isNotNull);
      expect(queue, contains('Artist'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('offline-only mode queues instead of posting', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('setting_offline_only_mode', true);
      await enableLastFm();

      await service.notifyPlaybackState(
        id: 9,
        artist: 'Artist',
        track: 'Track',
        album: '',
        durationMs: 200000,
        positionMs: 1000,
        isPlaying: true,
      );
      await service.notifyPlaybackState(
        id: 9,
        artist: 'Artist',
        track: 'Track',
        album: '',
        durationMs: 200000,
        positionMs: 150000,
        isPlaying: true,
      );
      expect(
          httpRequests.any((r) => r.body.contains('track.scrobble')), isFalse);
      expect(prefs.getString('scrobbler_offline_queue'), contains('Artist'));
    });
  });

  group('checkPendingScrobble', () {
    test('submits a pending scrobble past the threshold', () async {
      await enableLastFm();
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('scrobbler_last_song', 42);
      await prefs.setInt('scrobbler_last_time', now - 1000);
      await prefs.setInt('scrobbler_last_position', 250000);
      await prefs.setInt('scrobbler_last_duration', 300000);
      await prefs.setString('scrobbler_last_artist', 'Artist');
      await prefs.setString('scrobbler_last_track', 'Track');
      await prefs.setString('scrobbler_last_album', 'Album');

      await service.checkPendingScrobble();

      expect(httpRequests.any((r) => r.body.contains('track.scrobble')), isTrue);
      expect(prefs.getInt('scrobbler_last_song'), isNull);
      expect(prefs.getString('scrobbler_last_artist'), isNull);
    });

    test('skips a duplicate within the 5-minute window', () async {
      await enableLastFm();
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('scrobbler_last_song', 42);
      await prefs.setInt('scrobbler_last_time', now - 1000);
      await prefs.setInt('scrobbler_last_position', 250000);
      await prefs.setInt('scrobbler_last_duration', 300000);
      await prefs.setString('scrobbler_last_artist', 'Artist');
      await prefs.setString('scrobbler_last_track', 'Track');
      await prefs.setString('last_scrobble_key', 'Artist_Track');
      await prefs.setInt('last_scrobble_time', now);

      await service.checkPendingScrobble();
      expect(httpRequests.where((r) => r.body.contains('track.scrobble')),
          isEmpty);
    });

    test('does nothing when no pending scrobble is stored', () async {
      await service.checkPendingScrobble();
      expect(httpRequests, isEmpty);
    });
  });

  group('flushOfflineQueue', () {
    test('drops entries when no service is enabled', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'scrobbler_offline_queue',
          jsonEncode([
            {
              'artist': 'A',
              'track': 'T',
              'album': '',
              'durationSec': 100,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }
          ]));
      await service.flushOfflineQueue();
      expect(prefs.getString('scrobbler_offline_queue'), isNull);
    });

    test('retains entries when a configured service rejects them', () async {
      httpStatus = 500;
      await enableLastFm();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'scrobbler_offline_queue',
          jsonEncode([
            {
              'artist': 'A',
              'track': 'T',
              'album': '',
              'durationSec': 100,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }
          ]));
      await service.flushOfflineQueue();
      expect(prefs.getString('scrobbler_offline_queue'), isNotNull);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('is a no-op without a stored queue', () async {
      await service.flushOfflineQueue();
      expect(httpRequests, isEmpty);
    });
  });

  group('credential migration', () {
    test('migrates prefs secrets into secure storage and wipes them',
        () async {
      SharedPreferences.setMockInitialValues({
        ScrobblerService.keyLastFmApiKey: 'api',
        ScrobblerService.keyLastFmSecret: 'secret',
        ScrobblerService.keyLastFmSessionKey: 'session',
        ScrobblerService.keyLibreFmSessionKey: 'libre',
        ScrobblerService.keyListenBrainzToken: 'token',
      });
      await service.migrateAllCredentialsToSecureStorage();

      expect(secureStore[ScrobblerService.keyLastFmApiKeySecure], 'api');
      expect(secureStore[ScrobblerService.keyLastFmSecretSecure], 'secret');
      expect(secureStore[ScrobblerService.keyListenBrainzTokenSecure], 'token');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ScrobblerService.keyLastFmApiKey), isNull);
      expect(prefs.getString(ScrobblerService.keyLastFmSecret), isNull);
    });
  });
}
