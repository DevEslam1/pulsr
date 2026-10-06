// test/data/audio/playback_interruption_manager_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/playback_interruption_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackInterruptionManager Transition Table Tests (Phase 3)', () {
    late PlaybackInterruptionManager manager;

    setUp(() {
      manager = PlaybackInterruptionManager();
    });

    test('1. (idle, playing: true) x duckBegin -> duck -> (ducked)', () {
      final decision = manager.onDuckBegin(isPlaying: true, shouldPauseInstead: false);
      expect(decision, InterruptionDecision.duck);
      expect(manager.isDucked, isTrue);

      // Nested duck
      final nested = manager.onDuckBegin(isPlaying: true, shouldPauseInstead: false);
      expect(nested, InterruptionDecision.ignore);
      expect(manager.isDucked, isTrue);

      // Duck end 1
      final end1 = manager.onDuckEnd(shouldPauseInstead: false, resumeAllowed: true);
      expect(end1, InterruptionDecision.ignore);
      expect(manager.isDucked, isTrue);

      // Duck end 2 -> unduck
      final end2 = manager.onDuckEnd(shouldPauseInstead: false, resumeAllowed: true);
      expect(end2, InterruptionDecision.unduck);
      expect(manager.isDucked, isFalse);
    });

    test('2. (idle, playing: false) x duckBegin -> ignore -> (idle)', () {
      final decision = manager.onDuckBegin(isPlaying: false, shouldPauseInstead: false);
      expect(decision, InterruptionDecision.ignore);
      expect(manager.isDucked, isFalse);
    });

    test('3. duck with shouldPauseInstead -> pause, and duck end -> resume', () {
      final decision = manager.onDuckBegin(isPlaying: true, shouldPauseInstead: true);
      expect(decision, InterruptionDecision.pause);

      final end = manager.onDuckEnd(shouldPauseInstead: true, resumeAllowed: true);
      expect(end, InterruptionDecision.resume);
    });

    test('4. Call interruption: pauseBegin -> pause, pauseEnd -> resume iff resumeAllowed', () {
      final p1 = manager.onPauseInterruptionBegin(isPlaying: true);
      expect(p1, InterruptionDecision.pause);
      expect(manager.hasActiveInterruption, isTrue);

      // If resumeAllowed is false
      final endNoResume = manager.onPauseInterruptionEnd(resumeAllowed: false);
      expect(endNoResume, InterruptionDecision.ignore);
      expect(manager.hasActiveInterruption, isFalse);

      // With resumeAllowed is true
      manager.onPauseInterruptionBegin(isPlaying: true);
      final endResume = manager.onPauseInterruptionEnd(resumeAllowed: true);
      expect(endResume, InterruptionDecision.resume);
      expect(manager.hasActiveInterruption, isFalse);
    });

    test('5. Becoming noisy debounce and device reconnect timeout', () {
      final t0 = DateTime(2026, 10, 7, 10, 0, 0);
      final noisyDecision = manager.onBecomingNoisy(isPlaying: true, now: t0);
      expect(noisyDecision, InterruptionDecision.pause);
      expect(manager.isPausedForNoisy, isTrue);

      // Rapid noisy event is ignored (debounced)
      final rapidNoisy = manager.onBecomingNoisy(
        isPlaying: true,
        now: t0.add(const Duration(milliseconds: 300)),
      );
      expect(rapidNoisy, InterruptionDecision.ignore);

      // Reconnect after timeout -> ignored
      final timeoutReconnect = manager.onDeviceReconnect(
        now: t0.add(const Duration(seconds: 100)),
        autoResumeEnabled: true,
        timeout: const Duration(seconds: 90),
        hasHeadsetOutput: true,
      );
      expect(timeoutReconnect, InterruptionDecision.ignore);

      // Re-trigger noisy
      final t1 = t0.add(const Duration(seconds: 200));
      manager.onBecomingNoisy(isPlaying: true, now: t1);
      expect(manager.isPausedForNoisy, isTrue);

      // Reconnect without headset (speaker) -> ignored
      final speakerReconnect = manager.onDeviceReconnect(
        now: t1.add(const Duration(seconds: 10)),
        autoResumeEnabled: true,
        timeout: const Duration(seconds: 90),
        hasHeadsetOutput: false,
      );
      expect(speakerReconnect, InterruptionDecision.ignore);

      // Reconnect with headset within timeout -> resume
      final t2 = t1.add(const Duration(seconds: 10));
      manager.onBecomingNoisy(isPlaying: true, now: t2);
      final validReconnect = manager.onDeviceReconnect(
        now: t2.add(const Duration(seconds: 10)),
        autoResumeEnabled: true,
        timeout: const Duration(seconds: 90),
        hasHeadsetOutput: true,
      );
      expect(validReconnect, InterruptionDecision.resume);
      expect(manager.isPausedForNoisy, isFalse);
    });

    test('6. User action clears all pending interruptions and auto-resumes', () {
      manager.onPauseInterruptionBegin(isPlaying: true);
      manager.onBecomingNoisy(isPlaying: true, now: DateTime.now());
      manager.onDuckBegin(isPlaying: true, shouldPauseInstead: false);

      expect(manager.hasActiveInterruption, isTrue);
      expect(manager.isPausedForNoisy, isTrue);
      expect(manager.isDucked, isTrue);

      // User pauses or plays
      manager.onUserAction();

      expect(manager.hasActiveInterruption, isFalse);
      expect(manager.isPausedForNoisy, isFalse);
      expect(manager.isDucked, isFalse);
    });
  });
}
