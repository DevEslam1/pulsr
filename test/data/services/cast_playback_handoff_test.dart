import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/services/cast_playback_handoff.dart';
import 'package:pulsr/data/services/cast_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final castService = CastService();

  tearDown(() {
    castService.debugSetSessionStatus(CastSessionStatus.unavailable);
  });

  group('CastPlaybackHandoff', () {
    test('pauses if already connected on start', () async {
      var paused = false;
      var resumed = false;
      castService.debugSetSessionStatus(const CastSessionStatus(
        available: true,
        connected: true,
      ));

      final handoff = CastPlaybackHandoff(
        isLocalPlaying: () => true,
        pauseLocal: () async {
          paused = true;
        },
        resumeLocal: () async {
          resumed = true;
        },
      );

      handoff.start();
      await Future<void>.delayed(Duration.zero);

      expect(paused, isTrue);
      expect(resumed, isFalse);

      await handoff.dispose();
    });

    test('pauses when connected and resumes when disconnected', () async {
      var localPlaying = true;
      var paused = false;
      var resumed = false;

      castService.debugSetSessionStatus(const CastSessionStatus(
        available: true,
        connected: false,
      ));

      final handoff = CastPlaybackHandoff(
        isLocalPlaying: () => localPlaying,
        pauseLocal: () async {
          paused = true;
          localPlaying = false;
        },
        resumeLocal: () async {
          resumed = true;
          localPlaying = true;
        },
      );

      handoff.start();
      await Future<void>.delayed(Duration.zero);

      // Connect
      castService.debugSetSessionStatus(const CastSessionStatus(
        available: true,
        connected: true,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(paused, isTrue);
      expect(resumed, isFalse);

      // Disconnect
      castService.debugSetSessionStatus(const CastSessionStatus(
        available: true,
        connected: false,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(resumed, isTrue);

      await handoff.dispose();
    });

    test('does not resume if local was not playing when cast connected',
        () async {
      var paused = false;
      var resumed = false;

      castService.debugSetSessionStatus(const CastSessionStatus(
        available: true,
        connected: false,
      ));

      final handoff = CastPlaybackHandoff(
        isLocalPlaying: () => false,
        pauseLocal: () async {
          paused = true;
        },
        resumeLocal: () async {
          resumed = true;
        },
      );

      handoff.start();
      await Future<void>.delayed(Duration.zero);

      // Connect while not playing
      castService.debugSetSessionStatus(const CastSessionStatus(
        available: true,
        connected: true,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(paused, isFalse);

      // Disconnect
      castService.debugSetSessionStatus(const CastSessionStatus(
        available: true,
        connected: false,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(resumed, isFalse);

      await handoff.dispose();
    });
  });
}
