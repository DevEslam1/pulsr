// Regression test for P0-1.3: casting a mixed queue must not carry the current
// track's position onto a different file. The (startIndex, startPositionMs)
// pair is the contract with the cast renderer.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/presentation/widgets/pulsr_cast_sheet.dart';

SongsTableData song(int id,
    {String source = SongSource.local, String? path, bool? isDownloaded}) {
  return SongsTableData(
    id: id,
    title: 'Track $id',
    artist: 'Artist',
    album: 'Album',
    durationMs: 200000,
    path: path ?? '/music/$id.flac',
    isFavorite: false,
    isMissing: false,
    isDownloaded: isDownloaded ?? source == SongSource.local,
    playCount: 0,
    lastPositionMs: 0,
    source: source,
  );
}

void main() {
  group('selectCastableQueue', () {
    final local1 = song(1);
    final youtube = song(2, source: SongSource.youtube, path: 'ytmusic://vid2');
    final remote = song(3,
        source: SongSource.remote, path: 'http://127.0.0.1:8080/stream/3.flac');
    final local4 = song(4);
    final radio = song(5,
        source: SongSource.radio, path: 'https://stream.example/radio.mp3');

    test('anchor in the middle keeps its remapped index and its offset', () {
      final selection = selectCastableQueue(
        queue: [local1, youtube, remote, local4, radio],
        currentSong: local4,
        position: const Duration(seconds: 42),
      );

      expect(selection.items.map((s) => s.id), [1, 4]);
      expect((selection.startIndex, selection.startPositionMs), (1, 42000));
    });

    test('non-castable anchor resets the offset to zero', () {
      final selection = selectCastableQueue(
        queue: [local1, youtube, remote, local4],
        currentSong: youtube,
        position: const Duration(seconds: 42),
      );

      expect(selection.items.map((s) => s.id), [1, 4]);
      expect((selection.startIndex, selection.startPositionMs), (0, 0),
          reason: 'the position belongs to the YouTube row, not to track 1');
    });

    test('net-library anchor (remote source) also resets the offset', () {
      final selection = selectCastableQueue(
        queue: [local1, remote, local4],
        currentSong: remote,
        position: const Duration(minutes: 2),
      );

      expect(selection.items.map((s) => s.id), [1, 4]);
      expect((selection.startIndex, selection.startPositionMs), (0, 0));
    });

    test('no current song starts the first castable track at zero', () {
      final selection = selectCastableQueue(
        queue: [youtube, local4],
        position: const Duration(seconds: 10),
      );

      expect((selection.startIndex, selection.startPositionMs), (0, 0));
    });

    test('queue with nothing castable is reported empty', () {
      final selection = selectCastableQueue(
        queue: [youtube, remote, radio],
        currentSong: youtube,
        position: const Duration(seconds: 5),
      );

      expect(selection.isEmpty, isTrue);
      expect((selection.startIndex, selection.startPositionMs), (0, 0));
    });

    test('downloaded YouTube rows stay castable', () {
      final downloaded = song(9,
          source: SongSource.youtube,
          path: 'content://media/audio/9',
          isDownloaded: true);

      final selection = selectCastableQueue(
        queue: [downloaded],
        currentSong: downloaded,
        position: const Duration(seconds: 7),
      );

      expect(selection.items, hasLength(1));
      expect((selection.startIndex, selection.startPositionMs), (0, 7000));
    });
  });
}
