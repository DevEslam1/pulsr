import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/motion/gesture_map.dart';
import 'package:pulsr/core/services/ambient_sound_service.dart';
import 'package:pulsr/core/widgets/gestures_sheet.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/onboarding/presentation/onboarding_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/mini_player.dart';
import 'package:pulsr/features/player/presentation/widgets/player_more_sheet.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _MockSettingsCubit extends Mock implements SettingsCubit {}

class _MockAmbientSoundService extends Mock implements AmbientSoundService {}

class _MockMediaScannerService extends Mock implements MediaScannerService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockSettingsCubit settings;
  late PlayerCubit player;
  late _MockAmbientSoundService ambient;
  late List<SongsTableData> songs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MiniPlayerState.resetSessionTrackingForTest();

    settings = _MockSettingsCubit();
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());

    songs = [
      createTestSong(id: 1, title: 'Track One', artist: 'Artist One'),
      createTestSong(id: 2, title: 'Track Two', artist: 'Artist Two'),
      createTestSong(id: 3, title: 'Track Three', artist: 'Artist Three'),
    ];
    player = stubPlayerCubit(
      PlayerState(
        playback: PlaybackSlice(
          currentSong: songs.first,
          isPlaying: true,
          duration: const Duration(minutes: 3),
        ),
        queueSlice: QueueSlice(
          queue: songs,
          currentIndex: 0,
        ),
      ),
    );
    when(() => player.skipToQueueItem(any())).thenAnswer((_) async {});
    when(() => player.togglePlayPause()).thenAnswer((_) async {});

    ambient = _MockAmbientSoundService();
    when(() => ambient.isEnabled).thenReturn(false);
    when(() => ambient.activeEffects).thenReturn(<AmbientSoundEffect>{});
    when(() => ambient.isAudioPlaying).thenReturn(false);
    AmbientSoundService.testInstance = ambient;
  });

  tearDown(() {
    AmbientSoundService.testInstance = null;
  });

  testWidgets('PulsrGestureMap & GesturesSheet cover all documented gestures',
      (tester) async {
    final ids = PulsrGestureMap.entries.map((e) => e.id).toSet();
    expect(
      ids,
      containsAll([
        'mini_swipe_horizontal',
        'mini_swipe_up',
        'dock_swipe_down',
        'artwork_tap',
        'artwork_double_tap',
        'artwork_swipe',
        'now_playing_dismiss',
        'platter_scrub',
        'rpm_speed_shortcut',
        'waveform_pinch',
        'lyrics_offset',
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: GesturesSheet()),
      ),
    );
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(GesturesSheet)))!;
    for (final entry in PulsrGestureMap.entries) {
      expect(
        find.text(entry.titleBuilder(l10n), skipOffstage: false),
        findsOneWidget,
      );
    }
  });

  testWidgets('PlayerMoreSheet opens GesturesSheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: player),
              BlocProvider<SettingsCubit>.value(value: settings),
            ],
            child: PlayerMoreSheet(
              song: songs.first,
              activeColor: Colors.cyan,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(PlayerMoreSheet)))!;
    await tester.tap(find.text(l10n.gesturesGuideTitle));
    await tester.pumpAndSettle();

    expect(find.byType(GesturesSheet), findsOneWidget);
  });

  testWidgets('Onboarding page 4 exposes View all gestures button',
      (tester) async {
    final scanner = _MockMediaScannerService();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<SettingsCubit>.value(
          value: settings,
          child: OnboardingScreen(scannerService: scanner),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Advance to page 4 (index 3: privacy -> playback -> beauty -> gestures)
    final l10n =
        AppLocalizations.of(tester.element(find.byType(OnboardingScreen)))!;
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text(l10n.next));
      await tester.pumpAndSettle();
    }

    expect(find.text(l10n.viewAllGestures), findsOneWidget);
    await tester.tap(find.text(l10n.viewAllGestures));
    await tester.pumpAndSettle();

    expect(find.byType(GesturesSheet), findsOneWidget);
  });

  testWidgets(
      'MiniPlayer shows grab-handle chevron during first N sessions and hides afterward',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.dockGrabChevronSessions: 2,
    });
    MiniPlayerState.resetSessionTrackingForTest();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: player),
              BlocProvider<SettingsCubit>.value(value: settings),
            ],
            child: MiniPlayer(
              key: const ValueKey('mini_session_2'),
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dock_grab_chevron')), findsOneWidget);

    SharedPreferences.setMockInitialValues({
      PrefsKeys.dockGrabChevronSessions: 5,
    });
    MiniPlayerState.resetSessionTrackingForTest();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: player),
              BlocProvider<SettingsCubit>.value(value: settings),
            ],
            child: MiniPlayer(
              key: const ValueKey('mini_session_5'),
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dock_grab_chevron')), findsNothing);
  });

  testWidgets(
      'MiniPlayer displays directional badge during horizontal carousel drag',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<PlayerCubit>.value(value: player),
                BlocProvider<SettingsCubit>.value(value: settings),
              ],
              child: MiniPlayer(onTap: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageView = find.byType(PageView);
    expect(pageView, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(pageView));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-110, 0));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mini_player_carousel_badge_next')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
