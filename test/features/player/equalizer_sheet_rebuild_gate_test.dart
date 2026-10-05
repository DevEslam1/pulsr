import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';

void main() {
  group('H-10: dspSheetRebuildGate tests', () {
    test('returns false for identical states', () {
      const state = PlayerState();
      expect(dspSheetRebuildGate(state, state), isFalse);
    });

    test(
        'ignores gains-only changes in eqPreset to avoid full sheet rebuild during slider drag',
        () {
      final stateA = PlayerState(
        dsp: const DspSlice(
          eqPreset:
              EqPreset(name: 'Custom', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ),
      );
      final stateB = PlayerState(
        dsp: const DspSlice(
          eqPreset:
              EqPreset(name: 'Custom', gains: [3, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ),
      );
      expect(dspSheetRebuildGate(stateA, stateB), isFalse);
    });

    test('triggers rebuild when eqPreset preset name changes', () {
      final stateA = PlayerState(
        dsp: const DspSlice(
          eqPreset:
              EqPreset(name: 'Flat', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ),
      );
      final stateB = PlayerState(
        dsp: const DspSlice(
          eqPreset:
              EqPreset(name: 'Rock', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ),
      );
      expect(dspSheetRebuildGate(stateA, stateB), isTrue);
    });

    test('triggers rebuild when liveProgStatus changes', () {
      const stateA = PlayerState(
        dsp: DspSlice(liveProgStatus: 'idle'),
      );
      const stateB = PlayerState(
        dsp: DspSlice(liveProgStatus: 'compiled'),
      );
      expect(dspSheetRebuildGate(stateA, stateB), isTrue);
    });

    test('triggers rebuild when stereoWidthMultiband toggles', () {
      const stateA = PlayerState(
        dsp: DspSlice(stereoWidthMultiband: false),
      );
      const stateB = PlayerState(
        dsp: DspSlice(stereoWidthMultiband: true),
      );
      expect(dspSheetRebuildGate(stateA, stateB), isTrue);
    });

    test('triggers rebuild when stereoWidth sub-fields change', () {
      const base = PlayerState(
        dsp: DspSlice(
          stereoWidthLow: 1.0,
          stereoWidthMid: 1.0,
          stereoWidthHigh: 1.0,
          stereoWidthLowCrossoverHz: 160.0,
          stereoWidthHighCrossoverHz: 2500.0,
        ),
      );

      final withLow =
          base.copyWith(dsp: base.dsp.copyWith(stereoWidthLow: 1.5));
      final withMid =
          base.copyWith(dsp: base.dsp.copyWith(stereoWidthMid: 1.2));
      final withHigh =
          base.copyWith(dsp: base.dsp.copyWith(stereoWidthHigh: 0.8));
      final withLowCross = base.copyWith(
          dsp: base.dsp.copyWith(stereoWidthLowCrossoverHz: 200.0));
      final withHighCross = base.copyWith(
          dsp: base.dsp.copyWith(stereoWidthHighCrossoverHz: 3000.0));

      expect(dspSheetRebuildGate(base, withLow), isTrue);
      expect(dspSheetRebuildGate(base, withMid), isTrue);
      expect(dspSheetRebuildGate(base, withHigh), isTrue);
      expect(dspSheetRebuildGate(base, withLowCross), isTrue);
      expect(dspSheetRebuildGate(base, withHighCross), isTrue);
    });

    test('triggers rebuild when currentSong ID changes', () {
      final stateA = PlayerState(
        playback: const PlaybackSlice(
          currentSong: SongsTableData(
            id: 1,
            title: 'Song 1',
            artist: 'Artist 1',
            album: 'Album 1',
            path: '/path/1',
            durationMs: 1000,
            source: SongSource.local,
            isFavorite: false,
            isMissing: false,
            isDownloaded: false,
            playCount: 0,
            lastPositionMs: 0,
          ),
        ),
      );
      final stateB = PlayerState(
        playback: const PlaybackSlice(
          currentSong: SongsTableData(
            id: 2,
            title: 'Song 2',
            artist: 'Artist 2',
            album: 'Album 2',
            path: '/path/2',
            durationMs: 1000,
            source: SongSource.local,
            isFavorite: false,
            isMissing: false,
            isDownloaded: false,
            playCount: 0,
            lastPositionMs: 0,
          ),
        ),
      );
      expect(dspSheetRebuildGate(stateA, stateB), isTrue);
    });

    test('triggers rebuild when errorMessage changes', () {
      const stateA = PlayerState(playback: PlaybackSlice(errorMessage: null));
      const stateB =
          PlayerState(playback: PlaybackSlice(errorMessage: 'DSP error'));
      expect(dspSheetRebuildGate(stateA, stateB), isTrue);
    });
  });
}
