import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_section_header.dart';
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
  });
}
