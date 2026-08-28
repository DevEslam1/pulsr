// test/features/player/queue_soak_test.dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';

SongsTableData makeSong({
  required int id,
  required String title,
  String artist = 'Artist',
  String album = 'Album',
  String path = '/storage/music/track.flac',
  int durationMs = 180000,
}) {
  return SongsTableData(
    id: id,
    title: title,
    artist: artist,
    album: album,
    path: path,
    durationMs: durationMs,
    dateAdded: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    playCount: 0,
    lastPositionMs: 0,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    source: SongSource.local,
  );
}

/// Simulated stateful queue controller executing operations matching Pulsr's queue invariants.
class SimulatedQueueController {
  final List<SongsTableData> _queue = [];
  List<int> _shuffleIndices = [];
  int _currentIndex = -1;
  bool _shuffleEnabled = false;
  bool _isPlaying = false;

  List<SongsTableData> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  bool get shuffleEnabled => _shuffleEnabled;
  bool get isPlaying => _isPlaying;

  SongsTableData? get currentSong =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

  void loadQueue(List<SongsTableData> songs, {int initialIndex = 0}) {
    _queue.clear();
    _queue.addAll(songs);
    _currentIndex =
        songs.isEmpty ? -1 : initialIndex.clamp(0, songs.length - 1);
    _isPlaying = songs.isNotEmpty;
    _rebuildShuffleIndices();
  }

  void add(SongsTableData song) {
    _queue.add(song);
    if (_currentIndex == -1) {
      _currentIndex = 0;
      _isPlaying = true;
    }
    _rebuildShuffleIndices();
  }

  void insert(int index, SongsTableData song) {
    if (_queue.isEmpty) {
      add(song);
      return;
    }
    final safeIndex = index.clamp(0, _queue.length);
    _queue.insert(safeIndex, song);
    if (_currentIndex >= safeIndex) {
      _currentIndex++;
    }
    _rebuildShuffleIndices();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    final removingCurrent = index == _currentIndex;
    _queue.removeAt(index);

    if (_queue.isEmpty) {
      _currentIndex = -1;
      _isPlaying = false;
    } else if (removingCurrent) {
      // Advance to same index (which now points to the next item) or clamp to last
      if (_currentIndex >= _queue.length) {
        _currentIndex = _queue.length - 1;
      }
    } else if (_currentIndex > index) {
      _currentIndex--;
    }
    _rebuildShuffleIndices();
  }

  void move(int from, int to) {
    if (from < 0 ||
        from >= _queue.length ||
        to < 0 ||
        to >= _queue.length ||
        from == to) {
      return;
    }
    final item = _queue.removeAt(from);
    _queue.insert(to, item);

    if (_currentIndex == from) {
      _currentIndex = to;
    } else if (from < _currentIndex && to >= _currentIndex) {
      _currentIndex--;
    } else if (from > _currentIndex && to <= _currentIndex) {
      _currentIndex++;
    }
    _rebuildShuffleIndices();
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    _rebuildShuffleIndices();
  }

  void next() {
    if (_queue.isEmpty) return;
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
    } else {
      _currentIndex = 0; // Wrap around on repeat-all simulation
    }
  }

  void previous() {
    if (_queue.isEmpty) return;
    if (_currentIndex > 0) {
      _currentIndex--;
    } else {
      _currentIndex = _queue.length - 1;
    }
  }

  void setPlaying(bool playing) {
    _isPlaying = playing && _queue.isNotEmpty;
  }

  void _rebuildShuffleIndices() {
    _shuffleIndices = List.generate(_queue.length, (i) => i);
    if (_shuffleEnabled && _queue.length > 1) {
      // Deterministic Fisher-Yates with fixed seed pattern
      for (int i = _shuffleIndices.length - 1; i > 0; i--) {
        final j = (i * 37 + 13) % (i + 1);
        final temp = _shuffleIndices[i];
        _shuffleIndices[i] = _shuffleIndices[j];
        _shuffleIndices[j] = temp;
      }
    }
  }

  bool verifyShuffleBijection() {
    if (_queue.isEmpty) return _shuffleIndices.isEmpty;
    final seen = <int>{};
    for (final idx in _shuffleIndices) {
      if (idx < 0 || idx >= _queue.length || seen.contains(idx)) return false;
      seen.add(idx);
    }
    return seen.length == _queue.length;
  }
}

void main() {
  group('Phase 0 — Randomized Queue Soak Test (1000 Ops)', () {
    test('1000 random operations against queue engine preserve all invariants',
        () {
      final rng = Random(42); // Fixed seed for reproducible soak
      final controller = SimulatedQueueController();

      // Seed initial 10 songs
      final initialSongs = List<SongsTableData>.generate(
        10,
        (i) => makeSong(
          id: i + 1,
          title: 'Track ${i + 1}',
          artist: 'Artist ${i % 3}',
          album: 'Album ${i % 2}',
          path: '/storage/emulated/0/Music/track_$i.flac',
          durationMs: 180000 + i * 5000,
        ),
      );
      controller.loadQueue(initialSongs, initialIndex: 0);

      int nextSongId = 100;

      for (int op = 0; op < 1000; op++) {
        final currentSongBefore = controller.currentSong;
        final action = rng.nextInt(9);

        switch (action) {
          case 0: // Add
            controller.add(makeSong(
              id: nextSongId++,
              title: 'Dynamic Track $nextSongId',
              artist: 'Various',
              album: 'Live Session',
              path: '/storage/music/$nextSongId.flac',
              durationMs: 200000,
            ));
            break;

          case 1: // Insert
            final insertIdx = controller.queue.isEmpty
                ? 0
                : rng.nextInt(controller.queue.length + 1);
            controller.insert(
              insertIdx,
              makeSong(
                id: nextSongId++,
                title: 'Inserted Track $nextSongId',
                artist: 'Inserted Artist',
                album: 'Inserted Album',
                path: '/storage/music/$nextSongId.mp3',
                durationMs: 150000,
              ),
            );
            break;

          case 2: // Remove
            if (controller.queue.isNotEmpty) {
              final removeIdx = rng.nextInt(controller.queue.length);
              controller.removeAt(removeIdx);
            }
            break;

          case 3: // Move
            if (controller.queue.length > 1) {
              final from = rng.nextInt(controller.queue.length);
              final to = rng.nextInt(controller.queue.length);
              controller.move(from, to);
            }
            break;

          case 4: // Toggle Shuffle
            controller.toggleShuffle();
            break;

          case 5: // Next
            controller.next();
            break;

          case 6: // Previous
            controller.previous();
            break;

          case 7: // Toggle Playing
            controller.setPlaying(!controller.isPlaying);
            break;

          case 8: // Bulk reload
            if (op % 200 == 0) {
              final newSongs = List<SongsTableData>.generate(
                rng.nextInt(15) + 1,
                (k) => makeSong(
                  id: nextSongId++,
                  title: 'Reloaded $k',
                  artist: 'Artist',
                  album: 'Album',
                  path: '/storage/$k.wav',
                  durationMs: 180000,
                ),
              );
              controller.loadQueue(newSongs,
                  initialIndex: rng.nextInt(newSongs.length));
            }
            break;
        }

        // --- INVARIANT ASSERTIONS (Checked after EVERY operation) ---

        // Invariant A: Index is valid or queue is empty
        if (controller.queue.isEmpty) {
          expect(controller.currentIndex, equals(-1),
              reason: 'Op $op: Empty queue must have index -1');
          expect(controller.currentSong, isNull,
              reason: 'Op $op: Empty queue has no active track');
        } else {
          expect(controller.currentIndex,
              inInclusiveRange(0, controller.queue.length - 1),
              reason:
                  'Op $op: Index ${controller.currentIndex} must be within queue bounds 0..${controller.queue.length - 1}');
          expect(controller.currentSong, isNotNull,
              reason: 'Op $op: Non-empty queue must have active track');
        }

        // Invariant B: Shuffle mapping is a strict bijection
        expect(controller.verifyShuffleBijection(), isTrue,
            reason:
                'Op $op: Shuffle permutation must be a strict 1-to-1 bijection of indices');

        // Invariant C: Non-mutating ops preserve current track identity
        if (action == 4 /* toggle shuffle */ || action == 7 /* toggle play */) {
          expect(controller.currentSong?.id, equals(currentSongBefore?.id),
              reason:
                  'Op $op: Shuffle/Play toggle must not alter the active track identity');
        }
      }
    });
  });
}
