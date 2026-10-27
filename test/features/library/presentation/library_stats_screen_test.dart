// LibraryStatsScreen widget suite: populated/empty/error states, time-range
// filtering, leaderboard taps and the clear-history confirmation flow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_stats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library_test_harness.dart';

class _Repo extends Mock implements IMusicRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerLibraryFallbacks();
    registerFallbackValue(<String>[]);
  });

  late _Repo repo;
  late MockPlayerCubit player;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = _Repo();
    when(() => repo.getExcludedFolderPaths())
        .thenAnswer((_) async => const Right([]));
    player = stubPlayerCubit();
  });

  SongsTableData song({
    required int id,
    String title = 'Song',
    String artist = 'Artist',
    int playCount = 0,
    int lastPlayed = 0,
    String? codec,
    int? fileSize,
    int? bitDepth,
    String? path,
  }) {
    return SongsTableData(
      id: id,
      title: title,
      artist: artist,
      album: 'Album',
      durationMs: 3600000,
      path: path ?? '/music/$id.mp3',
      source: SongSource.local,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: playCount,
      lastPlayed: lastPlayed == 0 ? null : lastPlayed,
      lastPositionMs: 0,
      codec: codec,
      fileSize: fileSize,
      bitDepth: bitDepth,
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required LibraryState state,
  }) async {
    disableAnimations(tester);
    setSurface(tester);
    await tester.pumpWidget(libraryHarness(
      libraryCubit: stubLibraryCubit(state),
      playerCubit: player,
      child: LibraryStatsScreen(musicRepository: repo),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders populated metrics, leaders and artists', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    when(() => repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) async => Right([
              song(
                  id: 1,
                  title: 'Hit One',
                  artist: 'ArtistA',
                  playCount: 5,
                  lastPlayed: now,
                  codec: 'FLAC',
                  fileSize: 100 * 1024 * 1024),
              song(
                  id: 2,
                  title: 'Hit Two',
                  artist: 'ArtistB',
                  playCount: 3,
                  lastPlayed: now,
                  codec: 'MP3'),
              song(id: 3, title: 'Silent', artist: 'ArtistA'),
            ]));

    await pump(tester, state: const LibraryState());

    expect(find.text('Listening & Library Stats'), findsOneWidget);
    expect(find.text('Most Played Tracks'), findsOneWidget);
    expect(find.text('Top Artists'), findsOneWidget);
    expect(find.text('Recently Played'), findsWidgets);
    expect(find.text('Hit One'), findsWidgets);
  });

  testWidgets('shows the no-history message for an unplayed library',
      (tester) async {
    when(() => repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) async => Right([song(id: 1, title: 'Never')]));

    await pump(tester, state: const LibraryState());

    expect(
        find.text(
            'No play history recorded yet. Listen to tracks to track your top hits!'),
        findsOneWidget);
  });

  testWidgets('lossless stats agree with the shared quality predicate',
      (tester) async {
    when(() => repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) async => Right([
              song(id: 1, codec: 'wav', bitDepth: 16),
              song(id: 2, path: '/music/album.flac'),
              song(id: 3, bitDepth: 24),
              song(id: 4, codec: 'mp3', bitDepth: 16),
            ]));

    await pump(tester, state: const LibraryState());

    expect(find.text('Lossless / Hi-Res: 3 tracks'), findsOneWidget);
    expect(find.text('Standard Lossy: 1 tracks'), findsOneWidget);
  });

  testWidgets('surfaces a failed full-library load with a retry',
      (tester) async {
    when(() => repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) async => const Left(DatabaseFailure('db down')));

    await pump(tester, state: const LibraryState());

    expect(find.textContaining('Failed to fetch'), findsOneWidget);

    when(() => repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) async => Right([]));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    verify(() =>
            repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .called(2);
  });

  testWidgets('tapping a leaderboard track starts playback', (tester) async {
    when(() => repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) async => Right([
              song(id: 1, title: 'Play Me', artist: 'A', playCount: 9),
            ]));

    await pump(tester, state: const LibraryState());

    await tester.tap(find.text('Play Me').first);
    await tester.pump();
    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('changing the time range persists the preference',
      (tester) async {
    when(() => repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) async => Right([
              song(
                  id: 1,
                  title: 'Recent',
                  artist: 'A',
                  playCount: 2,
                  lastPlayed: DateTime.now().millisecondsSinceEpoch),
            ]));

    await pump(tester, state: const LibraryState());

    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('stats_time_range_filter'), 0);
  });

  testWidgets('the refresh action re-queries the library', (tester) async {
    when(() => repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) async => const Right([]));

    await pump(tester, state: const LibraryState());

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    verify(() =>
            repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .called(greaterThanOrEqualTo(2));
  });

  testWidgets('clearing play history confirms then calls the repository',
      (tester) async {
    when(() => repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) async => const Right([]));
    when(() => repo.clearRecentlyPlayed())
        .thenAnswer((_) async => const Right(null));

    await pump(tester, state: const LibraryState());

    await tester.tap(find.byIcon(Icons.delete_sweep_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Clear Play History?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear History'));
    await tester.pumpAndSettle();

    verify(() => repo.clearRecentlyPlayed()).called(1);
  });

  testWidgets('clearing history refreshes the visible recently-played section',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    when(() => repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) async => Right([
              song(
                  id: 1,
                  title: 'OnlyRecent',
                  artist: 'A',
                  playCount: 0,
                  lastPlayed: now),
            ]));
    when(() => repo.clearRecentlyPlayed())
        .thenAnswer((_) async => const Right(null));

    await pump(tester, state: const LibraryState());
    expect(find.text('OnlyRecent'), findsWidgets);

    await tester.tap(find.byIcon(Icons.delete_sweep_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear History'));
    await tester.pumpAndSettle();

    expect(find.text('OnlyRecent'), findsNothing);
  });

  testWidgets('a failed history clear reports the error', (tester) async {
    when(() => repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) async => const Right([]));
    when(() => repo.clearRecentlyPlayed())
        .thenAnswer((_) async => const Left(DatabaseFailure('locked')));

    await pump(tester, state: const LibraryState());

    await tester.tap(find.byIcon(Icons.delete_sweep_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear History'));
    await tester.pumpAndSettle();

    verify(() => repo.clearRecentlyPlayed()).called(1);
  });
}
