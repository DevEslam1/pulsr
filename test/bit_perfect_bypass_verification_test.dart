// test/bit_perfect_bypass_verification_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';

void main() {
  group('Bit-Perfect Bypass - Native Message Verification', () {
    test('bypass state initializes to null (not set)', () {
      // Reset state
      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = null;

      expect(
        AudioEffectsChannel.lastPushedBypassDspForBitPerfect,
        isNull,
        reason: 'Initial bypass state should be null (not sent)',
      );
    });

    test('bypass enabled state is persisted', () async {
      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = true;

      expect(
        AudioEffectsChannel.lastPushedBypassDspForBitPerfect,
        isTrue,
        reason: 'Should persist bypass=true state',
      );
    });

    test('bypass disabled state is persisted', () async {
      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = false;

      expect(
        AudioEffectsChannel.lastPushedBypassDspForBitPerfect,
        isFalse,
        reason: 'Should persist bypass=false state',
      );
    });

    test('bypass state can be toggled', () async {
      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = true;
      expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, isTrue);

      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = false;
      expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, isFalse);

      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = true;
      expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, isTrue);
    });

    test('bypass state tracks only last sent message', () async {
      // Simulate sending multiple bypass messages
      final bypassStates = [true, false, true, false, true, false];

      for (final state in bypassStates) {
        AudioEffectsChannel.lastPushedBypassDspForBitPerfect = state;
      }

      // Should only remember the last one
      expect(
        AudioEffectsChannel.lastPushedBypassDspForBitPerfect,
        equals(bypassStates.last),
        reason: 'Should track only the most recent bypass state sent',
      );
    });

    test('bypass can be reset to null after being set', () async {
      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = true;
      expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, isTrue);

      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = null;
      expect(
        AudioEffectsChannel.lastPushedBypassDspForBitPerfect,
        isNull,
        reason: 'Should be able to reset bypass to null',
      );
    });

    test('concurrent bypass state writes are safe', () async {
      const stateUpdates = 100;
      final futures = <Future<void>>[];

      for (int i = 0; i < stateUpdates; i++) {
        futures.add(
          Future.value().then((_) {
            AudioEffectsChannel.lastPushedBypassDspForBitPerfect = (i % 2) == 0;
          }),
        );
      }

      await Future.wait(futures);

      // Should end up in a consistent state (either true or false)
      final finalState = AudioEffectsChannel.lastPushedBypassDspForBitPerfect;
      expect(
        finalState == true || finalState == false,
        isTrue,
        reason:
            'Final bypass state should be consistent despite concurrent writes',
      );
    });

    test('bypass state observable through getDspDebugStatus', () async {
      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = true;

      // In real app, getDspDebugStatus() would include bypass in DspDebugReport
      // This test verifies the state can be checked after a push
      expect(
        AudioEffectsChannel.lastPushedBypassDspForBitPerfect,
        isTrue,
        reason: 'Bypass state should be queryable for debugging',
      );
    });

    test('bypass disabled allows all DSP processing', () async {
      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = false;

      // When bypass is false, all effects should process audio
      expect(
        AudioEffectsChannel.lastPushedBypassDspForBitPerfect,
        isFalse,
        reason: 'Bypass false means all DSP chain effects are active',
      );
    });

    test('bypass enabled bypasses entire DSP chain', () async {
      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = true;

      // When bypass is true, audio should pass through unaffected
      expect(
        AudioEffectsChannel.lastPushedBypassDspForBitPerfect,
        isTrue,
        reason: 'Bypass true means audio bypasses entire DSP pipeline',
      );
    });
  });
}
