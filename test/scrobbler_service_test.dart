import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/scrobbler_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScrobblerService Tests', () {
    late ScrobblerService service;
    final List<MethodCall> methodCalls = [];

    setUp(() {
      methodCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.pulsr.music/scrobbler'),
        (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          return true;
        },
      );
      service = ScrobblerService();
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
  });
}
