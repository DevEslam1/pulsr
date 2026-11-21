// test/core/utils/yin_pitch_detector_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/yin_pitch_detector.dart';

void main() {
  group('EmaPitchSmoother', () {
    test('smooths voiced frames with exponential moving average', () {
      final smoother = EmaPitchSmoother(alpha: 0.5);

      final r1 = smoother.smooth(const PitchResult(
        frequencyHz: 440.0,
        midiNote: 69.0,
        noteName: 'A4',
        probability: 0.95,
        isVoiced: true,
      ));

      expect(r1.isVoiced, isTrue);
      expect(r1.frequencyHz, closeTo(440.0, 0.01));
      expect(r1.midiNote, closeTo(69.0, 0.01));
      expect(r1.noteName, 'A4');

      final r2 = smoother.smooth(const PitchResult(
        frequencyHz: 450.0,
        midiNote: 70.0,
        noteName: 'A#4',
        probability: 0.90,
        isVoiced: true,
      ));

      // With alpha=0.5, new freq = 0.5*450 + 0.5*440 = 445.0
      expect(r2.frequencyHz, closeTo(445.0, 0.01));
      expect(r2.midiNote, closeTo(69.5, 0.01));
    });

    test('emits held note name (not --) across brief unvoiced gaps', () {
      final smoother = EmaPitchSmoother(alpha: 0.28);

      // 1. Voiced frame: A4 (MIDI 69, ~440 Hz)
      final initial = smoother.smooth(const PitchResult(
        frequencyHz: 440.0,
        midiNote: 69.0,
        noteName: 'A4',
        probability: 0.95,
        isVoiced: true,
      ));
      expect(initial.isVoiced, isTrue);
      expect(initial.noteName, 'A4');

      // 2. Brief unvoiced frames (frames 1 to 4 <= maxHoldFrames)
      for (int i = 1; i <= 4; i++) {
        final unvoicedResult = smoother.smooth(PitchResult.unvoiced);
        expect(unvoicedResult.isVoiced, isTrue,
            reason: 'Frame $i should be bridged as voiced');
        expect(unvoicedResult.noteName, 'A4',
            reason: 'Frame $i should retain note name A4, not --');
        expect(unvoicedResult.frequencyHz, closeTo(440.0, 0.01));
        expect(unvoicedResult.midiNote, closeTo(69.0, 0.01));
      }

      // 3. Exceeding maxHoldFrames (frame 5) reverts to unvoiced
      final droppedResult = smoother.smooth(PitchResult.unvoiced);
      expect(droppedResult.isVoiced, isFalse);
      expect(droppedResult.noteName, '--');
      expect(smoother.smoothedFrequencyHz, isNull);
      expect(smoother.smoothedMidiNote, isNull);
    });

    test('resets unvoiced hold counter when new voiced frame arrives', () {
      final smoother = EmaPitchSmoother(alpha: 0.28);

      smoother.smooth(const PitchResult(
        frequencyHz: 440.0,
        midiNote: 69.0,
        noteName: 'A4',
        probability: 0.95,
        isVoiced: true,
      ));

      // 2 unvoiced frames held
      expect(smoother.smooth(PitchResult.unvoiced).isVoiced, isTrue);
      expect(smoother.smooth(PitchResult.unvoiced).isVoiced, isTrue);

      // Re-voice with C5 (523.25 Hz, MIDI 72)
      final revoiced = smoother.smooth(const PitchResult(
        frequencyHz: 523.25,
        midiNote: 72.0,
        noteName: 'C5',
        probability: 0.92,
        isVoiced: true,
      ));
      expect(revoiced.isVoiced, isTrue);

      // Subsequent unvoiced frame should bridge using C-range pitch
      final held = smoother.smooth(PitchResult.unvoiced);
      expect(held.isVoiced, isTrue);
      expect(held.noteName, isNot('--'));
    });
  });
}
