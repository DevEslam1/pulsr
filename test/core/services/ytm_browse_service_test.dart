// test/core/services/ytm_browse_service_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/ytm_browse_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

class MockYtmService extends Mock implements YtmService {}

YtmTrack _track(int i) => YtmTrack(
      videoId: 'video$i',
      title: 'Track $i',
      artist: 'Artist $i',
      duration: Duration(seconds: 60 + i),
      artworkUrl: 'https://art/$i.jpg',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockYtmService ytm;
  late YtmBrowseService browse;

  setUp(() {
    ytm = MockYtmService();
    browse = YtmBrowseService(ytm);
  });

  group('YtmBrowseItem', () {
    test('hasKnownDuration is false only for zero durations', () {
      const zero =
          YtmBrowseItem(id: 'a', title: 't', subtitle: 's', type: 'song');
      const known = YtmBrowseItem(
          id: 'b',
          title: 't',
          subtitle: 's',
          type: 'song',
          duration: Duration(seconds: 1));
      expect(zero.hasKnownDuration, isFalse);
      expect(known.hasKnownDuration, isTrue);
    });

    test('toYtmTrack carries id/title/subtitle/duration/artwork', () {
      const item = YtmBrowseItem(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        subtitle: 'Rick Astley',
        artworkUrl: 'https://art/x.jpg',
        type: 'song',
        duration: Duration(minutes: 3, seconds: 33),
      );
      final track = item.toYtmTrack();
      expect(track.videoId, 'dQw4w9WgXcQ');
      expect(track.title, 'Never Gonna Give You Up');
      expect(track.artist, 'Rick Astley');
      expect(track.duration, const Duration(minutes: 3, seconds: 33));
      expect(track.artworkUrl, 'https://art/x.jpg');
    });
  });

  group('getTrendingCharts', () {
    test('uses charts and caps the list at eight entries', () async {
      when(() => ytm.getCharts(limit: 15))
          .thenAnswer((_) async => List.generate(12, (i) => _track(i)));

      final items = await browse.getTrendingCharts();

      expect(items.length, 8);
      expect(items.first.id, 'video0');
      expect(items.first.type, 'song');
      expect(items.first.subtitle, 'Artist 0');
      verifyNever(() => ytm.trending(limit: any(named: 'limit')));
    });

    test('empty charts fall through to trending', () async {
      when(() => ytm.getCharts(limit: 15)).thenAnswer((_) async => []);
      when(() => ytm.trending(limit: 15))
          .thenAnswer((_) async => List.generate(3, (i) => _track(100 + i)));

      final items = await browse.getTrendingCharts();

      expect(items.map((e) => e.id), ['video100', 'video101', 'video102']);
    });

    test('a charts exception falls through to trending', () async {
      when(() => ytm.getCharts(limit: 15)).thenThrow(StateError('charts down'));
      when(() => ytm.trending(limit: 15)).thenAnswer((_) async => [_track(7)]);

      final items = await browse.getTrendingCharts();

      expect(items.single.id, 'video7');
    });

    test('charts + trending failures fall back to search', () async {
      when(() => ytm.getCharts(limit: 15)).thenThrow(StateError('no'));
      when(() => ytm.trending(limit: 15)).thenThrow(StateError('no'));
      when(() => ytm.searchWithFallback('Top Global Hits', limit: 15))
          .thenAnswer((_) async => [_track(42)]);

      final items = await browse.getTrendingCharts();

      expect(items.single.id, 'video42');
    });

    test('everything failing yields an empty list, never fabricated IDs',
        () async {
      when(() => ytm.getCharts(limit: 15)).thenAnswer((_) async => []);
      when(() => ytm.trending(limit: 15)).thenAnswer((_) async => []);
      when(() => ytm.searchWithFallback('Top Global Hits', limit: 15))
          .thenThrow(StateError('offline'));

      expect(await browse.getTrendingCharts(), isEmpty);
    });

    test('search fallback that is also empty yields an empty list', () async {
      when(() => ytm.getCharts(limit: 15)).thenAnswer((_) async => []);
      when(() => ytm.trending(limit: 15)).thenAnswer((_) async => []);
      when(() => ytm.searchWithFallback('Top Global Hits', limit: 15))
          .thenAnswer((_) async => []);

      expect(await browse.getTrendingCharts(), isEmpty);
    });
  });

  group('getNewReleases', () {
    test('maps search results and caps at eight', () async {
      when(() => ytm.searchWithFallback('New Music Releases', limit: 15))
          .thenAnswer((_) async => List.generate(10, (i) => _track(i)));

      final items = await browse.getNewReleases();

      expect(items.length, 8);
      expect(items.last.id, 'video7');
    });

    test('a search failure yields an empty list', () async {
      when(() => ytm.searchWithFallback('New Music Releases', limit: 15))
          .thenThrow(StateError('network'));
      expect(await browse.getNewReleases(), isEmpty);
    });

    test('an empty search result yields an empty list', () async {
      when(() => ytm.searchWithFallback('New Music Releases', limit: 15))
          .thenAnswer((_) async => []);
      expect(await browse.getNewReleases(), isEmpty);
    });
  });

  group('getMoodsAndGenres', () {
    test('uses the native moods bridge first', () async {
      when(() => ytm.getMoods(limit: 15)).thenAnswer((_) async => [_track(1)]);

      final items = await browse.getMoodsAndGenres();

      expect(items.single.id, 'video1');
      verifyNever(() => ytm.searchWithFallback('Popular Hits Playlist',
          limit: any(named: 'limit')));
    });

    test('empty moods fall back to a popular-hits search', () async {
      when(() => ytm.getMoods(limit: 15)).thenAnswer((_) async => []);
      when(() => ytm.searchWithFallback('Popular Hits Playlist', limit: 15))
          .thenAnswer((_) async => [_track(2)]);

      final items = await browse.getMoodsAndGenres();

      expect(items.single.id, 'video2');
    });

    test('a moods exception falls back to search', () async {
      when(() => ytm.getMoods(limit: 15)).thenThrow(StateError('bridge'));
      when(() => ytm.searchWithFallback('Popular Hits Playlist', limit: 15))
          .thenAnswer((_) async => [_track(3)]);

      expect((await browse.getMoodsAndGenres()).single.id, 'video3');
    });

    test('both engines failing yields empty, not fabricated content', () async {
      when(() => ytm.getMoods(limit: 15)).thenThrow(StateError('bridge'));
      when(() => ytm.searchWithFallback('Popular Hits Playlist', limit: 15))
          .thenThrow(StateError('offline'));

      expect(await browse.getMoodsAndGenres(), isEmpty);
    });
  });

  group('getHomeFeed', () {
    void stubAll({int charts = 1, int releases = 1, int moods = 1}) {
      when(() => ytm.getCharts(limit: 15))
          .thenAnswer((_) async => List.generate(charts, (i) => _track(i)));
      when(() => ytm.searchWithFallback('New Music Releases', limit: 15))
          .thenAnswer(
              (_) async => List.generate(releases, (i) => _track(10 + i)));
      when(() => ytm.getMoods(limit: 15))
          .thenAnswer((_) async => List.generate(moods, (i) => _track(20 + i)));
    }

    test('builds the three curated sections and caches the feed', () async {
      stubAll();

      final first = await browse.getHomeFeed();
      expect(first.map((s) => s.title), [
        'Top Charts & Trending',
        'New Releases',
        'Moods & Genres',
      ]);
      expect(first.first.subtitle, 'Most played tracks right now');
      expect(first.first.items.single.id, 'video0');

      // Second call inside the TTL must not touch the network again.
      final second = await browse.getHomeFeed();
      expect(identical(second, first), isTrue);
      verify(() => ytm.getCharts(limit: 15)).called(1);
      verify(() => ytm.searchWithFallback('New Music Releases', limit: 15))
          .called(1);
    });

    test('drops sections with no items', () async {
      stubAll(charts: 2, releases: 0, moods: 0);

      final sections = await browse.getHomeFeed();

      expect(sections.length, 1);
      expect(sections.single.title, 'Top Charts & Trending');
    });

    test('an all-empty feed is not cached, so the next call retries', () async {
      stubAll(charts: 0, releases: 0, moods: 0);

      expect(await browse.getHomeFeed(), isEmpty);
      expect(await browse.getHomeFeed(), isEmpty);

      verify(() => ytm.getCharts(limit: 15)).called(2);
    });

    test('concurrent callers share one in-flight fetch', () async {
      final charts = Completer<List<YtmTrack>>();
      final releases = Completer<List<YtmTrack>>();
      final moods = Completer<List<YtmTrack>>();
      when(() => ytm.getCharts(limit: 15)).thenAnswer((_) => charts.future);
      when(() => ytm.searchWithFallback('New Music Releases', limit: 15))
          .thenAnswer((_) => releases.future);
      when(() => ytm.getMoods(limit: 15)).thenAnswer((_) => moods.future);

      final futureA = browse.getHomeFeed();
      final futureB = browse.getHomeFeed();

      charts.complete([_track(0)]);
      releases.complete([_track(1)]);
      moods.complete([_track(2)]);

      final results = await Future.wait([futureA, futureB]);
      expect(results[0].length, 3);
      expect(identical(results[0], results[1]), isTrue);
      verify(() => ytm.getCharts(limit: 15)).called(1);
    });

    test('clearCache drops the cached feed and releases pending waiters',
        () async {
      stubAll();
      await browse.getHomeFeed();
      browse.clearCache();

      final charts = Completer<List<YtmTrack>>();
      final releases = Completer<List<YtmTrack>>();
      final moods = Completer<List<YtmTrack>>();
      when(() => ytm.getCharts(limit: 15)).thenAnswer((_) => charts.future);
      when(() => ytm.searchWithFallback('New Music Releases', limit: 15))
          .thenAnswer((_) => releases.future);
      when(() => ytm.getMoods(limit: 15)).thenAnswer((_) => moods.future);

      // First caller owns the fetch; the second joins the shared pending feed.
      final owner = browse.getHomeFeed();
      final joiner = browse.getHomeFeed();

      browse.clearCache();

      releases.complete([_track(1)]);
      moods.complete([_track(2)]);
      charts.complete([_track(0)]);

      // The joiner is released with an empty feed instead of hanging on a
      // dropped completer.
      expect(await joiner, isEmpty);
      expect((await owner).length, 3);
    });
  });
}
