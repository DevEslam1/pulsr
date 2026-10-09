// QueueScreen branch coverage: every overflow-menu action (clear/undo,
// shuffle, auto-mix in all its exits, save-as-playlist success + failure),
// reordering, and the current/remote row decorations.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/playlist_suggestions_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/queue/presentation/queue_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _GetSongs extends Mock implements GetSongsUseCase {}

class _Suggestions extends Mock implements PlaylistSuggestionsService {}

class _PlaylistUseCases extends Mock implements PlaylistUseCases {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(createTestSong(id: -1));
    registerFallbackValue(<SongsTableData>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await getIt.reset();
  });

  MockPlayerCubit buildPlayer(List<SongsTableData> songs, {int currentIndex = 0}) {
    final player = MockPlayerCubit();
    when(() => player.state).thenReturn(PlayerState(
      playback: PlaybackSlice(
          currentSong: songs.isEmpty ? null : songs[currentIndex]),
      queueSlice: QueueSlice(queue: songs, currentIndex: currentIndex),
    ));
    when(() => player.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => player.clearQueue()).thenAnswer((_) async {});
    when(() => player.restoreQueue(any(), any())).thenReturn(null);
    when(() => player.reorderQueue(any(), any())).thenAnswer((_) async {});
    when(() => player.addAllToQueue(any())).thenAnswer((_) async {});
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
    when(() => player.removeQueueItem(any())).thenAnswer((_) async {});
    return player;
  }

  Future<void> pump(WidgetTester tester, PlayerCubit player) async {
    useScreenSize(tester, const Size(800, 1600));
    await tester.pumpWidget(screenHarness(
      providers: [BlocProvider<PlayerCubit>.value(value: player)],
      child: const QueueScreen(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    tester.takeException();
  }

  testWidgets('clear action confirms, clears and restores on undo',
      (tester) async {
    final player = buildPlayer([createTestSong(id: 1, title: 'Alpha')]);
    await pump(tester, player);

    await openMenu(tester);
    await tester.tap(find.text('Clear Queue'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();

    verify(() => player.clearQueue()).called(1);
    expect(find.text('Queue cleared'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    verify(() => player.restoreQueue(any(), any())).called(1);
  });

  testWidgets('shuffle action replays the queue shuffled', (tester) async {
    final player = buildPlayer([
      createTestSong(id: 1, title: 'Alpha'),
      createTestSong(id: 2, title: 'Beta'),
    ]);
    await pump(tester, player);

    await openMenu(tester);
    await tester.tap(find.text('Shuffle'));
    await tester.pumpAndSettle();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('auto-mix appends similar tracks', (tester) async {
    final seed = createTestSong(id: 1, title: 'Seed');
    final other = createTestSong(id: 2, title: 'Other');
    final player = buildPlayer([seed]);
    final getSongs = _GetSongs();
    final suggestions = _Suggestions();
    when(() => getSongs.getAllSongs())
        .thenAnswer((_) async => Right([seed, other]));
    when(() => suggestions.buildAutoDjQueue(any(), any(),
            limit: any(named: 'limit'), excludeIds: any(named: 'excludeIds')))
        .thenReturn([other]);
    getIt.registerSingleton<GetSongsUseCase>(getSongs);
    getIt.registerSingleton<PlaylistSuggestionsService>(suggestions);

    await pump(tester, player);
    await openMenu(tester);
    await tester.tap(find.text('Auto-mix'));
    await tester.pumpAndSettle();

    verify(() => player.addAllToQueue(any())).called(1);
    expect(find.textContaining('Auto-DJ added'), findsWidgets);
  });

  testWidgets('auto-mix reports a library read failure', (tester) async {
    final player = buildPlayer([createTestSong(id: 1, title: 'Seed')]);
    final getSongs = _GetSongs();
    when(() => getSongs.getAllSongs())
        .thenAnswer((_) async => const Left(DatabaseFailure('boom')));
    getIt.registerSingleton<GetSongsUseCase>(getSongs);

    await pump(tester, player);
    await openMenu(tester);
    await tester.tap(find.text('Auto-mix'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    verifyNever(() => player.addAllToQueue(any()));
  });

  testWidgets('auto-mix reports an empty library', (tester) async {
    final player = buildPlayer([createTestSong(id: 1, title: 'Seed')]);
    final getSongs = _GetSongs();
    when(() => getSongs.getAllSongs())
        .thenAnswer((_) async => const Right(<SongsTableData>[]));
    getIt.registerSingleton<GetSongsUseCase>(getSongs);

    await pump(tester, player);
    await openMenu(tester);
    await tester.tap(find.text('Auto-mix'));
    await tester.pumpAndSettle();

    expect(find.text('No similar tracks found in your library'), findsWidgets);
  });

  testWidgets('auto-mix reports when nothing similar was generated',
      (tester) async {
    final seed = createTestSong(id: 1, title: 'Seed');
    final player = buildPlayer([seed]);
    final getSongs = _GetSongs();
    final suggestions = _Suggestions();
    when(() => getSongs.getAllSongs())
        .thenAnswer((_) async => Right([seed, createTestSong(id: 2)]));
    when(() => suggestions.buildAutoDjQueue(any(), any(),
            limit: any(named: 'limit'), excludeIds: any(named: 'excludeIds')))
        .thenReturn(const <SongsTableData>[]);
    getIt.registerSingleton<GetSongsUseCase>(getSongs);
    getIt.registerSingleton<PlaylistSuggestionsService>(suggestions);

    await pump(tester, player);
    await openMenu(tester);
    await tester.tap(find.text('Auto-mix'));
    await tester.pumpAndSettle();

    expect(find.text('No similar tracks found in your library'), findsWidgets);
    verifyNever(() => player.addAllToQueue(any()));
  });

  testWidgets('save-as-playlist persists the queue', (tester) async {
    final player = buildPlayer([
      createTestSong(id: 1, title: 'Alpha'),
      createTestSong(id: 2, title: 'Beta'),
    ]);
    final useCases = _PlaylistUseCases();
    when(() => useCases.createPlaylist(any()))
        .thenAnswer((_) async => const Right(9));
    when(() => useCases.addSongsToPlaylist(any(), any()))
        .thenAnswer((_) async => const Right<AppFailure, void>(null));
    getIt.registerSingleton<PlaylistUseCases>(useCases);

    await pump(tester, player);
    await openMenu(tester);
    await tester.tap(find.text('Save as Playlist'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'My Mix');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => useCases.createPlaylist('My Mix')).called(1);
    verify(() => useCases.addSongsToPlaylist(9, [1, 2])).called(1);
    expect(find.text('Saved queue playlist'), findsOneWidget);
  });

  testWidgets('save-as-playlist reports a create failure', (tester) async {
    final player = buildPlayer([createTestSong(id: 1, title: 'Alpha')]);
    final useCases = _PlaylistUseCases();
    when(() => useCases.createPlaylist(any()))
        .thenAnswer((_) async => const Left(DatabaseFailure('nope')));
    getIt.registerSingleton<PlaylistUseCases>(useCases);

    await pump(tester, player);
    await openMenu(tester);
    await tester.tap(find.text('Save as Playlist'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Bad Mix');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Save failed'), findsWidgets);
  });

  testWidgets('decorates the current and online rows', (tester) async {
    final remote = SongsTableData(
      id: 2,
      title: 'Online',
      artist: 'A',
      album: 'Album',
      durationMs: 180000,
      path: 'ytmusic://video2',
      isMissing: false,
      isFavorite: false,
      playCount: 0,
      lastPositionMs: 0,
      source: 'youtube',
      isDownloaded: false,
      remoteId: 'vid2',
    );
    final player = buildPlayer([
      createTestSong(id: 1, title: 'Alpha'),
      remote,
    ]);
    await pump(tester, player);

    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cloud_rounded), findsOneWidget);
  });

  testWidgets('reordering a track reaches the cubit', (tester) async {
    final player = buildPlayer([
      createTestSong(id: 1, title: 'Alpha'),
      createTestSong(id: 2, title: 'Beta'),
    ]);
    await pump(tester, player);

    final list =
        tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    list.onReorderItem!(0, 1);
    await tester.pumpAndSettle();

    verify(() => player.reorderQueue(0, 1)).called(1);
  });
}
