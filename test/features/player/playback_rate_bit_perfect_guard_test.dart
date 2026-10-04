import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/features/player/cubit/controllers/player_playback_options_controller.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAudioHandler extends Mock implements PulsrAudioHandler {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'speed and pitch changes are refused while the bit-perfect rate guard is on',
      () async {
    final handler = _MockAudioHandler();
    when(() => handler.minPlaybackSpeed).thenReturn(0.5);
    when(() => handler.maxPlaybackSpeed).thenReturn(3.0);

    var state = const PlayerState();
    final controller = PlayerPlaybackOptionsController(
      audioHandler: handler,
      playbackRateBlockedReason: () =>
          'Bit-Perfect bypass is ON — resampling would alter the bitstream',
      getState: () => state,
      emit: (s) => state = s,
      isClosed: () => false,
    );

    await controller.setPlaybackSpeed(1.5);
    expect(state.playbackSpeed, 1.0);
    expect(state.playback.errorMessage, contains('Bit-Perfect bypass'));

    final speedError = state.playback.errorMessage;
    await controller.setPlaybackPitch(1.25);
    expect(state.playbackPitch, 1.0);
    expect(state.playback.errorMessage, contains('Bit-Perfect bypass'));
    expect(state.playback.errorMessage, isNot(equals(speedError)));

    // Neither guarded call may reach the engine.
    verifyNever(() => handler.setSpeed(any()));
    verifyNever(() => handler.setPitch(any()));
  });

  test('a null block reason leaves speed changes untouched', () async {
    final handler = _MockAudioHandler();
    when(() => handler.minPlaybackSpeed).thenReturn(0.5);
    when(() => handler.maxPlaybackSpeed).thenReturn(3.0);
    when(() => handler.setSpeed(any())).thenAnswer((_) async {});

    var state = const PlayerState();
    final controller = PlayerPlaybackOptionsController(
      audioHandler: handler,
      playbackRateBlockedReason: () => null,
      getState: () => state,
      emit: (s) => state = s,
      isClosed: () => false,
    );

    await controller.setPlaybackSpeed(1.5);
    expect(state.playbackSpeed, 1.5);
    verify(() => handler.setSpeed(1.5)).called(1);
  });
}
