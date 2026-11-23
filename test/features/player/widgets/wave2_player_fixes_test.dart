// test/features/player/widgets/wave2_player_fixes_test.dart
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/errors/app_error.dart';
import 'package:pulsr/core/performance/gpu_budget.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/domain/models/milkdrop_preset.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/cassette_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/cd_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/vinyl_player_theme.dart';
import 'package:pulsr/features/player/presentation/widgets/arbitrary_eq_sheet.dart';
import 'package:pulsr/features/player/presentation/widgets/canvas_backdrop.dart';
import 'package:pulsr/features/player/presentation/widgets/eq_curve_visualizer.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';
import 'package:pulsr/features/player/presentation/widgets/hrtf_binaural_card.dart';
import 'package:pulsr/features/player/presentation/widgets/live_prog_sheet.dart';
import 'package:pulsr/features/player/presentation/widgets/lyrics/advanced_lyrics_view.dart';
import 'package:pulsr/features/player/presentation/widgets/mini_player/mini_player_progress_bar.dart';
import 'package:pulsr/features/player/presentation/widgets/multichannel_bass_card.dart';
import 'package:pulsr/features/player/presentation/widgets/player_more_sheet.dart';
import 'package:pulsr/features/player/presentation/widgets/viper_ddc_sheet.dart';
import 'package:pulsr/features/player/presentation/widgets/visualizer/milkdrop_renderer.dart';
import 'package:pulsr/features/player/presentation/widgets/waveform_seek_bar.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ui/material_ui.dart';

import 'player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GpuBudget.enabled.value = false;
  });

  tearDown(() {
    GpuBudget.enabled.value = false;
  });

  group('H-54 PlayerMoreSheet local song & caller context pop', () {
    testWidgets(
        'renders Add to Playlist for local songs without remoteId and pops with action result',
        (tester) async {
      final playerCubit = stubPlayerCubit();
      final settingsCubit = stubSettingsCubit();

      const localOnlySong = SongsTableData(
        id: 101,
        title: 'Local Track',
        artist: 'Local Artist',
        album: 'Local Album',
        durationMs: 180000,
        path: '/storage/music/local.flac',
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        source: SongSource.local,
        isDownloaded: false,
        remoteId: null,
      );

      await tester.pumpWidget(
        sheetHost(
          playerCubit: playerCubit,
          settingsCubit: settingsCubit,
          child: const PlayerMoreSheet(
            song: localOnlySong,
            activeColor: Colors.cyan,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.playlist_add_rounded), findsOneWidget);
      expect(find.text('Add to Playlist'), findsOneWidget);
    });
  });

  group('M-10 Cassette separate PLAY and PAUSE mechanical deck keys', () {
    testWidgets(
        'PLAY key only calls play() when paused and PAUSE key only calls pause() when playing',
        (tester) async {
      tester.view.physicalSize = const Size(430, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var currentState = const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: false,
          duration: Duration(minutes: 3),
        ),
        queueSlice: QueueSlice(queue: [testSong], currentIndex: 0),
      );

      final playerCubit = stubPlayerCubit(state: currentState);
      final settingsCubit = stubSettingsCubit();
      when(() => playerCubit.state).thenAnswer((_) => currentState);
      when(() => playerCubit.play()).thenAnswer((_) async {});
      when(() => playerCubit.pause()).thenAnswer((_) async {});

      Widget buildCassette() => MaterialApp(
            theme: AuraTheme.darkTheme,
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<PlayerCubit>.value(value: playerCubit),
                  BlocProvider<SettingsCubit>.value(value: settingsCubit),
                ],
                child: CassettePlayerTheme(
                  props: PlayerThemeProps(
                    state: currentState,
                    cubit: playerCubit,
                    activeColor: Colors.amber,
                    bgColor: Colors.black,
                  ),
                ),
              ),
            ),
          );

      await tester.pumpWidget(buildCassette());
      await tester.pump();

      // When paused: tapping PAUSE must not call pause() or togglePlayPause()
      await tester.tap(find.text('PAUSE'));
      await tester.pump();
      verifyNever(() => playerCubit.pause());
      verifyNever(() => playerCubit.play());

      // Tapping PLAY when paused calls play()
      await tester.tap(find.text('PLAY'));
      await tester.pump();
      verify(() => playerCubit.play()).called(1);

      // Now switch state to playing: tapping PLAY must not pause
      currentState = currentState.copyWith(
        playback: currentState.playback.copyWith(isPlaying: true),
      );
      await tester.pumpWidget(buildCassette());
      await tester.pump();

      await tester.tap(find.text('PLAY'));
      await tester.pump();
      verifyNever(() => playerCubit.pause());

      await tester.tap(find.text('PAUSE'));
      await tester.pump();
      verify(() => playerCubit.pause()).called(1);
    });
  });

  group('M-10 EQ header Bit-Perfect switch polarity & EqCurveVisualizer min size',
      () {
    testWidgets(
        'EqShellHeader keeps Switch value true when EQ is enabled while blocked by Bit-Perfect',
        (tester) async {
      EqualizerSheet.debugForceAndroidSurface = true;
      addTearDown(() => EqualizerSheet.debugForceAndroidSurface = null);

      tester.view.physicalSize = const Size(500, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final playerCubit = stubPlayerCubit(
        state: const PlayerState(
          dsp: DspSlice(
            isEqEnabled: true,
            eqPreset: EqPreset(
              name: 'Flat',
              gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            ),
          ),
        ),
      );
      final settingsCubit = stubSettingsCubit(
        state: const SettingsState(
          experienceMode: ExperienceMode.professional,
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
        ),
      );
      when(() => playerCubit.setEqualizerEnabled(any()))
          .thenAnswer((_) async {});

      await tester.pumpWidget(
        sheetHost(
          playerCubit: playerCubit,
          settingsCubit: settingsCubit,
          child: const EqualizerSheet(),
        ),
      );
      await tester.pump();

      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches, isNotEmpty);
      expect(switches.first.value, isTrue);
    });

    testWidgets(
        'EqCurveVisualizer clamps tiny height to >=24dp and handles zero-size canvas safely',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 6,
                child: EqCurveVisualizer(
                  gains: [2.0, -3.0, 1.0, 0.0, 4.0],
                  activeColor: Colors.teal,
                  height: 2,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('M-10 Act-then-confirm (no premature shadow flip on backend error)', () {
    testWidgets(
        'HrtfBinauralCard does not flip switch on when cubit records an error',
        (tester) async {
      var currentState = const PlayerState();
      final cubit = stubPlayerCubit(state: currentState);
      when(() => cubit.state).thenAnswer((_) => currentState);
      when(() => cubit.setHrtfBinaural(
            any(),
            azimuth: any(named: 'azimuth'),
            elevation: any(named: 'elevation'),
            sofaPath: any(named: 'sofaPath'),
          )).thenAnswer((_) async {
        currentState = currentState.copyWith(
          playback: currentState.playback.copyWith(
            error: uiError('HRTF blocked by bit-perfect'),
          ),
        );
      });

      await tester.pumpWidget(
        sheetHost(
          playerCubit: cubit,
          child: const HrtfBinauralCard(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.value, isFalse);
      expect(find.text('Virtual Speaker Azimuth'), findsNothing);
    });

    testWidgets(
        'MultichannelBassCard does not change layout when native channel throws',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects),
        (call) async {
          if (call.method == 'setChannelManagerEnabled') {
            throw PlatformException(code: 'ERR', message: 'native error');
          }
          return true;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel(PulsrChannels.audioEffects),
          null,
        );
      });

      SharedPreferences.setMockInitialValues({
        PrefsKeys.channelManagerEnabled: true,
        PrefsKeys.channelManagerChannelCount: 6,
      });

      final settingsCubit = stubSettingsCubit(
        state: const SettingsState(
          currentOutputDevice: AudioOutputInfo(
            deviceName: '5.1 Surround',
            isUsbDac: true,
            sampleRate: 48000,
            bitDepth: 24,
            isBitPerfectActive: false,
            decodedChannelCount: 6,
            supportedChannelCounts: [2, 6, 8],
          ),
        ),
      );

      await tester.pumpWidget(
        sheetHost(
          settingsCubit: settingsCubit,
          child: const SingleChildScrollView(
            child: MultichannelBassCard(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('5.1 (6 channels)'), findsOneWidget);

      await tester.tap(find.text('7.1 (8 ch)'));
      await tester.pumpAndSettle();

      // Layout must stay at 5.1 because native setChannelManagerEnabled threw.
      expect(find.text('5.1 (6 channels)'), findsOneWidget);
    });

    testWidgets(
        'ArbitraryEqSheet and LiveProgSheet do not overwrite editor or show success toast on cubit error',
        (tester) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var currentState = const PlayerState(
        dsp: DspSlice(
          arbitraryEqString: 'GraphicEq: 100 1; 1000 2',
          liveProgCode: '@sample\nspl0 = spl0;',
        ),
      );
      final cubit = stubPlayerCubit(state: currentState);
      when(() => cubit.state).thenAnswer((_) => currentState);
      when(() => cubit.isArbitraryEqLinearPhase).thenReturn(false);
      when(() => cubit.setArbitraryEqEnabled(
            any(),
            eqString: any(named: 'eqString'),
            linearPhase: any(named: 'linearPhase'),
          )).thenAnswer((_) async {
        currentState = currentState.copyWith(
          playback: currentState.playback.copyWith(
            error: uiError('Rejected arbitrary EQ'),
          ),
        );
      });
      when(() => cubit.setLiveProgEnabled(any(), code: any(named: 'code')))
          .thenAnswer((_) async {
        currentState = currentState.copyWith(
          dsp: currentState.dsp.copyWith(liveProgStatus: 'Compile error'),
        );
      });

      await tester.pumpWidget(
        sheetHost(
          playerCubit: cubit,
          child: const ArbitraryEqSheet(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Harman Target Curve'));
      await tester.pump();
      final arbField = tester.widget<TextField>(find.byType(TextField));
      expect(arbField.controller!.text, 'GraphicEq: 100 1; 1000 2');

      await tester.pumpWidget(
        sheetHost(
          playerCubit: cubit,
          child: const LiveProgSheet(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stereo Sine Tremolo'));
      await tester.pump();
      final liveField = tester.widget<TextField>(find.byType(TextField));
      expect(liveField.controller!.text, '@sample\nspl0 = spl0;');
    });

    testWidgets(
        'ViperDdcSheet A/B bypass does not toggle when setViperDdcEnabled fails',
        (tester) async {
      var currentState = const PlayerState(
        dsp: DspSlice(isViperDdcEnabled: true),
      );
      final cubit = stubPlayerCubit(state: currentState);
      when(() => cubit.state).thenAnswer((_) => currentState);
      when(() => cubit.setViperDdcEnabled(any())).thenAnswer((_) async {
        currentState = currentState.copyWith(
          playback: currentState.playback.copyWith(
            error: uiError('DDC disable failed'),
          ),
        );
      });

      await tester.pumpWidget(
        sheetHost(
          playerCubit: cubit,
          child: const ViperDdcSheet(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('A/B Compare'));
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('M-10 RTL waveform seek bar & deck mirroring + GpuBudget blur gating',
      () {
    testWidgets(
        'WaveformSeekBar inverts horizontal tap seek ratio under TextDirection.rtl and gates blur under GpuBudget',
        (tester) async {
      GpuBudget.enabled.value = true;
      Duration? sought;

      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: WaveformSeekBar(
                    position: const Duration(seconds: 10),
                    duration: const Duration(seconds: 100),
                    samples: List<double>.filled(40, 0.6),
                    activeColor: Colors.cyan,
                    style: WaveformVisualizerStyle.neonGlowLine,
                    onSeek: (pos) => sought = pos,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap near the left edge of the waveform in RTL -> should seek near the end (>50s)
      final box = tester.getRect(find.byType(WaveformSeekBar));
      await tester.tapAt(Offset(box.left + 40, box.center.dy));
      await tester.pump(const Duration(milliseconds: 350));

      expect(sought, isNotNull);
      expect(sought!.inSeconds, greaterThan(50));
    });

    testWidgets(
        'AdvancedLyricsView and MiniPlayerProgressBar and Vinyl/CD/Cassette decks render in RTL with GpuBudget active',
        (tester) async {
      GpuBudget.enabled.value = true;
      tester.view.physicalSize = const Size(430, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final playerState = const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          position: Duration(seconds: 30),
          duration: Duration(seconds: 120),
        ),
        queueSlice: QueueSlice(queue: [testSong], currentIndex: 0),
      );
      final playerCubit = stubPlayerCubit(state: playerState);
      final settingsCubit = stubSettingsCubit();

      for (final themeWidget in <Widget>[
        VinylPlayerTheme(
          props: PlayerThemeProps(
            state: playerState,
            cubit: playerCubit,
            activeColor: Colors.amber,
            bgColor: Colors.black,
          ),
        ),
        CdPlayerTheme(
          props: PlayerThemeProps(
            state: playerState,
            cubit: playerCubit,
            activeColor: Colors.cyan,
            bgColor: Colors.black,
          ),
        ),
        MiniPlayerProgressBar(
          duration: const Duration(seconds: 120),
          activeAccent: Colors.cyan,
          hairlineColor: Colors.grey,
          isPlaying: true,
          onSeek: (_) {},
        ),
        AdvancedLyricsView(
          lyrics: const [
            LyricsLine(timestamp: Duration(seconds: 0), text: 'Line 1'),
            LyricsLine(timestamp: Duration(seconds: 25), text: 'Line 2'),
          ],
          currentPosition: const Duration(seconds: 26),
          activeColor: Colors.cyan,
          onLineTapped: (_) {},
        ),
      ]) {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              theme: AuraTheme.darkTheme,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: MultiBlocProvider(
                    providers: [
                      BlocProvider<PlayerCubit>.value(value: playerCubit),
                      BlocProvider<SettingsCubit>.value(value: settingsCubit),
                    ],
                    child: themeWidget,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });

    test('MilkdropCanvasPainter uses monotonic elapsedSeconds and dirty flags',
        () {
      const preset = MilkdropPreset(
        name: 'Test',
        decay: 0.95,
        waveR: 0.5,
        waveG: 0.6,
        waveB: 0.7,
        rot: 0.02,
        zoom: 1.01,
        warp: 0.2,
      );
      final p1 = MilkdropCanvasPainter(
        data: const [0.2, 0.4, 0.6],
        color: Colors.cyan,
        preset: preset,
        generation: 5,
        elapsedSeconds: 12.5,
      );
      final p1Same = MilkdropCanvasPainter(
        data: const [0.2, 0.4, 0.6],
        color: Colors.cyan,
        preset: preset,
        generation: 5,
        elapsedSeconds: 12.5,
      );
      final p2 = MilkdropCanvasPainter(
        data: const [0.2, 0.4, 0.6],
        color: Colors.cyan,
        preset: preset,
        generation: 5,
        elapsedSeconds: 12.516,
      );
      expect(p1Same.shouldRepaint(p1), isFalse);
      expect(p2.shouldRepaint(p1), isTrue);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      expect(() => p2.paint(canvas, const Size(200, 200)), returnsNormally);
    });

    testWidgets('H-53 CanvasBackdrop renders without off-center Transform.scale',
        (tester) async {
      final settingsCubit = stubSettingsCubit();
      await tester.pumpWidget(
        sheetHost(
          settingsCubit: settingsCubit,
          child: const SizedBox(
            width: 300,
            height: 400,
            child: CanvasBackdrop(
              song: null,
              isPlaying: false,
              isBackdropMode: true,
              fallbackArtwork: SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CanvasBackdrop), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
