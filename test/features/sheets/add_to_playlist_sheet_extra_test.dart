// AddToPlaylistSheet extra coverage: empty + error + populated states, the
// create-playlist flow (success, insert failure, create failure), adding to an
// existing playlist (success + failure) and the multi-song (batch) path.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/sheets/add_to_playlist_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlaylistUseCases extends Mock implements PlaylistUseCases {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlaylistUseCases useCases;

  const dummySong = SongsTableData(
    id: 101,
    title: 'Test Song',
    artist: 'Test Artist',
    album: 'Test Album',
    path: '/music/test.mp3',
    durationMs: 180000,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    dateAdded: 0,
    lastPositionMs: 0,
    source: SongSource.local,
  );

  const dummySong2 = SongsTableData(
    id: 102,
    title: 'Second Song',
    artist: 'Test Artist',
    album: 'Test Album',
    path: '/music/test2.mp3',
    durationMs: 181000,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    dateAdded: 0,
    lastPositionMs: 0,
    source: SongSource.local,
  );

  final playlist = PlaylistsTableData(
    id: 1,
    name: 'My Favorites',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    isSmart: false,
  );

  setUpAll(() {
    registerFallbackValue(<int>[]);
    registerFallbackValue('');
  });

  setUp(() {
    useCases = MockPlaylistUseCases();
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    List<SongsTableData>? songs,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      body: AddToPlaylistSheet(
                        song: dummySong,
                        songs: songs,
                        playlistUseCases: useCases,
                      ),
                    ),
                  ),
                ),
                child: const Text('open-sheet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the empty state and opens the create dialog',
      (tester) async {
    when(() => useCases.watchPlaylists())
        .thenAnswer((_) => Stream.value(const Right([])));
    await pumpSheet(tester);

    expect(find.text('No playlists created yet'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'New Playlist'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('renders the error state and retry re-renders',
      (tester) async {
    when(() => useCases.watchPlaylists())
        .thenAnswer((_) => Stream.value(const Left(DatabaseFailure('boom'))));
    await pumpSheet(tester);

    expect(find.text('Something went wrong'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
  });

  testWidgets('creates a playlist and adds a single song', (tester) async {
    when(() => useCases.watchPlaylists())
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => useCases.createPlaylist(any()))
        .thenAnswer((_) async => const Right(9));
    when(() => useCases.addSongToPlaylist(9, 101))
        .thenAnswer((_) async => const Right(null));
    await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'New Playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fresh Mix');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => useCases.createPlaylist('Fresh Mix')).called(1);
    verify(() => useCases.addSongToPlaylist(9, 101)).called(1);
    // Sheet popped back to the host.
    expect(find.text('open-sheet'), findsOneWidget);
  });

  testWidgets('create failure surfaces the failure message', (tester) async {
    when(() => useCases.watchPlaylists())
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => useCases.createPlaylist(any()))
        .thenAnswer((_) async => const Left(DatabaseFailure('dup name')));
    await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'New Playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fresh Mix');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('dup name'), findsOneWidget);
    verifyNever(() => useCases.addSongToPlaylist(any(), any()));
  });

  testWidgets('insert failure after create surfaces the message',
      (tester) async {
    when(() => useCases.watchPlaylists())
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => useCases.createPlaylist(any()))
        .thenAnswer((_) async => const Right(9));
    when(() => useCases.addSongToPlaylist(9, 101))
        .thenAnswer((_) async => const Left(DatabaseFailure('insert failed')));
    await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'New Playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fresh Mix');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('insert failed'), findsOneWidget);
    // The sheet did not pop.
    expect(find.text('open-sheet'), findsNothing);
  });

  testWidgets('adds the song to an existing playlist', (tester) async {
    when(() => useCases.watchPlaylists())
        .thenAnswer((_) => Stream.value(Right([playlist])));
    when(() => useCases.addSongToPlaylist(1, 101))
        .thenAnswer((_) async => const Right(null));
    await pumpSheet(tester);

    expect(find.text('My Favorites'), findsOneWidget);
    await tester.tap(find.text('My Favorites'));
    await tester.pumpAndSettle();

    verify(() => useCases.addSongToPlaylist(1, 101)).called(1);
    expect(find.text('open-sheet'), findsOneWidget);
  });

  testWidgets('existing-playlist failure surfaces the message',
      (tester) async {
    when(() => useCases.watchPlaylists())
        .thenAnswer((_) => Stream.value(Right([playlist])));
    when(() => useCases.addSongToPlaylist(1, 101))
        .thenAnswer((_) async => const Left(DatabaseFailure('cannot add')));
    await pumpSheet(tester);

    await tester.tap(find.text('My Favorites'));
    await tester.pumpAndSettle();

    expect(find.text('cannot add'), findsOneWidget);
  });

  testWidgets('batch mode adds every song id', (tester) async {
    when(() => useCases.watchPlaylists())
        .thenAnswer((_) => Stream.value(Right([playlist])));
    when(() => useCases.addSongsToPlaylist(1, any()))
        .thenAnswer((_) async => const Right(null));
    await pumpSheet(tester, songs: [dummySong, dummySong2]);

    await tester.tap(find.text('My Favorites'));
    await tester.pumpAndSettle();

    verify(() => useCases.addSongsToPlaylist(1, [101, 102])).called(1);
    verifyNever(() => useCases.addSongToPlaylist(any(), any()));
  });
}
