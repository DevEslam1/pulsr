import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/search_algorithm_utils.dart';
import 'package:pulsr/data/db/app_database.dart';

SongsTableData _song({
  required int id,
  required String title,
  required String artist,
  String album = 'Album',
  String? codec,
  String? path,
}) {
  return SongsTableData(
    id: id,
    title: title,
    artist: artist,
    album: album,
    durationMs: 200000,
    path: path ?? '/music/$id.mp3',
    source: SongSource.local,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    lastPositionMs: 0,
    codec: codec,
  );
}

void main() {
  setUp(SearchAlgorithmUtils.clearCache);

  group('normalize', () {
    test('lowercases, trims and strips Latin accents', () {
      expect(SearchAlgorithmUtils.normalize('  Café  '), 'cafe');
      expect(SearchAlgorithmUtils.normalize('Señor'), 'senor');
    });

    test('strips Arabic diacritics and normalizes letter variants', () {
      expect(SearchAlgorithmUtils.normalize('أحمد'), 'احمد');
      expect(SearchAlgorithmUtils.normalize('مُحَمَّد'), 'محمد');
    });
  });

  group('levenshtein', () {
    test('is zero for identical strings', () {
      expect(SearchAlgorithmUtils.levenshtein('coldplay', 'coldplay'), 0);
    });

    test('detects a single transposition', () {
      expect(SearchAlgorithmUtils.levenshtein('clodplay', 'coldplay'), 2);
    });

    test('short-circuits when the length gap exceeds the tolerance', () {
      expect(SearchAlgorithmUtils.levenshtein('a', 'abcdefgh'), greaterThan(2));
    });
  });

  group('filterWithFuzzy', () {
    final songs = [
      _song(id: 1, title: 'Fix You', artist: 'Coldplay'),
      _song(id: 2, title: 'Bohemian Rhapsody', artist: 'Queen'),
    ];

    test('matches an artist typo via Levenshtein', () {
      final results =
          SearchAlgorithmUtils.filterWithFuzzy(songs, 'clodplay', 'Artists');
      expect(results.map((s) => s.artist), contains('Coldplay'));
    });

    test('ranks an exact title first', () {
      final pool = [
        _song(id: 1, title: 'Another Fix You', artist: 'X'),
        _song(id: 2, title: 'Fix You', artist: 'Y'),
      ];
      final results =
          SearchAlgorithmUtils.filterWithFuzzy(pool, 'fix you', 'Songs');
      expect(results.first.title, 'Fix You');
    });

    test('caps results at maxResultCount', () {
      final big = List.generate(
        SearchAlgorithmUtils.maxResultCount + 25,
        (i) => _song(id: i + 1, title: 'Song $i', artist: 'Artist'),
      );
      final results = SearchAlgorithmUtils.filterWithFuzzy(big, 'song', 'Songs');
      expect(results.length, SearchAlgorithmUtils.maxResultCount);
    });
  });

  // C-04: format filter chips.
  group('filterWithFuzzy format chips', () {
    final songs = [
      _song(id: 1, title: 'Lossless Track', artist: 'A', codec: 'FLAC'),
      _song(id: 2, title: 'Lossy Track', artist: 'A', codec: 'MP3'),
      _song(id: 3, title: 'Alac Track', artist: 'A', codec: 'ALAC'),
      _song(id: 4, title: 'Unknown Track', artist: 'A', codec: null,
          path: '/music/4.flac'),
    ];

    test('FLAC keeps only flac codecs', () {
      final results = SearchAlgorithmUtils.filterWithFuzzy(songs, 'track', 'FLAC');
      expect(results.map((s) => s.id), containsAll([1, 4]));
      expect(results.map((s) => s.id), isNot(contains(2)));
    });

    test('MP3 keeps only mp3 codecs', () {
      final results = SearchAlgorithmUtils.filterWithFuzzy(songs, 'track', 'MP3');
      expect(results.map((s) => s.id), [2]);
    });

    test('Lossless keeps flac/alac (codec or extension)', () {
      final results =
          SearchAlgorithmUtils.filterWithFuzzy(songs, 'track', 'Lossless');
      expect(results.map((s) => s.id), containsAll([1, 3, 4]));
      expect(results.map((s) => s.id), isNot(contains(2)));
    });

    test('format filter still honours the text query', () {
      final results =
          SearchAlgorithmUtils.filterWithFuzzy(songs, 'lossless', 'Lossless');
      expect(results.map((s) => s.id), [1]);
    });

    test('falls back to file extension when codec is null', () {
      final mp3 = [
        _song(id: 9, title: 'Ext', artist: 'A', codec: null,
            path: '/music/9.MP3'),
      ];
      final results = SearchAlgorithmUtils.filterWithFuzzy(mp3, 'ext', 'MP3');
      expect(results.map((s) => s.id), [9]);
    });
  });
}
