import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/party/listen_together_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ListenTogetherService', () {
    test('resets lastHandledSeq to -1 on leaveParty across rooms', () async {
      final service = ListenTogetherService();
      addTearDown(() => service.dispose());

      expect(service.lastHandledSeq, equals(-1));

      // Simulate handling updates in Room A up to seq 42
      service.debugLastHandledSeq = 42;
      expect(service.lastHandledSeq, equals(42));

      // Leave Room A
      await service.leaveParty();

      // Verify sequence is reset so Room B (starting at seq 0 or low seq) is not dropped
      expect(service.lastHandledSeq, equals(-1),
          reason: 'lastHandledSeq must be reset to -1 so new room updates are not ignored');
    });

    test('BUG-P0-3: sendPing registers ping so pong sets clockSynced == true', () {
      final service = ListenTogetherService();
      addTearDown(() => service.dispose());

      expect(service.clockSynced.value, isFalse);

      service.sendPingForTesting();
      final sentMs = service.clock.nowMs();
      // The ping timestamp registered is <= sentMs; ensure the clock has a pending ping
      // Find the exact registered ping timestamp within [sentMs - 50, sentMs]
      int? registeredMs;
      for (var t = sentMs; t >= sentMs - 50; t--) {
        if (service.clock.hasPendingPing(t)) {
          registeredMs = t;
          break;
        }
      }
      expect(registeredMs, isNotNull,
          reason: '_sendPing must register outgoing ping timestamp in ServerClock');

      service.handleWebSocketMessageForTesting(jsonEncode({
        'type': 'pong',
        'clientMs': registeredMs,
        'serverMs': registeredMs! + 1000,
      }));

      expect(service.clockSynced.value, isTrue);
      expect(service.clock.synced, isTrue);
      expect(service.clock.serverNowMs(), isNotNull);
    });

    test('BUG-P2-23: normalizeServerUrl and isValidServerUrl handle ws/wss and http rules', () async {
      expect(
        ListenTogetherService.normalizeServerUrl('wss://party.pulsr.app/'),
        equals('https://party.pulsr.app'),
      );
      expect(
        ListenTogetherService.normalizeServerUrl('ws://192.168.1.10:8000/'),
        equals('http://192.168.1.10:8000'),
      );
      expect(
        ListenTogetherService.isValidServerUrl('wss://party.pulsr.app'),
        isTrue,
      );
      expect(
        ListenTogetherService.isValidServerUrl('ws://127.0.0.1:8000'),
        isTrue,
      );
      expect(
        ListenTogetherService.isValidServerUrl('http://party.pulsr.app'),
        isFalse,
      );

      final service = ListenTogetherService();
      addTearDown(() => service.dispose());
      await service.setCustomServerUrl('wss://party.example.com/');
      expect(await service.getServerUrl(), equals('https://party.example.com'));

      expect(
        () => service.setCustomServerUrl('http://party.example.com'),
        throwsArgumentError,
      );
    });

    test('BUG-P1-16: tracks matched local song ID and clears on leaveParty', () async {
      final service = ListenTogetherService();
      addTearDown(() => service.dispose());

      service.setMatchedLocalTrackForTesting(
        partyVideoId: 'ytm_vid_1',
        localSongId: 77,
      );
      expect(service.activePartyTrackVideoId, equals('ytm_vid_1'));
      expect(service.activePartyMatchedSongId, equals(77));

      await service.leaveParty();
      expect(service.activePartyTrackVideoId, isNull);
      expect(service.activePartyMatchedSongId, isNull);
    });
  });
}
