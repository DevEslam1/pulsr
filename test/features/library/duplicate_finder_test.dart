// test/features/library/duplicate_finder_test.dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/duplicate_finder_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/features/library/presentation/duplicate_finder_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/test_song_factory.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMusicRepository repo;
  late MockPlayerCubit cubit;

  setUpAll(() {
    registerFallbackValue(<int>[]);
  });

  setUp(() {
    repo = MockMusicRepository();
    cubit = MockPlayerCubit();
    when(() => cubit.state).thenReturn(const PlayerState());
    when(() => cubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());

    if (getIt.isRegistered<DuplicateFinderService>()) {
      getIt.unregister<DuplicateFinderService>();
    }
    getIt.registerLazySingleton<DuplicateFinderService>(
        () => DuplicateFinderService());
    if (getIt.isRegistered<IMusicRepository>()) {
      getIt.unregister<IMusicRepository>();
    }
    getIt.registerSingleton<IMusicRepository>(repo);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> pumpScreen(
      WidgetTester tester, List<SongsTableData> songs) async {
    when(() => repo.getAllSongs()).thenAnswer((_) async => Right(songs));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [BlocProvider<PlayerCubit>.value(value: cubit)],
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DuplicateFinderScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SongsTableData song({
    required int id,
    String title = 'Comfortably Numb',
    String artist = 'Pink Floyd',
    String album = 'The Wall',
    int durationMs = 382000,
    String path = '/storage/music/song.mp3',
    int? bitrateKbps,
    int? fileSize,
  }) =>
      createTestSong(
        id: id,
        title: title,
        artist: artist,
        album: album,
        durationMs: durationMs,
        path: path,
        bitrateKbps: bitrateKbps,
      ).copyWith(fileSize: Value(fileSize));

  testWidgets(
      'detects duplicates, auto-selects the best quality and deletes the copy',
      (tester) async {
    when(() => repo.deleteSongs(any(that: equals([2]))))
        .thenAnswer((_) async => const Right(null));

    final flac = song(
        id: 1, path: '/storage/music/Comfortably Numb.flac', bitrateKbps: 950);
    final mp3 = song(
        id: 2,
        title: 'comfortably numb',
        path: '/storage/music/Comfortably Numb.mp3',
        bitrateKbps: 320);
    final unique = song(
        id: 3,
        title: 'Time',
        album: 'The Dark Side of the Moon',
        durationMs: 425000,
        path: '/storage/music/Time.mp3',
        bitrateKbps: 320);

    await pumpScreen(tester, [flac, mp3, unique]);

    expect(find.text('Identical Title & Artist (2 copies)'), findsOneWidget);
    expect(find.text('2 tracks'), findsOneWidget);
    expect(find.text('Kept'), findsNothing);

    await tester.tap(find.byIcon(Icons.auto_awesome_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Selected highest quality for 1 groups'), findsOneWidget);
    expect(find.text('Kept'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    verify(() => repo.deleteSongs(any(that: equals([2])))).called(1);
    expect(find.text('No Duplicates Found!'), findsOneWidget);
  });

  testWidgets('same title/artist on different albums are not duplicates',
      (tester) async {
    await pumpScreen(tester, [
      song(id: 1, title: 'Intro', album: 'Album A'),
      song(id: 2, title: 'Intro', album: 'Album B'),
    ]);

    expect(find.text('No Duplicates Found!'), findsOneWidget);
  });

  testWidgets('durations in different buckets are not duplicates',
      (tester) async {
    await pumpScreen(tester, [
      song(id: 1, title: 'Intro', durationMs: 100000),
      song(id: 2, title: 'Intro', durationMs: 130000),
    ]);

    expect(find.text('No Duplicates Found!'), findsOneWidget);
  });

  testWidgets('codec variants of one recording are grouped', (tester) async {
    await pumpScreen(tester, [
      song(id: 1, title: 'Intro', path: '/a/intro.flac', fileSize: 40000000),
      song(id: 2, title: 'Intro', path: '/a/intro.mp3', fileSize: 8000000),
    ]);

    expect(find.text('Identical Title & Artist (2 copies)'), findsOneWidget);
  });
}
