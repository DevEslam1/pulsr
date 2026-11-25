import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/core/services/scrobbler_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScrobblerService Tests', () {
    late ScrobblerService service;
    final List<MethodCall> methodCalls = [];
    final List<http.Request> httpRequests = [];

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      methodCalls.clear();
      httpRequests.clear();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.pulsr.music/scrobbler'),
        (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          return true;
        },
      );

      final mockClient = MockClient((request) async {
        httpRequests.add(request);
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      service = ScrobblerService(mockClient);
    });

    test('Invokes broadcastPlaybackState with correct arguments', () async {
      await service.notifyPlaybackState(
        id: 123,
        artist: 'Pink Floyd',
        track: 'Time',
        album: 'The Dark Side of the Moon',
        durationMs: 420000,
        positionMs: 60000,
        isPlaying: true,
      );

      expect(methodCalls.length, equals(1));
      expect(methodCalls.first.method, equals('broadcastPlaybackState'));
      expect(methodCalls.first.arguments['artist'], equals('Pink Floyd'));
      expect(methodCalls.first.arguments['track'], equals('Time'));
      expect(methodCalls.first.arguments['isPlaying'], isTrue);
    });

    test(
        'Direct ListenBrainz scrobbling triggers HTTP POST when enabled and threshold reached',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ScrobblerService.keyListenBrainzEnabled, true);
      await prefs.setString(
          ScrobblerService.keyListenBrainzToken, 'test_token_12345');

      // 1. Initial play -> Playing Now
      await service.notifyPlaybackState(
        id: 456,
        artist: 'Radiohead',
        track: 'Paranoid Android',
        album: 'OK Computer',
        durationMs: 387000,
        positionMs: 5000,
        isPlaying: true,
      );

      expect(httpRequests.length, equals(1));
      expect(httpRequests.first.url.host, equals('api.listenbrainz.org'));
      expect(httpRequests.first.body, contains('playing_now'));

      // 2. Played > 50% -> Scrobble / single listen
      await service.notifyPlaybackState(
        id: 456,
        artist: 'Radiohead',
        track: 'Paranoid Android',
        album: 'OK Computer',
        durationMs: 387000,
        positionMs: 200000, // > 50% of 387000
        isPlaying: true,
      );

      expect(httpRequests.length, equals(2));
      expect(httpRequests.last.body, contains('single'));
    });

    test('Custom webhook rejects private/loopback targets', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ScrobblerService.keyCustomWebhookEnabled, true);
      await prefs.setString(ScrobblerService.keyCustomWebhookUrl,
          'http://127.0.0.1:8080/scrobble');

      await service.notifyPlaybackState(
        id: 789,
        artist: 'Daft Punk',
        track: 'Around the World',
        album: 'Homework',
        durationMs: 425000,
        positionMs: 220000,
        isPlaying: true,
      );

      // Webhook should be skipped due to SSRF policy
      expect(httpRequests.where((r) => r.url.host == '127.0.0.1'), isEmpty);
      // Scrobble count must not be inflated when all services failed or blocked
      expect(prefs.getInt(ScrobblerService.keyTotalScrobbleCount), isNull);
    });

    test('Custom webhook accepts routable targets', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ScrobblerService.keyCustomWebhookEnabled, true);
      await prefs.setString(
          ScrobblerService.keyCustomWebhookUrl, 'https://example.com/scrobble');

      await service.notifyPlaybackState(
        id: 790,
        artist: 'Daft Punk',
        track: 'Around the World',
        album: 'Homework',
        durationMs: 425000,
        positionMs: 220000,
        isPlaying: true,
      );

      expect(
          httpRequests.where((r) => r.url.host == 'example.com'), hasLength(1));
      expect(prefs.getInt(ScrobblerService.keyTotalScrobbleCount), equals(1));
    });

    test('Custom webhook rejects redirect pointing to private network',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ScrobblerService.keyCustomWebhookEnabled, true);
      await prefs.setString(
          ScrobblerService.keyCustomWebhookUrl, 'https://example.com/webhook');

      final redirectRequests = <http.Request>[];
      final redirectClient = MockClient((request) async {
        redirectRequests.add(request);
        if (request.url.toString() == 'https://example.com/webhook') {
          return http.Response('', 302, headers: {
            'location': 'http://192.168.1.1/secret',
          });
        }
        return http.Response('', 200);
      });

      final testService = ScrobblerService(redirectClient);
      await testService.notifyPlaybackState(
        id: 791,
        artist: 'Daft Punk',
        track: 'One More Time',
        album: 'Discovery',
        durationMs: 320000,
        positionMs: 200000,
        isPlaying: true,
      );

      expect(
          redirectRequests.where((r) => r.url.host == '192.168.1.1'), isEmpty);
      expect(prefs.getInt(ScrobblerService.keyTotalScrobbleCount), isNull);
    });

    test('Custom webhook follows safe redirects up to 3 hops', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ScrobblerService.keyCustomWebhookEnabled, true);
      await prefs.setString(
          ScrobblerService.keyCustomWebhookUrl, 'https://example.com/redir1');

      final redirectRequests = <http.Request>[];
      final redirectClient = MockClient((request) async {
        redirectRequests.add(request);
        if (request.url.toString() == 'https://example.com/redir1') {
          return http.Response('', 302, headers: {
            'location': 'https://example.com/final_hook',
          });
        }
        if (request.url.toString() == 'https://example.com/final_hook') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        return http.Response('not found', 404);
      });

      final testService = ScrobblerService(redirectClient);
      await testService.notifyPlaybackState(
        id: 792,
        artist: 'Daft Punk',
        track: 'Harder, Better, Faster, Stronger',
        album: 'Discovery',
        durationMs: 224000,
        positionMs: 150000,
        isPlaying: true,
      );

      expect(redirectRequests.length, equals(2));
      expect(redirectRequests.last.url.toString(),
          'https://example.com/final_hook');
      expect(prefs.getInt(ScrobblerService.keyTotalScrobbleCount), equals(1));
    });

    test('dispose closes owned client without throwing', () {
      final ownedService = ScrobblerService();
      expect(() => ownedService.dispose(), returnsNormally);
    });
  });
}
