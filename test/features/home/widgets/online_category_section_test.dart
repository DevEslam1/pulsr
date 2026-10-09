import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/features/home/presentation/widgets/online_category_section.dart';
import 'package:pulsr/features/home/presentation/widgets/trending_card.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

const _fallbackSong = SongsTableData(
  id: 1,
  title: 'Fallback',
  artist: 'Fallback',
  album: '',
  durationMs: 0,
  path: '',
  source: SongSource.youtube,
  isFavorite: false,
  isMissing: false,
  isDownloaded: false,
  playCount: 0,
  lastPositionMs: 0,
);

List<YtmTrack> _tracks() => const [
      YtmTrack(
        videoId: 'v1',
        title: 'Track One',
        artist: 'Artist One',
        duration: Duration(minutes: 3),
      ),
      YtmTrack(
        videoId: 'v2',
        title: 'Track Two',
        artist: 'Artist Two',
        duration: Duration(minutes: 4),
      ),
      YtmTrack(
        videoId: 'v3',
        title: 'Track Three',
        artist: 'Artist Three',
        duration: Duration(minutes: 5),
      ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit playerCubit;

  setUpAll(() {
    registerFallbackValue(_fallbackSong);
    registerFallbackValue(<SongsTableData>[]);
    registerFallbackValue(0);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(
      const {'pulsr_hint_song_tile_swipe': true},
    );
    playerCubit = MockPlayerCubit();
    when(() => playerCubit.state).thenReturn(const PlayerState());
    when(() => playerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => playerCubit.warmStreams(any(), count: any(named: 'count')))
        .thenAnswer((_) {});
    when(() => playerCubit.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
  });

  Widget wrap(
    Widget child, {
    Size size = const Size(800, 800),
  }) =>
      BlocProvider<PlayerCubit>.value(
        value: playerCubit,
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(size: size, disableAnimations: true),
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      );

  group('OnlineCategorySection', () {
    testWidgets('renders tracks and warms the first streams on load',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          OnlineCategorySection(
            title: 'Trending Now',
            future: Future.value(_tracks()),
            playerCubit: playerCubit,
            onRetry: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TRENDING NOW'), findsOneWidget);
      expect(find.text('Track One'), findsWidgets);
      expect(find.byType(TrendingCard), findsNWidgets(3));
      verify(() => playerCubit.warmStreams(any(), count: 2)).called(1);
    });

    testWidgets('plays a track when its card is tapped', (tester) async {
      await tester.pumpWidget(
        wrap(
          OnlineCategorySection(
            title: 'Trending Now',
            future: Future.value(_tracks()),
            playerCubit: playerCubit,
            onRetry: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TrendingCard).first);
      await tester.pump();

      verify(() => playerCubit.playSong(any(), queue: any(named: 'queue')))
          .called(1);
    });

    testWidgets('renders a single-column song list on a narrow phone',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          OnlineCategorySection(
            title: 'Trending Now',
            future: Future.value(_tracks()),
            playerCubit: playerCubit,
            onRetry: () {},
          ),
          size: const Size(390, 844),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Track One'), findsWidgets);
    });

    testWidgets('shows the retry card for an empty result', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        wrap(
          OnlineCategorySection(
            title: 'Empty Category',
            future: Future.value(const <YtmTrack>[]),
            playerCubit: playerCubit,
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.retry), findsOneWidget);
      expect(find.byType(TrendingCard), findsNothing);

      await tester.tap(find.text(l10n.retry));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('shows the retry card when the future fails', (tester) async {
      var retries = 0;
      final completer = Completer<List<YtmTrack>>();
      await tester.pumpWidget(
        wrap(
          OnlineCategorySection(
            title: 'Broken Category',
            future: completer.future,
            playerCubit: playerCubit,
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.pump();
      completer.completeError(Exception('boom'));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.retry), findsOneWidget);

      await tester.tap(find.text(l10n.retry));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('renders a skeleton while the future is pending',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          OnlineCategorySection(
            title: 'Loading Category',
            future: Completer<List<YtmTrack>>().future,
            playerCubit: playerCubit,
            onRetry: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('LOADING CATEGORY'), findsOneWidget);
      expect(find.byType(TrendingCard), findsNothing);
    });

    testWidgets('re-warms when the title and future change', (tester) async {
      const key = Key('online-category');
      var warmCalls = 0;
      when(() => playerCubit.warmStreams(any(), count: any(named: 'count')))
          .thenAnswer((_) => warmCalls++);
      final future = Future.value(_tracks());
      await tester.pumpWidget(
        wrap(
          OnlineCategorySection(
            key: key,
            title: 'First',
            future: future,
            playerCubit: playerCubit,
            onRetry: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      verify(() => playerCubit.warmStreams(any(), count: 2)).called(1);

      await tester.pumpWidget(
        wrap(
          OnlineCategorySection(
            key: key,
            title: 'Second',
            future: future,
            playerCubit: playerCubit,
            onRetry: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SECOND'), findsOneWidget);
      expect(warmCalls, greaterThan(1), reason: 'warmCalls=$warmCalls');
    });
  });
}
