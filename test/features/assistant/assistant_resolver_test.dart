// test/features/assistant/assistant_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/assistant/assistant_query.dart';
import 'package:pulsr/features/assistant/assistant_resolver.dart';
import 'package:pulsr/features/assistant/assistant_strings.dart';

void main() {
  const searchHit = <int>[11, 12, 13];

  AssistantResolver buildResolver({
    List<int> search = searchHit,
    List<int> playlist = const <int>[],
    List<int> favorites = const <int>[21, 22],
    List<int> lastAlbum = const <int>[31, 32],
    List<String>? searchCalls,
    List<String>? playlistCalls,
    bool failSearch = false,
    bool failPlaylist = false,
  }) =>
      AssistantResolver(
        searchSongIds: (query) async {
          searchCalls?.add(query);
          if (failSearch) throw StateError('search failed');
          return search;
        },
        playlistSongIds: (name) async {
          playlistCalls?.add(name);
          if (failPlaylist) throw StateError('playlist failed');
          return playlist;
        },
        favoritesSongIds: () async => favorites,
        lastAlbumSongIds: () async => lastAlbum,
      );

  group('search-intent extras', () {
    test('a playlist request plays the playlist in order', () async {
      final calls = <String>[];
      final resolver = buildResolver(
        playlist: const [4, 5],
        playlistCalls: calls,
      );
      final resolution = await resolver.resolveSearchExtras(
        parseSearchExtras({'PLAYLIST': 'Chill Mix'}),
      );

      expect(resolution, isA<AssistantPlayPlan>());
      final plan = resolution as AssistantPlayPlan;
      expect(plan.songIds, [4, 5]);
      expect(plan.startIndex, 0);
      expect(plan.shuffle, isFalse);
      expect(plan.title, 'Chill Mix');
      expect(plan.source, AssistantPlanSource.playlist);
      expect(calls, ['chill mix']);
    });

    test('an unknown playlist falls back to a song search', () async {
      final searchCalls = <String>[];
      final resolver = buildResolver(searchCalls: searchCalls);
      final resolution = await resolver.resolveSearchExtras(
        parseSearchExtras({'PLAYLIST': 'Road Trip'}),
      );

      final plan = resolution as AssistantPlayPlan;
      expect(plan.songIds, searchHit);
      expect(plan.source, AssistantPlanSource.search);
      expect(plan.title, 'Road Trip');
      expect(searchCalls, ['road trip']);
    });

    test('nothing found for a playlist fails with the term in the message',
        () async {
      final resolver = buildResolver(search: const <int>[]);
      final resolution = await resolver.resolveSearchExtras(
        parseSearchExtras({'PLAYLIST': 'Road Trip'}),
      );

      expect(resolution, isA<AssistantResolutionFailure>());
      expect(
        (resolution as AssistantResolutionFailure).message,
        AssistantStrings.nothingMatched('Road Trip'),
      );
    });

    test('album, artist, genre, song and title all use the search port',
        () async {
      const expected = <String, AssistantPlanSource>{
        'ALBUM': AssistantPlanSource.album,
        'ARTIST': AssistantPlanSource.artist,
        'GENRE': AssistantPlanSource.genre,
        'SONG': AssistantPlanSource.song,
        'TITLE': AssistantPlanSource.title,
        'QUERY': AssistantPlanSource.search,
      };
      for (final entry in expected.entries) {
        final calls = <String>[];
        final resolver = buildResolver(searchCalls: calls);
        final resolution = await resolver.resolveSearchExtras(
          parseSearchExtras({entry.key: 'So What'}),
        );
        final plan = resolution as AssistantPlayPlan;
        expect(plan.source, entry.value, reason: entry.key);
        expect(plan.title, 'So What', reason: entry.key);
        expect(calls, ['so what'], reason: entry.key);
      }
    });
  });

  group('natural-language intents', () {
    test('bare text searches the library', () async {
      final resolver = buildResolver();
      final resolution =
          await resolver.resolveText(parseAssistantText('blue in green'));

      final plan = resolution as AssistantPlayPlan;
      expect(plan.songIds, searchHit);
      expect(plan.title, 'blue in green');
      expect(plan.source, AssistantPlanSource.search);
    });

    test('resume last album plays the last album without shuffling', () async {
      final resolver = buildResolver(lastAlbum: const [7, 8]);
      final resolution =
          await resolver.resolveText(parseAssistantText('resume last album'));

      final plan = resolution as AssistantPlayPlan;
      expect(plan.songIds, [7, 8]);
      expect(plan.title, AssistantStrings.lastAlbumTitle);
      expect(plan.source, AssistantPlanSource.lastAlbum);
      expect(plan.shuffle, isFalse);
    });

    test('shuffle favourites plays the favourites shuffled', () async {
      final resolver = buildResolver(favorites: const [3, 4, 5]);
      final resolution =
          await resolver.resolveText(parseAssistantText('shuffle favourites'));

      final plan = resolution as AssistantPlayPlan;
      expect(plan.songIds, [3, 4, 5]);
      expect(plan.shuffle, isTrue);
      expect(plan.source, AssistantPlanSource.favorites);
    });

    test('artist radio searches the artist and shuffles', () async {
      final calls = <String>[];
      final resolver = buildResolver(searchCalls: calls);
      final resolution = await resolver.resolveText(
        parseAssistantText('play Miles Davis radio'),
      );

      final plan = resolution as AssistantPlayPlan;
      expect(calls, ['miles davis']);
      expect(plan.shuffle, isTrue);
      expect(plan.title, 'Miles Davis radio');
      expect(plan.source, AssistantPlanSource.artistRadio);
    });

    test('a shuffled playlist keeps the shuffle flag', () async {
      final resolver = buildResolver(playlist: const [1, 2]);
      final resolution =
          await resolver.resolveText(parseAssistantText('shuffle rock'));

      final plan = resolution as AssistantPlayPlan;
      expect(plan.shuffle, isTrue);
      expect(plan.source, AssistantPlanSource.playlist);
    });

    test('resolveFavorites defaults to unshuffled playback', () async {
      final resolver = buildResolver();
      final plan = await resolver.resolveFavorites() as AssistantPlayPlan;
      expect(plan.shuffle, isFalse);
      expect(plan.title, AssistantStrings.favoritesTitle);
    });
  });

  group('failures', () {
    test('empty favourites report the dedicated message', () async {
      final resolver = buildResolver(favorites: const <int>[]);
      final resolution = await resolver.resolveFavorites();

      expect(resolution, isA<AssistantResolutionFailure>());
      expect(
        (resolution as AssistantResolutionFailure).message,
        AssistantStrings.noFavorites,
      );
    });

    test('no last album reports the dedicated message', () async {
      final resolver = buildResolver(lastAlbum: const <int>[]);
      final resolution = await resolver.resolveLastAlbum();

      expect(resolution, isA<AssistantResolutionFailure>());
      expect(
        (resolution as AssistantResolutionFailure).message,
        AssistantStrings.noLastAlbum,
      );
    });

    test('a throwing search port becomes a failure, not an exception',
        () async {
      final resolver = buildResolver(failSearch: true);
      final resolution = await resolver.resolveText(
        parseAssistantText('blue in green'),
      );

      expect(resolution, isA<AssistantResolutionFailure>());
      expect(
        (resolution as AssistantResolutionFailure).message,
        AssistantStrings.libraryUnavailable,
      );
    });

    test('a throwing playlist port becomes a failure', () async {
      final resolver = buildResolver(failPlaylist: true);
      final resolution = await resolver.resolveSearchExtras(
        parseSearchExtras({'PLAYLIST': 'Chill Mix'}),
      );

      expect(
        (resolution as AssistantResolutionFailure).message,
        AssistantStrings.libraryUnavailable,
      );
    });

    test('empty requests fail without touching the callbacks', () async {
      final resolver = buildResolver();
      final emptyText = AssistantTextIntent(
        kind: AssistantIntentKind.searchSongs,
        term: '',
        display: '',
        rawText: '',
      );
      expect(
        await resolver.resolveText(emptyText),
        isA<AssistantResolutionFailure>(),
      );
      expect(
        await resolver.resolveSearchExtras(
          const AssistantPlayRequest(
            field: AssistantExtraField.query,
            term: '',
            display: '',
          ),
        ),
        isA<AssistantResolutionFailure>(),
      );
    });
  });

  group('plan invariants', () {
    test('start index is clamped into range', () {
      final high = AssistantPlayPlan(
        songIds: const [1, 2, 3],
        title: 'x',
        source: AssistantPlanSource.search,
        startIndex: 99,
      );
      final negative = AssistantPlayPlan(
        songIds: const [1, 2, 3],
        title: 'x',
        source: AssistantPlanSource.search,
        startIndex: -4,
      );
      expect(high.startIndex, 2);
      expect(negative.startIndex, 0);
      expect(high.length, 3);
    });

    test('an empty queue keeps index zero', () {
      final plan = AssistantPlayPlan(
        songIds: const <int>[],
        title: 'x',
        source: AssistantPlanSource.search,
        startIndex: 5,
      );
      expect(plan.startIndex, 0);
    });

    test('song ids cannot be mutated by the player adapter', () {
      final plan = AssistantPlayPlan(
        songIds: const [1],
        title: 'x',
        source: AssistantPlanSource.search,
      );
      expect(() => plan.songIds.add(2), throwsUnsupportedError);
    });
  });
}
