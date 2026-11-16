// test/features/player/widgets/compressor_limiter_sheet_test.dart
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/compressor_limiter_sheet.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

import 'player_sheet_test_support.dart';

/// Real [EqualizerManager] with the capability getters forced. The DSP setters
/// live in extensions, which a mocktail Mock cannot intercept (extension
/// dispatch is static), so we assert on the manager's public state instead of
/// verifying mock calls.
///
/// Only the non-advanced mode is exercised: the advanced branch renders
/// [ExpansionTile]s inside a decorated container, which trips a Flutter
/// debug-only ListTile ink-splash assertion that cannot be fixed from a test.
class FakeEqualizerManager extends EqualizerManager {
  FakeEqualizerManager({required this.advanced});

  final bool advanced;

  @override
  bool get isCompressorAdvancedParamsSupported => advanced;

  @override
  bool get isDynamicsSupported => advanced;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      (call) async => true,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects), null);
  });

  FakeEqualizerManager buildManager() {
    final manager = FakeEqualizerManager(advanced: false);
    addTearDown(manager.dispose);
    return manager;
  }

  MockPlayerCubit wiredCubitFor(
    FakeEqualizerManager manager, {
    bool bitPerfect = false,
  }) {
    final settings = stubSettingsCubit(
      state: bitPerfect
          ? const SettingsState(
              bitPerfectOutput: true,
              bypassDspOnBitPerfect: true,
              currentOutputDevice: AudioOutputInfo(
                deviceName: 'USB DAC',
                isUsbDac: true,
                sampleRate: 96000,
                pcmEncoding: 2,
                bitDepth: 24,
                isBitPerfectActive: true,
                isBitPerfectSupported: true,
              ),
            )
          : const SettingsState(),
    );
    var state = const PlayerState();
    final streamCtrl = StreamController<PlayerState>.broadcast();
    addTearDown(streamCtrl.close);
    final handler = _FakeDspAudioHandler(manager);
    final dspController = PlayerDspController(
      audioHandler: handler,
      settingsCubit: settings,
      getState: () => state,
      emit: (s) {
        state = s;
        if (!streamCtrl.isClosed) streamCtrl.add(s);
      },
      syncAudioEffects: ({bool force = false}) {},
      isClosed: () => false,
    );

    final cubit = stubPlayerCubit(state: state);
    when(() => cubit.state).thenAnswer((_) => state);
    when(() => cubit.stream).thenAnswer((_) => streamCtrl.stream);
    when(() => cubit.setLookaheadLimiter(
          any(),
          thresholdDb: any(named: 'thresholdDb'),
          releaseMs: any(named: 'releaseMs'),
        )).thenAnswer((inv) async {
      await dspController.setLookaheadLimiter(
        inv.positionalArguments[0] as bool,
        thresholdDb: inv.namedArguments[#thresholdDb] as double?,
        releaseMs: inv.namedArguments[#releaseMs] as double?,
      );
    });
    when(() => cubit.setCompressorParams(
          thresholdDb: any(named: 'thresholdDb'),
          ratio: any(named: 'ratio'),
          attackMs: any(named: 'attackMs'),
          releaseMs: any(named: 'releaseMs'),
          makeupGainDb: any(named: 'makeupGainDb'),
        )).thenAnswer((inv) => dspController.setCompressorParams(
          thresholdDb: inv.namedArguments[#thresholdDb] as double?,
          ratio: inv.namedArguments[#ratio] as double?,
          attackMs: inv.namedArguments[#attackMs] as double?,
          releaseMs: inv.namedArguments[#releaseMs] as double?,
          makeupGainDb: inv.namedArguments[#makeupGainDb] as double?,
        ));
    when(() => cubit.setMultibandCompressor(
          any(),
          f0: any(named: 'f0'),
          f1: any(named: 'f1'),
          f2: any(named: 'f2'),
        )).thenAnswer((inv) => dspController.setMultibandCompressor(
          inv.positionalArguments[0] as bool,
          f0: inv.namedArguments[#f0] as double?,
          f1: inv.namedArguments[#f1] as double?,
          f2: inv.namedArguments[#f2] as double?,
        ));
    when(() => cubit.setMultibandCompressorBand(any(), any())).thenAnswer(
      (inv) => dspController.setMultibandCompressorBand(
        inv.positionalArguments[0] as int,
        inv.positionalArguments[1] as dynamic,
      ),
    );
    return cubit;
  }

  Future<void> pumpSheet(
    WidgetTester tester,
    FakeEqualizerManager manager, {
    PlayerCubit? cubit,
  }) async {
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit ?? wiredCubitFor(manager),
      child: CompressorLimiterSheet(equalizerManager: manager),
    ));
    await tester.pumpAndSettle();
  }

  group('CompressorLimiterSheet', () {
    testWidgets('renders limiter controls in the unsupported (native) mode',
        (tester) async {
      final manager = buildManager();
      await pumpSheet(tester, manager);

      expect(find.byType(CompressorLimiterSheet), findsOneWidget);
      expect(find.byType(Slider), findsWidgets);
      // Only the limiter switch remains when advanced params are unsupported.
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
    });

    testWidgets('toggling the limiter forwards to the manager', (tester) async {
      final manager = buildManager();
      await pumpSheet(tester, manager);
      expect(manager.isLimiterEnabled, isFalse);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(manager.isLimiterEnabled, isTrue);
    });

    testWidgets('dragging enabled sliders applies compressor params',
        (tester) async {
      final manager = buildManager();
      await pumpSheet(tester, manager);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      // Threshold and release are enabled; ratio/attack/makeup stay disabled.
      final enabled = sliders.where((s) => s.onChanged != null).toList();
      expect(enabled.length, greaterThanOrEqualTo(2));
      for (final slider in enabled) {
        slider.onChanged!(slider.min);
      }
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));

      expect(manager.limiterThresholdDb, -30.0);
    });

    testWidgets('reset button restores studio defaults', (tester) async {
      final manager = buildManager();
      await pumpSheet(tester, manager);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      final thresholdSlider =
          tester.widgetList<Slider>(find.byType(Slider)).first;
      thresholdSlider.onChanged!(thresholdSlider.min);
      await tester.pumpAndSettle();
      expect(manager.limiterThresholdDb, -30.0);

      final reset = find.byType(OutlinedButton);
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();

      expect(manager.limiterThresholdDb, -0.2);
    });

    testWidgets('static show opens the sheet in a modal route', (tester) async {
      final manager = buildManager();
      await tester.pumpWidget(sheetHost(
        playerCubit: stubPlayerCubit(),
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () =>
                CompressorLimiterSheet.show(ctx, equalizerManager: manager),
            child: const Text('open-compressor'),
          ),
        ),
      ));

      await tester.tap(find.text('open-compressor'));
      await tester.pumpAndSettle();

      expect(find.byType(CompressorLimiterSheet), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets(
        'P3-25: writes go exclusively through PlayerCubit with single native call per change',
        (tester) async {
      final recordedCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects),
        (call) async {
          recordedCalls.add(call);
          return true;
        },
      );

      final manager = buildManager();
      final cubit = wiredCubitFor(manager);
      await pumpSheet(tester, manager, cubit: cubit);

      recordedCalls.clear();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      // Enable invokes setLimiterParams once + setLimiterEnabled once (no 3x fan-out).
      expect(
        recordedCalls.where((c) => c.method == 'setLimiterParams').length,
        equals(1),
      );

      recordedCalls.clear();
      final thresholdSlider =
          tester.widgetList<Slider>(find.byType(Slider)).first;
      thresholdSlider.onChanged!(thresholdSlider.min);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        recordedCalls.where((c) => c.method == 'setLimiterParams').length,
        equals(1),
        reason: 'Slider change must emit a single native setLimiterParams call',
      );
      expect(manager.limiterThresholdDb, -30.0);
    });

    testWidgets(
        'P3-25: refuses limiter toggle cleanly when bit-perfect guard blocks DSP writes',
        (tester) async {
      final recordedCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects),
        (call) async {
          recordedCalls.add(call);
          return true;
        },
      );

      final manager = buildManager();
      final cubit = wiredCubitFor(manager, bitPerfect: true);
      await pumpSheet(tester, manager, cubit: cubit);
      recordedCalls.clear();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // Bit-perfect guard must block both native writes and revert the switch.
      expect(manager.isLimiterEnabled, isFalse);
      expect(
        recordedCalls.where((c) => c.method == 'setLimiterEnabled'),
        isEmpty,
      );
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    });
  });
}

class _FakeDspAudioHandler extends BaseAudioHandler
    implements PulsrAudioHandler {
  _FakeDspAudioHandler(this._manager);
  final EqualizerManager _manager;

  @override
  EqualizerManager get equalizerManager => _manager;

  @override
  Future<void> setLookaheadLimiter(
    bool enabled, {
    double? thresholdDb,
    double? releaseMs,
    double? lookaheadMs,
  }) =>
      _manager.setLookaheadLimiter(
        enabled,
        thresholdDb: thresholdDb,
        releaseMs: releaseMs,
        lookaheadMs: lookaheadMs,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
