// test/perf_gate_regression_test.dart
//
// REGRESSION GUARD for the position-tick rebuild gating (perf campaign 2026-08).
//
// WHY: freezed 3.2 `copyWith` does NOT preserve list reference identity — even
// a no-argument `state.copyWith()` returns new instances of `@Default([])`
// list fields. Any `!identical(a.list, b.list)` inside a BlocBuilder
// `buildWhen` therefore false-positives on EVERY emission, which used to make
// the whole Now Playing screen (and all 8 player themes) rebuild ~5x/second on
// position ticks alone (~22 ms host frames; full 120 Hz budget is 8.3 ms).
//
// The gate below must stay FALSE for position-only emissions. If this test
// fails, a list-field comparison was changed back to reference identity (or a
// new list field was added without using [listContentDiffers]).
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/core/utils/list_content_diff.dart';

SongsTableData _song(int id) => SongsTableData(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      album: 'Album',
      path: '/tmp/$id.mp3',
      durationMs: 192000,
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
      source: 'local',
      isDownloaded: false,
    );

void main() {
  test(
    'position-only copyWith must NOT pass differsFromBeyondPosition '
    '(freezed copyWith breaks list identity — see listContentDiffers doc)',
    () {
      final base = PlayerState(
        currentSong: _song(1),
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(minutes: 3, seconds: 12),
        queue: [_song(1), _song(2)],
      );

      final ticked = base.copyWith(position: const Duration(milliseconds: 200));
      expect(ticked.differsFromBeyondPosition(base), isFalse,
          reason: 'a position-only emission must not rebuild the Now Playing '
              'screen subtree. If this fails, a list field was compared by '
              'identity again (freezed copyWith does not preserve identity) — '
              'use listContentDiffers instead.');

      // Content changes must still pass the gate:
      final newQueue = base.copyWith(queue: [_song(9)]);
      expect(newQueue.differsFromBeyondPosition(base), isTrue,
          reason: 'queue content changes must rebuild the screen');

      final playing = base.copyWith(isPlaying: false);
      expect(playing.differsFromBeyondPosition(base), isTrue,
          reason: 'isPlaying changes must rebuild the screen');

      // listContentDiffers semantics:
      final a = <int>[1, 2, 3];
      expect(listContentDiffers(a, a), isFalse, reason: 'same instance');
      expect(listContentDiffers(a, [1, 2, 3]), isFalse,
          reason: 'equal content is not a change (length + first/last equal)');
      expect(listContentDiffers(a, [1, 2]), isTrue, reason: 'length change');
      expect(listContentDiffers(a, [9, 2, 3]), isTrue, reason: 'head change');
      expect(listContentDiffers(<int>[], <int>[]), isFalse,
          reason: 'both empty');
      expect(listContentDiffers(<int>[], a), isTrue, reason: 'was empty');
    },
  );
}
