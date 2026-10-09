// test/features/player/widgets/audio_quality_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_quality_sheet.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'player_sheet_test_support.dart';

const _usbDevice = AudioDeviceEntry(
  id: 1,
  name: 'USB DAC',
  type: 11,
  typeName: 'USB Device',
  isCurrent: false,
);

const _usbOutput = AudioOutputInfo(
  deviceName: 'USB DAC',
  isUsbDac: true,
  sampleRate: 96000,
  bitDepth: 24,
  isBitPerfectActive: false,
  availableDevices: [_usbDevice],
  supportedSampleRates: [44100, 48000, 96000],
  targetSampleRate: 0,
  targetBitDepth: 0,
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

/// Hosts the sheet above a two-route navigator so `Navigator.pop()` has a
/// route to return to.
Widget qualityHost({
  required SettingsCubit? settings,
  required PlayerCubit player,
  required WidgetBuilder sheetBuilder,
}) {
  return MaterialApp(
    theme: AuraTheme.darkTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<PlayerCubit>.value(value: player),
        if (settings != null)
          BlocProvider<SettingsCubit>.value(value: settings),
      ],
      child: Navigator(
        onGenerateInitialRoutes: (_, __) => [
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: SizedBox.shrink()),
          ),
          MaterialPageRoute<void>(builder: sheetBuilder),
        ],
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(YtmAudioQuality.high);
  });

  group('AudioQualitySheet', () {
    testWidgets('renders a local track with the unverified route fallback',
        (tester) async {
      final player = stubPlayerCubit();
      final settings = stubSettingsCubit();

      await tester.pumpWidget(sheetHost(
        playerCubit: player,
        settingsCubit: settings,
        child: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
      ));
      await tester.pump();

      expect(find.byType(AudioQualitySheet), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      // No streaming selector for a local track.
      expect(find.text('Low • 64k'), findsNothing);
    });

    testWidgets('shows and applies the streaming quality selector for YouTube',
        (tester) async {
      final player = stubPlayerCubit();
      final settings = stubSettingsCubit();
      when(() => settings.setStreamingQuality(any()))
          .thenAnswer((_) async {});

      await tester.pumpWidget(sheetHost(
        playerCubit: player,
        settingsCubit: settings,
        child: const AudioQualitySheet(song: ytSong, activeColor: Colors.teal),
      ));
      await tester.pump();

      expect(find.text('High • 160k'), findsOneWidget);
      await tester.tap(find.text('Low • 64k'));
      await tester.pump();
      verify(() => settings.setStreamingQuality(YtmAudioQuality.low)).called(1);
    });

    testWidgets('lists output devices and forwards selection', (tester) async {
      final player = stubPlayerCubit();
      final settings = stubSettingsCubit(
        state: const SettingsState().copyWith(currentOutputDevice: _usbOutput),
      );
      when(() => settings.selectOutputDevice(any()))
          .thenAnswer((_) async => true);

      await tester.pumpWidget(sheetHost(
        playerCubit: player,
        settingsCubit: settings,
        child: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
      ));
      await tester.pump();

      expect(find.text('USB DAC'), findsWidgets);
      await tester.tap(find.text('USB DAC').last);
      await tester.pump();
      verify(() => settings.selectOutputDevice(1)).called(1);
    });

    testWidgets('renders the Bluetooth codec section for an A2DP route',
        (tester) async {
      final player = stubPlayerCubit();
      final settings = stubSettingsCubit(
        state: const SettingsState().copyWith(currentOutputDevice: _btOutput),
      );
      when(() => settings.setBluetoothCodec(any()))
          .thenAnswer((_) async => true);

      await tester.pumpWidget(sheetHost(
        playerCubit: player,
        settingsCubit: settings,
        child: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
      ));
      await tester.pump();

      expect(find.text('LDAC'), findsWidgets);
      await tester.tap(find.text('SBC'));
      await tester.pump();
      verify(() => settings.setBluetoothCodec('SBC')).called(1);
    });

    testWidgets('apply button pops the sheet', (tester) async {
      final player = stubPlayerCubit();
      final settings = stubSettingsCubit();

      await tester.pumpWidget(qualityHost(
        settings: settings,
        player: player,
        sheetBuilder: (_) => const AudioQualitySheet(
          song: testSong,
          activeColor: Colors.teal,
        ),
      ));
      await tester.pump();

      expect(find.byType(AudioQualitySheet), findsOneWidget);
      final apply = find.byType(FilledButton);
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      await tester.tap(apply);
      await tester.pumpAndSettle();

      expect(find.byType(AudioQualitySheet), findsNothing);
    });
  });
}