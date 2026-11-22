import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/artwork_placeholder.dart';
import 'package:pulsr/core/widgets/cached_artwork.dart';
import 'package:pulsr/core/widgets/marquee_text.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/services/cast_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/clean_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_chrome.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;

  const testSong = SongsTableData(
    id: 101,
    title: 'Test Song Title',
    artist: 'Test Artist',
    album: 'Test Album',
    durationMs: 200000,
    path: '/music/test.mp3',
    dateAdded: 0,
    playCount: 0,
    lastPositionMs: 0,
    isFavorite: false,
    isMissing: false,
    source: 'local',
    isDownloaded: true,
  );

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    mockSettingsCubit = MockSettingsCubit();

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsState(
        themeMode: AppThemeMode.dark,
        nowPlayingDoubleTap: NowPlayingDoubleTapAction.none,
        nowPlayingArtworkSwipe: NowPlayingArtworkSwipeAction.none,
        playerSliderStyle: PlayerSliderStyle.capsule,
        canvasEnabled: false,
        canvasAsBackdrop: false,
        experienceMode: ExperienceMode.normal,
        currentOutputDevice: AudioOutputInfo(
          deviceName: 'Phone Speaker',
          isUsbDac: false,
          sampleRate: 48000,
          pcmEncoding: 2,
          bitDepth: 16,
          isBitPerfectActive: false,
          isBitPerfectSupported: false,
        ),
      ),
    );
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream.empty());

    when(() => mockPlayerCubit.state).thenReturn(
      const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          duration: Duration(seconds: 200),
          position: Duration(seconds: 30),
          isShuffle: false,
          repeatMode: PlayerRepeatMode.off,
        ),
        queueSlice: QueueSlice(
          queue: [testSong, testSong, testSong],
          currentIndex: 1,
        ),
      ),
    );
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayerCubit.sleepTimerRemainingTracks).thenReturn(null);
    when(() => mockPlayerCubit.isEndOfQueueSleepTimer).thenReturn(false);
  });

  Widget buildSubject({PlayerState? playerState}) {
    final state = playerState ?? mockPlayerCubit.state;
    final props = PlayerThemeProps(
      state: state,
      cubit: mockPlayerCubit,
      activeColor: const Color(0xFFE50914),
      bgColor: const Color(0xFF101010),
    );

    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
          BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
        ],
        child: Scaffold(
          body: CleanPlayerTheme(props: props),
        ),
      ),
    );
  }

  group('CleanPlayerTheme all buttons presence and interaction', () {
    testWidgets('renders all transport, header, top-bar and dock buttons',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // 1. Top bar: Down arrow removed, grab handle present
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(find.byType(PlayerPlayHandle), findsOneWidget);

      // 2. Track Header: Title is start-aligned with Artist, plus Favorite & More (...)
      final titleMarquee = tester.widget<MarqueeText>(find.byType(MarqueeText));
      expect(titleMarquee.textAlign, TextAlign.start);
      final titleRect = tester.getRect(find.text('Test Song Title'));
      final artistRect = tester.getRect(find.text('Test Artist'));
      expect(titleRect.left, closeTo(artistRect.left, 1.0));
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

      // 3. Transport Controls: Shuffle, Previous, Play/Pause, Next, Repeat
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fast_rewind_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fast_forward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);

      // 4. Minimal 4-item Bottom Row: Lyrics, Output, Queue, and Tools trigger
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.speaker_rounded), findsOneWidget);
      expect(find.byIcon(Icons.format_list_bulleted_rounded), findsOneWidget);
      expect(find.byType(PlayerToolsTriggerButton), findsOneWidget);

      // Tapping Tools trigger opens PlayerToolsSheet with secondary actions
      await tester.tap(find.byType(PlayerToolsTriggerButton));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerToolsSheet), findsOneWidget);
      expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
      expect(find.byIcon(Icons.auto_stories_rounded), findsOneWidget);
      expect(find.byIcon(Icons.water_drop_rounded), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    });

    testWidgets('taps trigger expected cubit callbacks', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);

      when(() => mockPlayerCubit.toggleShuffle()).thenAnswer((_) async {});
      when(() => mockPlayerCubit.toggleRepeat()).thenAnswer((_) async {});
      when(() => mockPlayerCubit.previous()).thenAnswer((_) async {});
      when(() => mockPlayerCubit.next()).thenAnswer((_) async {});
      when(() => mockPlayerCubit.togglePlayPause()).thenAnswer((_) async {});

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // Tap Shuffle
      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await tester.pumpAndSettle();
      verify(() => mockPlayerCubit.toggleShuffle()).called(1);

      // Tap Previous
      await tester.tap(find.byIcon(Icons.fast_rewind_rounded));
      await tester.pumpAndSettle();
      verify(() => mockPlayerCubit.previous()).called(1);

      // Tap Next
      await tester.tap(find.byIcon(Icons.fast_forward_rounded));
      await tester.pumpAndSettle();
      verify(() => mockPlayerCubit.next()).called(1);

      // Tap Play/Pause
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pumpAndSettle();
      verify(() => mockPlayerCubit.togglePlayPause()).called(1);

      // Tap Repeat (shows toast, so we pump to dismiss toast afterwards)
      await tester.tap(find.byIcon(Icons.repeat_rounded));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      verify(() => mockPlayerCubit.toggleRepeat()).called(1);
    });

    testWidgets(
        'does not render A/B circle buttons even in professional mode or when points are set, while keeping Bookmark banner',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);

      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsState(
          themeMode: AppThemeMode.dark,
          nowPlayingDoubleTap: NowPlayingDoubleTapAction.none,
          nowPlayingArtworkSwipe: NowPlayingArtworkSwipeAction.none,
          playerSliderStyle: PlayerSliderStyle.capsule,
          canvasEnabled: false,
          canvasAsBackdrop: false,
          experienceMode: ExperienceMode.professional,
          currentOutputDevice: AudioOutputInfo(
            deviceName: 'Phone Speaker',
            isUsbDac: false,
            sampleRate: 48000,
            pcmEncoding: 2,
            bitDepth: 16,
            isBitPerfectActive: false,
            isBitPerfectSupported: false,
          ),
        ),
      );

      final activeState = PlayerState(
        playback: const PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          duration: Duration(seconds: 200),
          position: Duration(seconds: 30),
          isShuffle: false,
          repeatMode: PlayerRepeatMode.off,
          abPointA: Duration(seconds: 10),
          abPointB: Duration(seconds: 50),
          bookmarkPosition: Duration(seconds: 45),
        ),
        queueSlice: QueueSlice(
          queue: [testSong, testSong],
          currentIndex: 0,
        ),
      );

      await tester.pumpWidget(buildSubject(playerState: activeState));
      await tester.pumpAndSettle();

      // Loop points A and B circular buttons are not rendered
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);

      // Bookmark banner is rendered
      expect(find.byType(PlayerBookmarkPromptBanner), findsOneWidget);
    });

    testWidgets(
        'P3-24: CleanPlayerTheme down bar updates Cast icon and CAST badge reactively',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);
      CastService().debugSetSessionStatus(CastSessionStatus.unavailable);
      addTearDown(
        () =>
            CastService().debugSetSessionStatus(CastSessionStatus.unavailable),
      );

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cast_connected_rounded), findsNothing);
      expect(find.text('CAST'), findsNothing);
      expect(find.byIcon(Icons.speaker_rounded), findsOneWidget);

      CastService().debugSetSessionStatus(
        const CastSessionStatus(
          available: true,
          connected: true,
          deviceName: 'Living Room TV',
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.cast_connected_rounded), findsOneWidget);
      expect(find.text('CAST'), findsOneWidget);

      CastService().debugSetSessionStatus(
        const CastSessionStatus(available: true, connected: false),
      );
      await tester.pump();

      expect(find.byIcon(Icons.cast_connected_rounded), findsNothing);
      expect(find.text('CAST'), findsNothing);
      expect(find.byIcon(Icons.speaker_rounded), findsOneWidget);
    });

    testWidgets(
        'P3-24: PlayerBottomActionDock updates Cast icon and CAST badge reactively',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);
      CastService().debugSetSessionStatus(CastSessionStatus.unavailable);
      addTearDown(
        () =>
            CastService().debugSetSessionStatus(CastSessionStatus.unavailable),
      );

      final props = PlayerThemeProps(
        state: mockPlayerCubit.state,
        cubit: mockPlayerCubit,
        activeColor: const Color(0xFFE50914),
        bgColor: const Color(0xFF101010),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
              BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
            ],
            child: Scaffold(
              body: Center(
                child: PlayerBottomActionDock(
                  props: props,
                  barWidth: 360,
                  barHeight: 60,
                  isTablet: false,
                  settingsState: mockSettingsCubit.state,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cast_connected_rounded), findsNothing);
      expect(find.text('CAST'), findsNothing);

      CastService().debugSetSessionStatus(
        const CastSessionStatus(
          available: true,
          connected: true,
          deviceName: 'Bedroom Speaker',
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.cast_connected_rounded), findsOneWidget);
      expect(find.text('CAST'), findsOneWidget);

      CastService().debugSetSessionStatus(
        const CastSessionStatus(available: true, connected: false),
      );
      await tester.pump();

      expect(find.byIcon(Icons.cast_connected_rounded), findsNothing);
      expect(find.text('CAST'), findsNothing);
    });

    testWidgets(
        'landscape places artwork stage cleanly in left half and centers play handle',
        (tester) async {
      tester.view.physicalSize = const Size(994, 456);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(left: 48);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final stageArtwork = find.descendant(
        of: find.byType(Hero),
        matching: find.byType(CachedArtwork),
      );
      expect(stageArtwork, findsOneWidget);
      final artRect = tester.getRect(stageArtwork);
      final placeholderRect = tester.getRect(
        find.descendant(
          of: stageArtwork,
          matching: find.byType(ArtworkPlaceholder),
        ),
      );
      final handleRect = tester.getRect(find.byType(PlayerPlayHandle));

      // Artwork stage stays inside the safe left half without overflowing.
      expect(artRect.left, greaterThanOrEqualTo(48.0));
      expect(artRect.top, greaterThanOrEqualTo(0.0));
      expect(artRect.right, lessThanOrEqualTo(521.0));
      expect(artRect.bottom, lessThanOrEqualTo(456.0));

      // Inner placeholder matches the artwork bounds cleanly.
      expect(placeholderRect.width, closeTo(artRect.width, 1.0));
      expect(placeholderRect.height, closeTo(artRect.height, 1.0));

      // Top grab handle remains horizontally centered within the safe display area
      // (left cutout 48dp -> safe span [48, 994], center = 521.0).
      expect(handleRect.center.dx, closeTo(521.0, 1.0));
    });
  });
}
