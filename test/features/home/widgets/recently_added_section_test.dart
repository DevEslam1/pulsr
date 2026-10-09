import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_static_grid.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/features/home/presentation/widgets/empty_library.dart';
import 'package:pulsr/features/home/presentation/widgets/recently_added_section.dart';
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
      title: 'Song $id',
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

  void stubRecentlyAdded(Result<List<SongsTableData>> result) {
    when(() => getSongs.watchRecentlyAdded(limit: any(named: 'limit')))
        .thenAnswer((_) => Stream<Result<List<SongsTableData>>>.value(result));
  }

  void stubRecentlyAddedError() {
    when(() => getSongs.watchRecentlyAdded(limit: any(named: 'limit')))
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
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      );

  group('RecentlyAddedSection', () {
    testWidgets('renders song tiles on a narrow phone', (tester) async {
      stubRecentlyAdded(Right<AppFailure, List<SongsTableData>>(_songs(3)));

      await tester.pumpWidget(
        wrap(RecentlyAddedSection(getSongsUseCase: getSongs)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SongTile), findsNWidgets(3));
      expect(find.byType(PulsrStaticGrid), findsNothing);
    });

    testWidgets('renders a multi-column grid on a tablet', (tester) async {
      stubRecentlyAdded(Right<AppFailure, List<SongsTableData>>(_songs(3)));

      await tester.pumpWidget(
        wrap(
          RecentlyAddedSection(getSongsUseCase: getSongs),
          size: const Size(800, 800),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PulsrStaticGrid), findsOneWidget);
      expect(find.byType(SongTile), findsNWidgets(3));
    });

    testWidgets('plays a song when its tile is tapped', (tester) async {
      stubRecentlyAdded(Right<AppFailure, List<SongsTableData>>(_songs(2)));

      await tester.pumpWidget(
        wrap(RecentlyAddedSection(getSongsUseCase: getSongs)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SongTile).first);
      await tester.pump();

      verify(() => playerCubit.playSong(any(), queue: any(named: 'queue')))
          .called(1);
    });

    testWidgets('renders the empty library state for an empty stream',
        (tester) async {
      stubRecentlyAdded(const Right<AppFailure, List<SongsTableData>>([]));

      await tester.pumpWidget(
        wrap(RecentlyAddedSection(getSongsUseCase: getSongs)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmptyLibrary), findsOneWidget);
      expect(find.byType(SongTile), findsNothing);
    });

    testWidgets('renders SectionError for a failed stream', (tester) async {
      stubRecentlyAddedError();

      await tester.pumpWidget(
        wrap(RecentlyAddedSection(getSongsUseCase: getSongs)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SectionError), findsOneWidget);

      await tester.tap(find.byType(TextButton));
      await tester.pump();
    });

    testWidgets('loads more when the compact load-more button is tapped',
        (tester) async {
      stubRecentlyAdded(Right<AppFailure, List<SongsTableData>>(_songs(50)));

      await tester.pumpWidget(
        wrap(RecentlyAddedSection(getSongsUseCase: getSongs)),
      );
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text('${l10n.loadMore} (+50)'), findsOneWidget);

      await tester.ensureVisible(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));

      verify(() => getSongs.watchRecentlyAdded(limit: 100))
          .called(greaterThan(0));
    });

    testWidgets('loads more from the tablet grid load-more button',
        (tester) async {
      stubRecentlyAdded(Right<AppFailure, List<SongsTableData>>(_songs(50)));

      await tester.pumpWidget(
        wrap(
          RecentlyAddedSection(getSongsUseCase: getSongs),
          size: const Size(800, 800),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PulsrStaticGrid), findsOneWidget);

      await tester.ensureVisible(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));

      verify(() => getSongs.watchRecentlyAdded(limit: 100))
          .called(greaterThan(0));
    });
  });
}
