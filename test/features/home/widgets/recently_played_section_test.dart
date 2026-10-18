import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_section_header.dart';
import 'package:pulsr/core/widgets/shimmer_skeleton.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/features/home/presentation/widgets/recently_played_section.dart';
import 'package:pulsr/features/home/presentation/widgets/section_error.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockGetSongsUseCase extends Mock implements GetSongsUseCase {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockLibraryCubit extends Mock implements LibraryCubit {}

SongsTableData _song(int id) => SongsTableData(
      id: id,
      title: 'Recent $id',
      artist: 'Artist $id',
      album: 'Album $id',
      durationMs: 180000,
      path: '/music/$id.mp3',
      source: SongSource.local,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );

List<SongsTableData> _songs(int n) => [for (var i = 1; i <= n; i++) _song(i)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockGetSongsUseCase getSongs;
  late MockPlayerCubit playerCubit;
  late MockLibraryCubit libraryCubit;

  setUpAll(() {
    registerFallbackValue(_song(1));
    registerFallbackValue(<SongsTableData>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(
      const {'pulsr_hint_song_tile_swipe': true},
    );
    getSongs = MockGetSongsUseCase();
    playerCubit = MockPlayerCubit();
    libraryCubit = MockLibraryCubit();

    when(() => playerCubit.state).thenReturn(const PlayerState());
    when(() => playerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => playerCubit.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
    when(() => libraryCubit.state)
        .thenReturn(LibraryState(songs: [_song(1), _song(2)]));
    when(() => libraryCubit.stream)
        .thenAnswer((_) => const Stream<LibraryState>.empty());
  });

  void stubRecentlyPlayed(Result<List<SongsTableData>> result) {
    when(() => getSongs.watchRecentlyPlayed(limit: any(named: 'limit')))
        .thenAnswer((_) => Stream<Result<List<SongsTableData>>>.value(result));
  }

  void stubRecentlyPlayedError() {
    when(() => getSongs.watchRecentlyPlayed(limit: any(named: 'limit')))
        .thenAnswer((_) => Stream<Result<List<SongsTableData>>>.error(
            const DatabaseFailure('boom')));
  }

  Widget wrap(
    Widget child, {
    Size size = const Size(390, 844),
  }) =>
      MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: playerCubit),
          BlocProvider<LibraryCubit>.value(value: libraryCubit),
        ],
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
            child: Scaffold(
              body: SingleChildScrollView(child: child),
            ),
          ),
        ),
      );

  group('RecentlyPlayedSection', () {
    testWidgets('collapses to nothing when there is no history',
        (tester) async {
      stubRecentlyPlayed(const Right<AppFailure, List<SongsTableData>>([]));

      await tester.pumpWidget(
        wrap(RecentlyPlayedSection(getSongsUseCase: getSongs, isTablet: false)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PulsrSectionHeader), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('renders a skeleton before the first emission', (tester) async {
      final controller = StreamController<Result<List<SongsTableData>>>();
      addTearDown(controller.close);
      when(() => getSongs.watchRecentlyPlayed(limit: any(named: 'limit')))
          .thenAnswer((_) => controller.stream);

      await tester.pumpWidget(
        wrap(RecentlyPlayedSection(getSongsUseCase: getSongs, isTablet: false)),
      );
      await tester.pump();

      expect(find.byType(SkeletonShimmer), findsOneWidget);
      expect(find.byType(PulsrSectionHeader), findsOneWidget);

      controller.add(const Right<AppFailure, List<SongsTableData>>([]));
      await tester.pumpAndSettle();

      expect(find.byType(SkeletonShimmer), findsNothing);
      expect(find.byType(PulsrSectionHeader), findsNothing);
    });

    testWidgets('renders history cards on a phone', (tester) async {
      stubRecentlyPlayed(Right<AppFailure, List<SongsTableData>>(_songs(3)));

      await tester.pumpWidget(
        wrap(RecentlyPlayedSection(getSongsUseCase: getSongs, isTablet: false)),
      );
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.recentlyPlayed.toUpperCase()), findsOneWidget);
      expect(find.text('Recent 1'), findsOneWidget);
    });

    testWidgets('renders history cards with the tablet sizing', (tester) async {
      stubRecentlyPlayed(Right<AppFailure, List<SongsTableData>>(_songs(2)));

      await tester.pumpWidget(
        wrap(
          RecentlyPlayedSection(getSongsUseCase: getSongs, isTablet: true),
          size: const Size(800, 800),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recent 1'), findsOneWidget);
    });

    testWidgets('plays a song when its card is tapped', (tester) async {
      stubRecentlyPlayed(Right<AppFailure, List<SongsTableData>>(_songs(2)));

      await tester.pumpWidget(
        wrap(RecentlyPlayedSection(getSongsUseCase: getSongs, isTablet: false)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recent 1'));
      await tester.pump();

      verify(() => playerCubit.playSong(any(), queue: any(named: 'queue')))
          .called(1);
    });

    testWidgets('queues the full recents list, not just the loaded window',
        (tester) async {
      stubRecentlyPlayed(Right<AppFailure, List<SongsTableData>>(_songs(50)));
      when(() => getSongs.getRecentlyPlayed(limit: any(named: 'limit')))
          .thenAnswer((_) async =>
              Right<AppFailure, List<SongsTableData>>(_songs(120)));

      await tester.pumpWidget(
        wrap(RecentlyPlayedSection(getSongsUseCase: getSongs, isTablet: false)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recent 1'));
      await tester.pumpAndSettle();

      final captured = verify(() => playerCubit.playSong(
            any(),
            queue: captureAny(named: 'queue'),
          )).captured;
      final queue = captured.single as List<SongsTableData>;
      expect(queue.length, 120);
    });

    testWidgets('falls back to the visible window when the full fetch fails',
        (tester) async {
      stubRecentlyPlayed(Right<AppFailure, List<SongsTableData>>(_songs(50)));
      when(() => getSongs.getRecentlyPlayed(limit: any(named: 'limit')))
          .thenAnswer((_) async => const Left<AppFailure,
              List<SongsTableData>>(DatabaseFailure('boom')));

      await tester.pumpWidget(
        wrap(RecentlyPlayedSection(getSongsUseCase: getSongs, isTablet: false)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recent 1'));
      await tester.pumpAndSettle();

      final captured = verify(() => playerCubit.playSong(
            any(),
            queue: captureAny(named: 'queue'),
          )).captured;
      final queue = captured.single as List<SongsTableData>;
      expect(queue.length, 50);
    });

    testWidgets('renders SectionError for a failed stream', (tester) async {
      stubRecentlyPlayedError();

      await tester.pumpWidget(
        wrap(RecentlyPlayedSection(getSongsUseCase: getSongs, isTablet: false)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SectionError), findsOneWidget);

      await tester.tap(find.byType(TextButton));
      await tester.pump();
    });

    testWidgets('loads the next page when scrolled near the end',
        (tester) async {
      stubRecentlyPlayed(Right<AppFailure, List<SongsTableData>>(_songs(50)));

      await tester.pumpWidget(
        wrap(RecentlyPlayedSection(getSongsUseCase: getSongs, isTablet: false)),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 20; i++) {
        await tester.drag(find.byType(ListView), const Offset(-600, 0));
        await tester.pump();
      }

      verify(() => getSongs.watchRecentlyPlayed(limit: 100))
          .called(greaterThan(0));
    });

    testWidgets('does not grow the limit on repeated scrolls at the end',
        (tester) async {
      stubRecentlyPlayed(Right<AppFailure, List<SongsTableData>>(_songs(50)));

      await tester.pumpWidget(
        wrap(RecentlyPlayedSection(getSongsUseCase: getSongs, isTablet: false)),
      );
      await tester.pumpAndSettle();

      // Scroll all the way to the end, which requests the next page once.
      for (var i = 0; i < 20; i++) {
        await tester.drag(find.byType(ListView), const Offset(-600, 0));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // The 100-limit stream only carries 50 rows, so extra scrolls at the end
      // must not keep growing the window.
      for (var i = 0; i < 5; i++) {
        await tester.drag(find.byType(ListView), const Offset(-600, 0));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      verify(() => getSongs.watchRecentlyPlayed(limit: 100))
          .called(greaterThan(0));
      verifyNever(() => getSongs.watchRecentlyPlayed(limit: 150));
    });
  });
}
