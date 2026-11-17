// test/features/assistant/assistant_intent_service_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/assistant/assistant_intent_service.dart';
import 'package:pulsr/features/assistant/assistant_resolver.dart';

AssistantResolver _resolver({
  List<int> search = const [1, 2],
  List<int> playlist = const <int>[],
  List<int> favorites = const [5, 6],
  List<int> lastAlbum = const [9],
}) =>
    AssistantResolver(
      searchSongIds: (query) async => search,
      playlistSongIds: (name) async => playlist,
      favoritesSongIds: () async => favorites,
      lastAlbumSongIds: () async => lastAlbum,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<AssistantPlayPlan> played;

  setUp(() => played = <AssistantPlayPlan>[]);

  AssistantIntentService build({
    AssistantResolver? resolver,
    Future<void> Function(AssistantPlayPlan plan)? playPlan,
    Duration Function()? monotonicClock,
    Duration dedupeWindow = const Duration(seconds: 1),
  }) {
    final service = AssistantIntentService(
      resolver: resolver ?? _resolver(),
      playPlan: playPlan ?? (plan) async => played.add(plan),
      monotonicClock: monotonicClock,
      dedupeWindow: dedupeWindow,
    );
    addTearDown(service.dispose);
    return service;
  }

  group('handle', () {
    test('plays the resolved plan', () async {
      final service = build();
      await service.handle({'QUERY': 'Miles Davis'});

      expect(played, hasLength(1));
      expect(played.single.songIds, [1, 2]);
      expect(played.single.title, 'Miles Davis');
    });

    test('drops an identical request inside the dedupe window', () async {
      const elapsed = Duration.zero;
      final service = build(monotonicClock: () => elapsed);
      await service.handle({'QUERY': 'Miles Davis'});
      await service.handle({'QUERY': 'Miles Davis'});

      expect(played, hasLength(1));
    });

    test('plays again once the dedupe window has passed', () async {
      var elapsed = Duration.zero;
      final service = build(monotonicClock: () => elapsed);
      await service.handle({'QUERY': 'Miles Davis'});
      elapsed += const Duration(milliseconds: 1500);
      await service.handle({'QUERY': 'Miles Davis'});

      expect(played, hasLength(2));
    });

    test('does not dedupe a different term', () async {
      const elapsed = Duration.zero;
      final service = build(monotonicClock: () => elapsed);
      await service.handle({'QUERY': 'Miles Davis'});
      await service.handle({'QUERY': 'John Coltrane'});

      expect(played, hasLength(2));
    });

    test('dedupes an identical shortcut request too', () async {
      const elapsed = Duration.zero;
      final service = build(monotonicClock: () => elapsed);
      await service.handleShortcut('shortcut_shuffle');
      await service.handleShortcut('shortcut_shuffle');

      expect(played, hasLength(1));
    });

    test('ignores extras without a term', () async {
      final service = build();
      await expectLater(
        service.handle({'QUERY': '   '}),
        completes,
      );
      expect(played, isEmpty);
    });

    test('does not play when resolution fails', () async {
      final service = build(resolver: _resolver(search: const <int>[]));
      await service.handle({'QUERY': 'nothing here'});

      expect(played, isEmpty);
    });

    test('absorbs a throwing player port', () async {
      final service = build(
        playPlan: (plan) async => throw StateError('player not ready'),
      );
      await expectLater(
        service.handle({'QUERY': 'Miles Davis'}),
        completes,
      );
    });
  });

  group('monotonic dedupe clock', () {
    test('a forward wall-clock jump does not defeat dedupe', () async {
      const jump = Duration(hours: 6);
      var wallClock = DateTime.utc(2026, 1, 1, 12);
      var elapsed = Duration.zero;
      final service = build(monotonicClock: () => elapsed);
      // Premise: the jump dwarfs the window, so the old DateTime-based delta
      // would have looked expired and replayed the duplicate.
      expect(jump > service.dedupeWindow, isTrue);

      await service.handle({'QUERY': 'Miles Davis'});
      wallClock = wallClock.add(jump);
      elapsed += const Duration(milliseconds: 250);
      expect(wallClock, DateTime.utc(2026, 1, 1, 18));
      await service.handle({'QUERY': 'Miles Davis'});

      expect(played, hasLength(1));
    });

    test('a backwards wall-clock jump does not trigger dedupe', () async {
      const jump = Duration(hours: 6);
      var wallClock = DateTime.utc(2026, 1, 1, 12);
      var elapsed = Duration.zero;
      final service = build(monotonicClock: () => elapsed);

      await service.handle({'QUERY': 'Miles Davis'});
      wallClock = wallClock.subtract(jump);
      // Monotonic time moved past the window even though the device clock went
      // back: a negative wall-clock delta used to latch dedupe on until the
      // clock caught up, swallowing every legitimate repeat.
      elapsed += const Duration(milliseconds: 1500);
      expect(wallClock, DateTime.utc(2026, 1, 1, 6));
      await service.handle({'QUERY': 'Miles Davis'});

      expect(played, hasLength(2));
    });

    test('defaults to a real monotonic source', () async {
      final service = build(dedupeWindow: const Duration(milliseconds: 200));

      await service.handle({'QUERY': 'Miles Davis'});
      await service.handle({'QUERY': 'Miles Davis'});
      expect(played, hasLength(1));

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await service.handle({'QUERY': 'Miles Davis'});
      expect(played, hasLength(2));
    });

    test('the dedupe path never reads the wall clock', () {
      final source = File(
        'lib/features/assistant/assistant_intent_service.dart',
      ).readAsStringSync();

      expect(
        source.contains('DateTime.now'),
        isFalse,
        reason: 'Dedupe must stay on the injected Stopwatch source; a '
            'DateTime.now read reintroduces the clock-jump bug pinned above.',
      );
    });
  });

  group('shortcuts', () {
    test('shuffle shortcut plays favourites shuffled', () async {
      final service = build();
      await service.handleShortcut('shortcut_shuffle');

      expect(played.single.shuffle, isTrue);
      expect(played.single.songIds, [5, 6]);
    });

    test('favourites shortcut plays favourites unshuffled', () async {
      final service = build();
      await service.handleShortcut('shortcut_favorites');

      expect(played.single.shuffle, isFalse);
      expect(played.single.source, AssistantPlanSource.favorites);
    });

    test('play shortcut resumes the last album', () async {
      final service = build();
      await service.handleShortcut('shortcut_play');

      expect(played.single.source, AssistantPlanSource.lastAlbum);
      expect(played.single.songIds, [9]);
    });

    test('search and unknown shortcuts play nothing', () async {
      final service = build();
      await service.handleShortcut('shortcut_search');
      await service.handleShortcut('shortcut_nope');

      expect(played, isEmpty);
    });
  });

  group('channel contract', () {
    test('onSearchQuery routes the extras map', () async {
      final service = build();
      await service.handleMethodCall(
        const MethodCall('onSearchQuery', {'QUERY': 'blue in green'}),
      );

      expect(played, hasLength(1));
      expect(played.single.title, 'blue in green');
    });

    test('onShortcut routes the shortcut id', () async {
      final service = build();
      await service.handleMethodCall(
        const MethodCall('onShortcut', 'shortcut_play'),
      );

      expect(played.single.source, AssistantPlanSource.lastAlbum);
    });

    test('a non-string shortcut argument is ignored', () async {
      final service = build();
      await expectLater(
        service.handleMethodCall(const MethodCall('onShortcut', 42)),
        completes,
      );
      expect(played, isEmpty);
    });

    test('an unknown method is ignored', () async {
      final service = build();
      await expectLater(
        service.handleMethodCall(const MethodCall('onSomethingElse')),
        completes,
      );
      expect(played, isEmpty);
    });

    test('the readiness probe does not play anything', () async {
      final service = build();
      await expectLater(
        service.handleMethodCall(const MethodCall('isReady')),
        completes,
      );
      expect(played, isEmpty);
    });

    test('dispose stops handling further requests', () async {
      final service = build();
      service.dispose();
      await service.handle({'QUERY': 'Miles Davis'});
      await service.handleMethodCall(
        const MethodCall('onSearchQuery', {'QUERY': 'Miles Davis'}),
      );

      expect(played, isEmpty);
    });
  });
}
