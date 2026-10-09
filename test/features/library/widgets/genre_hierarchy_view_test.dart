// Covers lib/features/library/presentation/widgets/genre_hierarchy_view.dart
//
// Exercises the empty/populated/search states, category expansion and chip
// navigation, the uncategorized group, and the GenreCategory regex cache
// eviction + clear paths.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/genre_item.dart';
import 'package:pulsr/features/library/presentation/widgets/genre_hierarchy_view.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  Widget build(List<GenreItem> genres) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(body: GenreHierarchyView(genres: genres)),
        ),
        GoRoute(
          path: '/genre',
          builder: (_, __) => const Scaffold(body: Text('genre-route')),
        ),
      ],
    );
    return MaterialApp.router(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }

  setUp(GenreCategory.clearCache);

  // GenreHierarchyView schedules a 10s cache-clear Timer from dispose() when
  // the last instance unmounts. Pump past it so the test framework does not
  // report a pending timer.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 11));
  }

  testWidgets('renders the empty state when there are no genres',
      (tester) async {
    await tester.pumpWidget(build(const []));
    await tester.pumpAndSettle();

    expect(find.text(l10n.browseNoGenresFound), findsOneWidget);
    expect(find.text(l10n.browseScanForGenres), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);

    await unmount(tester);
  });

  testWidgets('renders the summary, matching categories and uncategorized group',
      (tester) async {
    await tester.pumpWidget(build(const [
      GenreItem(name: 'Rock', songCount: 5),
      GenreItem(name: 'Pop', songCount: 3),
      GenreItem(name: 'Chill', songCount: 2),
    ]));
    await tester.pumpAndSettle();

    expect(find.text(l10n.browseAllGenresFallback), findsOneWidget);
    expect(find.text(l10n.browseGenreRockMetal), findsOneWidget);
    expect(find.text(l10n.browseGenrePopAcoustic), findsOneWidget);
    // Unmatched genre lands in the "other" bucket.
    expect(find.text(l10n.otherGenres), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('expanding a category reveals its chips and navigates on tap',
      (tester) async {
    await tester.pumpWidget(build(const [
      GenreItem(name: 'Rock', songCount: 5),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.browseGenreRockMetal));
    await tester.pumpAndSettle();

    expect(find.text('Rock (5)'), findsOneWidget);

    await tester.tap(find.text('Rock (5)'));
    await tester.pumpAndSettle();

    expect(find.text('genre-route'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('typing a query auto-expands matching categories',
      (tester) async {
    await tester.pumpWidget(build(const [
      GenreItem(name: 'Rock', songCount: 5),
      GenreItem(name: 'Jazz', songCount: 4),
    ]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'rock');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Rock (5)'), findsOneWidget);
    expect(find.text('Jazz (4)'), findsNothing);

    await unmount(tester);
  });

  testWidgets('an unmatched query shows the no-results state and clear action',
      (tester) async {
    await tester.pumpWidget(build(const [
      GenreItem(name: 'Rock', songCount: 5),
    ]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'zzzzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text(l10n.noResultsFound), findsOneWidget);

    await tester.tap(find.text(l10n.clear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text(l10n.noResultsFound), findsNothing);
    expect(find.text(l10n.browseAllGenresFallback), findsOneWidget);

    await unmount(tester);
  });

  group('GenreCategory.matches', () {
    test('matches keywords with word boundaries and is case-insensitive', () {
      const category = GenreCategory('Rock', Icons.music_note, ['rock', 'metal']);
      expect(category.matches('Hard Rock 90s'), isTrue);
      expect(category.matches('METAL'), isTrue);
      expect(category.matches('Pop'), isFalse);
    });

    test('evicts the oldest cached regex past the cache cap', () {
      GenreCategory.clearCache();
      final keywords = [for (var i = 0; i < 120; i++) 'kw$i'];
      final category = GenreCategory('Big', Icons.music_note, keywords);

      for (final kw in keywords) {
        expect(category.matches('prefix $kw suffix'), isTrue);
      }
      // Re-matching the first (evicted) keyword still works after eviction.
      expect(category.matches('kw0'), isTrue);
      GenreCategory.clearCache();
    });
  });
}
