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
          reason:
              'lastHandledSeq must be reset to -1 so new room updates are not ignored');
    });

    test('BUG-P0-3: sendPing registers ping so pong sets clockSynced == true',
        () {
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
          reason:
              '_sendPing must register outgoing ping timestamp in ServerClock');

      service.handleWebSocketMessageForTesting(jsonEncode({
        'type': 'pong',
        'clientMs': registeredMs,
        'serverMs': registeredMs! + 1000,
      }));

      expect(service.clockSynced.value, isTrue);
      expect(service.clock.synced, isTrue);
      expect(service.clock.serverNowMs(), isNotNull);
    });

    test(
        'BUG-P2-23: normalizeServerUrl and isValidServerUrl handle ws/wss and http rules',
        () async {
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

    test('BUG-P1-16: tracks matched local song ID and clears on leaveParty',
        () async {
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

    test('C-14: init() is idempotent across concurrent and repeated calls',
        () async {
      final service = ListenTogetherService();
      addTearDown(() => service.dispose());

      // Concurrent calls share the same initialization future and do not throw
      await Future.wait([
        service.init(),
        service.init(),
      ]);
      // Subsequent call after completion returns immediately
      await service.init();
      expect(service.inParty, isFalse);
    });

    test(
        'H-43: isTerminalSessionFailure detects 401/403/404 and terminal WS close codes',
        () {
      expect(
          ListenTogetherService.isTerminalSessionFailure(
              'HTTP 401 Unauthorized', null),
          isTrue);
      expect(
          ListenTogetherService.isTerminalSessionFailure(
              'HTTP 403 Forbidden', null),
          isTrue);
      expect(
          ListenTogetherService.isTerminalSessionFailure(
              'HTTP 404 Not Found', null),
          isTrue);
      expect(
          ListenTogetherService.isTerminalSessionFailure(null, 4001), isTrue);
      expect(
          ListenTogetherService.isTerminalSessionFailure(null, 4003), isTrue);
      expect(
          ListenTogetherService.isTerminalSessionFailure(null, 4004), isTrue);
      expect(
          ListenTogetherService.isTerminalSessionFailure(null, 1008), isTrue);
      expect(
          ListenTogetherService.isTerminalSessionFailure(
              'SocketException: Network unreachable', 1006),
          isFalse);
    });

    test(
        'H-43: welcome frame populates partySnapshot and currentMember, and bye clears session without network throw',
        () async {
      final service = ListenTogetherService();
      addTearDown(() => service.dispose());

      service.handleWebSocketMessageForTesting(jsonEncode({
        'type': 'welcome',
        'party': {
          'code': 'XYZ789',
          'maxMembers': 5,
          'hostOnlyControl': true,
          'members': [
            {
              'memberId': 'm1',
              'displayName': 'Alice',
              'isHost': true,
              'connected': true,
            }
          ],
          'playback': {
            'isPlaying': false,
            'positionMs': 15000,
            'seq': 3,
          },
          'queue': {
            'index': 0,
            'items': [],
          },
        },
        'you': {
          'memberId': 'm1',
          'displayName': 'Alice',
          'isHost': true,
          'connected': true,
        },
      }));

      expect(service.partySnapshot.value?.code, equals('XYZ789'));
      expect(service.partySnapshot.value?.hostOnlyControl, isTrue);
      expect(service.currentMember.value?.memberId, equals('m1'));
      expect(service.isHost, isTrue);
      expect(service.connectionState.value, equals(PartyConnectionState.live));

      // Receiving 'bye' sets lastError and tears down local session cleanly
      service.handleWebSocketMessageForTesting(jsonEncode({
        'type': 'bye',
        'reason': 'Host ended the party',
      }));
      await Future<void>.delayed(Duration.zero);

      expect(service.lastError.value, equals('Host ended the party'));
      expect(service.partySnapshot.value, isNull);
      expect(
          service.connectionState.value, equals(PartyConnectionState.offline));
    });
  });
}
