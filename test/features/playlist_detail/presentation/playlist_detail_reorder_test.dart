// Reorder mode wiring for local playlists: entering the mode, selecting songs
// and moving the selection must persist the new id order through the use case.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/playlist_detail/presentation/playlist_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _Playlists extends Mock implements PlaylistUseCases {}

final _playlist = PlaylistsTableData(
  id: 1,
  name: 'Reorder Me',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  isSmart: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Playlists useCases;
  final songs = [
    createTestSong(id: 1, title: 'Song A'),
    createTestSong(id: 2, title: 'Song B'),
    createTestSong(id: 3, title: 'Song C'),
  ];

  setUpAll(() {
    registerFallbackValue(<int>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
    useCases = _Playlists();
    when(() => useCases.watchPlaylistSongs(1)).thenAnswer(
      (_) => Stream.value(Right<AppFailure, List<SongsTableData>>(songs)),
    );
    when(() => useCases.reorderPlaylistSongs(any(), any()))
        .thenAnswer((_) async => const Right<AppFailure, void>(null));
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    useScreenSize(tester, const Size(800, 1400));
    await tester.pumpWidget(screenHarness(
      providers: [
        BlocProvider<PlayerCubit>.value(value: stubPlayerCubit()),
      ],
      child: PlaylistDetailScreen(
        playlist: _playlist,
        playlistUseCases: useCases,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('moving a selected song to the bottom persists the order',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Reorder Songs'), findsOneWidget);
    expect(
      find.text('Drag to reorder. Select tracks to move them in bulk.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Song B'));
    await tester.pump();

    await tester.tap(find.text('Move to bottom'));
    await tester.pumpAndSettle();

    verify(() => useCases.reorderPlaylistSongs(1, [1, 3, 2])).called(1);
  });

  testWidgets('done leaves reorder mode', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').first);
    await tester.pumpAndSettle();

    expect(find.text('Reorder Songs'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });
}
