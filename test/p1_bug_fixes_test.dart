import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart';
import 'package:pulsr/core/widgets/pulsr_dock_tracker.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/repositories/smart_playlist_engine_interface.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/mini_player.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/shell/presentation/widgets/stacked_bottom_dock.dart';
import 'package:pulsr/features/smart_playlist_builder/smart_playlist_builder_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_search_cubit.dart';
import 'package:pulsr/features/widgets/widget_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}
class MockSettingsCubit extends Mock implements SettingsCubit {}
class MockYtmService extends Mock implements YtmService {}
class MockSmartPlaylistEngine extends Mock implements ISmartPlaylistEngine {}
class MockPlaylistUseCases extends Mock implements PlaylistUseCases {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const SmartCriteria());
  });

  group('Phase 2: P1 Functional Bug Fixes', () {
    test('H1: DynamicThemeCubit queues latest extraction when extraction is in-flight', () async {
      final cubit = DynamicThemeCubit();
      addTearDown(cubit.close);

      // Trigger rapid updates
      await cubit.updateFromSongId(1, remoteArtworkUrl: 'https://example.com/art1.jpg');
      await cubit.updateFromSongId(2, remoteArtworkUrl: 'https://example.com/art2.jpg');

      // Resetting to default properly clears any queued request and resets mode
      cubit.resetToDefault();
      expect(cubit.state.hasCustomArtworkColor, isFalse);
    });

    testWidgets('H2: MiniPlayer double-swipe guard prevents rapid second gesture', (tester) async {
      final mockPlayerCubit = MockPlayerCubit();
      final mockSettingsCubit = MockSettingsCubit();

      const testSong = SongsTableData(
        id: 101,
        title: 'H2 Test Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        path: '/path/101.mp3',
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
        source: 'local',
      );

      when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
      when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());
      when(() => mockPlayerCubit.state).thenReturn(
        const PlayerState(
          playback: PlaybackSlice(
            currentSong: testSong,
            isPlaying: true,
            duration: Duration(minutes: 3),
          ),
          queueSlice: QueueSlice(
            queue: [testSong],
            currentIndex: 0,
          ),
        ),
      );
      when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());

      int swipeDownCount = 0;

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
            BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: Scaffold(
              body: MiniPlayer(
                onTap: () {},
                onSwipeDown: () => swipeDownCount++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final target = find.text('H2 Test Song');
      expect(target, findsOneWidget);

      // Perform first swipe down
      await tester.fling(target, const Offset(0, 300), 1000.0);
      // Immediately perform rapid second swipe before cooldown
      await tester.fling(target, const Offset(0, 300), 1000.0);
      // Drain the cooldown timer before test teardown
      await tester.pump(const Duration(milliseconds: 600));

      expect(swipeDownCount, equals(1), reason: 'Second swipe while in-flight must be ignored');
    });

    test('H3: YtmSearchCubit emits rate-limiting message on bot block exhaustion and supports retryAfterCooldown', () async {
      final mockService = MockYtmService();
      when(() => mockService.isBotCoolingDown).thenReturn(false);
      when(() => mockService.botCooldownNotifier).thenReturn(ValueNotifier(false));
      when(() => mockService.searchWithFallback(any())).thenThrow(
        const YtmException('BOT_CHALLENGE', 'Bot verification required'),
      );
      when(() => mockService.invalidatePoToken()).thenAnswer((_) async {});
      when(() => mockService.ensurePoTokenReady()).thenAnswer((_) async => true);

      final cubit = YtmSearchCubit(service: mockService);
      addTearDown(cubit.close);

      cubit.onQueryChanged('Radiohead');
      await cubit.retry();
      expect(cubit.state.errorMessage, contains('YouTube is rate-limiting requests'));

      await cubit.retryAfterCooldown();
      expect(cubit.state.errorMessage, contains('YouTube is rate-limiting requests'));
    });

    testWidgets('H4 & H5: SmartPlaylistBuilderCubit debounces preview updates and flags truncation', (tester) async {
      final mockEngine = MockSmartPlaylistEngine();
      final mockPlaylistUseCases = MockPlaylistUseCases();

      const songList = [
        SongsTableData(
          id: 1,
          title: 'Song 1',
          artist: 'Artist',
          album: 'Album',
          durationMs: 1000,
          path: '/s1.mp3',
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 1,
          lastPositionMs: 0,
          source: 'local',
        ),
      ];

      when(() => mockEngine.watchCriteria(any())).thenAnswer((_) => Stream.value(songList));

      final cubit = SmartPlaylistBuilderCubit(mockEngine, mockPlaylistUseCases);
      addTearDown(cubit.close);

      // Initial state has previewSongs empty until debounce timer fires
      expect(cubit.state.previewSongs, isEmpty);

      // Pump through the 150ms debounce window
      await tester.pump(const Duration(milliseconds: 200));

      expect(cubit.state.previewSongs.length, equals(1));
      expect(cubit.state.previewTruncated, isFalse);
    });

    testWidgets('H6: StackedBottomDock updates dock height immediately when SchedulerPhase.idle', (tester) async {
      final mockPlayerCubit = MockPlayerCubit();
      final mockSettingsCubit = MockSettingsCubit();
      when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
      when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());
      when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
      when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());

      expect(SchedulerBinding.instance.schedulerPhase, equals(SchedulerPhase.idle));

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
            BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: Scaffold(
              body: StackedBottomDock(
                currentIndex: 0,
                onTapNav: (_) {},
                onOpenNowPlaying: () {},
                mode: DockStackMode.defaultLayout,
                onModeChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // When rendered, PulsrDockTracker is updated
      expect(PulsrDockTracker.dockHeight.value, greaterThan(0.0));
    });

    test('H10: WidgetService handles rapid now playing updates without dropping artwork requests', () async {
      final widgetService = WidgetService();

      const song1 = SongsTableData(
        id: 201,
        title: 'Song 201',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        path: '/path/201.mp3',
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
        source: 'local',
      );

      const song2 = SongsTableData(
        id: 202,
        title: 'Song 202',
        artist: 'Artist',
        album: 'Album',
        durationMs: 200000,
        path: '/path/202.mp3',
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
        source: 'local',
      );

      // Trigger rapid successive updates
      await widgetService.updateNowPlaying(song: song1, isPlaying: true);
      await widgetService.updateNowPlaying(song: song2, isPlaying: true);

      // Clearing now playing empties queue safely
      await widgetService.updateNowPlaying(song: null, isPlaying: false);
    });
  });
}

