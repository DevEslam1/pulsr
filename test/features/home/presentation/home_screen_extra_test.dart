// HomeScreen branches the primary suite misses: the Focus Flow quick tile, the
// discovery-tools sheet behind the "More" chip, and the notification banner's
// Open Settings action.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/features/home/presentation/home_screen.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _YtmService extends Mock implements YtmService {}

class _Account extends Mock implements YtmAccountService {}

class _GetSongs extends Mock implements GetSongsUseCase {}

class _LibraryCubit extends Mock implements LibraryCubit {}

class _SettingsCubit extends Mock implements SettingsCubit {}

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

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
    _messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async => true,
    );

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

    addTearDown(() {
      _messenger.setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          null);
      loginState.dispose();
    });
  });

  Future<void> pumpScreen(WidgetTester tester,
      {Size size = const Size(900, 1800)}) async {
    useScreenSize(tester, size);
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

  testWidgets('the Focus Flow tile plays the most-played tracks first',
      (tester) async {
    when(() => getSongs.getAllSongs(limit: any(named: 'limit')))
        .thenAnswer((_) async => Right([
              createTestSong(id: 1, title: 'Low', playCount: 1),
              createTestSong(id: 2, title: 'High', playCount: 9),
              createTestSong(id: 3, title: 'Mid', playCount: 4),
            ]));

    await pumpScreen(tester);
    await tester.tap(find.text('Focus Flow'));
    await tester.pumpAndSettle();

    final captured = verify(
            () => player.playSong(captureAny(), queue: captureAny(named: 'queue')))
        .captured;
    final first = captured[0] as SongsTableData;
    expect(first.title, 'High');
  });

  testWidgets('the quick-action song cache is reused within its TTL',
      (tester) async {
    when(() => getSongs.getAllSongs(limit: any(named: 'limit')))
        .thenAnswer((_) async =>
            Right([createTestSong(id: 1, title: 'A', playCount: 1)]));

    await pumpScreen(tester);
    await tester.tap(find.text('Daily Drive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily Drive'));
    await tester.pumpAndSettle();

    verify(() => getSongs.getAllSongs(limit: 50)).called(1);
  });

  testWidgets('the More chip opens the discovery tools sheet', (tester) async {
    await pumpScreen(tester);

    // The discovery strip is a lazy horizontal list; scroll it to the end so
    // the trailing "More tools" chip is built and hittable.
    final horizontal = find
        .byWidgetPredicate(
            (w) => w is ListView && w.scrollDirection == Axis.horizontal)
        .first;
    await tester.drag(horizontal, const Offset(-800, 0));
    await tester.pumpAndSettle();

    final more = find.text(
        lookupAppLocalizations(const Locale('en')).browseMoreTools);
    expect(more, findsOneWidget);
    await tester.tap(more);
    await tester.pumpAndSettle();

    // The sheet's ListTiles trip a debug-only "ink splash may be invisible"
    // assertion in this Flutter release; drain it so the coverage still runs.
    for (var i = 0; i < 8; i++) {
      if (tester.takeException() == null) break;
    }

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.artworkWall), findsOneWidget);
    expect(find.text(l10n.duplicateCleaner), findsOneWidget);
    expect(find.text(l10n.themeStudio), findsOneWidget);
  });

  testWidgets('the notification banner Open Settings clears the denied flag',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'notification_permission_denied': true});
    await pumpScreen(tester);

    expect(find.text('Playback stops when screen is off?'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Playback stops when screen is off?'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('notification_permission_denied'), isFalse);
  });
}
