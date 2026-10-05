// test/features/ytm_search/ytm_search_cubit_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_search_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_search_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtmService extends Mock implements YtmService {}

YtmTrack _track(String id, [String? title]) => YtmTrack(
      videoId: id,
      title: title ?? id,
      artist: 'Artist',
      duration: const Duration(minutes: 3),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockYtmService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = MockYtmService();
    when(() => service.invalidatePoToken()).thenAnswer((_) async {});
    when(() => service.ensurePoTokenReady()).thenAnswer((_) async => true);
    when(() => service.isBotCoolingDown).thenReturn(false);
    when(() => service.botCooldownNotifier)
        .thenReturn(ValueNotifier<bool>(false));
  });

  YtmSearchCubit build() {
    final cubit = YtmSearchCubit(service: service);
    addTearDown(cubit.close);
    return cubit;
  }

  group('initial state', () {
    test('is idle with no query/results/error and idle phase', () {
      final cubit = build();
      expect(cubit.state.query, isEmpty);
      expect(cubit.state.results, isEmpty);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.phase, SearchPhase.idle);
      expect(cubit.state.hasSearched, isFalse);
    });

    test('loads persisted history into historyNotifier (capped at 10)', () async {
      SharedPreferences.setMockInitialValues({
        'ytm_search_history': List.generate(15, (i) => 'query$i'),
      });
      final cubit = build();
      await pumpEventQueue();
      expect(cubit.historyNotifier.value.length, 10);
      expect(cubit.historyNotifier.value.first, 'query0');
    });
  });

  group('SearchPhase getter', () {
    test('reports error, fetching, displaying and debouncing', () {
      const withError = YtmSearchState(query: 'x', errorMessage: 'boom');
      expect(withError.phase, SearchPhase.error);
      expect(const YtmSearchState(query: 'x', isLoading: true).phase,
          SearchPhase.fetching);
      expect(
          YtmSearchState(query: 'x', results: [_track('aaaaaaaaaaa')]).phase,
          SearchPhase.displaying);
      expect(const YtmSearchState(query: 'x').phase, SearchPhase.debouncing);
      expect(const YtmSearchState().phase, SearchPhase.idle);
      expect(const YtmSearchState(errorMessage: '').phase, SearchPhase.idle);
    });

    test('isTerminal only for displaying and error', () {
      expect(SearchPhase.displaying.isTerminal, isTrue);
      expect(SearchPhase.error.isTerminal, isTrue);
      expect(SearchPhase.idle.isTerminal, isFalse);
      expect(SearchPhase.debouncing.isTerminal, isFalse);
      expect(SearchPhase.fetching.isTerminal, isFalse);
    });
  });

  group('onQueryChanged', () {
    test('sets query immediately then searches after the debounce', () async {
      when(() => service.searchWithFallback(any()))
          .thenAnswer((_) async => [_track('dQw4w9WgXcQ', 'Hit')]);

      final cubit = build();
      cubit.onQueryChanged('rick');
      expect(cubit.state.query, 'rick');

      // Before the debounce fires, no search is made.
      verifyNever(() => service.searchWithFallback(any()));
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();

      verify(() => service.searchWithFallback('rick')).called(1);
      expect(cubit.state.results.single.title, 'Hit');
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.errorMessage, isNull);
    });

    test('debounces rapid typing: only the last query is searched', () async {
      when(() => service.searchWithFallback(any()))
          .thenAnswer((_) async => const []);

      final cubit = build();
      cubit.onQueryChanged('a');
      cubit.onQueryChanged('ab');
      cubit.onQueryChanged('abc');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();

      verifyNever(() => service.searchWithFallback('a'));
      verifyNever(() => service.searchWithFallback('ab'));
      verify(() => service.searchWithFallback('abc')).called(1);
    });

    test('empty query clears results without searching', () async {
      when(() => service.searchWithFallback(any()))
          .thenAnswer((_) async => [_track('aaaaaaaaaaa')]);

      final cubit = build();
      cubit.onQueryChanged('hit');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();
      expect(cubit.state.results, isNotEmpty);

      cubit.onQueryChanged('');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();

      expect(cubit.state.results, isEmpty);
      expect(cubit.state.isLoading, isFalse);
      verifyNever(() => service.searchWithFallback(''));
    });
  });

  group('clearQuery', () {
    test('cancels the pending debounce and resets state', () async {
      when(() => service.searchWithFallback(any()))
          .thenAnswer((_) async => const []);

      final cubit = build();
      cubit.onQueryChanged('abc');
      cubit.clearQuery();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      verifyNever(() => service.searchWithFallback(any()));
      expect(cubit.state.query, isEmpty);
      expect(cubit.state.results, isEmpty);
      expect(cubit.state.errorMessage, isNull);
    });
  });

  group('clearError', () {
    test('clears the error message while keeping the query', () async {
      when(() => service.searchWithFallback(any()))
          .thenThrow(const YtmException('YTM_TIMEOUT'));

      final cubit = build();
      cubit.onQueryChanged('anything');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();
      expect(cubit.state.errorMessage, isNotNull);

      cubit.clearError();
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.query, 'anything');
    });
  });

  group('search success & history', () {
    test('saves a successful query to history and pref list', () async {
      when(() => service.searchWithFallback(any()))
          .thenAnswer((_) async => [_track('dQw4w9WgXcQ', 'Hit')]);

      final cubit = build();
      cubit.onQueryChanged('Rick Astley');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('ytm_search_history'),
          contains('Rick Astley'));
      expect(cubit.historyNotifier.value, contains('Rick Astley'));
    });

    test('does not save when the search returns no results', () async {
      when(() => service.searchWithFallback(any()))
          .thenAnswer((_) async => const []);

      final cubit = build();
      cubit.onQueryChanged('empty query');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('ytm_search_history'), isNull);
    });

    test('de-dupes case-insensitively, keeping the newest casing', () async {
      when(() => service.searchWithFallback(any()))
          .thenAnswer((_) async => [_track('dQw4w9WgXcQ', 'Hit')]);

      final cubit = build();
      cubit.onQueryChanged('beatles');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();
      cubit.onQueryChanged('Beatles');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('ytm_search_history')!;
      expect(list, ['Beatles']);
    });

    test('caps history at 20 entries', () async {
      when(() => service.searchWithFallback(any()))
          .thenAnswer((_) async => [_track('dQw4w9WgXcQ', 'Hit')]);

      final cubit = build();
      for (var i = 0; i < 25; i++) {
        cubit.onQueryChanged('query number $i');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await pumpEventQueue();
      }

      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('ytm_search_history')!;
      expect(list.length, 20);
      // Newest first.
      expect(list.first, 'query number 24');
      expect(list.contains('query number 0'), isFalse);
    });

    test('ignores queries shorter than two characters', () async {
      when(() => service.searchWithFallback(any()))
          .thenAnswer((_) async => [_track('dQw4w9WgXcQ', 'Hit')]);

      final cubit = build();
      cubit.onQueryChanged('a');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('ytm_search_history'), isNull);
    });
  });

  group('history mutations', () {
    test('removeHistoryQuery removes case-insensitively', () async {
      SharedPreferences.setMockInitialValues({
        'ytm_search_history': ['Alpha', 'Beta'],
      });
      final cubit = build();
      await pumpEventQueue();

      await cubit.removeHistoryQuery('alpha');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('ytm_search_history'), ['Beta']);
      expect(cubit.historyNotifier.value, ['Beta']);
    });

    test('clearHistory wipes prefs and notifier', () async {
      SharedPreferences.setMockInitialValues({
        'ytm_search_history': ['Alpha', 'Beta'],
      });
      final cubit = build();
      await pumpEventQueue();

      await cubit.clearHistory();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('ytm_search_history'), isNull);
      expect(cubit.historyNotifier.value, isEmpty);
    });
  });

  group('error paths', () {
    test('network failure surfaces a classified message', () async {
      when(() => service.searchWithFallback(any()))
          .thenThrow(const YtmException('YTM_TIMEOUT'));

      final cubit = build();
      cubit.onQueryChanged('anything');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.results, isEmpty);
      expect(cubit.state.errorMessage, contains('connection'));
    });

    test('bot block invalidates/refreshes poToken then retries once', () async {
      var calls = 0;
      when(() => service.searchWithFallback(any())).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          throw const YtmException('BOT_CHALLENGE');
        }
        return [_track('dQw4w9WgXcQ', 'Recovered')];
      });

      final cubit = build();
      cubit.onQueryChanged('anything');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();

      verify(() => service.invalidatePoToken()).called(1);
      verify(() => service.ensurePoTokenReady()).called(1);
      expect(calls, 2);
      expect(cubit.state.results.single.title, 'Recovered');
      expect(cubit.state.errorMessage, isNull);
    });

    test('bot block surfaces rate-limit message when recovery fails', () async {
      when(() => service.searchWithFallback(any()))
          .thenThrow(const YtmException('BOT_CHALLENGE'));
      when(() => service.ensurePoTokenReady()).thenAnswer((_) async => false);

      final cubit = build();
      cubit.onQueryChanged('anything');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();

      expect(cubit.state.errorMessage, contains('rate-limiting'));
      expect(cubit.state.results, isEmpty);
    });
  });

  group('URL / video-id resolution', () {
    test('a direct YouTube URL resolves a single track without text search',
        () async {
      when(() => service.resolveStream(any())).thenAnswer((_) async =>
          const YtmStream(
            videoId: 'dQw4w9WgXcQ',
            url: 'https://example.com/a.m4a',
            mimeType: 'audio/mp4',
            container: 'm4a',
            bitrateKbps: 128,
            duration: Duration(minutes: 3),
            title: 'Resolved Title',
            artist: 'Resolved Artist',
          ));

      final cubit = build();
      cubit.onQueryChanged('https://youtu.be/dQw4w9WgXcQ');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();

      expect(cubit.state.results.single.title, 'Resolved Title');
      verifyNever(() => service.searchWithFallback(any()));
    });
  });

  group('statusMessageFor', () {
    test('reports bot cooldown first regardless of error', () {
      final cubit = build();
      expect(cubit.statusMessageFor(true), contains('cooling down'));
    });

    test('reports offline for connectivity-style messages', () async {
      when(() => service.searchWithFallback(any()))
          .thenThrow(const YtmException('YTM_TIMEOUT'));
      final cubit = build();
      cubit.onQueryChanged('anything');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await pumpEventQueue();

      expect(cubit.statusMessageFor(false), contains('offline'));
    });

    test('returns null when healthy and no connectivity error', () {
      final cubit = build();
      expect(cubit.statusMessageFor(false), isNull);
    });

    test('statusMessage getter reflects the service cooldown state', () {
      when(() => service.isBotCoolingDown).thenReturn(true);
      final cubit = build();
      expect(cubit.statusMessage, contains('cooling down'));
    });
  });
}
