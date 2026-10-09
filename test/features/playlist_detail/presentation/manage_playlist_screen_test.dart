// ManagePlaylistScreen widget suite.
//
// Covers loading, populated/empty/error states, the search filter, selection
// toggling and applying changes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/playlist_detail/presentation/manage_playlist_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _Playlists extends Mock implements PlaylistUseCases {}

class _GetSongs extends Mock implements GetSongsUseCase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Playlists playlists;
  late _GetSongs getSongs;

  final playlist = PlaylistsTableData(
    id: 1,
    name: 'Road Trip',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    isSmart: false,
  );

  setUpAll(() {
    registerFallbackValue(<int>[]);
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    playlists = _Playlists();
    getSongs = _GetSongs();
    getIt.registerSingleton<PlaylistUseCases>(playlists);
    getIt.registerSingleton<GetSongsUseCase>(getSongs);
    addTearDown(() async {
      await getIt.reset();
    });
  });

  Widget build() => screenHarness(
        child: ManagePlaylistScreen(playlist: playlist),
      );

  testWidgets('shows a skeleton while the playlist songs load, then the list',
      (tester) async {
    useScreenSize(tester, const Size(800, 1400));
    final controller = StreamController<Result<List<SongsTableData>>>();
    addTearDown(controller.close);

    when(() => playlists.watchPlaylistSongs(any()))
        .thenAnswer((_) => controller.stream);
    when(() => getSongs.watchSongs()).thenAnswer(
        (_) => Stream.value(Right([createTestSong(id: 1, title: 'Alpha')])));

    await tester.pumpWidget(build());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Skeleton is rendered by SkeletonList while _isLoading.
    expect(find.text('Alpha'), findsNothing);

    controller.add(Right([createTestSong(id: 1, title: 'Alpha')]));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('renders the header, count and every song', (tester) async {
    useScreenSize(tester, const Size(800, 1400));
    final songs = [
      createTestSong(id: 1, title: 'Alpha'),
      createTestSong(id: 2, title: 'Beta'),
    ];
    when(() => playlists.watchPlaylistSongs(any()))
        .thenAnswer((_) => Stream.value(Right(songs)));
    when(() => getSongs.watchSongs())
        .thenAnswer((_) => Stream.value(Right(songs)));

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('Manage Playlist'), findsOneWidget);
    expect(find.text('Road Trip'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));
  });

  testWidgets('renders the empty-library state', (tester) async {
    useScreenSize(tester, const Size(800, 1400));
    when(() => playlists.watchPlaylistSongs(any()))
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => getSongs.watchSongs())
        .thenAnswer((_) => Stream.value(const Right([])));

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('No songs in library'), findsOneWidget);
  });

  testWidgets('renders the error state and retries', (tester) async {
    useScreenSize(tester, const Size(800, 1400));
    var calls = 0;
    when(() => playlists.watchPlaylistSongs(any())).thenAnswer((_) {
      calls++;
      return Stream.value(const Left(DatabaseFailure('boom')));
    });
    when(() => getSongs.watchSongs())
        .thenAnswer((_) => Stream.value(const Right([])));

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('Failed to load playlist.'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(calls, greaterThanOrEqualTo(2));
  });

  testWidgets('filters the song list as the user types', (tester) async {
    useScreenSize(tester, const Size(800, 1400));
    final songs = [
      createTestSong(id: 1, title: 'Alpha'),
      createTestSong(id: 2, title: 'Beta'),
    ];
    when(() => playlists.watchPlaylistSongs(any()))
        .thenAnswer((_) => Stream.value(Right(songs)));
    when(() => getSongs.watchSongs())
        .thenAnswer((_) => Stream.value(Right(songs)));

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Search songs by title or artist...'),
        'Alpha');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
  });

  testWidgets('applying a deselection removes the song', (tester) async {
    useScreenSize(tester, const Size(800, 1400));
    final songs = [
      createTestSong(id: 1, title: 'Alpha'),
      createTestSong(id: 2, title: 'Beta'),
    ];
    when(() => playlists.watchPlaylistSongs(any()))
        .thenAnswer((_) => Stream.value(Right([songs.first])));
    when(() => getSongs.watchSongs())
        .thenAnswer((_) => Stream.value(Right(songs)));
    when(() => playlists.removeSongFromPlaylist(any(), any()))
        .thenAnswer((_) async => const Right(null));

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    // Deselect the currently-selected playlist song.
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Will remove'), findsOneWidget);

    await tester.tap(find.textContaining('Apply Changes'));
    await tester.pumpAndSettle();

    verify(() => playlists.removeSongFromPlaylist(1, 1)).called(1);
  });
}
