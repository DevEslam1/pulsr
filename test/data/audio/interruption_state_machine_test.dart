// test/data/audio/interruption_state_machine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/interruption_state_machine.dart';

void main() {
  group('InterruptionStateMachine', () {
    test(
        'duck begin (pause mode) -> unrelated user pause -> play -> pause-type '
        'interruption still pauses and resumes (B-1 sequence)', () {
      final m = InterruptionStateMachine();

      // 1. A duck interruption begins while playback is running; ducking is
      //    configured to pause. The snapshot must be "was playing = true".
      m.begin(InterruptionKind.duck, playing: true);
      expect(m.activeKind, InterruptionKind.duck);
      expect(m.wasPlayingBeforeInterruption, isTrue);

      // 2. The user pauses for an unrelated reason (e.g. notification/headset)
      //    before the duck ever ends.
      m.onUserPause();
      expect(m.isActive, isFalse,
          reason: 'a user pause must clear the pending interruption state');
      expect(m.wasPlayingBeforeInterruption, isFalse);

      // A late duck-end must not resurrect or clobber anything.
      expect(m.end(InterruptionKind.duck), isFalse);
      expect(m.isActive, isFalse);

      // 3. The user starts playback again.
      // 4. A real phone call (pause-type interruption) begins while playing.
      m.begin(InterruptionKind.pause, playing: true);
      expect(m.activeKind, InterruptionKind.pause);
      expect(m.wasPlayingBeforeInterruption, isTrue,
          reason: 'a real call after a user pause must still pause playback');

      // Call ends -> resume decision is "was playing = true".
      expect(m.end(InterruptionKind.pause), isTrue);
      expect(m.isActive, isFalse);
      expect(m.wasPlayingBeforeInterruption, isFalse);
    });

    test('duck end clears a pause-mode duck so a later call can snapshot', () {
      final m = InterruptionStateMachine();
      m.begin(InterruptionKind.duck, playing: true);
      // A duck that began in pause mode must be ended by the duck end event.
      expect(m.end(InterruptionKind.duck), isTrue);
      expect(m.isActive, isFalse);

      m.begin(InterruptionKind.pause, playing: true);
      expect(m.wasPlayingBeforeInterruption, isTrue);
    });

    test('one kind end never clears another kind active begin', () {
      final m = InterruptionStateMachine();
      m.begin(InterruptionKind.duck, playing: true);

      expect(m.end(InterruptionKind.pause), isFalse);
      expect(m.activeKind, InterruptionKind.duck);
      expect(m.wasPlayingBeforeInterruption, isTrue);

      expect(m.end(InterruptionKind.unknown), isFalse);
      expect(m.isActive, isTrue);
    });

    test('begin is stack-safe: an overlapping begin keeps the original snapshot',
        () {
      final m = InterruptionStateMachine();
      m.begin(InterruptionKind.duck, playing: true);
      // An overlapping call must not clobber the pre-duck snapshot.
      m.begin(InterruptionKind.pause, playing: false);

      expect(m.activeKind, InterruptionKind.duck);
      expect(m.wasPlayingBeforeInterruption, isTrue);
    });

    test('unknown never auto-resumes and its end clears everything', () {
      final m = InterruptionStateMachine();
      m.begin(InterruptionKind.unknown, playing: true);
      m.neverResume();
      expect(m.wasPlayingBeforeInterruption, isFalse);
      expect(m.end(InterruptionKind.unknown), isFalse);
      expect(m.isActive, isFalse);
    });

    test('pause begin when nothing was playing never requests a resume', () {
      final m = InterruptionStateMachine();
      m.begin(InterruptionKind.pause, playing: false);
      expect(m.end(InterruptionKind.pause), isFalse);
    });
  });
}
