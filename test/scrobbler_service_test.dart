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

    test('Direct ListenBrainz scrobbling triggers HTTP POST when enabled and threshold reached', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ScrobblerService.keyListenBrainzEnabled, true);
      await prefs.setString(ScrobblerService.keyListenBrainzToken, 'test_token_12345');

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
  });
}
