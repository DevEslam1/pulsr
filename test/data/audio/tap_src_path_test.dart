import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/collaborators/tap_src_controller.dart';

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

  group('pushTapSrcRateToPlayers (tap-side SRC bridge)', () {
    test('the mixer rate reaches every player', () async {
      when(() => playerA.dspSetTapSrcRate(48000))
          .thenAnswer((_) async => true);
      when(() => playerB.dspSetTapSrcRate(48000))
          .thenAnswer((_) async => true);
      when(() => prefetch.dspSetTapSrcRate(48000))
          .thenAnswer((_) async => true);

      await pushTapSrcRateToPlayers(48000, [playerA, playerB, prefetch]);

      verify(() => playerA.dspSetTapSrcRate(48000)).called(1);
      verify(() => playerB.dspSetTapSrcRate(48000)).called(1);
      verify(() => prefetch.dspSetTapSrcRate(48000)).called(1);
    });

    test('rate 0 disables conversion on every player', () async {
      when(() => playerA.dspSetTapSrcRate(0)).thenAnswer((_) async => true);
      when(() => playerB.dspSetTapSrcRate(0)).thenAnswer((_) async => true);
      when(() => prefetch.dspSetTapSrcRate(0)).thenAnswer((_) async => true);

      await pushTapSrcRateToPlayers(0, [playerA, playerB, prefetch]);

      verify(() => playerA.dspSetTapSrcRate(0)).called(1);
      verify(() => prefetch.dspSetTapSrcRate(0)).called(1);
    });

    test('a player that cannot honour the tap does not abort the fan-out',
        () async {
      when(() => playerA.dspSetTapSrcRate(48000))
          .thenThrow(Exception('not the Pulsr Android fork'));
      when(() => playerB.dspSetTapSrcRate(48000))
          .thenAnswer((_) async => false);
      when(() => prefetch.dspSetTapSrcRate(48000))
          .thenAnswer((_) async => true);

      // Must not throw: the platform-resample path stays in force per player.
      await pushTapSrcRateToPlayers(48000, [playerA, playerB, prefetch]);

      verify(() => playerB.dspSetTapSrcRate(48000)).called(1);
      verify(() => prefetch.dspSetTapSrcRate(48000)).called(1);
    });
  });
}
