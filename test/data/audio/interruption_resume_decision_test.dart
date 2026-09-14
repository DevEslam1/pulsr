// test/data/audio/interruption_resume_decision_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/interruption_state_machine.dart';

/// Regression coverage for the resume decision the handler applies to *every*
/// interruption-end path. A pause-mode duck used to pause playback and never
/// resume it because the end path discarded the state machine's return value.
void main() {
  group('PulsrAudioHandler.shouldResumeAfterInterruption', () {
    test('resumes only when playing before, allowed, and not already playing',
        () {
      expect(
        PulsrAudioHandler.shouldResumeAfterInterruption(
          wasPlayingBeforeInterruption: true,
          resumeAfterInterruption: true,
          currentlyPlaying: false,
        ),
        isTrue,
      );
    });

    test('never resumes when playback was not running before the interruption',
        () {
      expect(
        PulsrAudioHandler.shouldResumeAfterInterruption(
          wasPlayingBeforeInterruption: false,
          resumeAfterInterruption: true,
          currentlyPlaying: false,
        ),
        isFalse,
      );
    });

    test('respects the resume-after-interruption preference', () {
      expect(
        PulsrAudioHandler.shouldResumeAfterInterruption(
          wasPlayingBeforeInterruption: true,
          resumeAfterInterruption: false,
          currentlyPlaying: false,
        ),
        isFalse,
      );
    });

    test('does not double-play when something already resumed playback', () {
      expect(
        PulsrAudioHandler.shouldResumeAfterInterruption(
          wasPlayingBeforeInterruption: true,
          resumeAfterInterruption: true,
          currentlyPlaying: true,
        ),
        isFalse,
      );
    });

    test('duck-pause end resumes (regression B-7)', () {
      final machine = InterruptionStateMachine();
      // A duck that begins in pause mode snapshots the running state...
      machine.begin(InterruptionKind.duck, playing: true);
      // ...and the end event returns exactly that snapshot.
      final wasPlayingBeforeDuck = machine.end(InterruptionKind.duck);

      expect(
        PulsrAudioHandler.shouldResumeAfterInterruption(
          wasPlayingBeforeInterruption: wasPlayingBeforeDuck,
          resumeAfterInterruption: true,
          currentlyPlaying: false,
        ),
        isTrue,
      );
    });

    test('an attenuate-mode duck end does not request a resume (regression B-7)',
        () {
      final machine = InterruptionStateMachine();
      // Attenuate-mode ducks never begin() the interruption bookkeeping.
      expect(machine.end(InterruptionKind.duck), isFalse);
      expect(
        PulsrAudioHandler.shouldResumeAfterInterruption(
          wasPlayingBeforeInterruption: false,
          resumeAfterInterruption: true,
          currentlyPlaying: true,
        ),
        isFalse,
      );
    });
  });
}
