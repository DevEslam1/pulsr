// Covers lib/features/settings/presentation/widgets/usb_dac_section.dart:
// non-attached short-circuit, disabled (no UAC volume) rendering, the hardware
// volume slider commit, permission grant/deny on enable, exclusive claim and
// the bit-perfect streaming start/failure paths.
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/usb_dac_section.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'support/settings_section_harness.dart';

import 'package:pulsr/core/errors/app_error.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';
class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockSettingsCubit cubit;
  late MockPlayerCubit player;
  late Map<String, dynamic> status;
  late List<bool> hwVolumeCalls;
  late bool grantPermission;
  late bool refuseStreaming;
  final List<MethodCall> usbCalls = [];
  final List<MethodCall> dacCalls = [];
  final List<bool> modeRequests = [];
  Map<String, dynamic>? uac2Range;
  Object? uac2Volume;

  const usbChannel = MethodChannel(PulsrChannels.usbExclusive);
  const usbEvents = MethodChannel(PulsrChannels.usbExclusiveEvents);
  const hiresChannel = MethodChannel(PulsrChannels.hiresDac);

  Map<String, dynamic> attachedStatus({
    bool permitted = true,
    bool hasVolumeControl = true,
    bool exclusiveSupported = true,
    bool exclusiveActive = false,
    bool streamingSupported = true,
    bool streamingActive = false,
  }) =>
      <String, dynamic>{
        'attached': true,
        'permitted': permitted,
        'deviceName': 'Test DAC',
        'uacVersion': 2,
        'uacLabel': 'UAC2',
        'hasVolumeControl': hasVolumeControl,
        'exclusiveActive': exclusiveActive,
        'exclusiveSupported': exclusiveSupported,
        'hardwareVolumeDb': -10.0,
        'minVolumeDb': -60.0,
        'maxVolumeDb': 0.0,
        'streamingActive': streamingActive,
        'streamingSupported': streamingSupported,
        'supportedRates': <int>[44100, 48000, 96000],
        // A start is only confirmed against the device-matched, actually
        // opened endpoint format, never against a bare boolean.
        'deviceId': 7,
        'streamingSampleRate': streamingActive ? 48000 : 0,
        'streamingBitDepth': streamingActive ? 16 : 0,
        'streamingChannels': streamingActive ? 2 : 0,
        'hardwareVolumeApplied': false,
      };

  void installChannelHandler() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(usbChannel, (call) async {
      usbCalls.add(call);
      switch (call.method) {
        case 'getStatus':
          return status;
        case 'requestPermission':
          return grantPermission;
        case 'setExclusive':
          status = {...status, 'exclusiveActive': true};
          return {'error': null};
        case 'setHardwareVolume':
          return {'error': null};
        case 'startStreaming':
          if (refuseStreaming) {
            return {'success': false, 'error': 'claim_failed'};
          }
          status = {...status, 'streamingActive': true};
          return {'success': true};
        case 'stopStreaming':
          status = {...status, 'streamingActive': false};
          return {'success': true};
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(usbEvents, (call) async => null);
    // The DAC's own UAC2 attenuator lives on the hires_dac channel. Null
    // answers keep every legacy test on the dB path it was written for.
    messenger.setMockMethodCallHandler(hiresChannel, (call) async {
      dacCalls.add(call);
      switch (call.method) {
        case 'getUac2VolumeRange':
          return uac2Range;
        case 'getUac2HardwareVolume':
          return uac2Volume;
        case 'setUac2HardwareVolume':
          return true;
        default:
          return null;
      }
    });
  }

  setUp(() {
    stubSettingsChannels();
    usbCalls.clear();
    dacCalls.clear();
    uac2Range = null;
    uac2Volume = null;
    hwVolumeCalls = [];
    grantPermission = true;
    refuseStreaming = false;
    status = attachedStatus();

    player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());

    cubit = MockSettingsCubit();
    when(() => cubit.state).thenReturn(const SettingsState());
    modeRequests.clear();
    when(() => cubit.setBitPerfectOutput(any())).thenAnswer((inv) async {
      modeRequests.add(inv.positionalArguments.first as bool);
    });
    when(() => cubit.setUsbHardwareVolumeEnabled(any()))
        .thenAnswer((inv) async {
      hwVolumeCalls.add(inv.positionalArguments.first as bool);
      return true;
    });
  });

  tearDown(() {
    clearSettingsChannels();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(usbChannel, null);
    messenger.setMockMethodCallHandler(usbEvents, null);
    messenger.setMockMethodCallHandler(hiresChannel, null);
  });

  Future<void> pump(WidgetTester tester, {SettingsState? state}) async {
    if (state != null) {
      when(() => cubit.state).thenReturn(state);
    }
    installChannelHandler();
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      BlocProvider<PlayerCubit>.value(
        value: player,
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: UsbDacSection(
                cubit: cubit,
                state: state ?? const SettingsState(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('renders nothing when no USB audio device is attached',
      (tester) async {
    status = {'attached': false};
    await pump(tester);
    expect(find.byType(Slider), findsNothing);
    expect(find.text(l10n.settingsUsbDacHardwareVolume), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a DAC without UAC volume shows the disabled reason',
      (tester) async {
    status = attachedStatus(hasVolumeControl: false);
    await pump(tester);

    expect(find.text(l10n.settingsUsbDacHardwareVolume), findsOneWidget);
    expect(find.text(l10n.settingsDacNoUacVolume), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('enabled hardware volume exposes a slider that commits on drag',
      (tester) async {
    status = attachedStatus(hasVolumeControl: true);
    await pump(
      tester,
      state: const SettingsState(usbHardwareVolumeEnabled: true),
    );

    expect(find.byType(Slider), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pump();

    expect(
      usbCalls.any((c) => c.method == 'setHardwareVolume'),
      isTrue,
      reason: 'releasing the slider must commit the hardware volume',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a reported UAC2 range drives the DAC position slider',
      (tester) async {
    uac2Range = {'minQ8': -15360, 'maxQ8': 0};
    uac2Volume = 0.5;
    await pump(
      tester,
      state: const SettingsState(usbHardwareVolumeEnabled: true),
    );

    expect(find.text(l10n.settingsUac2VolumeTitle), findsOneWidget);
    expect(find.text('50 %'), findsOneWidget);
    expect(find.text(l10n.settingsUac2VolumeDesc), findsOneWidget);

    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pump();

    expect(
      dacCalls.any((c) => c.method == 'setUac2HardwareVolume'),
      isTrue,
      reason: 'the position slider must write the DAC attenuator',
    );
    expect(
      usbCalls.any((c) => c.method == 'setHardwareVolume'),
      isFalse,
      reason: 'a dB write would move the DAC off the shown position',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a range without a readable position shows no dead slider',
      (tester) async {
    uac2Range = {'minQ8': -15360, 'maxQ8': 0};
    uac2Volume = null;
    final noSnapshotDb = attachedStatus();
    noSnapshotDb['hardwareVolumeDb'] = null;
    status = noSnapshotDb;

    await pump(
      tester,
      state: const SettingsState(usbHardwareVolumeEnabled: true),
    );

    // Neither an assumed -60 dB scale nor a guessed position is offered.
    expect(find.byType(Slider), findsNothing);
    expect(find.text(l10n.settingsUac2VolumeTitle), findsOneWidget);
    expect(find.text(l10n.settingsUac2VolumeUnsupported), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('enabling without prior permission requests and persists',
      (tester) async {
    status = attachedStatus(permitted: false);
    await pump(tester);

    await tester.tap(find.text(l10n.settingsUsbDacHardwareVolume));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      usbCalls.map((c) => c.method),
      containsAllInOrder(['getStatus', 'requestPermission', 'getStatus']),
    );
    expect(hwVolumeCalls, [true]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('denied permission surfaces a clear message', (tester) async {
    status = attachedStatus(permitted: false);
    grantPermission = false;
    await pump(tester);

    await tester.tap(find.text(l10n.settingsUsbDacHardwareVolume));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(l10n.usbPermDenied), findsOneWidget);
    expect(hwVolumeCalls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('exclusive claim toggles through the service', (tester) async {
    status = attachedStatus(exclusiveSupported: true);
    await pump(tester);

    await tester.tap(find.text(l10n.settingsExclusiveUsb));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(usbCalls.any((c) => c.method == 'setExclusive'), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('the streaming switch delegates the mode to SettingsCubit',
      (tester) async {
    status = attachedStatus(streamingSupported: true, streamingActive: false);
    await pump(tester);

    expect(find.text(l10n.settingsUsbBitPerfectStreaming), findsOneWidget);
    await tester.tap(find.text(l10n.settingsUsbBitPerfectStreaming));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(modeRequests, [true]);
    // Starting the endpoint from the widget used to bypass the DSP bypass,
    // crossfade exclusion, strict contract and rollback only the owner does.
    expect(usbCalls.where((c) => c.method == 'startStreaming'), isEmpty);
    expect(find.textContaining(l10n.usbBpFailed), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a refused mode from the owner surfaces the retry snackbar',
      (tester) async {
    status = attachedStatus(streamingSupported: true, streamingActive: false);
    await pump(tester);
    var state = const SettingsState();
    when(() => cubit.state).thenAnswer((_) => state);
    when(() => cubit.setBitPerfectOutput(true)).thenAnswer((_) async {
      modeRequests.add(true);
      state = state.copyWith(error: uiError('claim_failed'));
    });

    await tester.tap(find.text(l10n.settingsUsbBitPerfectStreaming));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining(l10n.usbBpFailed), findsOneWidget);

    // The Retry action re-runs the same owned transition. The failure banner is
    // the app's floating toast (PulsrToast), not a Material SnackBar, so the
    // action is matched by its label.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text(l10n.retry), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(modeRequests.where((v) => v).length, greaterThanOrEqualTo(2));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('disabling the owned mode goes through SettingsCubit too',
      (tester) async {
    status = attachedStatus(streamingSupported: true, streamingActive: true);
    await pump(tester, state: const SettingsState(bitPerfectOutput: true));
    await tester.pump();

    await tester.tap(find.text(l10n.settingsUsbBitPerfectStreaming));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(modeRequests, [false]);
    expect(usbCalls.where((c) => c.method == 'stopStreaming'), isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'active direct stream displays rate/depth telemetry and locks exclusive toggle',
      (tester) async {
    status = {
      ...attachedStatus(
        exclusiveSupported: true,
        exclusiveActive: true,
        streamingSupported: true,
        streamingActive: true,
      ),
      'streamingSampleRate': 96000,
      'streamingBitDepth': 24,
      'rateVerified': true,
    };
    await pump(tester, state: const SettingsState(bitPerfectOutput: true));
    await tester.pump();

    expect(find.textContaining('96 kHz'), findsOneWidget);
    expect(find.textContaining('24-bit'), findsOneWidget);
    expect(find.textContaining('Clock verified'), findsOneWidget);

    await tester.tap(find.text(l10n.settingsExclusiveUsb));
    await tester.pump();
    expect(usbCalls.where((c) => c.method == 'setExclusive'), isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
