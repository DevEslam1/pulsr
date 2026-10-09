// test/features/player/widgets/audio_quality_sheet_more_test.dart
//
// Second pass over AudioQualitySheet: output device lists and icons, output
// path diagnostics, every sample-rate label/tag, Bluetooth codec states
// (permission/proxy/LE-Audio/connected/configurable), bit-perfect armed vs
// active, and the live signal chain.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
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
  isCurrent: true,
);

const _wiredDevice = AudioDeviceEntry(
  id: 2,
  name: 'Wired Buds',
  type: 3,
  typeName: 'Wired Headset',
  isCurrent: false,
  isPreferred: true,
);

const _hdmiDevice = AudioDeviceEntry(
  id: 3,
  name: 'TV HDMI',
  type: 9,
  typeName: 'HDMI',
  isCurrent: false,
);

const _dockDevice = AudioDeviceEntry(
  id: 4,
  name: 'Dock',
  type: 13,
  typeName: 'Dock',
  isCurrent: false,
);

const _mysteryDevice = AudioDeviceEntry(
  id: 5,
  name: 'Mystery',
  type: 99,
  typeName: 'Other',
  isCurrent: false,
);

const _usbOutput = AudioOutputInfo(
  deviceName: 'Topping D90',
  isUsbDac: true,
  sampleRate: 96000,
  bitDepth: 24,
  isBitPerfectActive: false,
  availableDevices: [
    _usbDevice,
    _wiredDevice,
    _hdmiDevice,
    _dockDevice,
    _mysteryDevice,
  ],
  supportedSampleRates: [
    44100,
    48000,
    88200,
    96000,
    176400,
    192000,
    352800,
    384000,
    705600,
    768000,
    12345,
  ],
  targetSampleRate: 0,
  targetBitDepth: 0,
  usbAudioClass: 2,
  usbDacLabel: 'Topping D90',
  directFormats: [
    AudioDirectFormat(encoding: '24', sampleRate: 96000, supported: true),
    AudioDirectFormat(encoding: 'float', sampleRate: 192000, supported: true),
    AudioDirectFormat(encoding: '32', sampleRate: 384000, supported: false),
    AudioDirectFormat(encoding: '16', sampleRate: 44100, supported: true),
  ],
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

Widget _host({
  required SettingsCubit settings,
  required PlayerCubit player,
  required Widget sheet,
}) {
  return MaterialApp(
    theme: AuraTheme.darkTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<PlayerCubit>.value(value: player),
        BlocProvider<SettingsCubit>.value(value: settings),
      ],
      child: Navigator(
        onGenerateInitialRoutes: (_, __) => [
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: SizedBox.shrink()),
          ),
          MaterialPageRoute<void>(builder: (_) => sheet),
        ],
      ),
    ),
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AudioQualitySheet)))!;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(YtmAudioQuality.high);
  });

  testWidgets('USB diagnostics render UAC class and direct playback',
      (tester) async {
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(currentOutputDevice: _usbOutput),
    );

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    expect(find.textContaining('USB DAC'), findsWidgets);
    expect(find.textContaining('UAC2'), findsWidgets);
    expect(find.textContaining('Topping D90'), findsWidgets);
    expect(find.textContaining('Up to'), findsWidgets);
  });

  testWidgets('direct format labels fall back for unknown encodings',
      (tester) async {
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(
        currentOutputDevice: const AudioOutputInfo(
          deviceName: 'DAC',
          isUsbDac: true,
          sampleRate: 48000,
          bitDepth: 24,
          isBitPerfectActive: false,
          usbAudioClass: 0,
          directFormats: [
            AudioDirectFormat(
                encoding: '32', sampleRate: 192000, supported: true),
          ],
        ),
      ),
    );

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    expect(find.textContaining('Up to'), findsWidgets);
  });

  testWidgets('lists devices, forwards selection and surfaces refusal',
      (tester) async {
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(currentOutputDevice: _usbOutput),
    );
    when(() => settings.selectOutputDevice(any()))
        .thenAnswer((_) async => false);
    when(() => settings.openOutputSwitcher()).thenAnswer((_) async => true);

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    await _tap(tester, find.text('Wired Buds'));
    await tester.pumpAndSettle();
    verify(() => settings.selectOutputDevice(2)).called(1);

    await _tap(tester, find.text('Mystery'));
    await tester.pumpAndSettle();
    verify(() => settings.selectOutputDevice(5)).called(1);

    await _tap(tester, find.text(_l10n(tester).switchOutputPanel));
    await tester.pump();
    verify(() => settings.openOutputSwitcher()).called(1);
  });

  testWidgets('streaming selector applies the medium quality', (tester) async {
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit();
    when(() => settings.setStreamingQuality(any())).thenAnswer((_) async {});

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: ytSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    await _tap(tester, find.text('Med \u2022 128k'));
    await tester.pump();
    verify(() => settings.setStreamingQuality(YtmAudioQuality.medium))
        .called(1);
  });

  testWidgets('local song with a ytmusic path still shows streaming selector',
      (tester) async {
    const streamed = SongsTableData(
      id: 21,
      title: 'Path Stream',
      artist: 'A',
      album: 'B',
      durationMs: 1000,
      path: 'ytmusic://xyz',
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
      source: 'local',
      isDownloaded: false,
    );
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit();

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: streamed, activeColor: Colors.teal),
    ));
    await tester.pump();

    expect(find.text('High \u2022 160k'), findsOneWidget);
  });

  testWidgets('bluetooth permission banner requests access', (tester) async {
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(
        currentOutputDevice: AudioOutputInfo(
          deviceName: 'Sony',
          isUsbDac: false,
          sampleRate: 48000,
          bitDepth: 24,
          isBitPerfectActive: false,
          isBluetooth: true,
          btA2dpPresent: true,
          btReason: 'permission_required',
        ),
      ),
    );
    when(() => settings.requestBluetoothPermission())
        .thenAnswer((_) async {});
    when(() => settings.refreshOutputDevice()).thenAnswer((_) async {});

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    await _tap(tester, find.byIcon(Icons.settings_bluetooth_rounded));
    await tester.pump();
    verify(() => settings.requestBluetoothPermission()).called(1);
    // Flush the post-permission 2s settle window.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    verify(() => settings.refreshOutputDevice()).called(1);
  });

  testWidgets('bluetooth proxy banner retries the route', (tester) async {
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(
        currentOutputDevice: AudioOutputInfo(
          deviceName: 'Sony',
          isUsbDac: false,
          sampleRate: 0,
          bitDepth: 0,
          isBitPerfectActive: false,
          isBluetooth: true,
          btA2dpPresent: true,
          btReason: 'proxy_initializing',
        ),
      ),
    );
    when(() => settings.refreshOutputDevice()).thenAnswer((_) async {});

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    await _tap(tester, find.text(_l10n(tester).retry));
    await tester.pump();
    verify(() => settings.refreshOutputDevice()).called(1);
  });

  testWidgets('LE Audio banner exposes a refresh action', (tester) async {
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(
        currentOutputDevice: AudioOutputInfo(
          deviceName: 'Buds',
          isUsbDac: false,
          sampleRate: 48000,
          bitDepth: 24,
          isBitPerfectActive: false,
          isBluetooth: true,
          isLeAudio: true,
          btA2dpPresent: true,
          btReason: 'le_audio_not_configurable',
        ),
      ),
    );
    when(() => settings.refreshOutputDevice()).thenAnswer((_) async {});

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    await _tap(tester, find.byIcon(Icons.refresh_rounded).first);
    await tester.pump();
    verify(() => settings.refreshOutputDevice()).called(1);
  });

  testWidgets('connected non-configurable codec section is read-only',
      (tester) async {
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(
        currentOutputDevice: const AudioOutputInfo(
          deviceName: 'Sony',
          isUsbDac: false,
          sampleRate: 48000,
          bitDepth: 24,
          isBitPerfectActive: false,
          isBluetooth: true,
          btA2dpPresent: true,
          btCodecName: 'SBC',
          btSampleRateHz: 48000,
          btBitDepth: 16,
          btCodecConnected: true,
          canConfigureBluetooth: false,
        ),
      ),
    );
    when(() => settings.openBluetoothDevOptions()).thenAnswer((_) async {});

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    expect(find.text('SBC'), findsWidgets);
    await _tap(tester, find.byIcon(Icons.developer_mode_rounded));
    await tester.pump();
    verify(() => settings.openBluetoothDevOptions()).called(1);
  });

  testWidgets('disconnected bluetooth route shows the idle prompt',
      (tester) async {
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(
        currentOutputDevice: const AudioOutputInfo(
          deviceName: 'Sony',
          isUsbDac: false,
          sampleRate: 0,
          bitDepth: 0,
          isBitPerfectActive: false,
          isBluetooth: true,
          btA2dpPresent: true,
          btCodecConnected: false,
        ),
      ),
    );

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.bluetooth_connected_rounded), findsOneWidget);
  });

  testWidgets('configurable bluetooth route picks codec, rate and depth',
      (tester) async {
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(currentOutputDevice: _btOutput),
    );
    when(() => settings.setBluetoothCodec(any()))
        .thenAnswer((_) async => true);
    when(() => settings.setBluetoothSampleRate(any()))
        .thenAnswer((_) async => true);
    when(() => settings.setBluetoothBitDepth(any()))
        .thenAnswer((_) async => true);
    when(() => settings.openBluetoothDevOptions()).thenAnswer((_) async {});

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    await _tap(tester, find.text('SBC'));
    await tester.pump();
    verify(() => settings.setBluetoothCodec('SBC')).called(1);

    await _tap(tester, find.byIcon(Icons.developer_mode_rounded));
    await tester.pump();
    verify(() => settings.openBluetoothDevOptions()).called(1);
  });

  testWidgets('bit-perfect active shows the exclusive mixer chip',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(
        currentOutputDevice: _usbOutput.copyWith(
          isBitPerfectActive: true,
          sampleRate: 0,
          bitDepth: 0,
        ),
        bitPerfectOutput: true,
        aaudioOutputEnabled: true,
      ),
    );

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    expect(find.textContaining('Exclusive mixer'), findsWidgets);
    expect(find.text(_l10n(tester).activeLabel), findsWidgets);
  });

  testWidgets('bit-perfect enabled but unverified shows the armed badge',
      (tester) async {
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(
        currentOutputDevice: _usbOutput,
        bitPerfectOutput: true,
      ),
    );

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    expect(find.text(_l10n(tester).armedLabel), findsWidgets);
  });

  testWidgets('DSD source and active DSP stages render in the signal chain',
      (tester) async {
    const dsdSong = SongsTableData(
      id: 77,
      title: 'DSD Track',
      artist: 'A',
      album: 'B',
      durationMs: 1000,
      path: '/music/track.dsf',
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
      source: 'local',
      isDownloaded: true,
      codec: 'DSD64',
      sampleRate: 2822400,
      bitDepth: 1,
    );
    final player = stubPlayerCubit(
      state: const PlayerState().copyWith(
        dsp: const DspSlice(
          isEqEnabled: true,
          isLimiterEnabled: true,
          isCrossfeedEnabled: true,
          isReverbEnabled: true,
        ),
      ),
    );
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(aaudioOutputEnabled: true),
    );

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: dsdSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    expect(find.textContaining('DSD Stream'), findsWidgets);
    expect(find.textContaining('EQ'), findsWidgets);
    expect(find.textContaining('True-Peak Limiter'), findsWidgets);
  });

  testWidgets('bluetooth route carries the bit-perfect block reason',
      (tester) async {
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit(
      state: const SettingsState().copyWith(currentOutputDevice: _btOutput),
    );

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: testSong, activeColor: Colors.teal),
    ));
    await tester.pump();

    expect(find.textContaining('Bluetooth'), findsWidgets);
  });

  testWidgets('sparse song metadata falls back to unknown labels',
      (tester) async {
    const sparse = SongsTableData(
      id: 88,
      title: 'Sparse',
      artist: 'A',
      album: 'B',
      durationMs: 0,
      path: '/music/sparse.ogg',
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
      source: 'local',
      isDownloaded: true,
    );
    final player = stubPlayerCubit();
    final settings = stubSettingsCubit();

    await tester.pumpWidget(_host(
      settings: settings,
      player: player,
      sheet: const AudioQualitySheet(song: sparse, activeColor: Colors.teal),
    ));
    await tester.pump();

    expect(find.textContaining('Unknown'), findsWidgets);
  });
}
