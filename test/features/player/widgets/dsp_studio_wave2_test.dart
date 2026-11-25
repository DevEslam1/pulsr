// test/features/player/widgets/dsp_studio_wave2_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/headphone_target_curve.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_quality_sheet.dart';
import 'package:pulsr/features/player/presentation/widgets/dsp_inspector_sheet.dart';
import 'package:pulsr/features/player/presentation/widgets/eq_curve_visualizer.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_sheet_test_support.dart';

const _usbOutput = AudioOutputInfo(
  deviceName: 'Topping D90',
  isUsbDac: true,
  sampleRate: 96000,
  bitDepth: 24,
  isBitPerfectActive: false,
  usbAudioClass: 2,
  usbDacLabel: 'Topping D90',
  supportedSampleRates: [44100, 48000, 96000],
);

const _btOutput = AudioOutputInfo(
  deviceName: 'Sony XM5',
  isUsbDac: false,
  sampleRate: 48000,
  bitDepth: 24,
  isBitPerfectActive: false,
  isBluetooth: true,
  btA2dpPresent: true,
  btCodecName: 'LDAC',
  btSampleRateHz: 96000,
  btBitDepth: 24,
  btCodecConnected: true,
  canConfigureBluetooth: true,
  btLdacQualityMode: 3,
  btSelectableCodecs: ['SBC', 'LDAC'],
  btSelectableSampleRates: [48000, 96000],
  btSelectableBitDepths: [16, 24],
);

const _internalOutput = AudioOutputInfo(
  deviceName: 'Phone Speaker',
  isUsbDac: false,
  isBluetooth: false,
  sampleRate: 48000,
  bitDepth: 24,
  isBitPerfectActive: false,
  supportedSampleRates: [44100, 48000],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(ExperienceMode.professional);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.coachMarkUsbDacSeen: true,
      PrefsKeys.coachMarkDspSeen: true,
      PrefsKeys.coachMarkDockSwipeSeen: true,
    });
  });

  group('Wave 2A: EqualizerSheet Normal vs Pro Studio modes', () {
    testWidgets(
        'Normal mode renders Quick Sound Studio and Open Pro Studio pill switches to 4-tab Pro Rack',
        (tester) async {
      EqualizerSheet.debugForceAndroidSurface = true;
      addTearDown(() => EqualizerSheet.debugForceAndroidSurface = null);

      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final playerCubit = stubPlayerCubit(
        state: PlayerState(
          dsp: DspSlice(
            isEqEnabled: true,
            eqPreset: EqPreset(
              name: 'Flat',
              gains: List<double>.filled(10, 0.0),
            ),
          ),
        ),
      );
      final settingsCubit = stubSettingsCubit(
        state: const SettingsState(experienceMode: ExperienceMode.normal),
      );
      when(() => settingsCubit.setExperienceMode(any()))
          .thenAnswer((_) async {});

      await tester.pumpWidget(sheetHost(
        playerCubit: playerCubit,
        settingsCubit: settingsCubit,
        child: const EqualizerSheet(),
      ));
      await tester.pump();

      // Normal Mode: Quick Sound View with curve, preset carousel, macro
      // sliders, AutoEQ badge, A/B Flat toggle, and Open Pro Studio pill.
      expect(find.byKey(const ValueKey('eq_quick_sound_view')), findsOneWidget);
      expect(find.byType(EqCurveVisualizer), findsOneWidget);
      expect(
        find.byKey(const ValueKey('eq_quick_preset_carousel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('eq_quick_autoeq_badge')),
        findsOneWidget,
      );
      expect(find.text('A/B Flat'), findsOneWidget);
      expect(find.text('Bass & Punch'), findsOneWidget);
      expect(find.text('Vocal & Presence'), findsOneWidget);
      expect(find.text('Clarity & Air'), findsOneWidget);

      final proPill = find.byKey(const ValueKey('eq_open_pro_studio_pill'));
      expect(proPill, findsOneWidget);
      expect(tester.getSize(proPill).height, greaterThanOrEqualTo(48.0));

      // Switch to Pro Studio Mode via the pill.
      await tester.ensureVisible(proPill);
      await tester.pump();
      await tester.tap(proPill);
      await tester.pumpAndSettle();

      verify(() => settingsCubit.setExperienceMode(ExperienceMode.professional))
          .called(1);
      expect(find.byKey(const ValueKey('eq_pro_rack_view')), findsOneWidget);

      // Verify 4 focused Pro Rack tabs exist and switch cleanly.
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.tabs.length, 4);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byType(Tab).at(i));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('Wave 2A: eq_band_slider_column >= 48x48dp hit targets', () {
    testWidgets(
        'band slider and Mute/Solo toggles meet >= 48x48dp touch targets on compact phone width',
        (tester) async {
      EqualizerSheet.debugForceAndroidSurface = true;
      addTearDown(() => EqualizerSheet.debugForceAndroidSurface = null);

      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(sheetHost(
        playerCubit: stubPlayerCubit(
          state: PlayerState(
            dsp: DspSlice(
              isEqEnabled: true,
              eqPreset: EqPreset(
                name: 'Custom',
                gains: List<double>.filled(10, 0.0),
              ),
            ),
          ),
        ),
        settingsCubit: stubSettingsCubit(
          state:
              const SettingsState(experienceMode: ExperienceMode.professional),
        ),
        child: const EqualizerSheet(),
      ));
      await tester.pump();

      final band0Slider = find.byKey(const ValueKey('eq_band_0'));
      final band0Mute = find.byKey(const ValueKey('eq_band_mute_0'));
      final band0Solo = find.byKey(const ValueKey('eq_band_solo_0'));

      expect(band0Slider, findsOneWidget);
      expect(band0Mute, findsOneWidget);
      expect(band0Solo, findsOneWidget);

      final sliderSize = tester.getSize(band0Slider);
      final muteSize = tester.getSize(band0Mute);
      final soloSize = tester.getSize(band0Solo);

      expect(sliderSize.width, greaterThanOrEqualTo(48.0));
      expect(sliderSize.height, greaterThanOrEqualTo(48.0));
      expect(muteSize.width, greaterThanOrEqualTo(48.0));
      expect(muteSize.height, greaterThanOrEqualTo(48.0));
      expect(soloSize.width, greaterThanOrEqualTo(48.0));
      expect(soloSize.height, greaterThanOrEqualTo(48.0));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });

  group('Wave 2A: EqCurveVisualizer full Semantics & Reduce Motion', () {
    testWidgets(
        'publishes label, curve range value, selected band, target curve, and interactive hint',
        (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    height: 96,
                    child: EqCurveVisualizer(
                      gains: const [-3.0, 0.0, 4.5, 2.0, -1.0],
                      activeColor: Colors.teal,
                      height: 96,
                      selectedBandIndex: 2,
                      targetCurve: HeadphoneTargetCurve.harmanInEar2019,
                      onGainChanged: (_, __) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final curveNode = tester.getSemantics(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == 'Equalizer response curve',
          ),
        );
        final data = curveNode.getSemanticsData();

        expect(data.label, equals('Equalizer response curve'));
        expect(data.value, contains('5'));
        expect(data.value, contains('-3.0 to +4.5 dB'));
        expect(data.value, contains('Band 3: +4.5 dB'));
        expect(data.value, contains(HeadphoneTargetCurve.harmanInEar2019.name));
        expect(data.hint, isNotEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    });
  });

  group('Wave 2A: AudioQualitySheet Signal Path Header & Route Drawers', () {
    testWidgets(
        'renders live 4-stage Signal Path header and collapsible USB DAC drawer',
        (tester) async {
      final player = stubPlayerCubit();
      final settings = stubSettingsCubit(
        state: const SettingsState(
          experienceMode: ExperienceMode.professional,
          currentOutputDevice: _usbOutput,
        ),
      );

      await tester.pumpWidget(sheetHost(
        playerCubit: player,
        settingsCubit: settings,
        child:
            const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
      ));
      await tester.pump();

      // Signal Path header is visible immediately with all 4 stage pills.
      expect(
        find.byKey(const ValueKey('audio_quality_signal_path_header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('signal_path_pill_source')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('signal_path_pill_dsp')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('signal_path_pill_resampler')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('signal_path_pill_output')),
        findsOneWidget,
      );

      // Open Output tab and verify collapsible USB DAC drawer toggles.
      await tester.tap(find.text('Output'));
      await tester.pumpAndSettle();

      final usbDrawer =
          find.byKey(const ValueKey('audio_route_drawer_usb_dac'));
      expect(usbDrawer, findsOneWidget);
      expect(find.byKey(const ValueKey('audio_route_drawer_bluetooth')),
          findsNothing);

      // Initially expanded: Bit-Perfect switch is visible.
      expect(find.byType(Switch), findsOneWidget);

      // Collapse the drawer by tapping its header text.
      await tester.tap(find.text('USB Hi-Res DAC'));
      await tester.pumpAndSettle();

      // Re-expand the drawer.
      await tester.tap(find.text('USB Hi-Res DAC'));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets(
        'Bluetooth route shows collapsible Bluetooth drawer while Internal route shows Internal drawer',
        (tester) async {
      // 1. Bluetooth route
      await tester.pumpWidget(sheetHost(
        playerCubit: stubPlayerCubit(),
        settingsCubit: stubSettingsCubit(
          state: const SettingsState(
            experienceMode: ExperienceMode.normal,
            currentOutputDevice: _btOutput,
          ),
        ),
        child:
            const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
      ));
      await tester.pump();

      await tester.tap(find.text('Output'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('audio_route_drawer_bluetooth')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('audio_route_drawer_usb_dac')),
          findsNothing);

      // 2. Internal route (with Reduce Motion enabled)
      await tester.pumpWidget(
        sheetHost(
          playerCubit: stubPlayerCubit(),
          settingsCubit: stubSettingsCubit(
            state: const SettingsState(
              experienceMode: ExperienceMode.normal,
              reduceMotion: true,
              currentOutputDevice: _internalOutput,
            ),
          ),
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const AudioQualitySheet(
                  song: testSong, activeColor: Colors.teal),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Output'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('audio_route_drawer_internal')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('audio_route_drawer_bluetooth')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Wave 2A: DspInspectorSheet plain-language stage subtitles', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel(PulsrChannels.audioEffects), null);
    });

    testWidgets('renders plain-language subtitles for known DSP stages',
        (tester) async {
      messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects),
        (call) async {
          if (call.method == 'getDspDebugStatus') {
            return {
              'audioSessionId': 101,
              'isSessionAttached': true,
              'dspPreference': 'native',
              'isBitPerfectBypassActive': false,
              'isNativeDspLoaded': true,
              'activeDspStagesMask': 1,
              'autoDegradedStagesMask': 0,
              'hasOemAudio': false,
              'detectedOemEngines': const <String>[],
              'activeEffectNames': const ['EQ'],
              'detectedEngines': const <String>[],
              'stages': [
                {
                  'name': 'Parametric EQ',
                  'category': 'C++ Native',
                  'isSupported': true,
                  'isEnabled': true,
                  'isBypassed': false,
                  'isDegraded': false,
                  'parameters': const <String, dynamic>{},
                  'statusDescription': 'Applying 10 bands',
                },
                {
                  'name': 'Limiter',
                  'category': 'C++ Native',
                  'isSupported': true,
                  'isEnabled': true,
                  'isBypassed': false,
                  'isDegraded': false,
                  'parameters': const <String, dynamic>{},
                  'statusDescription': 'Ceiling -0.2 dBFS',
                },
              ],
              'timestamp': DateTime(2026).toIso8601String(),
            };
          }
          if (call.method == 'getTelemetry') {
            return List<dynamic>.generate(17, (_) => 0.0);
          }
          return null;
        },
      );

      await tester.pumpWidget(sheetHost(
        playerCubit: stubPlayerCubit(),
        settingsCubit: stubSettingsCubit(),
        child: const DspInspectorSheet(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('Parametric EQ'), findsOneWidget);
      expect(find.text('±15 dB per band, Q=1.414, flat by default'),
          findsOneWidget);
      expect(find.text('True-peak, 0.5–20 ms lookahead'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
