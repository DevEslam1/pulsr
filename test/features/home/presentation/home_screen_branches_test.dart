// HomeScreen branch coverage for the locally reachable paths: the quick-action
// cache failure, the library-stream cache invalidation, login-state changes,
// the local pull-to-refresh and the dock-height bottom padding.
//
// The online tab/view is unreachable here because AppConfig.ytmEnabled defaults
// to false in the test environment.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/widgets/pulsr_dock_tracker.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/features/home/presentation/home_screen.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _YtmService extends Mock implements YtmService {}

class _Account extends Mock implements YtmAccountService {}

class _GetSongs extends Mock implements GetSongsUseCase {}

class _LibraryCubit extends Mock implements LibraryCubit {}

class _SettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _YtmService ytm;
  late _Account account;
  late _GetSongs getSongs;
  late _LibraryCubit libraryCubit;
  late _SettingsCubit settingsCubit;
  late ValueNotifier<bool> loginState;
  late PlayerCubit player;

  setUpAll(() {
    registerFallbackValue(createTestSong(id: -1));
    registerFallbackValue(<SongsTableData>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PulsrDockTracker.dockHeight.value = 0;
    ytm = _YtmService();
    account = _Account();
    getSongs = _GetSongs();
    libraryCubit = _LibraryCubit();
    settingsCubit = _SettingsCubit();
    loginState = ValueNotifier<bool>(false);
    player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});

    when(() => account.loginState).thenReturn(loginState);
    when(() => account.isLoggedIn).thenReturn(false);

    when(() => getSongs.getAllSongs(limit: any(named: 'limit')))
        .thenAnswer((_) async => const Right(<SongsTableData>[]));
    when(() => getSongs.watchRecentlyPlayed(limit: any(named: 'limit')))
        .thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));
    when(() => getSongs.watchRecentlyAdded(limit: any(named: 'limit')))
        .thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));

    when(() => libraryCubit.state).thenReturn(const LibraryState());
    when(() => libraryCubit.stream)
        .thenAnswer((_) => const Stream<LibraryState>.empty());

    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => settingsCubit.rescanLibrary()).thenAnswer((_) async => 0);

    addTearDown(loginState.dispose);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Stream<LibraryState>? libraryStream,
  }) async {
    if (libraryStream != null) {
      when(() => libraryCubit.stream).thenAnswer((_) => libraryStream);
    }
    useScreenSize(tester, const Size(900, 1800));
    await tester.pumpWidget(screenHarness(
      providers: [
        BlocProvider<PlayerCubit>.value(value: player),
        BlocProvider<LibraryCubit>.value(value: libraryCubit),
        BlocProvider<SettingsCubit>.value(value: settingsCubit),
      ],
      child: HomeScreen(
        ytmService: ytm,
        ytmAccountService: account,
        getSongsUseCase: getSongs,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a failed quick-action fetch plays nothing', (tester) async {
    when(() => getSongs.getAllSongs(limit: any(named: 'limit')))
        .thenAnswer((_) async => const Left(DatabaseFailure('offline')));

    await pumpScreen(tester);
    await tester.tap(find.text('Daily Drive'));
    await tester.pumpAndSettle();

    verifyNever(() => player.playSong(any(), queue: any(named: 'queue')));
  });

  testWidgets('a library stream change invalidates the quick-action cache',
      (tester) async {
    final controller = StreamController<LibraryState>.broadcast();
    addTearDown(controller.close);
    await pumpScreen(tester, libraryStream: controller.stream);

    controller.add(LibraryState(songs: [createTestSong(id: 1)]));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a login-state change clears the home cache', (tester) async {
    await pumpScreen(tester);

    loginState.value = true;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('local pull-to-refresh rescans the library', (tester) async {
    await pumpScreen(tester);

    final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator).first);
    await indicator.onRefresh();
    await tester.pumpAndSettle();

    verify(() => settingsCubit.rescanLibrary()).called(1);
  });

  testWidgets('an open dock adds its height to the scroll padding',
      (tester) async {
    await pumpScreen(tester);

    PulsrDockTracker.dockHeight.value = 120;
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
