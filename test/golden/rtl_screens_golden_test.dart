// test/golden/rtl_screens_golden_test.dart
//
// RTL (Arabic) layout & golden verification for the 10 highest-traffic screens.
// Golden PNG baselines live in `test/golden/goldens/` (gitignored): when
// absent on a clean checkout, tests still pump and verify `TextDirection.rtl`
// and zero overflow exceptions; when baselines exist (generated via
// `flutter test test/golden/rtl_screens_golden_test.dart --update-goldens`),
// exact pixel goldens are enforced.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/models/radio_station.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/features/album_detail/presentation/album_detail_screen.dart';
import 'package:pulsr/features/auth/cubit/auth_cubit.dart';
import 'package:pulsr/features/auth/cubit/auth_state.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/downloads/cubit/downloads_state.dart';
import 'package:pulsr/features/downloads/presentation/downloads_screen.dart';
import 'package:pulsr/features/folder_detail/presentation/folder_detail_screen.dart';
import 'package:pulsr/features/home/presentation/home_screen.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/favorites_screen.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:pulsr/features/playlists/cubit/playlist_state.dart';
import 'package:pulsr/features/playlists/presentation/playlists_screen.dart';
import 'package:pulsr/features/queue/presentation/queue_screen.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';
import 'package:pulsr/features/search/cubit/search_state.dart';
import 'package:pulsr/features/search/presentation/search_screen.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/presentation/settings_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/library/library_test_harness.dart' as lib_h;
import '../helpers/detail_screen_harness.dart' as detail_h;
import '../helpers/screen_harness.dart' as scr_h;
import '../helpers/test_song_factory.dart';

class _MockYtmService extends Mock implements YtmService {}

class _MockYtmAccount extends Mock implements YtmAccountService {}

class _MockGetSongs extends Mock implements GetSongsUseCase {}

class _MockGetAlbums extends Mock implements GetAlbumsUseCase {}

class _MockFolderUseCases extends Mock implements FolderUseCases {}

class _MockSearchCubit extends Mock implements SearchCubit {}

class _MockPlaylistCubit extends Mock implements PlaylistCubit {}

class _MockDownloadsCubit extends Mock implements DownloadsCubit {}

class _MockScanner extends Mock implements MediaScannerService {}

class _MockAuthCubit extends Mock implements AuthCubit {}

class _FakeRadioStation extends Fake implements RadioStation {}

Future<void> _verifyRtlAndOptionalGolden(
  WidgetTester tester,
  String goldenName,
) async {
  expect(tester.takeException(), isNull);
  final scaffoldContext = tester.element(find.byType(Scaffold).first);
  expect(Directionality.of(scaffoldContext), equals(TextDirection.rtl));

  final goldenPath = 'goldens/$goldenName.png';
  final fullPath = 'test/golden/$goldenPath';
  if (autoUpdateGoldenFiles || File(fullPath).existsSync()) {
    await expectLater(
      find.byType(MaterialApp).first,
      matchesGoldenFile(goldenPath),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const arLocale = Locale('ar');
  const phoneSize = Size(390, 844);

  setUpAll(() {
    lib_h.registerLibraryFallbacks();
    registerFallbackValue(createTestSong(id: -1));
    registerFallbackValue(<SongsTableData>[]);
    registerFallbackValue(<String>[]);
    registerFallbackValue(_FakeRadioStation());
    registerFallbackValue('');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
      'smart_playlists_seeded': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel(PulsrChannels.hiresDacEvents),
      MockStreamHandler.inline(onListen: (_, __) {}),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.hiresDac),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      (call) async {
        if (call.method == 'setSystemEffectsPolicy') {
          return <String, dynamic>{
            'status': 'unsupportedDevice',
            'detectedBundles': <String>[],
          };
        }
        return null;
      },
    );
  });

  // 1. HomeScreen
  testWidgets('1. HomeScreen RTL layout & golden', (tester) async {
    scr_h.useScreenSize(tester, phoneSize);
    lib_h.disableAnimations(tester);
    final ytm = _MockYtmService();
    final account = _MockYtmAccount();
    final getSongs = _MockGetSongs();
    final loginState = ValueNotifier<bool>(false);
    addTearDown(loginState.dispose);

    when(() => account.loginState).thenReturn(loginState);
    when(() => account.isLoggedIn).thenReturn(false);
    when(() => getSongs.getAllSongs(
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
          limit: any(named: 'limit'),
          excludedFolders: any(named: 'excludedFolders'),
        )).thenAnswer((_) async => const Right(<SongsTableData>[]));
    when(() => getSongs.watchTopPlayed(
            limit: any(named: 'limit'),
            excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));
    when(() => getSongs.watchRecentlyPlayed(limit: any(named: 'limit')))
        .thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));
    when(() => getSongs.watchRecentlyAdded(limit: any(named: 'limit')))
        .thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));

    final libraryCubit = lib_h.stubLibraryCubit(const LibraryState());
    final settingsCubit = lib_h.stubSettingsCubit();
    final playerCubit = scr_h.stubPlayerCubit();

    await tester.pumpWidget(
      scr_h.screenHarness(
        locale: arLocale,
        size: phoneSize,
        providers: [
          BlocProvider<LibraryCubit>.value(value: libraryCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
          BlocProvider<PlayerCubit>.value(value: playerCubit),
        ],
        child: HomeScreen(
          ytmService: ytm,
          ytmAccountService: account,
          getSongsUseCase: getSongs,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _verifyRtlAndOptionalGolden(tester, 'rtl_home_screen');
  });

  // 2. LibraryScreen
  testWidgets('2. LibraryScreen RTL layout & golden', (tester) async {
    lib_h.setSurface(tester, size: phoneSize);
    lib_h.disableAnimations(tester);
    final songs = [
      createTestSong(id: 1, title: 'أغنية أولى', artist: 'فنان أ'),
      createTestSong(id: 2, title: 'أغنية ثانية', artist: 'فنان ب'),
    ];
    await tester.pumpWidget(
      lib_h.libraryHarness(
        locale: arLocale,
        size: phoneSize,
        libraryCubit: lib_h.stubLibraryCubit(LibraryState(songs: songs)),
        child: const LibraryScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await _verifyRtlAndOptionalGolden(tester, 'rtl_library_screen');
  });

  // 3. SearchScreen
  testWidgets('3. SearchScreen RTL layout & golden', (tester) async {
    scr_h.useScreenSize(tester, phoneSize);
    lib_h.disableAnimations(tester);
    final searchCubit = _MockSearchCubit();
    final saved = ValueNotifier<List<String>>(const ['موسيقى']);
    final played = ValueNotifier<List<SongsTableData>>(const []);
    final hasMore = ValueNotifier<bool>(false);
    addTearDown(() {
      saved.dispose();
      played.dispose();
      hasMore.dispose();
    });

    when(() => searchCubit.state).thenReturn(const SearchState());
    when(() => searchCubit.stream)
        .thenAnswer((_) => const Stream<SearchState>.empty());
    when(() => searchCubit.savedSearches).thenReturn(saved);
    when(() => searchCubit.searchPlayedSongs).thenReturn(played);
    when(() => searchCubit.hasMoreResults).thenReturn(hasMore);
    when(() => searchCubit.isDebouncing).thenReturn(false);
    when(() => searchCubit.isSaved(any(), any())).thenReturn(false);
    when(() => searchCubit.suggestionsFor(any()))
        .thenAnswer((_) async => const <String>[]);

    await tester.pumpWidget(
      scr_h.screenHarness(
        locale: arLocale,
        size: phoneSize,
        providers: [
          BlocProvider<SearchCubit>.value(value: searchCubit),
          BlocProvider<PlayerCubit>.value(value: scr_h.stubPlayerCubit()),
        ],
        child: const SearchScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await _verifyRtlAndOptionalGolden(tester, 'rtl_search_screen');
  });

  // 4. PlaylistsScreen
  testWidgets('4. PlaylistsScreen RTL layout & golden', (tester) async {
    scr_h.useScreenSize(tester, phoneSize);
    lib_h.disableAnimations(tester);
    final playlistCubit = _MockPlaylistCubit();
    final playlist = PlaylistsTableData(
      id: 1,
      name: 'مفضلات السفر',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      isSmart: false,
    );
    when(() => playlistCubit.state).thenReturn(
      PlaylistState(
        isLoading: false,
        playlists: [playlist],
        smartPlaylistCounts: const {1: 8},
      ),
    );
    when(() => playlistCubit.stream)
        .thenAnswer((_) => const Stream<PlaylistState>.empty());
    when(() => playlistCubit.reloadPlaylists()).thenReturn(null);
    await getIt.reset();
    getIt.registerSingleton<GetSongsUseCase>(_MockGetSongs());
    addTearDown(() => getIt.reset());

    await tester.pumpWidget(
      scr_h.screenHarness(
        locale: arLocale,
        size: phoneSize,
        providers: [
          BlocProvider<PlaylistCubit>.value(value: playlistCubit),
          BlocProvider<PlayerCubit>.value(value: scr_h.stubPlayerCubit()),
        ],
        child: const PlaylistsScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await _verifyRtlAndOptionalGolden(tester, 'rtl_playlists_screen');
  });

  // 5. SettingsScreen
  testWidgets('5. SettingsScreen RTL layout & golden', (tester) async {
    scr_h.useScreenSize(tester, phoneSize);
    lib_h.disableAnimations(tester);
    final settingsCubit = SettingsCubit(scannerService: _MockScanner());
    final authCubit = _MockAuthCubit();
    when(() => authCubit.state).thenReturn(const AuthState());
    when(() => authCubit.stream)
        .thenAnswer((_) => const Stream<AuthState>.empty());
    addTearDown(settingsCubit.close);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: phoneSize, disableAnimations: true),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsCubit>.value(value: settingsCubit),
            BlocProvider<PlayerCubit>.value(value: scr_h.stubPlayerCubit()),
            BlocProvider<AuthCubit>.value(value: authCubit),
          ],
          child: MaterialApp(
            theme: AuraTheme.darkTheme,
            locale: arLocale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await _verifyRtlAndOptionalGolden(tester, 'rtl_settings_screen');
  });

  // 6. DownloadsScreen
  testWidgets('6. DownloadsScreen RTL layout & golden', (tester) async {
    scr_h.useScreenSize(tester, phoneSize);
    lib_h.disableAnimations(tester);
    final downloadsCubit = _MockDownloadsCubit();
    when(() => downloadsCubit.stream)
        .thenAnswer((_) => const Stream<DownloadsState>.empty());
    when(() => downloadsCubit.state).thenReturn(
      DownloadsState(
        tasks: {
          'v1': DownloadTask(
            id: 'd1',
            videoId: 'v1',
            title: 'مقطوعة موسيقية',
            artist: 'الفنان',
            status: DownloadStatus.downloading,
            progress: 0.45,
            speedKbps: 512,
            etaSeconds: 42,
            createdAt: DateTime(2024, 1, 1),
          ),
        },
      ),
    );
    await tester.pumpWidget(
      scr_h.screenHarness(
        locale: arLocale,
        size: phoneSize,
        providers: [
          BlocProvider<DownloadsCubit>.value(value: downloadsCubit),
          BlocProvider<PlayerCubit>.value(value: scr_h.stubPlayerCubit()),
        ],
        child: const DownloadsScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await _verifyRtlAndOptionalGolden(tester, 'rtl_downloads_screen');
  });

  // 7. QueueScreen
  testWidgets('7. QueueScreen RTL layout & golden', (tester) async {
    scr_h.useScreenSize(tester, phoneSize);
    lib_h.disableAnimations(tester);
    final queueSongs = [
      createTestSong(id: 1, title: 'الأولى'),
      createTestSong(id: 2, title: 'الثانية'),
    ];
    await tester.pumpWidget(
      scr_h.screenHarness(
        locale: arLocale,
        size: phoneSize,
        providers: [
          BlocProvider<PlayerCubit>.value(
            value: scr_h.stubPlayerCubit(
              PlayerState(
                queueSlice: QueueSlice(queue: queueSongs, currentIndex: 0),
              ),
            ),
          ),
        ],
        child: const QueueScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await _verifyRtlAndOptionalGolden(tester, 'rtl_queue_screen');
  });

  // 8. FavoritesScreen
  testWidgets('8. FavoritesScreen RTL layout & golden', (tester) async {
    lib_h.setSurface(tester, size: phoneSize);
    lib_h.disableAnimations(tester);
    await tester.pumpWidget(
      lib_h.libraryHarness(
        locale: arLocale,
        size: phoneSize,
        libraryCubit: lib_h.stubLibraryCubit(
          LibraryState(favorites: [
            createTestSong(id: 1, title: 'المفضلة الأولى', isFavorite: true),
          ]),
        ),
        child: const FavoritesScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await _verifyRtlAndOptionalGolden(tester, 'rtl_favorites_screen');
  });

  // 9. AlbumDetailScreen
  testWidgets('9. AlbumDetailScreen RTL layout & golden', (tester) async {
    lib_h.setSurface(tester, size: phoneSize);
    lib_h.disableAnimations(tester);
    final useCase = _MockGetAlbums();
    const album = AlbumsTableData(
      id: 1,
      title: 'ألبوم تجريبي',
      artist: 'فنان',
      songCount: 2,
    );
    when(() => useCase.watchAlbumSongs(any())).thenAnswer(
      (_) => Stream.value(Right([
        createTestSong(id: 1, title: 'المسار الأول'),
        createTestSong(id: 2, title: 'المسار الثاني'),
      ])),
    );
    await tester.pumpWidget(
      detail_h.detailHarness(
        locale: arLocale,
        size: phoneSize,
        child: AlbumDetailScreen(album: album, getAlbumsUseCase: useCase),
      ),
    );
    await tester.pumpAndSettle();
    await _verifyRtlAndOptionalGolden(tester, 'rtl_album_detail_screen');
  });

  // 10. FolderDetailScreen
  testWidgets('10. FolderDetailScreen RTL layout & golden', (tester) async {
    lib_h.setSurface(tester, size: phoneSize);
    lib_h.disableAnimations(tester);
    final useCase = _MockFolderUseCases();
    const folder = FolderItem(
      path: '/music/arabic',
      name: 'الموسيقى العربية',
      songCount: 2,
      isExcluded: false,
    );
    when(() => useCase.watchFolderSongs(any())).thenAnswer(
      (_) => Stream.value(Right([
        createTestSong(id: 1, title: 'مقطع أول', durationMs: 240000),
        createTestSong(id: 2, title: 'مقطع ثاني', durationMs: 180000),
      ])),
    );
    await tester.pumpWidget(
      detail_h.detailHarness(
        locale: arLocale,
        size: phoneSize,
        child: BlocProvider<LibraryCubit>.value(
          value: lib_h.stubLibraryCubit(const LibraryState()),
          child: FolderDetailScreen(folder: folder, folderUseCases: useCase),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _verifyRtlAndOptionalGolden(tester, 'rtl_folder_detail_screen');
  });
}
