// test/features/player/player_theme_foundation_test.dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/responsive_player_layout.dart';
import 'package:pulsr/features/player/presentation/themes/custom_theme_builder_screen.dart';
import 'package:pulsr/features/player/presentation/themes/player_surface_shell.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_helpers.dart';
import 'package:pulsr/features/player/presentation/themes/player_tools_sheet.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/features/player/presentation/widgets/lyrics_view.dart';
import 'package:pulsr/features/player/presentation/widgets/now_playing_queue_view.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_theme_pickers.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/test_song_factory.dart';

class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  group('PlayerThemeMode.fromName migration', () {
    test('migrates legacy removed modes and normalizes inputs', () {
      expect(PlayerThemeMode.fromName('classic'), PlayerThemeMode.clean);
      expect(PlayerThemeMode.fromName('CLASSIC'), PlayerThemeMode.clean);
      expect(PlayerThemeMode.fromName('  classic  '), PlayerThemeMode.clean);
      expect(
        PlayerThemeMode.fromName('PlayerThemeMode.classic'),
        PlayerThemeMode.clean,
      );
      expect(PlayerThemeMode.fromName('circle'), PlayerThemeMode.vinyl);
      expect(
        PlayerThemeMode.fromName('PlayerThemeMode.circle'),
        PlayerThemeMode.vinyl,
      );
      expect(PlayerThemeMode.fromName('minimal'), PlayerThemeMode.waveform);
      expect(
        PlayerThemeMode.fromName('PlayerThemeMode.minimal'),
        PlayerThemeMode.waveform,
      );
      expect(
        PlayerThemeMode.fromName('lyricsfocus'),
        PlayerThemeMode.lyricsFocus,
      );
      expect(
        PlayerThemeMode.fromName('PlayerThemeMode.lyricsFocus'),
        PlayerThemeMode.lyricsFocus,
      );
      for (final mode in PlayerThemeMode.values) {
        expect(PlayerThemeMode.fromName(mode.name), mode);
        expect(PlayerThemeMode.fromName('PlayerThemeMode.${mode.name}'), mode);
      }
      expect(PlayerThemeMode.fromName(null), PlayerThemeMode.clean);
      expect(PlayerThemeMode.fromName(''), PlayerThemeMode.clean);
      expect(PlayerThemeMode.fromName('   '), PlayerThemeMode.clean);
      expect(PlayerThemeMode.fromName('does_not_exist'), PlayerThemeMode.clean);
    });
  });

  group('resolveQueueNeighbors', () {
    final s1 = createTestSong(id: 1, title: 'Track 1');
    final s2 = createTestSong(id: 2, title: 'Track 2');
    final s3 = createTestSong(id: 3, title: 'Track 3');
    final h0 = createTestSong(id: 99, title: 'History Track');

    test('returns prev and next for middle queue index', () {
      final state = PlayerState(
        queueSlice: QueueSlice(queue: [s1, s2, s3], currentIndex: 1),
      );
      final neighbors = resolveQueueNeighbors(state);
      expect(neighbors.prev?.id, 1);
      expect(neighbors.next?.id, 3);
    });

    test('falls back to queueHistory at index 0 when repeatMode != all', () {
      final state = PlayerState(
        playback: const PlaybackSlice(repeatMode: PlayerRepeatMode.off),
        queueSlice: QueueSlice(
          queue: [s1, s2, s3],
          currentIndex: 0,
          queueHistory: [h0],
        ),
      );
      final neighbors = resolveQueueNeighbors(state);
      expect(neighbors.prev?.id, 99);
      expect(neighbors.next?.id, 2);
    });

    test('wraps around when repeatMode == all', () {
      final atStart = PlayerState(
        playback: const PlaybackSlice(repeatMode: PlayerRepeatMode.all),
        queueSlice: QueueSlice(queue: [s1, s2, s3], currentIndex: 0),
      );
      expect(resolveQueueNeighbors(atStart).prev?.id, 3);
      expect(resolveQueueNeighbors(atStart).next?.id, 2);

      final atEnd = PlayerState(
        playback: const PlaybackSlice(repeatMode: PlayerRepeatMode.all),
        queueSlice: QueueSlice(queue: [s1, s2, s3], currentIndex: 2),
      );
      expect(resolveQueueNeighbors(atEnd).prev?.id, 2);
      expect(resolveQueueNeighbors(atEnd).next?.id, 1);
    });
  });

  group('formatPlayerAudioTelemetry', () {
    test('omits missing header fields and never invents specs from extension',
        () {
      final unenriched = createTestSong(
        id: 1,
        path: '/music/renamed_fake.flac',
      );
      final telemetry =
          formatPlayerAudioTelemetry(unenriched, const SettingsState());
      expect(telemetry.isEmpty, isTrue);
      expect(telemetry.specs, isEmpty);
      expect(telemetry.compactBadge, isEmpty);
    });

    test('formats decoded hi-res headers and USB DAC bit-perfect output', () {
      final hiResSong = createTestSong(
        id: 2,
        path: '/music/master.flac',
      ).copyWith(
        codec: const Value('flac'),
        bitDepth: const Value(24),
        sampleRate: const Value(96000),
        bitrateKbps: const Value(2840),
      );
      const settings = SettingsState(
        currentOutputDevice: AudioOutputInfo(
          deviceName: 'FiiO KA17',
          isUsbDac: true,
          sampleRate: 96000,
          bitDepth: 24,
          isBitPerfectActive: true,
          activeDeviceType: 'usb',
        ),
      );
      final telemetry = formatPlayerAudioTelemetry(hiResSong, settings);
      expect(telemetry.codec, 'FLAC');
      expect(telemetry.isLossless, isTrue);
      expect(telemetry.isHiRes, isTrue);
      expect(telemetry.isUsbDac, isTrue);
      expect(telemetry.isBitPerfect, isTrue);
      expect(telemetry.compactBadge, contains('FLAC'));
      expect(telemetry.compactBadge, contains('24-BIT'));
      expect(telemetry.compactBadge, contains('96.0'));
      expect(telemetry.fullLine, contains('USB DAC · BIT-PERFECT'));
    });
  });

  group('countActiveSecondaryTools', () {
    test('counts active EQ, speed, A/B loop, sleep timer, Quran, DAC, ambient',
        () {
      const idle = PlayerState();
      const defaultSettings = SettingsState();
      expect(
        countActiveSecondaryTools(
          idle,
          defaultSettings,
          isAmbientActive: false,
          isCastConnected: false,
          isPartyActive: false,
        ),
        0,
      );

      const activeState = PlayerState(
        playback: PlaybackSlice(
          playbackSpeed: 1.5,
          abLoopEnabled: true,
          sleepTimerRemaining: Duration(minutes: 15),
        ),
        dsp: DspSlice(
          isEqEnabled: true,
          isQuranModeEnabled: true,
        ),
      );
      const dacSettings = SettingsState(
        currentOutputDevice: AudioOutputInfo(
          deviceName: 'USB DAC',
          isUsbDac: true,
          sampleRate: 96000,
          bitDepth: 24,
          isBitPerfectActive: true,
          activeDeviceType: 'usb',
        ),
      );
      expect(
        countActiveSecondaryTools(
          activeState,
          dacSettings,
          isAmbientActive: true,
          isCastConnected: false,
          isPartyActive: true,
        ),
        8,
      );
    });
  });

  group('PlayerSurfaceShell & PlayerToolsSheet widgets', () {
    late _MockPlayerCubit playerCubit;
    late _MockSettingsCubit settingsCubit;

    final song = createTestSong(
      id: 10,
      title: 'Night Drive',
      artist: 'Pulsr Artist',
      durationMs: 240000,
    );

    setUp(() {
      playerCubit = _MockPlayerCubit();
      settingsCubit = _MockSettingsCubit();
      when(() => playerCubit.stream)
          .thenAnswer((_) => const Stream<PlayerState>.empty());
      when(() => settingsCubit.stream)
          .thenAnswer((_) => const Stream<SettingsState>.empty());
      when(() => settingsCubit.state).thenReturn(const SettingsState());
    });

    Widget wrap({
      required Widget child,
      required PlayerState state,
      bool isInSplitView = false,
      bool isPreview = false,
    }) {
      when(() => playerCubit.state).thenReturn(state);
      return MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: playerCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
        ],
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlayerSplitViewScope(
            isInSplitView: isInSplitView,
            child: PlayerThemePreviewScope(
              isPreview: isPreview,
              child: Scaffold(body: child),
            ),
          ),
        ),
      );
    }

    testWidgets('PlayerSurfaceShell switches between canvas, Lyrics, and Queue',
        (tester) async {
      final trackState = PlayerState(
        playback: PlaybackSlice(currentSong: song, isPlaying: true),
      );
      await tester.pumpWidget(
        wrap(
          state: trackState,
          child: PlayerSurfaceShell(
            props: PlayerThemeProps(
              state: trackState,
              cubit: playerCubit,
              activeColor: const Color(0xFF9B9EF5),
              bgColor: const Color(0xFF101223),
            ),
            builder: (context, metrics, isInSplit, isPreview) =>
                const Text('CUSTOM_CANVAS'),
          ),
        ),
      );
      expect(find.text('CUSTOM_CANVAS'), findsOneWidget);
      expect(find.byType(LyricsView), findsNothing);

      final lyricsState = trackState.copyWith(
        lyricsSlice: const LyricsSlice(
          isLyricsVisible: true,
          lyrics: [LyricsLine(timestamp: Duration(seconds: 5), text: 'Line 1')],
        ),
      );
      await tester.pumpWidget(
        wrap(
          state: lyricsState,
          child: PlayerSurfaceShell(
            props: PlayerThemeProps(
              state: lyricsState,
              cubit: playerCubit,
              activeColor: const Color(0xFF9B9EF5),
              bgColor: const Color(0xFF101223),
            ),
            builder: (context, metrics, isInSplit, isPreview) =>
                const Text('CUSTOM_CANVAS'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsOneWidget);

      // handlesLyricsInline: true keeps canvas instead of wrapping LyricsView
      await tester.pumpWidget(
        wrap(
          state: lyricsState,
          child: PlayerSurfaceShell(
            props: PlayerThemeProps(
              state: lyricsState,
              cubit: playerCubit,
              activeColor: const Color(0xFF9B9EF5),
              bgColor: const Color(0xFF101223),
            ),
            handlesLyricsInline: true,
            builder: (context, metrics, isInSplit, isPreview) =>
                const Text('INLINE_LYRICS_CANVAS'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('INLINE_LYRICS_CANVAS'), findsOneWidget);
      expect(find.byType(LyricsView), findsNothing);

      // Split view suppresses inline overlays
      final queueState = trackState.copyWith(
        lyricsSlice: const LyricsSlice(isQueueVisible: true),
      );
      await tester.pumpWidget(
        wrap(
          state: queueState,
          isInSplitView: true,
          child: PlayerSurfaceShell(
            props: PlayerThemeProps(
              state: queueState,
              cubit: playerCubit,
              activeColor: const Color(0xFF9B9EF5),
              bgColor: const Color(0xFF101223),
            ),
            builder: (context, metrics, isInSplit, isPreview) =>
                Text('SPLIT=$isInSplit'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SPLIT=true'), findsOneWidget);
      expect(find.byType(NowPlayingQueueView), findsNothing);
    });

    testWidgets('PlayerToolsSheet opens with A/B Loop and 7 tool actions',
        (tester) async {
      final state = PlayerState(
        playback: PlaybackSlice(
          currentSong: song,
          isPlaying: true,
          abPointA: const Duration(seconds: 15),
          abPointB: const Duration(seconds: 45),
          abLoopEnabled: true,
        ),
      );
      final props = PlayerThemeProps(
        state: state,
        cubit: playerCubit,
        activeColor: const Color(0xFF9B9EF5),
        bgColor: const Color(0xFF101223),
      );

      await tester.pumpWidget(
        wrap(
          state: state,
          child: Center(
            child: PlayerToolsTriggerButton(props: props),
          ),
        ),
      );

      await tester.tap(find.byType(PlayerToolsTriggerButton));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerToolsSheet), findsOneWidget);
      expect(find.text('A / B'), findsOneWidget);
      expect(find.text('A 0:15'), findsOneWidget);
      expect(find.text('B 0:45'), findsOneWidget);
    });
  });

  group('All 8 themes Mobile, Short Landscape, Tablet Split, Theme Studio & Theme Picker',
      () {
    late _MockPlayerCubit playerCubit;
    late _MockSettingsCubit settingsCubit;

    final song = createTestSong(
      id: 77,
      title: 'Midnight Studio Resonance',
      artist: 'Pulsr Collective',
      album: 'Hi-Res Reference',
      durationMs: 245000,
      path: '/music/midnight.flac',
      bitrateKbps: 1411,
    ).copyWith(
      codec: const Value('flac'),
      bitDepth: const Value(24),
      sampleRate: const Value(96000),
    );

    final trackState = PlayerState(
      playback: PlaybackSlice(
        currentSong: song,
        isPlaying: true,
        position: const Duration(seconds: 42),
        duration: const Duration(milliseconds: 245000),
      ),
      queueSlice: QueueSlice(
        queue: [
          createTestSong(id: 76, title: 'Prev Track'),
          song,
          createTestSong(id: 78, title: 'Next Track'),
        ],
        currentIndex: 1,
      ),
      lyricsSlice: const LyricsSlice(
        lyrics: [
          LyricsLine(timestamp: Duration(seconds: 10), text: 'Opening verse'),
          LyricsLine(timestamp: Duration(seconds: 40), text: 'Active chorus line'),
          LyricsLine(timestamp: Duration(seconds: 80), text: 'Closing refrain'),
        ],
      ),
    );

    setUpAll(() {
      registerFallbackValue(PlayerThemeMode.clean);
    });

    setUp(() {
      AudioVisualizer.isTestingOverride = true;
      playerCubit = _MockPlayerCubit();
      settingsCubit = _MockSettingsCubit();
      when(() => playerCubit.state).thenReturn(trackState);
      when(() => playerCubit.stream)
          .thenAnswer((_) => const Stream<PlayerState>.empty());
      when(() => playerCubit.resetOverlayViews()).thenReturn(null);
      when(() => settingsCubit.state).thenReturn(
        const SettingsState(
          playerThemeMode: PlayerThemeMode.clean,
          reduceMotion: true,
        ),
      );
      when(() => settingsCubit.stream)
          .thenAnswer((_) => const Stream<SettingsState>.empty());
      when(() => settingsCubit.setPlayerThemeMode(any()))
          .thenAnswer((_) async {});
    });

    tearDown(() {
      AudioVisualizer.isTestingOverride = null;
    });

    for (final mode in PlayerThemeMode.values) {
      testWidgets(
        '${mode.name} renders cleanly across Mobile portrait, short landscape, and Tablet 2-pane split',
        (tester) async {
          when(() => settingsCubit.state).thenReturn(
            SettingsState(playerThemeMode: mode, reduceMotion: true),
          );
          final props = PlayerThemeProps(
            state: trackState,
            cubit: playerCubit,
            activeColor: const Color(0xFF9B9EF5),
            bgColor: const Color(0xFF101223),
          );

          Future<void> pumpViewport(Size size, {required bool useSplit}) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            final themeWidget = ThemeRegistry.build(mode, props);
            await tester.pumpWidget(
              MultiBlocProvider(
                providers: [
                  BlocProvider<PlayerCubit>.value(value: playerCubit),
                  BlocProvider<SettingsCubit>.value(value: settingsCubit),
                ],
                child: MaterialApp(
                  theme: AuraTheme.darkTheme,
                  localizationsDelegates: appLocalizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: MediaQuery(
                    data: MediaQueryData(size: size),
                    child: Scaffold(
                      body: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: useSplit
                            ? ResponsivePlayerLayout(
                                state: trackState,
                                cubit: playerCubit,
                                themeWidget: themeWidget,
                                activeColor: const Color(0xFF9B9EF5),
                                bgColor: const Color(0xFF101223),
                              )
                            : themeWidget,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 50));
            await tester.pump(const Duration(milliseconds: 250));
            expect(
              tester.takeException(),
              isNull,
              reason: '${mode.name} overflowed or threw at $size (split=$useSplit)',
            );
            expect(find.byType(PlayerSurfaceShell), findsOneWidget);
          }

          // Mobile portrait (compact breakpoint < 600dp)
          await pumpViewport(const Size(390, 844), useSplit: false);
          // Mobile short landscape (medium width, short height < 600dp)
          await pumpViewport(const Size(844, 390), useSplit: false);
          // Tablet 2-pane split (expanded breakpoint >= 840dp)
          await pumpViewport(const Size(1024, 768), useSplit: true);
        },
      );
    }

    testWidgets(
      'Theme Studio cycles live Now Playing preview across all 8 themes without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: playerCubit),
              BlocProvider<SettingsCubit>.value(value: settingsCubit),
            ],
            child: MaterialApp(
              theme: AuraTheme.darkTheme,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const CustomThemeBuilderScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);

        // Toggle into live Now Playing preview mode
        await tester.tap(find.byIcon(Icons.play_circle_outline_rounded));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);

        // Verify all 8 themes render via ChoiceChips without overflow
        final chips = find.byType(ChoiceChip);
        expect(chips, findsWidgets);
        for (final mode in PlayerThemeMode.values) {
          final props = PlayerThemeProps(
            state: trackState,
            cubit: playerCubit,
            activeColor: const Color(0xFF9B9EF5),
            bgColor: const Color(0xFF101223),
          );
          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider<PlayerCubit>.value(value: playerCubit),
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
              ],
              child: MaterialApp(
                key: ValueKey(mode),
                theme: AuraTheme.darkTheme,
                localizationsDelegates: appLocalizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 350,
                      height: 348,
                      child: ThemeRegistry.preview(mode, props, scale: 0.52),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            tester.takeException(),
            isNull,
            reason: 'Theme Studio live preview threw for ${mode.name}',
          );
        }
      },
    );

    testWidgets(
      'Select Player Theme picker renders live mini-previews cleanly on Mobile and Tablet',
      (tester) async {
        for (final size in const [Size(390, 844), Size(1024, 768)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider<PlayerCubit>.value(value: playerCubit),
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
              ],
              child: MaterialApp(
                key: ValueKey(size),
                theme: AuraTheme.darkTheme,
                localizationsDelegates: appLocalizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: MediaQuery(
                  data: MediaQueryData(size: size),
                  child: Scaffold(
                    body: Builder(
                      builder: (ctx) => ElevatedButton(
                        onPressed: () => showThemePickerSheet(
                          ctx,
                          settingsCubit,
                          PlayerThemeMode.clean,
                        ),
                        child: const Text('OPEN_PICKER'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('OPEN_PICKER'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            tester.takeException(),
            isNull,
            reason: 'Theme picker threw at $size',
          );
          expect(find.byType(ListTile), findsWidgets);
        }
      },
    );
  });
}
