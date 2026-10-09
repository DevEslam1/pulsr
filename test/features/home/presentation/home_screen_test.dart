// HomeScreen widget suite (local build): header/greeting, the quick-action
// tiles, recently played/added sections, the notification-denied banner and
// the offline-only presentation.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/features/home/presentation/home_screen.dart';
import 'package:pulsr/features/home/presentation/widgets/empty_library.dart';
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

    addTearDown(() => loginState.dispose());
  });

  Future<void> pumpScreen(WidgetTester tester,
      {SettingsState settings = const SettingsState()}) async {
    useScreenSize(tester, const Size(900, 1800));
    when(() => settingsCubit.state).thenReturn(settings);
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

  testWidgets('renders the header, hero action and quick tiles',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Daily Drive'), findsOneWidget);
    expect(find.text('Focus Flow'), findsOneWidget);
    expect(find.text('Favorites'), findsWidgets);
  });

  testWidgets('the Daily Drive hero starts a shuffled queue', (tester) async {
    when(() => getSongs.getAllSongs(limit: any(named: 'limit')))
        .thenAnswer((_) async =>
            Right([createTestSong(id: 1, title: 'A'), createTestSong(id: 2)]));

    await pumpScreen(tester);
    await tester.tap(find.text('Daily Drive'));
    await tester.pumpAndSettle();

    verify(() => getSongs.getAllSongs(limit: 50)).called(1);
    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('the Favorites quick tile navigates', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Favorites').first);
    await tester.pumpAndSettle();
    expect(find.text('favorites-route'), findsOneWidget);
  });

  testWidgets('recently played tracks render and play on tap', (tester) async {
    when(() => getSongs.watchRecentlyPlayed(limit: any(named: 'limit')))
        .thenAnswer((_) => Stream.value(Right([
              createTestSong(id: 1, title: 'Recent One'),
              createTestSong(id: 2, title: 'Recent Two'),
            ])));

    await pumpScreen(tester);
    expect(find.text('Recent One'), findsOneWidget);

    await tester.tap(find.text('Recent One'));
    await tester.pump();
    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('an empty recently-added section shows the empty library state',
      (tester) async {
    await pumpScreen(tester);
    expect(find.byType(EmptyLibrary), findsOneWidget);
  });

  testWidgets('the notification-denied banner can be dismissed',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'notification_permission_denied': true});
    await pumpScreen(tester);

    expect(find.text('Playback stops when screen is off?'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Playback stops when screen is off?'), findsNothing);
  });

  testWidgets('offline-only mode hides the online tab and shows the notice',
      (tester) async {
    await pumpScreen(tester, settings: const SettingsState(offlineOnlyMode: true));
    // The online/local segmented control is hidden in offline-only mode.
    expect(find.text('Online'), findsNothing);
    expect(find.text('Offline Only Mode'), findsOneWidget);
  });
}
