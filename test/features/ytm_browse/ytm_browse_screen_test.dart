// test/features/ytm_browse/ytm_browse_screen_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_browse_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/ytm_browse/presentation/ytm_browse_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/screen_harness.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';

class MockYtmBrowseService extends Mock implements YtmBrowseService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockYtmBrowseService mockBrowse;

  setUpAll(() {
    registerFallbackValue(false);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockBrowse = MockYtmBrowseService();
    getIt.registerSingleton<YtmBrowseService>(mockBrowse);
  });

  tearDown(() async {
    await getIt.reset();
  });

  // Track cards select from PlayerCubit, so the host has to provide it exactly
  // as the app's root MultiBlocProvider does.
  Widget host() => MultiBlocProvider(
        providers: [BlocProvider<PlayerCubit>.value(value: stubPlayerCubit())],
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const YtmBrowseScreen(),
        ),
      );

  testWidgets('renders loading skeleton while the feed is in flight',
      (tester) async {
    when(() => mockBrowse.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) => Future<List<YtmBrowseSection>>.delayed(
              const Duration(seconds: 5),
              () => const [],
            ));

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(YtmBrowseScreen), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Let the pending future resolve so no timer leaks into teardown.
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('renders the empty state when the feed has no items',
      (tester) async {
    when(() => mockBrowse.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async => const []);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byType(YtmBrowseScreen), findsOneWidget);
    expect(find.byIcon(Icons.explore_off_rounded), findsOneWidget);
    expect(find.text('No recommendations right now.'), findsOneWidget);
  });

  testWidgets('drops empty sections and renders only populated ones',
      (tester) async {
    when(() => mockBrowse.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async => const [
              YtmBrowseSection(title: 'Empty Section', items: []),
              YtmBrowseSection(title: 'Top Charts & Trending', items: [
                YtmBrowseItem(
                  id: 'dQw4w9WgXcQ',
                  title: 'Never Gonna Give You Up',
                  subtitle: 'Rick Astley',
                  type: 'song',
                ),
              ]),
            ]);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Top Charts & Trending'), findsOneWidget);
    expect(find.text('Never Gonna Give You Up'), findsOneWidget);
    expect(find.text('Empty Section'), findsNothing);
  });

  testWidgets(
      'renders the error state with a retry action when the feed throws',
      (tester) async {
    when(() => mockBrowse.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async => throw Exception('network down'));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    expect(find.text('Retry'), findsWidgets);
  });

  testWidgets('the refresh action forces a re-fetch past the cache',
      (tester) async {
    var calls = 0;
    when(() => mockBrowse.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async {
      calls++;
      return const [];
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.refresh_rounded),
    ));
    await tester.pumpAndSettle();
    expect(calls, 2);
    verify(() => mockBrowse.getHomeFeed(force: true)).called(1);
    // The error/empty retry actions keep using the non-forced load.
    verify(() => mockBrowse.getHomeFeed(force: false)).called(1);
  });

  testWidgets('keeps the feed and shows a retry banner when a refresh fails',
      (tester) async {
    var calls = 0;
    when(() => mockBrowse.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async {
      calls++;
      if (calls == 1) {
        return const [
          YtmBrowseSection(title: 'Top Charts & Trending', items: [
            YtmBrowseItem(
              id: 'dQw4w9WgXcQ',
              title: 'Never Gonna Give You Up',
              subtitle: 'Rick Astley',
              type: 'song',
            ),
          ]),
        ];
      }
      throw Exception('offline');
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Top Charts & Trending'), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.refresh_rounded),
    ));
    await tester.pumpAndSettle();

    // The previous feed stays usable; the failure is a retry strip, not a
    // full-screen error that throws the content away.
    expect(find.text('Top Charts & Trending'), findsOneWidget);
    expect(
      find.text('No connection. Check your network.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsWidgets);
  });

  testWidgets('error empty-state retry calls getHomeFeed with force: true',
      (tester) async {
    var calls = 0;
    when(() => mockBrowse.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async {
      calls++;
      if (calls == 1) throw Exception('offline');
      return const [
        YtmBrowseSection(title: 'Recovered', items: [
          YtmBrowseItem(
            id: 'dQw4w9WgXcQ',
            title: 'Recovered Track',
            subtitle: 'Artist',
            type: 'song',
          ),
        ]),
      ];
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    verify(() => mockBrowse.getHomeFeed(force: true)).called(1);
    expect(find.text('Recovered'), findsOneWidget);
  });

  testWidgets(
      'container items route to playlist detail or artist search instead of playback',
      (tester) async {
    final player = stubPlayerCubit();
    Object? pushedExtra;
    when(() => mockBrowse.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async => const [
              YtmBrowseSection(title: 'Mixed Picks', items: [
                YtmBrowseItem(
                  id: 'VLPL1234',
                  title: 'Evening Mix',
                  subtitle: 'Curated',
                  type: 'playlist',
                ),
                YtmBrowseItem(
                  id: 'UCartist1',
                  title: 'Fairuz',
                  subtitle: 'Artist',
                  type: 'artist',
                ),
              ]),
            ]);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const YtmBrowseScreen(),
        ),
        GoRoute(
          path: '/online-playlist',
          builder: (_, state) {
            pushedExtra = state.extra;
            return const Scaffold(body: Text('online-playlist-target'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [BlocProvider<PlayerCubit>.value(value: player)],
        child: MaterialApp.router(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.playlist_play_rounded), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    await tester.tap(find.text('Evening Mix'));
    await tester.pumpAndSettle();

    expect(find.text('online-playlist-target'), findsOneWidget);
    expect(pushedExtra, isNotNull);
  });
}
