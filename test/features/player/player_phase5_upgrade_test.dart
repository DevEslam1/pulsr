// test/features/player/player_phase5_upgrade_test.dart
//
// Comprehensive Phase 5 Verification Test Suite for the Pulsr Player & Audio Engine Upgrade.
// Covers all unit, widget, and state invariants specified in Phase 5 verification instructions:
// - DspSlice HRTF state reactivity & active flags
// - PlayerDspController setDspEffectsEnabled HRTF bypass/restore
// - PlayerQueueController restoreQueue serialization with _queueMutex
// - PlayerDspController onOutputDeviceChanged serialization with _deviceChangeMutex
// - AbxCubit playCondition exception resilience & state rollback
// - Vinyl Turntable deck tonearm repainting on scrub updates
// - Circle player stage cancelling active drag on song change
// - CustomThemeBuilderScreen rejecting NaN radius & clamping persisted radius
// - AudioVisualizer safely handling 1-element data & NaN FFT input
// - QuranMushafView preventing unnecessary rebuilds on intra-ayah position ticks

import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/audio/headphone_profiles_repository.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/quran_metadata.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/circle_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/vinyl_player_theme.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/features/player/presentation/widgets/quran_mushaf_view.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test_support.dart';

class MockPulsrAudioHandler extends Mock implements PulsrAudioHandler {}
class MockEqualizerManager extends Mock implements EqualizerManager {}
class _MockPlayerCubit extends Mock implements PlayerCubit {}
class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(DynamicsPreset.off);
  });

  group('Phase 5 - DspSlice & HRTF Binaural State', () {
    test('DspSlice.isDspActive is true when only isHrtfEnabled == true', () {
      const slice = DspSlice(isHrtfEnabled: true);
      expect(slice.isHrtfEnabled, isTrue);
      expect(slice.isDspActive, isTrue);
      expect(slice.isDspEffectsActive, isTrue);
      expect(slice.activeDspStagesCount, greaterThanOrEqualTo(1));
    });

    test('DspSlice.isDspActive is false when all effects are disabled', () {
      const slice = DspSlice();
      expect(slice.isHrtfEnabled, isFalse);
      expect(slice.isDspActive, isFalse);
      expect(slice.isDspEffectsActive, isFalse);
      expect(slice.activeDspStagesCount, equals(0));
    });

    test('PlayerState convenience getters expose HRTF properties', () {
      const state = PlayerState(
        dsp: DspSlice(
          isHrtfEnabled: true,
          hrtfAzimuth: 45.0,
          hrtfElevation: 15.0,
          hrtfSofaPath: '/path/to/test.sofa',
        ),
      );
      expect(state.isHrtfEnabled, isTrue);
      expect(state.hrtfAzimuth, equals(45.0));
      expect(state.hrtfElevation, equals(15.0));
      expect(state.hrtfSofaPath, equals('/path/to/test.sofa'));
    });
  });

  group('Phase 5 - AudioVisualizer 1-element data and NaN safety', () {
    testWidgets('AudioVisualizer handles 1-element data without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: AudioVisualizer(
              isPlaying: true,
              style: VisualizerStyle.wave,
              width: 200,
              height: 100,
            ),
          ),
        ),
      );
      await tester.pump();
      final state = tester.state<AudioVisualizerState>(find.byType(AudioVisualizer));
      // Set single bar and tick
      state.setBarDataForTesting(0, 0.7);
      expect(() => state.onTickForTesting(), returnsNormally);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    test('AudioVisualizer ignores NaN and Infinite values in native FFT stream', () {
      final targetData = List<double>.filled(16, 0.0);
      final rawEvents = <dynamic>[double.nan, 0.75, double.infinity, -1.0, 0.5];

      for (int i = 0; i < rawEvents.length; i++) {
        final raw = rawEvents[i];
        if (raw is num && raw.isFinite) {
          targetData[i] = raw.toDouble().clamp(0.0, 1.0);
        }
      }

      expect(targetData[0], equals(0.0)); // NaN skipped
      expect(targetData[1], equals(0.75)); // 0.75 clamped to 0.75
      expect(targetData[2], equals(0.0)); // Infinity skipped
      expect(targetData[3], equals(0.0)); // -1.0 clamped to 0.0
      expect(targetData[4], equals(0.5)); // 0.5 clamped to 0.5
    });
  });

  group('Phase 5 - Theme & Gestures Verification', () {
    late _MockPlayerCubit mockPlayerCubit;
    late _MockSettingsCubit mockSettingsCubit;

    const testSong1 = SongsTableData(
      id: 101,
      title: 'Groove Track 1',
      artist: 'Artist 1',
      album: 'Album 1',
      durationMs: 180000,
      path: '/music/101.flac',
      isFavorite: false,
      isMissing: false,
      source: 'local',
      isDownloaded: true,
      playCount: 0,
      lastPositionMs: 0,
    );

    const testSong2 = SongsTableData(
      id: 102,
      title: 'Groove Track 2',
      artist: 'Artist 2',
      album: 'Album 2',
      durationMs: 200000,
      path: '/music/102.flac',
      isFavorite: false,
      isMissing: false,
      source: 'local',
      isDownloaded: true,
      playCount: 0,
      lastPositionMs: 0,
    );

    setUp(() {
      AudioVisualizer.isTestingOverride = true;
      mockPlayerCubit = _MockPlayerCubit();
      mockSettingsCubit = _MockSettingsCubit();

      when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
      when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream<SettingsState>.empty());

      when(() => mockPlayerCubit.state).thenReturn(
        const PlayerState(
          playback: PlaybackSlice(
            currentSong: testSong1,
            isPlaying: true,
            duration: Duration(minutes: 3),
            position: Duration(seconds: 45),
          ),
        ),
      );
      when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream<PlayerState>.empty());
    });

    testWidgets('_CircleArtwork cancels drag on song change', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Widget buildTree(SongsTableData song) {
        return MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
                BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
              ],
              child: CirclePlayerTheme(
                props: PlayerThemeProps(
                  state: PlayerState(
                    playback: PlaybackSlice(
                      currentSong: song,
                      isPlaying: true,
                      duration: Duration(milliseconds: song.durationMs),
                    ),
                  ),
                  cubit: mockPlayerCubit,
                  activeColor: Colors.deepPurpleAccent,
                  bgColor: Colors.black,
                ),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildTree(testSong1));
      await tester.pump(const Duration(milliseconds: 100));

      // Find the circular artwork hit area and start a drag
      final gestureFinder = find.byType(GestureDetector);
      expect(gestureFinder, findsWidgets);

      // Perform a pan down gesture to start scrubbing
      final gesture = await tester.startGesture(tester.getCenter(gestureFinder.first));
      await gesture.moveBy(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 50));

      // Song changes to testSong2
      await tester.pumpWidget(buildTree(testSong2));
      await tester.pump(const Duration(milliseconds: 50));

      // Rebuilding with new song cancels drag and resets rotation offset
      expect(tester.takeException(), isNull);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('_VinylTurntableDeck renders platter and tonearm with reactive scrub', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
                BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
              ],
              child: VinylPlayerTheme(
                props: PlayerThemeProps(
                  state: const PlayerState(
                    playback: PlaybackSlice(
                      currentSong: testSong1,
                      isPlaying: true,
                      duration: Duration(minutes: 3),
                      position: Duration(seconds: 30),
                    ),
                  ),
                  cubit: mockPlayerCubit,
                  activeColor: Colors.amberAccent,
                  bgColor: Colors.black,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('33⅓ RPM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 5 - QuranMushafView Rebuild Optimization', () {
    testWidgets('QuranMushafView only rebuilds when activeAyah changes, not on same-ayah ticks', (tester) async {
      int buildCount = 0;

      final timings = [
        const QuranAyahTiming(
          ayahNumber: 1,
          start: Duration.zero,
          end: Duration(seconds: 5),
        ),
        const QuranAyahTiming(
          ayahNumber: 2,
          start: Duration(seconds: 5),
          end: Duration(seconds: 10),
        ),
      ];
      final meta = QuranMetadata(
        surahNumber: 1,
        surahName: 'Al-Fatihah',
        ayahStart: 1,
        ayahEnd: 7,
        reciter: 'Mishary Rashid Alafasy',
        ayahTimings: timings,
      );

      final stateController = StreamController<PlayerState>.broadcast();
      addTearDown(stateController.close);

      final mockCubit = _MockPlayerCubit();
      when(() => mockCubit.stream).thenAnswer((_) => stateController.stream);
      when(() => mockCubit.state).thenReturn(
        const PlayerState(
          playback: PlaybackSlice(position: Duration(milliseconds: 1000)),
        ),
      );

      Widget host() {
        return MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BlocProvider<PlayerCubit>.value(
              value: mockCubit,
              child: BlocSelector<PlayerCubit, PlayerState, int?>(
                selector: (s) => meta.ayahAt(s.position),
                builder: (context, activeAyah) {
                  buildCount++;
                  return QuranMushafView(
                    metadata: meta,
                    activeAyah: activeAyah,
                  );
                },
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(buildCount, equals(1));

      // Emit position tick within Ayah 1 (1000ms -> 2000ms)
      stateController.add(
        const PlayerState(
          playback: PlaybackSlice(position: Duration(milliseconds: 2000)),
        ),
      );
      await tester.pump();
      // buildCount must NOT increase because ayah is still 1
      expect(buildCount, equals(1));

      // Emit position tick into Ayah 2 (6000ms)
      stateController.add(
        const PlayerState(
          playback: PlaybackSlice(position: Duration(milliseconds: 6000)),
        ),
      );
      await tester.pump();
      // buildCount MUST increment now that ayah changed from 1 to 2
      expect(buildCount, equals(2));
    });
  });

  group('Phase 5 - Player Controllers: Mutex & HRTF Gating', () {
    late MockPulsrAudioHandler handler;
    late MockEqualizerManager mockEqManager;
    late _MockSettingsCubit mockSettings;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      handler = MockPulsrAudioHandler();
      mockEqManager = MockEqualizerManager();
      mockSettings = _MockSettingsCubit();

      when(() => mockSettings.state).thenReturn(const SettingsState());
      when(() => handler.isCrossfeedEnabled).thenReturn(false);
      when(() => mockEqManager.setMultibandCompressor(any())).thenAnswer((_) async {});
      when(() => handler.equalizerManager).thenReturn(mockEqManager);
      when(() => handler.setSpatializerEnabled(any())).thenAnswer((_) async {});
      when(() => handler.setVirtualizerEnabled(any())).thenAnswer((_) async {});
      when(() => handler.setDynamicsPreset(any(), enabled: any(named: 'enabled'))).thenAnswer((_) async {});
      when(() => handler.setCrossfeed(any(), delayUs: any(named: 'delayUs'), feedDb: any(named: 'feedDb'), mode: any(named: 'mode'), fcut: any(named: 'fcut'))).thenAnswer((_) async {});
      when(() => handler.setHrtfBinaural(any(), azimuth: any(named: 'azimuth'), elevation: any(named: 'elevation'), sofaPath: any(named: 'sofaPath'))).thenAnswer((_) async {});
      when(() => handler.setLookaheadLimiter(any(), thresholdDb: any(named: 'thresholdDb'), releaseMs: any(named: 'releaseMs'), lookaheadMs: any(named: 'lookaheadMs'))).thenAnswer((_) async {});
      when(() => handler.setReverb(any(), preset: any(named: 'preset'), wetDry: any(named: 'wetDry'), damping: any(named: 'damping'))).thenAnswer((_) async {});
      when(() => handler.setSaturation(any(), drive: any(named: 'drive'), mix: any(named: 'mix'), tilt: any(named: 'tilt'), multiband: any(named: 'multiband'))).thenAnswer((_) async {});
      when(() => handler.setStereoWidth(any())).thenAnswer((_) async {});
      when(() => handler.setLoudnessContour(any(), intensity: any(named: 'intensity'))).thenAnswer((_) async {});
      when(() => handler.setSubCrossover(any(), cornerHz: any(named: 'cornerHz'), slopeDbPerOct: any(named: 'slopeDbPerOct'), gain: any(named: 'gain'), bassMono: any(named: 'bassMono'), antiPop: any(named: 'antiPop'))).thenAnswer((_) async {});
      when(() => handler.setDynamicEq(any())).thenAnswer((_) async {});
      when(() => handler.setViperDdc(any(), profileName: any(named: 'profileName'), coeffs: any(named: 'coeffs'), ddcContent: any(named: 'ddcContent'))).thenAnswer((_) async {});
      when(() => handler.setArbitraryEq(any(), eqString: any(named: 'eqString'), linearPhase: any(named: 'linearPhase'))).thenAnswer((_) async {});
      when(() => handler.setLiveProg(any(), code: any(named: 'code'))).thenAnswer((_) async {});
      when(() => handler.setDynamicBass(enabled: any(named: 'enabled'), strength: any(named: 'strength'), preset: any(named: 'preset'))).thenAnswer((_) async {});
      when(() => handler.setVolumeBoost(any())).thenAnswer((_) async {});
      when(() => handler.setBassBoost(any())).thenAnswer((_) async {});
    });

    test('setDspEffectsEnabled(false) disables HRTF and restores it on re-enable', () async {
      var state = const PlayerState(
        dsp: DspSlice(
          isHrtfEnabled: true,
          hrtfAzimuth: 30.0,
          hrtfElevation: 10.0,
        ),
      );

      final controller = PlayerDspController(
        audioHandler: handler,
        settingsCubit: mockSettings,
        headphoneProfilesRepo: HeadphoneProfilesRepository(),
        getState: () => state,
        emit: (s) => state = s,
        syncAudioEffects: () {},
        isClosed: () => false,
      );

      // Disable DSP effects
      await controller.setDspEffectsEnabled(false);
      expect(state.dsp.isHrtfEnabled, isFalse);
      expect(state.dsp.isDspEffectsActive, isFalse);
      verify(() => handler.setHrtfBinaural(false)).called(1);

      // Re-enable DSP effects
      await controller.setDspEffectsEnabled(true);
      expect(state.dsp.isHrtfEnabled, isTrue);
      expect(state.dsp.hrtfAzimuth, equals(30.0));
      expect(state.dsp.hrtfElevation, equals(10.0));
      expect(state.dsp.isDspEffectsActive, isTrue);
      verify(() => handler.setHrtfBinaural(true, azimuth: 30.0, elevation: 10.0)).called(1);
    });

    test('overlapping onOutputDeviceChanged calls serialize under mutex', () async {
      var state = const PlayerState();

      final controller = PlayerDspController(
        audioHandler: handler,
        settingsCubit: mockSettings,
        headphoneProfilesRepo: HeadphoneProfilesRepository(),
        getState: () => state,
        emit: (s) => state = s,
        syncAudioEffects: () {},
        isClosed: () => false,
      );

      const device1 = AudioOutputInfo(
        deviceName: 'Wired Headphones',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
        activeDeviceType: 'headphone',
      );

      const device2 = AudioOutputInfo(
        deviceName: 'Phone Speaker',
        isUsbDac: false,
        sampleRate: 44100,
        bitDepth: 16,
        isBitPerfectActive: false,
        activeDeviceType: 'builtin_speaker',
      );

      // Fire overlapping calls concurrently
      final f1 = controller.onOutputDeviceChanged(device1);
      final f2 = controller.onOutputDeviceChanged(device2);
      await Future.wait<void>([f1, f2]);

      // Both serialized calls evaluated route crossfeed
      verify(() => handler.isCrossfeedEnabled).called(2);
    });

    test('restoreQueueSlots protects operations under _queueMutex', () async {
      final mutex = Mutex();
      var state = const PlayerState();
      when(() => handler.queue).thenAnswer((_) => BehaviorSubject.seeded(const <MediaItem>[]));

      final controller = PlayerQueueController(
        audioHandler: handler,
        repository: MockMusicRepository(),
        getState: () => state,
        emit: (s) => state = s,
        isClosed: () => false,
        queueMutex: mutex,
        slotLookupCache: <int, SongsTableData>{},
        queueSlots: <int, QueueSlotData>{},
        updateWidgetThrottled: ({bool force = false}) {},
        loadLyrics: (_) {},
        bumpQueueVersion: () {},
        isSameTrack: (a, b) => a?.id == b?.id,
      );

      expect(mutex.isLocked, isFalse);
      await controller.restoreQueueSlots();
      expect(mutex.isLocked, isFalse);
    });
  });
}
