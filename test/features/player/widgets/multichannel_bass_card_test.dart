// test/features/player/widgets/multichannel_bass_card_test.dart
import 'dart:convert';
import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/dsp_battery_estimate.dart';
import 'package:pulsr/features/player/presentation/widgets/multichannel_bass_card.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DspBatteryEstimate', () {
    test('parses empty and default map correctly', () {
      final est = DspBatteryEstimate.fromMap({});
      expect(est.estimatedMahPerHour, 0.0);
      expect(est.lowPowerBypassActive, isFalse);
      expect(est.activeStageCount, 0);
      expect(est.stageBreakdown, isEmpty);
      expect(est.stagePowerSpecs, isEmpty);
    });

    test('parses populated map with breakdown and low-power bypass', () {
      final map = {
        'estimatedMahPerHour': 0.0,
        'lowPowerBypassActive': true,
        'activeStageCount': 3,
        'stageBreakdown': {
          'reverb': 12.0,
          'saturation': 3.5,
          'limiter': 2.0,
        },
        'stagePowerSpecs': {
          'reverb': 12.0,
          'saturation': 3.5,
          'limiter': 2.0,
          'lfeCrossover': 2.0,
          'channelManager': 1.5,
        },
      };
      final est = DspBatteryEstimate.fromMap(map);
      expect(est.estimatedMahPerHour, 0.0);
      expect(est.lowPowerBypassActive, isTrue);
      expect(est.activeStageCount, 3);
      expect(est.stageBreakdown['reverb'], 12.0);
      expect(est.stageBreakdown['saturation'], 3.5);
      expect(est.stagePowerSpecs['lfeCrossover'], 2.0);
      expect(est.stagePowerSpecs['channelManager'], 1.5);
    });

    test('stageDisplayName provides readable labels', () {
      expect(DspBatteryEstimate.stageDisplayName('reverb'), 'Convolution Reverb');
      expect(DspBatteryEstimate.stageDisplayName('saturation'), 'Harmonic Saturation');
      expect(DspBatteryEstimate.stageDisplayName('lfeCrossover'), 'LFE Bass Management');
      expect(DspBatteryEstimate.stageDisplayName('channelManager'), 'Channel Manager');
      expect(DspBatteryEstimate.stageDisplayName('limiter'), 'True Peak Limiter');
      expect(DspBatteryEstimate.stageDisplayName('unknown_custom'), 'unknown_custom');
    });
  });

  group('MultichannelBassCard Widget', () {
    const stereoState = SettingsState(
      currentOutputDevice: AudioOutputInfo(
        deviceName: 'Stereo Headset',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
        decodedChannelCount: 2,
        supportedChannelCounts: [2],
      ),
    );

    const multichannelState = SettingsState(
      currentOutputDevice: AudioOutputInfo(
        deviceName: '5.1 Surround HDMI / USB DAC',
        isUsbDac: true,
        sampleRate: 48000,
        bitDepth: 24,
        isBitPerfectActive: false,
        decodedChannelCount: 6,
        supportedChannelCounts: [2, 6, 8],
      ),
    );

    Future<void> pumpCard(
      WidgetTester tester, {
      required SettingsState settingsState,
      bool forceVisible = false,
      String? blockedReason,
    }) async {
      final cubit = MockSettingsCubit();
      when(() => cubit.state).thenReturn(settingsState);
      when(() => cubit.stream)
          .thenAnswer((_) => const Stream<SettingsState>.empty());

      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider<SettingsCubit>.value(
            value: cubit,
            child: Scaffold(
              body: SingleChildScrollView(
                child: MultichannelBassCard(
                  forceVisible: forceVisible,
                  blockedReason: blockedReason,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects),
        (call) async => true,
      );

      SharedPreferences.setMockInitialValues({
        PrefsKeys.channelManagerEnabled: true,
        PrefsKeys.channelManagerChannelCount: 6,
        PrefsKeys.channelManagerTrims: json.encode([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
        PrefsKeys.channelManagerDelays: json.encode([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
        PrefsKeys.lfeCrossoverEnabled: true,
        PrefsKeys.lfeCrossoverHz: 80.0,
        PrefsKeys.lfeLowPassHz: 120.0,
        PrefsKeys.lfeSlopeDbPerOct: 24.0,
        PrefsKeys.lfeGainDb: 0.0,
        PrefsKeys.lfeChannelIndex: 3,
        PrefsKeys.lfeRedirectBass: true,
      });
    });

    testWidgets('hides when output is stereo and forceVisible is false', (tester) async {
      await pumpCard(tester, settingsState: stereoState, forceVisible: false);
      expect(find.text('Multichannel Speaker Alignment'), findsNothing);
      expect(find.text('LFE Crossover & Bass Management'), findsNothing);
    });

    testWidgets('renders when output is multichannel (>2 channels)', (tester) async {
      await pumpCard(tester, settingsState: multichannelState);
      expect(find.text('Multichannel Speaker Alignment'), findsOneWidget);
      expect(find.textContaining('AAudio is limited to 2 channels on Android'), findsOneWidget);
      expect(find.text('LFE Crossover & Bass Management'), findsOneWidget);
      expect(find.text('Speaker Layout'), findsOneWidget);
      expect(find.text('5.1 (6 channels)'), findsOneWidget);
      expect(find.text('2.1 (3 ch)'), findsNothing);
      expect(find.text('3.0 (3 ch)'), findsOneWidget);
      expect(find.text('Satellite Crossover (HPF)'), findsOneWidget);
      expect(find.text('Subwoofer Low-Pass (LPF)'), findsOneWidget);
      expect(find.text('24 dB/oct (LR4)'), findsOneWidget);
      expect(find.text('Redirect Satellite Bass'), findsOneWidget);
    });

    testWidgets('renders when forceVisible is true even on stereo', (tester) async {
      await pumpCard(tester, settingsState: stereoState, forceVisible: true);
      expect(find.text('Multichannel Speaker Alignment'), findsOneWidget);
      expect(find.text('LFE Crossover & Bass Management'), findsOneWidget);
    });

    testWidgets('switches layout count and selects speaker channels', (tester) async {
      await pumpCard(tester, settingsState: multichannelState);
      expect(find.text('7.1 (8 ch)'), findsOneWidget);

      await tester.tap(find.text('7.1 (8 ch)'));
      await tester.pumpAndSettle();

      expect(find.text('7.1 (8 channels)'), findsOneWidget);
      expect(find.text('SL'), findsOneWidget);
      expect(find.text('SR'), findsOneWidget);

      await tester.tap(find.text('LFE'));
      await tester.pumpAndSettle();
      expect(find.text('Low-Frequency Effects (LFE)'), findsOneWidget);
    });

    testWidgets('4.0 disables the LFE stage and persists the choice',
        (tester) async {
      await pumpCard(tester, settingsState: multichannelState);
      await tester.tap(find.text('4.0 (4 ch)'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.channelManagerChannelCount), 4);
      expect(prefs.getBool(PrefsKeys.lfeCrossoverEnabled), isFalse);
      expect(prefs.getInt(PrefsKeys.lfeChannelIndex), 0);
      expect(find.text('4.0 (4 channels)'), findsOneWidget);
    });

    testWidgets('adjusts slope chip between LR2 and LR4', (tester) async {
      await pumpCard(tester, settingsState: multichannelState);
      expect(find.text('12 dB/oct (LR2)'), findsOneWidget);

      await tester.tap(find.text('12 dB/oct (LR2)'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(PrefsKeys.lfeSlopeDbPerOct), 12.0);
    });
  });
}
