// test/features/player/player_playback_options_quran_race_test.dart
//
// Regression coverage for the Quran disable/re-enable race: a disable that is
// still in flight when the user re-enables must not null the manager's restore
// snapshot or delete the persisted copy.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test_support.dart';

class _GatedTransitionHandler extends RecordingAudioHandler {
  Completer<void>? transitionGate;
  bool failTransition = false;

  @override
  Future<void> setPreamp(double value) async {}

  @override
  Future<T> withSmoothDspTransition<T>(Future<T> Function() action) async {
    if (failTransition) throw StateError('Audio device unavailable');
    final gate = transitionGate;
    if (gate != null) {
      transitionGate = null;
      await gate.future;
    }
    return action();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('failed music restore retains snapshot for retry', () async {
    final handler = _GatedTransitionHandler();
    var state = const PlayerState();
    final controller = PlayerPlaybackOptionsController(
        audioHandler: handler,
        getState: () => state,
        emit: (s) => state = s,
        isClosed: () => false);
    await controller.setQuranModeEnabled(true);
    handler.failTransition = true;
    await controller.setQuranModeEnabled(false);
    expect(state.errorMessage, contains('Failed to restore'));
    expect(await controller.loadQuranSnapshot(), isNotNull);
    handler.failTransition = false;
    await controller.reapplyQuranProfile();
    expect(state.errorMessage, isNull);
    expect(await controller.loadQuranSnapshot(), isNull);
  });

  test('re-enable during an in-flight disable keeps the restore snapshot',
      () async {
    final handler = _GatedTransitionHandler();
    var state = const PlayerState();
    final controller = PlayerPlaybackOptionsController(
      audioHandler: handler,
      getState: () => state,
      emit: (s) => state = s,
      isClosed: () => false,
    );

    await controller.setQuranModeEnabled(true);
    expect(state.isQuranModeEnabled, isTrue);
    expect(await controller.loadQuranSnapshot(), isNotNull);

    // Hold the disable inside its restore transition.
    final gate = Completer<void>();
    handler.transitionGate = gate;
    final disable = controller.setQuranModeEnabled(false);
    await pumpEventQueue();
    expect(state.isQuranModeEnabled, isFalse);

    // User re-enables while the disable is still in flight.
    final enable = controller.setQuranModeEnabled(true);
    await pumpEventQueue();

    gate.complete();
    await disable;
    await enable;
    await pumpEventQueue();

    expect(state.isQuranModeEnabled, isTrue);
    // The stale disable must not have deleted the persisted snapshot.
    expect(await controller.loadQuranSnapshot(), isNotNull);
  });
}
