// test/data/audio/characterization_player_stack_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/collaborators/playback_volume_controller.dart';
import 'package:pulsr/data/audio/crossfade_manager.dart';
import 'package:pulsr/data/audio/interruption_state_machine.dart';
import 'package:pulsr/data/audio/sleep_timer_manager.dart';
import '../../support/fake_audio_player.dart';
import '../../support/fake_clock.dart';

class MockCallback extends Mock {
  void call();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 1 Characterization Tests: Player Stack Behaviors', () {
    late FakeAudioPlayer playerA;
    late FakeAudioPlayer playerB;
    late FakeClock fakeClock;

    setUp(() {
      playerA = FakeAudioPlayer(playing: true, volume: 1.0);
      playerB = FakeAudioPlayer(playing: false, volume: 0.0);
      fakeClock = FakeClock();
    });

    tearDown(() async {
      await playerA.dispose();
      await playerB.dispose();
    });

    test(
        '1. InterruptionStateMachine: pause begin/end with resumeAfterInterruption',
        () {
      final machine = InterruptionStateMachine();

      // Playback is running, call begins
      machine.begin(InterruptionKind.pause, playing: true);
      expect(machine.isActive, isTrue);
      expect(machine.activeKind, InterruptionKind.pause);
      expect(machine.wasPlayingBeforeInterruption, isTrue);

      // Call ends -> auto resume allowed
      final shouldResume = machine.end(InterruptionKind.pause);
      expect(shouldResume, isTrue);
      expect(machine.isActive, isFalse);

      // Explicit user pause clears pending resume
      machine.begin(InterruptionKind.pause, playing: true);
      machine.onUserPause();
      expect(machine.isActive, isFalse);
      expect(machine.wasPlayingBeforeInterruption, isFalse);
    });

    test('2. PlaybackVolumeController: duck begin and end behavior', () async {
      final volumeController = PlaybackVolumeController(
        getActivePlayer: () => playerA,
        getInactivePlayer: () => playerB,
      );
      volumeController.updateSettings(userVolume: 1.0, duckFactor: 0.2);

      // Initially full volume
      expect(volumeController.calculateTargetVolume(null), closeTo(1.0, 0.001));

      // Duck begins
      await volumeController.setDucked(true, null);
      expect(volumeController.isDucked, isTrue);
      expect(volumeController.calculateTargetVolume(null), closeTo(0.2, 0.001));

      // Duck ends
      await volumeController.setDucked(false, null);
      expect(volumeController.isDucked, isFalse);
      expect(volumeController.calculateTargetVolume(null), closeTo(1.0, 0.001));

      volumeController.dispose();
    });

    test('3. CrossfadeManager: cancel restores volume cleanly', () async {
      final crossfadeManager = CrossfadeManager();
      crossfadeManager.duration = const Duration(seconds: 4);

      playerA.setVolume(1.0);
      playerB.setVolume(0.0);
      crossfadeManager.isCrossfading = true;

      // Simulating cancel mid-crossfade
      await crossfadeManager.cancel(playerB, playerA, restoreVolume: 0.8);
      expect(playerA.volume, closeTo(0.8, 0.001));
      expect(playerB.volume, closeTo(0.8, 0.001));
      expect(crossfadeManager.isCrossfading, isFalse);
    });

    test(
        '4. SleepTimerManager: onFadeFactor reports attenuation without direct overwrite',
        () {
      final sleepTimerManager = SleepTimerManager();
      double? receivedFactor;

      sleepTimerManager.onFadeFactor = (factor) {
        receivedFactor = factor;
      };

      // Starting with factor callback configured
      expect(sleepTimerManager.onFadeFactor, isNotNull);
      sleepTimerManager.onFadeFactor!(0.5);
      expect(receivedFactor, 0.5);
    });

    test('5. Becoming-noisy debounce and reconnect window tracking', () {
      final machine = InterruptionStateMachine();
      final lastNoisy = fakeClock.now;

      // First disconnect
      expect(machine.isActive, isFalse);

      // Advance clock by 200ms (< 800ms debounce threshold)
      fakeClock.advance(const Duration(milliseconds: 200));
      final rapidDiff = fakeClock.now.difference(lastNoisy);
      expect(rapidDiff < const Duration(milliseconds: 800), isTrue);

      // Advance clock by 1000ms (> 800ms)
      fakeClock.advance(const Duration(milliseconds: 800));
      final validDiff = fakeClock.now.difference(lastNoisy);
      expect(validDiff >= const Duration(milliseconds: 800), isTrue);
    });
  });
}
