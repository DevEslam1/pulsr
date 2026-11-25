import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/yin_pitch_detector.dart';

void main() {
  group('EmaPitchSmoother noteName during unvoiced hold', () {
    test('computes noteName from smoothed midi instead of passing raw noteName',
        () {
      final smoother = EmaPitchSmoother();
      // Feed a voiced A4 (440 Hz, MIDI 69)
      final voicedResult = PitchResult(
        frequencyHz: 440.0,
        midiNote: 69.0,
        noteName: 'A4',
        probability: 0.95,
        isVoiced: true,
      );
      final smoothedVoiced = smoother.smooth(voicedResult);
      expect(smoothedVoiced.isVoiced, isTrue);
      expect(smoothedVoiced.noteName, 'A4');

      // Feed an unvoiced frame (PitchResult.unvoiced has noteName '--')
      final smoothedHold = smoother.smooth(PitchResult.unvoiced);
      expect(smoothedHold.isVoiced, isTrue);
      expect(smoothedHold.frequencyHz, closeTo(440.0, 0.1));
      expect(smoothedHold.midiNote, closeTo(69.0, 0.1));
      expect(smoothedHold.noteName, 'A4');
      expect(smoothedHold.noteName, isNot('--'));
    });
  });
}
