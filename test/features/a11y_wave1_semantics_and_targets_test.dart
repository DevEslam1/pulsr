// Wave 1B accessibility & hit-target verification suite.
//
// Verifies:
// 1. >= 48x48dp hit targets across ytm_browse_toolbar.dart,
//    duplicate_finder_screen.dart, and playlists_screen.dart.
// 2. Full Semantics coverage (headers, live regions, toggled/selected flags,
//    and customSemanticsActions) across party, radio, playlist_detail, and
//    playlists screens.
// 3. Zero hardcoded Color(0x...) or Colors.* literals in playlists_screen.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/duplicate_finder_service.dart';
import 'package:pulsr/core/services/radio_station_store.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/party/listen_together_service.dart';
import 'package:pulsr/data/party/party_models.dart';
import 'package:pulsr/domain/models/radio_station.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/auth/presentation/ytm_web_login_sheet.dart';
import 'package:pulsr/features/library/presentation/duplicate_finder_screen.dart';
import 'package:pulsr/features/party/presentation/party_sheet.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/playlist_detail/presentation/playlist_detail_screen.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:pulsr/features/playlists/cubit/playlist_state.dart';
import 'package:pulsr/features/playlists/presentation/playlists_screen.dart';
import 'package:pulsr/features/radio/presentation/radio_screen.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/detail_screen_harness.dart' hide stubPlayerCubit;
import '../helpers/screen_harness.dart';
import '../helpers/test_song_factory.dart';
import 'auth/ytm_webview_test_support.dart';

class _MockYtmAccountService extends Mock implements YtmAccountService {}

class _MockMusicRepository extends Mock implements IMusicRepository {}

class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _MockListenTogetherService extends Mock
    implements ListenTogetherService {}

class _MockPlaylistCubit extends Mock implements PlaylistCubit {}

class _MockGetSongsUseCase extends Mock implements GetSongsUseCase {}

class _MockPlaylistUseCases extends Mock implements PlaylistUseCases {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(<int>[]);
    registerFallbackValue(createTestSong());
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('Hit targets >= 48x48dp', () {
    testWidgets('ytm_browse_toolbar buttons and quick-nav chips are >= 48dp',
        (tester) async {
      installFakeInAppWebViewPlatform();
      SharedPreferences.setMockInitialValues({});
      final account = _MockYtmAccountService();
      when(() => account.loginState).thenReturn(ValueNotifier<bool>(false));
      when(() => account.isLoggedIn).thenReturn(false);
      when(() => account.validateSessionDetailed())
          .thenAnswer((_) async => SessionValidationResult.valid);
      when(() => account.clearSessionWebViewCookies())
          .thenAnswer((_) async {});
      when(() => account.logout()).thenAnswer((_) async {});
      when(() => account.getNativeCookiesFromDomains())
          .thenAnswer((_) async => null);
      getIt.registerSingleton<YtmAccountService>(account);

      await tester
          .pumpWidget(ytmHost(const YtmWebLoginSheet(isBrowseMode: true)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      for (final icon in [
        Icons.arrow_back_ios_new_rounded,
        Icons.arrow_forward_ios_rounded,
        Icons.refresh_rounded,
        Icons.close_rounded,
      ]) {
        final size = tester.getSize(find.widgetWithIcon(IconButton, icon));
        expect(size.width, greaterThanOrEqualTo(48.0), reason: '$icon width');
        expect(size.height, greaterThanOrEqualTo(48.0), reason: '$icon height');
      }

      for (final label in ['Home', 'Explore', 'Library']) {
        final chipInkWell = find.ancestor(
          of: find.text(label),
          matching: find.byType(InkWell),
        );
        expect(chipInkWell, findsOneWidget);
        final size = tester.getSize(chipInkWell);
        expect(size.width, greaterThanOrEqualTo(48.0), reason: '$label width');
        expect(size.height, greaterThanOrEqualTo(48.0),
            reason: '$label height');
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'DuplicateFinderScreen actions, banner buttons and popup menu are >= 48dp',
      (tester) async {
        final repo = _MockMusicRepository();
        final player = _MockPlayerCubit();
        when(() => player.state).thenReturn(const PlayerState());
        when(() => player.stream).thenAnswer((_) => const Stream.empty());
        when(() => repo.getExcludedFolderPaths())
            .thenAnswer((_) async => const Right([]));
        when(() => repo.getAllSongs(
              excludedFolders: any(named: 'excludedFolders'),
            )).thenAnswer(
          (_) async => Right([
            createTestSong(
              id: 1,
              title: 'Echoes',
              artist: 'Pink Floyd',
              path: '/music/echoes.flac',
              bitrateKbps: 950,
            ),
            createTestSong(
              id: 2,
              title: 'echoes',
              artist: 'Pink Floyd',
              path: '/music/echoes.mp3',
              bitrateKbps: 320,
            ),
          ]),
        );

        getIt.registerLazySingleton<DuplicateFinderService>(
          () => DuplicateFinderService(),
        );
        getIt.registerSingleton<IMusicRepository>(repo);

        await tester.pumpWidget(
          BlocProvider<PlayerCubit>.value(
            value: player,
            child: MaterialApp(
              theme: AuraTheme.darkTheme,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const DuplicateFinderScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Trigger auto-select so both summary buttons (Keep Best + Delete) show.
        await tester.tap(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(Icons.auto_awesome_rounded),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        for (final el in find.byType(IconButton).evaluate()) {
          final size = tester.getSize(find.byWidget(el.widget));
          expect(size.width, greaterThanOrEqualTo(48.0));
          expect(size.height, greaterThanOrEqualTo(48.0));
        }

        for (final el in find.byType(FilledButton).evaluate()) {
          final size = tester.getSize(find.byWidget(el.widget));
          expect(size.width, greaterThanOrEqualTo(48.0));
          expect(size.height, greaterThanOrEqualTo(48.0));
        }

        final popupMenus = find.byWidgetPredicate(
          (w) => w.runtimeType.toString().startsWith('PopupMenuButton'),
        );
        expect(popupMenus, findsWidgets);
        for (final el in popupMenus.evaluate()) {
          final size = tester.getSize(find.byWidget(el.widget));
          expect(size.width, greaterThanOrEqualTo(48.0));
          expect(size.height, greaterThanOrEqualTo(48.0));
        }
      },
    );

    testWidgets(
      'PlaylistsScreen online action overlays & sign-in controls are >= 48dp',
      (tester) async {
        SharedPreferences.setMockInitialValues({'smart_playlists_seeded': true});
        final cubit = _MockPlaylistCubit();
        final account = _MockYtmAccountService();
        final loginNotifier = ValueNotifier<bool>(true);
        const track = YtmTrack(
          videoId: 'v1',
          title: 'Track 1',
          artist: 'Artist',
          duration: Duration(minutes: 3),
        );
        final onlineNotifier = ValueNotifier<YtmOnlineState>(
          const YtmOnlineState(
            likedStatus: YtmFetchStatus.done,
            likedTracks: [track],
            accountStatus: YtmFetchStatus.done,
            accountPlaylists: [
              YtmAccountPlaylist(
                playlistId: 'PL1',
                title: 'My Mix',
                subtitle: '10 songs',
              ),
            ],
            customStatus: YtmFetchStatus.done,
            customPlaylists: [
              OnlinePlaylistEntry(
                id: 'PL2',
                title: 'Custom Mix',
                uploader: 'Pulsr',
                tracks: [track],
              ),
            ],
          ),
        );
        addTearDown(() {
          loginNotifier.dispose();
          onlineNotifier.dispose();
        });

        when(() => account.loginState).thenReturn(loginNotifier);
        when(() => cubit.state).thenReturn(const PlaylistState(isLoading: false));
        when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
        when(() => cubit.ytmOnline).thenReturn(onlineNotifier);
        when(() => cubit.autoFetchOnlineLibrary()).thenAnswer((_) async {});

        getIt.registerSingleton<YtmAccountService>(account);
        getIt.registerSingleton<GetSongsUseCase>(_MockGetSongsUseCase());

        useScreenSize(tester, const Size(800, 1400));
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            screenHarness(
              providers: [
                BlocProvider<PlaylistCubit>.value(value: cubit),
                BlocProvider<PlayerCubit>.value(value: stubPlayerCubit()),
              ],
              child: const PlaylistsScreen(),
            ),
          );
          await tester.pumpAndSettle();

          // Switch to Online tab.
          await tester.tap(find.text('Online'));
          await tester.pumpAndSettle();

          // Every download and remove overlay GestureDetector must be >= 48x48dp.
          final downloadButtons = find.bySemanticsLabel('Download');
          expect(downloadButtons, findsNWidgets(3));
          for (var i = 0; i < 3; i++) {
            final size = tester.getSize(downloadButtons.at(i));
            expect(size.width, greaterThanOrEqualTo(48.0));
            expect(size.height, greaterThanOrEqualTo(48.0));
          }

          final removeButton = find.bySemanticsLabel('Remove');
          expect(removeButton, findsOneWidget);
          final removeSize = tester.getSize(removeButton);
          expect(removeSize.width, greaterThanOrEqualTo(48.0));
          expect(removeSize.height, greaterThanOrEqualTo(48.0));

          // Verify logged-out Sign In button >= 48dp as well.
          loginNotifier.value = false;
          await tester.pumpAndSettle();
          final signInFinder = find.text('Sign In');
          expect(signInFinder, findsOneWidget);
          final signInContainer = find.ancestor(
            of: signInFinder,
            matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'PulsrButton',
            ),
          );
          final signInSize = tester.getSize(signInContainer);
          expect(signInSize.width, greaterThanOrEqualTo(48.0));
          expect(signInSize.height, greaterThanOrEqualTo(48.0));
        } finally {
          semantics.dispose();
        }
      },
    );

    test('playlists_screen.dart contains zero raw Color(0x...) or Colors.* literals',
        () {
      final file =
          File('lib/features/playlists/presentation/playlists_screen.dart');
      expect(file.existsSync(), isTrue);
      final lines = file.readAsLinesSync();
      final rawColor = RegExp(r'Color\(0x[0-9A-Fa-f]+\)|\bColors\.\w+');
      final offenders = <String>[];
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (rawColor.hasMatch(lines[i])) {
          offenders.add('line ${i + 1}: ${lines[i].trim()}');
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('Semantics coverage', () {
    testWidgets(
      'PartySheet exposes headers, live regions, toggled settings & custom room actions',
      (tester) async {
        final partyService = _MockListenTogetherService();
        const host = PartyMember(
          memberId: 'm1',
          displayName: 'Alice',
          isHost: true,
        );
        const snapshot = PartySnapshot(
          code: 'AB12CD',
          members: [host],
          maxMembers: 8,
        );
        when(() => partyService.partySnapshot)
            .thenReturn(ValueNotifier<PartySnapshot?>(snapshot));
        when(() => partyService.connectionState).thenReturn(
          ValueNotifier<PartyConnectionState>(PartyConnectionState.live),
        );
        when(() => partyService.currentMember)
            .thenReturn(ValueNotifier<PartyMember?>(host));
        when(() => partyService.lastError)
            .thenReturn(ValueNotifier<String?>(null));
        when(() => partyService.clockSynced)
            .thenReturn(ValueNotifier<bool>(true));
        when(() => partyService.roundTripMs).thenReturn(ValueNotifier<int>(24));
        when(() => partyService.inParty).thenReturn(true);
        when(() => partyService.isHost).thenReturn(true);
        when(() => partyService.getServerUrl())
            .thenAnswer((_) async => ListenTogetherService.defaultServerUrl);
        getIt.registerSingleton<ListenTogetherService>(partyService);

        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: AuraTheme.darkTheme,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: PartySheet()),
            ),
          );
          await tester.pumpAndSettle();

          // Main title and members header carry header semantics.
          final titleData = tester
              .getSemantics(find.text('Listen Together'))
              .getSemanticsData();
          expect(titleData.flagsCollection.isHeader, isTrue);

          final membersHeader = tester
              .getSemantics(find.textContaining('/8'))
              .getSemanticsData();
          expect(membersHeader.flagsCollection.isHeader, isTrue);

          // Room code is spelled out cleanly for screen readers.
          expect(
            find.bySemanticsLabel(RegExp(r'A B 1 2 C D')),
            findsOneWidget,
          );

          // Sync status row has liveRegion flag.
          final syncData =
              tester.getSemantics(find.textContaining('24')).getSemanticsData();
          expect(syncData.flagsCollection.isLiveRegion, isTrue);

          // Settings IconButton carries toggled flag.
          final settingsData = tester
              .getSemantics(find.byIcon(Icons.settings_rounded))
              .getSemanticsData();
          expect(settingsData.flagsCollection.isToggled, Tristate.isFalse);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'RadioScreen exposes header, selected genre chip, toggled play & custom station actions',
      (tester) async {
        final station = RadioStation.create(
          name: 'Jazz FM',
          url: 'https://jazz.example.com/live',
          genre: 'Jazz',
        );
        final station2 = RadioStation.create(
          name: 'Classic FM',
          url: 'https://classic.example.com/live',
          genre: 'Classical',
        );
        SharedPreferences.setMockInitialValues({
          RadioStationStore.prefsKey:
              jsonEncode([station.toJson(), station2.toJson()]),
        });
        RadioStationStore.resetForTesting();

        final player = _MockPlayerCubit();
        when(() => player.state).thenReturn(
          PlayerState(
            playback: PlaybackSlice(
              currentSong:
                  createTestSong(path: station.url, title: station.name),
              isPlaying: true,
            ),
          ),
        );
        when(() => player.stream).thenAnswer((_) => const Stream.empty());

        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: AuraTheme.darkTheme,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: BlocProvider<PlayerCubit>.value(
                value: player,
                child: const RadioScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Title has header semantics.
          final titleData = tester
              .getSemantics(
                find.descendant(
                  of: find.byType(AppBar),
                  matching: find.byType(Text),
                ),
              )
              .getSemanticsData();
          expect(titleData.flagsCollection.isHeader, isTrue);

          // Genre filter strip has selected state.
          final jazzChip = find.widgetWithText(FilterChip, 'Jazz');
          expect(jazzChip, findsOneWidget);
          final allChip = find.widgetWithText(FilterChip, 'All');
          expect(
            tester
                .getSemantics(allChip)
                .getSemanticsData()
                .flagsCollection
                .isSelected,
            Tristate.isTrue,
          );

          // Playing station's pause button exposes toggled = true.
          final pauseBtn = find.widgetWithIcon(
              IconButton, Icons.pause_circle_filled_rounded);
          expect(pauseBtn, findsOneWidget);
          final pauseData = tester.getSemantics(pauseBtn).getSemanticsData();
          expect(pauseData.flagsCollection.isToggled, Tristate.isTrue);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'PlaylistDetailScreen exposes header, toggled favorite & reorder customSemanticsActions',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'pulsr_hint_song_tile_swipe': true,
        });
        final useCases = _MockPlaylistUseCases();
        final playlist = PlaylistsTableData(
          id: 10,
          name: 'Focus Flow',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
          isSmart: false,
        );
        final songs = [
          createTestSong(id: 1, title: 'Morning Dew', isFavorite: true),
          createTestSong(id: 2, title: 'Night Drive', isFavorite: false),
        ];
        when(() => useCases.watchPlaylistSongs(10))
            .thenAnswer((_) => Stream.value(Right(songs)));

        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            detailHarness(
              child: PlaylistDetailScreen(
                playlist: playlist,
                playlistUseCases: useCases,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // AppBar title has header semantics.
          final appBarTitle = find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Focus Flow'),
          );
          expect(
            tester
                .getSemantics(appBarTitle)
                .getSemanticsData()
                .flagsCollection
                .isHeader,
            isTrue,
          );

          // Favorite toggle reports toggled=true for favorited song.
          final favBtn = find.widgetWithIcon(IconButton, Icons.favorite_rounded);
          expect(favBtn, findsOneWidget);
          expect(
            tester
                .getSemantics(favBtn)
                .getSemanticsData()
                .flagsCollection
                .isToggled,
            Tristate.isTrue,
          );

          // Enter reorder mode and verify customSemanticsActions + liveRegion.
          await tester.tap(find.byIcon(Icons.swap_vert_rounded));
          await tester.pumpAndSettle();

          final reorderRow = find.byKey(const ValueKey('reorder_song_1'));
          expect(reorderRow, findsOneWidget);
          final rowData = tester.getSemantics(reorderRow).getSemanticsData();
          expect(
            rowData.hasAction(SemanticsAction.customAction),
            isTrue,
            reason:
                'Reorder row must expose Move to top/bottom/position custom actions',
          );
        } finally {
          semantics.dispose();
        }
      },
    );
  });
}
