// Wave 2 regression tests for Home feature: C-09 (Decades shortcut routes to
// /library?tab=years in QuickDiscoveryHeader and StudioToolsRail), H-32
// (HomeCubit per-category typed state and reactive excludedFolders in Home
// recent sections).
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/app_error.dart';
import 'package:pulsr/core/network/connectivity_guard.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/features/home/cubit/home_cubit.dart';
import 'package:pulsr/features/home/presentation/widgets/online_category_section.dart';
import 'package:pulsr/features/home/presentation/widgets/quick_discovery_header.dart';
import 'package:pulsr/features/home/presentation/widgets/recently_added_section.dart';
import 'package:pulsr/features/home/presentation/widgets/recently_played_section.dart';
import 'package:pulsr/features/home/presentation/widgets/studio_tools_rail.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/screen_harness.dart';

class _MockYtmService extends Mock implements YtmService {}

class _MockAccount extends Mock implements YtmAccountService {}

class _MockConnectivity extends Mock implements Connectivity {}

class _MockGetSongsUseCase extends Mock implements GetSongsUseCase {}

class _MockLibraryCubit extends Mock implements LibraryCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('C-09: Home Decades shortcuts route to /library?tab=years', () {
    testWidgets('QuickDiscoveryHeader Decades chip pushes /library?tab=years',
        (tester) async {
      String? capturedUri;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: QuickDiscoveryHeader(onMore: () {}),
            ),
          ),
          GoRoute(
            path: '/library',
            builder: (context, state) {
              capturedUri = state.uri.toString();
              return const Scaffold(body: Text('LIBRARY_YEARS'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      useScreenSize(tester, const Size(1600, 800));
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark().copyWith(extensions: [AuraTheme.defaultDark]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.decades));
      await tester.pumpAndSettle();

      expect(find.text('LIBRARY_YEARS'), findsOneWidget);
      expect(capturedUri, '/library?tab=years');
    });

    testWidgets('StudioToolsRail Decades chip pushes /library?tab=years',
        (tester) async {
      String? capturedUri;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: StudioToolsRail(onMore: () {}),
            ),
          ),
          GoRoute(
            path: '/library',
            builder: (context, state) {
              capturedUri = state.uri.toString();
              return const Scaffold(body: Text('RAIL_LIBRARY_YEARS'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      useScreenSize(tester, const Size(1600, 800));
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark().copyWith(extensions: [AuraTheme.defaultDark]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.decades));
      await tester.pumpAndSettle();

      expect(find.text('RAIL_LIBRARY_YEARS'), findsOneWidget);
      expect(capturedUri, '/library?tab=years');
    });
  });

  group('H-32: HomeCubit per-category typed state and reactive exclusions', () {
    late _MockYtmService ytm;
    late _MockConnectivity connectivity;

    setUp(() {
      ytm = _MockYtmService();
      connectivity = _MockConnectivity();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      ConnectivityGuard.setMockConnectivity(connectivity);
    });

    test('loadCategory emits loaded state on tracks and offline state offline',
        () async {
      const track = YtmTrack(
        videoId: 'v1',
        title: 'Online Hit',
        artist: 'Artist',
        duration: Duration(minutes: 3),
      );
      when(() => ytm.searchWithFallback(any(), limit: any(named: 'limit')))
          .thenAnswer((_) async => const [track]);

      final account = _MockAccount();
      final loginState = ValueNotifier<bool>(false);
      addTearDown(loginState.dispose);
      when(() => account.loginState).thenReturn(loginState);
      when(() => account.isLoggedIn).thenReturn(false);

      final cubit = HomeCubit(ytmService: ytm, accountService: account);
      await cubit.loadCategory('Trending Egypt');

      final cat = cubit.state.categoryState('Trending Egypt');
      expect(cat.status, HomeCategoryStatus.loaded);
      expect(cat.tracks, const [track]);

      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);
      await cubit.loadCategory('Chill Vibes');
      expect(
        cubit.state.categoryState('Chill Vibes').status,
        HomeCategoryStatus.offline,
      );
      await cubit.close();
    });

    testWidgets(
        'OnlineCategorySection renders offline/error states from categoryState',
        (tester) async {
      var retried = false;
      await tester.pumpWidget(
        screenHarness(
          child: OnlineCategorySection(
            title: 'Trending Egypt',
            categoryState: HomeCategoryState(
              status: HomeCategoryStatus.error,
              error: uiError('Network down'),
            ),
            playerCubit: stubPlayerCubit(),
            onRetry: () => retried = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets(
        'RecentlyAddedSection and RecentlyPlayedSection forward reactive excludedFolders',
        (tester) async {
      final getSongs = _MockGetSongsUseCase();
      final libCubit = _MockLibraryCubit();
      final player = stubPlayerCubit();

      when(() => libCubit.state).thenReturn(
        LibraryState(
          folders: [
            FolderItem(
              path: '/storage/Ringtone',
              name: 'Ringtone',
              songCount: 2,
              isExcluded: true,
            ),
          ],
        ),
      );
      when(() => libCubit.stream)
          .thenAnswer((_) => const Stream<LibraryState>.empty());

      when(() => getSongs.watchRecentlyAdded(
            limit: any(named: 'limit'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));
      when(() => getSongs.watchRecentlyPlayed(
            limit: any(named: 'limit'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));

      await tester.pumpWidget(
        screenHarness(
          providers: [
            BlocProvider<PlayerCubit>.value(value: player),
            BlocProvider<LibraryCubit>.value(value: libCubit),
          ],
          child: SingleChildScrollView(
            child: Column(
              children: [
                RecentlyAddedSection(
                  getSongsUseCase: getSongs,
                ),
                RecentlyPlayedSection(
                  getSongsUseCase: getSongs,
                  isTablet: false,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      verify(() => getSongs.watchRecentlyAdded(
            limit: any(named: 'limit'),
            excludedFolders: const ['/storage/Ringtone'],
          )).called(1);
      verify(() => getSongs.watchRecentlyPlayed(
            limit: any(named: 'limit'),
            excludedFolders: const ['/storage/Ringtone'],
          )).called(1);
    });
  });
}
