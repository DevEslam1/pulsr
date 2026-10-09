// PlaylistsScreen widget suite.
//
// Covers the loading skeleton, error and empty states, the populated local
// grid, the create-playlist dialog flow and the local/online tab switch.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/widgets/shimmer_skeleton.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:pulsr/features/playlists/cubit/playlist_state.dart';
import 'package:pulsr/features/playlists/presentation/playlists_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';

class _PlaylistCubit extends Mock implements PlaylistCubit {}

class _GetSongs extends Mock implements GetSongsUseCase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PlaylistCubit cubit;
  late StreamController<PlaylistState> states;

  final userPlaylist = PlaylistsTableData(
    id: 1,
    name: 'Road Trip',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    isSmart: false,
  );

  setUp(() {
    // Mark default smart playlists as seeded so the real cubit seeding path is
    // never reached.
    SharedPreferences.setMockInitialValues({'smart_playlists_seeded': true});
    cubit = _PlaylistCubit();
    states = StreamController<PlaylistState>.broadcast();
    when(() => cubit.state).thenReturn(const PlaylistState(isLoading: true));
    when(() => cubit.stream).thenAnswer((_) => states.stream);
    when(() => cubit.createPlaylist(any())).thenAnswer((_) async {});
    when(() => cubit.autoFetchOnlineLibrary()).thenAnswer((_) async {});
    when(() => cubit.reloadPlaylists()).thenReturn(null);
    getIt.registerSingleton<GetSongsUseCase>(_GetSongs());
    addTearDown(() async {
      await states.close();
      await getIt.reset();
    });
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    useScreenSize(tester, const Size(800, 1400));
    final player = stubPlayerCubit();
    await tester.pumpWidget(screenHarness(
      providers: [
        BlocProvider<PlaylistCubit>.value(value: cubit),
        BlocProvider<PlayerCubit>.value(value: player),
      ],
      child: const PlaylistsScreen(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> emit(WidgetTester tester, PlaylistState state) async {
    states.add(state);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the loading skeleton while playlists load',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byType(PlaylistsScreen), findsOneWidget);
    expect(find.byType(SkeletonGrid), findsOneWidget);
  });

  testWidgets('renders the error state with a retry action', (tester) async {
    await pumpScreen(tester);

    await emit(
        tester, const PlaylistState(isLoading: false, errorMessage: 'boom'));

    expect(find.text('Failed to load playlist.'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    verify(() => cubit.reloadPlaylists()).called(1);
  });

  testWidgets('renders the empty playlists state', (tester) async {
    await pumpScreen(tester);

    await emit(tester, const PlaylistState(isLoading: false));

    expect(find.text('No playlists created yet'), findsOneWidget);
  });

  testWidgets('renders a card for each user playlist', (tester) async {
    await pumpScreen(tester);

    await emit(
        tester, PlaylistState(isLoading: false, playlists: [userPlaylist]));

    expect(find.text('Road Trip'), findsOneWidget);
    expect(find.text('Offline playlist'), findsOneWidget);
  });

  testWidgets('creating a playlist pushes the name to the cubit',
      (tester) async {
    await pumpScreen(tester);

    await emit(
        tester, PlaylistState(isLoading: false, playlists: [userPlaylist]));

    await tester.tap(find.widgetWithIcon(IconButton, Icons.add_rounded));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Fresh Mix');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => cubit.createPlaylist('Fresh Mix')).called(1);
  });

  testWidgets('switching to the online tab triggers the online fetch',
      (tester) async {
    await pumpScreen(tester);

    await emit(
        tester, PlaylistState(isLoading: false, playlists: [userPlaylist]));

    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();

    verify(() => cubit.autoFetchOnlineLibrary()).called(greaterThanOrEqualTo(1));
  });
}
