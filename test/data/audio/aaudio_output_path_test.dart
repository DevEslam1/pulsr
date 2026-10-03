import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/collaborators/aaudio_output_controller.dart';

class _Player extends Mock implements AudioPlayer {}

void main() {
  test('AAudio ON/OFF/ON reaches every player and reports acceptance',
      () async {
    final players = [_Player(), _Player(), _Player()];
    for (final player in players) {
      when(() => player.dspSetAaudioOutput(any(),
          preferExclusive: true,
          targetBufferMs: 150)).thenAnswer((_) async => true);
    }
    for (final enabled in [true, false, true]) {
      expect(await pushAaudioOutputToPlayers(enabled, players: players), true);
    }
    for (final player in players) {
      verify(() => player.dspSetAaudioOutput(true,
          preferExclusive: true, targetBufferMs: 150)).called(2);
      verify(() => player.dspSetAaudioOutput(false,
          preferExclusive: true, targetBufferMs: 150)).called(1);
    }
  });
  test(
      'rejection or exception is reported while remaining players still receive the change',
      () async {
    final players = [_Player(), _Player(), _Player()];
    when(() => players[0].dspSetAaudioOutput(true,
        preferExclusive: false,
        targetBufferMs: 50)).thenThrow(StateError('player unavailable'));
    when(() => players[1].dspSetAaudioOutput(true,
        preferExclusive: false,
        targetBufferMs: 50)).thenAnswer((_) async => false);
    when(() => players[2].dspSetAaudioOutput(true,
        preferExclusive: false,
        targetBufferMs: 50)).thenAnswer((_) async => true);
    expect(
        await pushAaudioOutputToPlayers(true,
            preferExclusive: false, targetBufferMs: 50, players: players),
        false);
    verify(() => players[2].dspSetAaudioOutput(true,
        preferExclusive: false, targetBufferMs: 50)).called(1);
  });
}
