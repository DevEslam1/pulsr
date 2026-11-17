// test/features/player/mini_player_rebuild_gate_test.dart
//
// Guards the two `buildWhen` diff gates the mini player variants rely on:
//
//   * `PlayerState.differsForMiniPlayer`           -> main mini player body
//   * `PlayerState.differsForMiniPlayerHorizontal` -> MiniPlayerHorizontal row
//
// Each gate used to be a hand-written field list inline at its call site, so a
// new `PlayerState` field could leave the always-on-screen mini player silently
// stale. These tests pin the exact field set of each gate, so widening or
// narrowing one is a visible, failing change rather than a silent regression.
//
// Pure unit tests on PlayerState: no widgets, no cubit, no plugin channels.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/app_error.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

SongsTableData _song({
  int id = 1,
  String title = 'Neon Drift',
  String artist = 'Aurora Lane',
  String album = 'Night Signal',
  String? remoteArtworkUrl = 'https://img.example/1.jpg',
  int playCount = 0,
}) {
  return SongsTableData(
    id: id,
    title: title,
    artist: artist,
    album: album,
    path: '/storage/music/$id.flac',
    source: 'local',
    isDownloaded: false,
    durationMs: 180000,
    isFavorite: false,
    isMissing: false,
    playCount: playCount,
    lastPositionMs: 0,
    remoteArtworkUrl: remoteArtworkUrl,
  );
}

/// Rebuilds [song] with individual columns overridden, so a test can flip
/// exactly one column and keep the rest of the row equal.
SongsTableData _respin(
  SongsTableData song, {
  int? id,
  String? title,
  String? artist,
  String? album,
  String? remoteArtworkUrl,
  int? playCount,
}) {
  return SongsTableData(
    id: id ?? song.id,
    title: title ?? song.title,
    artist: artist ?? song.artist,
    album: album ?? song.album,
    path: song.path,
    source: song.source,
    isDownloaded: song.isDownloaded,
    durationMs: song.durationMs,
    isFavorite: song.isFavorite,
    isMissing: song.isMissing,
    playCount: playCount ?? song.playCount,
    lastPositionMs: song.lastPositionMs,
    remoteArtworkUrl: remoteArtworkUrl ?? song.remoteArtworkUrl,
  );
}

PlayerState _base() {
  final first = _song();
  final second = _song(id: 2, title: 'Second Wind', album: 'Other');
  return PlayerState(
    playback: PlaybackSlice(
      currentSong: first,
      duration: const Duration(minutes: 3),
    ),
    queueSlice: QueueSlice(queue: [first, second], currentIndex: 0),
  );
}

PlayerState _withSong(PlayerState s, SongsTableData song) =>
    s.copyWith(playback: s.playback.copyWith(currentSong: song));

/// Mutations that change exactly one state dimension the main mini player body
/// renders. Every one of them must make [PlayerState.differsForMiniPlayer] true.
final Map<String, PlayerState Function(PlayerState)> _chromeFieldMutations = {
  'currentSong.id': (s) => _withSong(s, _respin(s.currentSong!, id: 42)),
  'currentSong.title': (s) =>
      _withSong(s, _respin(s.currentSong!, title: 'Renamed')),
  'currentSong.artist': (s) =>
      _withSong(s, _respin(s.currentSong!, artist: 'Other Artist')),
  'currentSong.remoteArtworkUrl': (s) => _withSong(
        s,
        _respin(s.currentSong!, remoteArtworkUrl: 'https://img/other.jpg'),
      ),
  'isPlaying': (s) =>
      s.copyWith(playback: s.playback.copyWith(isPlaying: !s.isPlaying)),
  'isBuffering': (s) =>
      s.copyWith(playback: s.playback.copyWith(isBuffering: !s.isBuffering)),
  'errorMessage': (s) => s.copyWith(
        playback: s.playback.copyWith(
          error: const AudioError(code: 'decode_failed', userMessage: 'boom'),
        ),
      ),
  'duration': (s) => s.copyWith(
        playback: s.playback.copyWith(duration: const Duration(minutes: 4)),
      ),
  'currentIndex': (s) =>
      s.copyWith(queueSlice: s.queueSlice.copyWith(currentIndex: 1)),
  'activeQueueSlot': (s) =>
      s.copyWith(queueSlice: s.queueSlice.copyWith(activeQueueSlot: 3)),
  // Queue identity as `listContentDiffers` sees it: same length, different
  // first row content (playCount is not otherwise watched by this gate).
  'queue content': (s) => s.copyWith(
        queueSlice: s.queueSlice.copyWith(
          queue: [_respin(s.queue.first, playCount: 7), ...s.queue.skip(1)],
        ),
      ),
  'queue length': (s) => s.copyWith(
        queueSlice: s.queueSlice.copyWith(
          queue: [...s.queue, _song(id: 9, title: 'Third')],
        ),
      ),
};

/// Mutations the 48dp horizontal row must react to. It compares the whole
/// `currentSong` row, so any column edit counts, not just the painted ones.
final Map<String, PlayerState Function(PlayerState)> _horizontalFieldMutations =
    {
  'currentSong.title': (s) =>
      _withSong(s, _respin(s.currentSong!, title: 'Renamed')),
  'currentSong.artist': (s) =>
      _withSong(s, _respin(s.currentSong!, artist: 'Other Artist')),
  'currentSong.album': (s) =>
      _withSong(s, _respin(s.currentSong!, album: 'Other Album')),
  'currentSong.remoteArtworkUrl': (s) => _withSong(
        s,
        _respin(s.currentSong!, remoteArtworkUrl: 'https://img/other.jpg'),
      ),
  'currentSong.playCount': (s) =>
      _withSong(s, _respin(s.currentSong!, playCount: 5)),
  'isPlaying': (s) =>
      s.copyWith(playback: s.playback.copyWith(isPlaying: !s.isPlaying)),
  'isBuffering': (s) =>
      s.copyWith(playback: s.playback.copyWith(isBuffering: !s.isBuffering)),
  'duration': (s) => s.copyWith(
        playback: s.playback.copyWith(duration: const Duration(minutes: 4)),
      ),
};

void main() {
  group('PlayerState.differsForMiniPlayer (main mini player body)', () {
    test('is false for an equal state', () {
      final base = _base();
      expect(base.differsForMiniPlayer(base), isFalse);
    });

    for (final entry in _chromeFieldMutations.entries) {
      test('flipping ${entry.key} triggers a rebuild', () {
        final base = _base();
        final changed = entry.value(base);
        expect(
          base.differsForMiniPlayer(changed),
          isTrue,
          reason: '${entry.key} must not leave the mini player stale',
        );
        // Diff is directional in the call site's sense: (prev, curr).
        expect(changed.differsForMiniPlayer(base), isTrue);
      });
    }

    test('position-only ticks do NOT trigger a rebuild', () {
      final base = _base();
      final ticked = base.copyWith(
        playback: base.playback.copyWith(
          position: const Duration(milliseconds: 1234),
        ),
      );
      expect(base.differsForMiniPlayer(ticked), isFalse);
    });

    test('unrelated DspSlice parameters do NOT trigger a rebuild', () {
      final base = _base();
      final tweaked = base.copyWith(
        dsp: base.dsp.copyWith(virtualizerStrength: 0.7, reverbWetDry: 0.45),
      );
      expect(base.differsForMiniPlayer(tweaked), isFalse);
    });

    test('state the mini player does not paint does NOT trigger a rebuild', () {
      final base = _base();
      final unrendered = base.copyWith(
        playback: base.playback.copyWith(
          isShuffle: true,
          volume: 0.33,
          sleepTimerRemaining: const Duration(minutes: 20),
        ),
        lyricsSlice: base.lyricsSlice.copyWith(isLyricsVisible: true),
      );
      expect(base.differsForMiniPlayer(unrendered), isFalse);
    });
  });

  group('PlayerState.differsForMiniPlayerHorizontal (48dp row)', () {
    test('is false for an equal state', () {
      final base = _base();
      expect(base.differsForMiniPlayerHorizontal(base), isFalse);
    });

    for (final entry in _horizontalFieldMutations.entries) {
      test('flipping ${entry.key} triggers a rebuild', () {
        final base = _base();
        final changed = entry.value(base);
        expect(
          base.differsForMiniPlayerHorizontal(changed),
          isTrue,
          reason: '${entry.key} must not leave the horizontal row stale',
        );
      });
    }

    test('position-only ticks do NOT trigger a rebuild', () {
      final base = _base();
      final ticked = base.copyWith(
        playback: base.playback.copyWith(
          position: const Duration(milliseconds: 1234),
        ),
      );
      expect(base.differsForMiniPlayerHorizontal(ticked), isFalse);
    });

    test('unrelated DspSlice parameters do NOT trigger a rebuild', () {
      final base = _base();
      final tweaked = base.copyWith(
        dsp: base.dsp.copyWith(virtualizerStrength: 0.7, reverbWetDry: 0.45),
      );
      expect(base.differsForMiniPlayerHorizontal(tweaked), isFalse);
    });

    test('queue and error changes do NOT trigger a rebuild', () {
      final base = _base();
      final queueChanged = _chromeFieldMutations['queue content']!(base);
      expect(base.differsForMiniPlayerHorizontal(queueChanged), isFalse);

      final indexChanged = _chromeFieldMutations['currentIndex']!(base);
      expect(base.differsForMiniPlayerHorizontal(indexChanged), isFalse);

      final errored = _chromeFieldMutations['errorMessage']!(base);
      expect(base.differsForMiniPlayerHorizontal(errored), isFalse);
    });
  });

  group('the two gates are deliberately not the same set', () {
    test('the carousel watches the queue, the row does not', () {
      final base = _base();
      final queueChanged = _chromeFieldMutations['queue content']!(base);
      expect(base.differsForMiniPlayer(queueChanged), isTrue);
      expect(base.differsForMiniPlayerHorizontal(queueChanged), isFalse);
    });

    test('the carousel watches the error bar, the row does not', () {
      final base = _base();
      final errored = _chromeFieldMutations['errorMessage']!(base);
      expect(base.differsForMiniPlayer(errored), isTrue);
      expect(base.differsForMiniPlayerHorizontal(errored), isFalse);
    });

    test('the row watches every song column, the carousel only display ones',
        () {
      final base = _base();
      final albumOnly = _withSong(
        base,
        _respin(base.currentSong!, album: 'Other Album'),
      );
      expect(base.differsForMiniPlayer(albumOnly), isFalse);
      expect(base.differsForMiniPlayerHorizontal(albumOnly), isTrue);
    });
  });

  group('regression: every field the mini player paints is caught', () {
    // This is the bug that motivated the extraction: one of these silently
    // falling out of a gate leaves the mini player showing stale metadata.
    final renderedMutations = <String, PlayerState Function(PlayerState)>{
      'title': (s) => _withSong(s, _respin(s.currentSong!, title: 'Renamed')),
      'artist': (s) =>
          _withSong(s, _respin(s.currentSong!, artist: 'Other Artist')),
      'artwork': (s) => _withSong(
            s,
            _respin(s.currentSong!, remoteArtworkUrl: 'https://img/other.jpg'),
          ),
      'isPlaying': (s) =>
          s.copyWith(playback: s.playback.copyWith(isPlaying: !s.isPlaying)),
      'isBuffering': (s) => s.copyWith(
          playback: s.playback.copyWith(isBuffering: !s.isBuffering)),
      'duration': (s) => s.copyWith(
            playback: s.playback.copyWith(duration: const Duration(minutes: 4)),
          ),
    };

    for (final entry in renderedMutations.entries) {
      test('${entry.key} rebuilds both variants', () {
        final base = _base();
        final changed = entry.value(base);
        expect(base.differsForMiniPlayer(changed), isTrue);
        expect(base.differsForMiniPlayerHorizontal(changed), isTrue);
      });
    }

    test('queue identity rebuilds the carousel body', () {
      final base = _base();
      for (final key in ['queue content', 'queue length']) {
        final changed = _chromeFieldMutations[key]!(base);
        expect(base.differsForMiniPlayer(changed), isTrue, reason: key);
      }
    });
  });
}
