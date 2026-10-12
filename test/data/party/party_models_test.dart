import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/party/server_clock.dart';
import 'package:pulsr/data/party/party_models.dart';

void main() {
  group('ServerClock', () {
    test('initial state is unsynced', () {
      final clock = ServerClock(localNowMs: () => 1000);
      expect(clock.synced, isFalse);
      expect(clock.offsetMs, isNull);
      expect(clock.roundTripMs, 0);
      expect(clock.serverNowMs(), isNull);
    });

    test('records pong sample and calculates NTP offset', () {
      int fakeLocalTime = 1000;
      final clock = ServerClock(localNowMs: () => fakeLocalTime);

      // t0 = 1000 (sent), server = 5050, t1 = 1100 (received)
      // roundTrip = 100ms, midpoint = 1050ms
      // offset = 5050 - 1050 = 4000ms
      clock.record(1000, 5050, 1100);

      expect(clock.synced, isTrue);
      expect(clock.offsetMs, 4000);
      expect(clock.roundTripMs, 100);

      fakeLocalTime = 1200;
      expect(clock.serverNowMs(), 5200);
    });

    test('chooses minimum round-trip sample over sliding window', () {
      const fakeLocalTime = 2000;
      final clock = ServerClock(localNowMs: () => fakeLocalTime);

      // Sample 1: high jitter (roundTrip = 300ms)
      // t0 = 1000, server = 6150, t1 = 1300 -> midpoint = 1150, offset = 5000
      clock.record(1000, 6150, 1300);
      expect(clock.roundTripMs, 300);
      expect(clock.offsetMs, 5000);

      // Sample 2: low jitter (roundTrip = 40ms)
      // t0 = 1400, server = 6440, t1 = 1440 -> midpoint = 1420, offset = 5020
      clock.record(1400, 6440, 1440);
      expect(clock.roundTripMs, 40);
      expect(clock.offsetMs, 5020);

      // Sample 3: high jitter again (roundTrip = 200ms)
      // t0 = 1500, server = 6620, t1 = 1700 -> midpoint = 1600, offset = 5020
      clock.record(1500, 6620, 1700);
      // Sample 2 should still win
      expect(clock.roundTripMs, 40);
      expect(clock.offsetMs, 5020);
    });

    test('drops stale samples outside 2-minute TTL', () {
      int fakeLocalTime = 1000;
      final clock = ServerClock(localNowMs: () => fakeLocalTime);

      // Sample 1 taken at t = 1000 with low roundTrip
      clock.record(980, 5000, 1000);
      expect(clock.offsetMs, 4010);
      expect(clock.roundTripMs, 20);

      // Advance past 120,000ms TTL
      fakeLocalTime = 150000;

      // Sample 2 taken at t = 150000 with slightly higher roundTrip
      clock.record(149950, 154000, 150000);
      // Sample 1 is stale (>120s old), so Sample 2 must be chosen
      expect(clock.offsetMs, 4025);
      expect(clock.roundTripMs, 50);
    });

    test('reset clears all samples and offsets', () {
      final clock = ServerClock();
      clock.record(100, 500, 200);
      expect(clock.synced, isTrue);

      clock.reset();
      expect(clock.synced, isFalse);
      expect(clock.offsetMs, isNull);
      expect(clock.roundTripMs, 0);
    });
  });

  group('PartyModels serialization', () {
    test('PartyTrack toJson and fromJson', () {
      const track = PartyTrack(
        videoId: 'abc123xyz',
        title: 'Song Title',
        artist: 'Artist Name',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        durationMs: 240000,
        fromAutoplay: false,
      );

      final json = track.toJson();
      final parsed = PartyTrack.fromJson(json);

      expect(parsed.videoId, track.videoId);
      expect(parsed.title, track.title);
      expect(parsed.artist, track.artist);
      expect(parsed.thumbnailUrl, track.thumbnailUrl);
      expect(parsed.durationMs, track.durationMs);
      expect(parsed.fromAutoplay, track.fromAutoplay);
    });

    test('PartyPlayback toJson and fromJson', () {
      const playback = PartyPlayback(
        seq: 42,
        track: PartyTrack(videoId: 'vid1', title: 'T1'),
        queueSeq: 3,
        queueLength: 10,
        queueIndex: 2,
        isPlaying: true,
        positionMs: 45000,
        anchorMs: 1600000000,
        effectivePositionMs: 46500,
        updatedBy: 'm1',
        startedBy: 'm1',
        startedByName: 'Alice',
      );

      final json = playback.toJson();
      final parsed = PartyPlayback.fromJson(json);

      expect(parsed.seq, 42);
      expect(parsed.track?.videoId, 'vid1');
      expect(parsed.queueSeq, 3);
      expect(parsed.isPlaying, isTrue);
      expect(parsed.positionMs, 45000);
      expect(parsed.anchorMs, 1600000000);
      expect(parsed.effectivePositionMs, 46500);
      expect(parsed.startedByName, 'Alice');
    });

    test('PartyMember serialization', () {
      const member = PartyMember(
        memberId: 'mem1',
        userId: 'usr1',
        displayName: 'Bob',
        isHost: true,
        connected: true,
      );

      final json = member.toJson();
      final parsed = PartyMember.fromJson(json);

      expect(parsed.memberId, 'mem1');
      expect(parsed.displayName, 'Bob');
      expect(parsed.isHost, isTrue);
      expect(parsed.connected, isTrue);
    });

    test('PartySnapshot serialization', () {
      const snapshot = PartySnapshot(
        code: 'ABCXYZ',
        maxMembers: 5,
        hostOnlyControl: false,
        members: [
          PartyMember(memberId: 'm1', displayName: 'Host User', isHost: true),
        ],
        playback: PartyPlayback(seq: 1, isPlaying: true),
        queue: PartyQueue(seq: 1, index: 0, items: [PartyTrack(videoId: 'v1')]),
      );

      final json = snapshot.toJson();
      final parsed = PartySnapshot.fromJson(json);

      expect(parsed.code, 'ABCXYZ');
      expect(parsed.members.length, 1);
      expect(parsed.playback.seq, 1);
      expect(parsed.queue.items.length, 1);
    });
  });
}
