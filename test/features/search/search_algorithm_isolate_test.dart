import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/search_algorithm_utils.dart';
import 'package:pulsr/data/db/app_database.dart';

void main() {
  List<SongsTableData> buildSongs(int count) => List.generate(
        count,
        (i) => SongsTableData(
          id: i + 1,
          title: 'Song ${i % 40}',
          artist: i % 2 == 0 ? 'Artist A' : 'Artist B',
          album: 'Album ${i % 7}',
          durationMs: 180000,
          path: '/music/${i % 40}/track_$i.mp3',
          source: SongSource.local,
          playCount: 0,
          dateAdded: 0,
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          lastPositionMs: 0,
        ),
        growable: false,
      );

  test('isolate fuzzy ranking matches the in-isolate implementation', () async {
    final songs = buildSongs(320);
    const query = 'song 12';
    final sync = SearchAlgorithmUtils.filterWithFuzzy(songs, query, 'All',
        maxResults: 200);
    final async = await Isolate.run(() => SearchAlgorithmUtils.filterWithFuzzy(
        songs, query, 'All',
        maxResults: 200));
    expect(async.map((song) => song.id).toList(),
        sync.map((song) => song.id).toList());
    expect(async, isNotEmpty);
  });
}
