import 'dart:async';
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

  late MockPlaylistUseCases mockPlaylistUseCases;
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

  final dummyPlaylist = PlaylistsTableData(
    id: 1,
    name: 'My Favorites',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    isSmart: false,
  );

  setUp(() {
    mockPlaylistUseCases = MockPlaylistUseCases();
  });

  testWidgets('[M-11] IgnorePointer does not block cancel button during mutation overlay', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mutationCompleter = Completer<Result<void>>();

    when(() => mockPlaylistUseCases.watchPlaylists()).thenAnswer(
      (_) => Stream.value(Right([dummyPlaylist])),
    );
    when(() => mockPlaylistUseCases.addSongToPlaylist(1, 101)).thenAnswer(
      (_) => mutationCompleter.future,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AddToPlaylistSheet(
            song: dummySong,
            playlistUseCases: mockPlaylistUseCases,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify playlist name is rendered
    expect(find.text('My Favorites'), findsOneWidget);

    // Tap on playlist to start mutation
    await tester.tap(find.text('My Favorites'));
    await tester.pump(); // Start mutation, build overlay

    // The mutation overlay is visible with progress indicators (trailing header + overlay)
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));

    // Find the Cancel button in the mutation overlay
    final cancelButton = find.text('Cancel');
    expect(cancelButton, findsOneWidget);

    // Tap the Cancel button while mutation is in flight - should succeed because IgnorePointer does not wrap it
    await tester.tap(cancelButton);
    await tester.pump();

    // Overlay is dismissed and mutation is cancelled
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Complete the pending future safely
    mutationCompleter.complete(const Right(null));
    await tester.pump();
  });
}
