import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/collaborators/float_output_controller.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  late MockAudioPlayer playerA;
  late MockAudioPlayer playerB;
  late MockAudioPlayer prefetch;

  setUp(() {
    playerA = MockAudioPlayer();
    playerB = MockAudioPlayer();
    prefetch = MockAudioPlayer();
  });

  group('pushFloatOutputToPlayers (24/32-bit float DSP path bridge)', () {
    test('flag ON pushes true to every player', () async {
      when(() => playerA.dspSetFloatOutput(true)).thenAnswer((_) async => true);
      when(() => playerB.dspSetFloatOutput(true)).thenAnswer((_) async => true);
      when(() => prefetch.dspSetFloatOutput(true))
          .thenAnswer((_) async => true);

      await pushFloatOutputToPlayers(true, [playerA, playerB, prefetch]);

      verify(() => playerA.dspSetFloatOutput(true)).called(1);
      verify(() => playerB.dspSetFloatOutput(true)).called(1);
      verify(() => prefetch.dspSetFloatOutput(true)).called(1);
    });

    test('flag OFF (default) pushes false, preserving the 16-bit path',
        () async {
      when(() => playerA.dspSetFloatOutput(false))
          .thenAnswer((_) async => true);
      when(() => playerB.dspSetFloatOutput(false))
          .thenAnswer((_) async => true);
      when(() => prefetch.dspSetFloatOutput(false))
          .thenAnswer((_) async => true);

      await pushFloatOutputToPlayers(false, [playerA, playerB, prefetch]);

      verify(() => playerA.dspSetFloatOutput(false)).called(1);
      verify(() => playerB.dspSetFloatOutput(false)).called(1);
      verify(() => prefetch.dspSetFloatOutput(false)).called(1);
      verifyNever(() => playerA.dspSetFloatOutput(true));
    });

    test('a player that rejects float output does not abort the fan-out',
        () async {
      when(() => playerA.dspSetFloatOutput(true))
          .thenThrow(Exception('not the Pulsr Android fork'));
      when(() => playerB.dspSetFloatOutput(true))
          .thenAnswer((_) async => false);
      when(() => prefetch.dspSetFloatOutput(true))
          .thenAnswer((_) async => true);

      // Must not throw: playback keeps the 16-bit path on unsupported players.
      await pushFloatOutputToPlayers(true, [playerA, playerB, prefetch]);

      verify(() => playerB.dspSetFloatOutput(true)).called(1);
      verify(() => prefetch.dspSetFloatOutput(true)).called(1);
    });
  });
}
