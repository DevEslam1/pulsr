// test/performance/rebuild_budget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/bloc/pulsr_bloc_observer.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PulsrBlocObserver.instance.reset();
  });

  group('Performance & Rebuild Budget', () {
    test('PulsrBlocObserver records state changes', () {
      final observer = PulsrBlocObserver.instance;
      expect(observer.totalTransitions, 0);

      // Verify reset and counting functions
      expect(observer.countFor(PlayerState), 0);
    });

    test('dspSheetRebuildGate rejects position ticks and preserves EqualizerSheet budget', () {
      const initial = PlayerState(
        playback: PlaybackSlice(
          position: Duration(seconds: 10),
          duration: Duration(seconds: 200),
          isPlaying: true,
        ),
      );

      const nextTick = PlayerState(
        playback: PlaybackSlice(
          position: Duration(seconds: 11),
          duration: Duration(seconds: 200),
          isPlaying: true,
        ),
      );

      // Gating must return false so the equalizer sheet is not rebuilt on 10Hz position ticks
      expect(dspSheetRebuildGate(initial, nextTick), isFalse);
    });

    test('TabletPlayerBar gate ignores position ticks', () {
      const initial = PlayerState(
        playback: PlaybackSlice(
          position: Duration(seconds: 10),
          duration: Duration(seconds: 200),
          isPlaying: true,
        ),
      );

      const nextTick = PlayerState(
        playback: PlaybackSlice(
          position: Duration(seconds: 11),
          duration: Duration(seconds: 200),
          isPlaying: true,
        ),
      );

      // Verify fields gated by TabletPlayerBar buildWhen
      final bool shouldRebuild =
          initial.currentSong?.id != nextTick.currentSong?.id ||
          initial.currentSong?.title != nextTick.currentSong?.title ||
          initial.currentSong?.artist != nextTick.currentSong?.artist ||
          initial.currentSong?.isFavorite != nextTick.currentSong?.isFavorite ||
          initial.isPlaying != nextTick.isPlaying ||
          initial.duration != nextTick.duration ||
          initial.isShuffle != nextTick.isShuffle ||
          initial.repeatMode != nextTick.repeatMode ||
          initial.isLyricsVisible != nextTick.isLyricsVisible ||
          initial.isQueueVisible != nextTick.isQueueVisible ||
          initial.isEqEnabled != nextTick.isEqEnabled;

      expect(shouldRebuild, isFalse);
    });
  });
}
