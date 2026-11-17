// test/features/player/widgets/compressor_limiter_sheet_coverage_test.dart
//
// Extra branch coverage for [CompressorLimiterSheet] beyond the base suite:
// the lifecycle re-sync paths (didUpdateWidget and the PlayerCubit listener),
// the native (non-advanced) limiter branches, and the drift guards that keep
// the sheet on the manager's values after a rejected write.
//
// The advanced multiband branch remains unreachable: its ExpansionTiles render
// ListTiles inside a decorated (colored) Container, so Flutter's debug-only
// "ListTile background color or ink splashes may be invisible" assertion fires
// during build and cannot be satisfied from a test without editing lib/.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/compressor_limiter_sheet.dart';

import 'player_sheet_test_support.dart';

class FakeEqualizerManager extends EqualizerManager {
  FakeEqualizerManager({required this.advanced});

  final bool advanced;

  @override
  bool get isCompressorAdvancedParamsSupported => advanced;

  @override
  bool get isDynamicsSupported => advanced;
}

class StreamingPlayerCubit extends MockPlayerCubit {
  StreamingPlayerCubit() {
    when(() => state).thenReturn(const PlayerState());
  }

  final controller = StreamController<PlayerState>.broadcast();

  @override
  Stream<PlayerState> get stream => controller.stream;
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

  FakeEqualizerManager buildManager({bool advanced = false}) {
    final manager = FakeEqualizerManager(advanced: advanced);
    addTearDown(manager.dispose);
    return manager;
  }

  Future<void> pumpSheet(WidgetTester tester, FakeEqualizerManager manager,
      {PlayerCubit? cubit}) async {
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit ?? stubPlayerCubit(),
      child: CompressorLimiterSheet(equalizerManager: manager),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('didUpdateWidget re-syncs when the manager instance changes',
      (tester) async {
    final first = buildManager();
    await pumpSheet(tester, first);
    expect(first.isLimiterEnabled, isFalse);

    final second = buildManager();
    second.isLimiterEnabled = true;
    second.limiterThresholdDb = -7.5;

    // Rebuild with the replacement manager: the sheet must reflect its state.
    await tester.pumpWidget(sheetHost(
      playerCubit: stubPlayerCubit(),
      child: CompressorLimiterSheet(equalizerManager: second),
    ));
    await tester.pumpAndSettle();

    final threshold = tester.widgetList<Slider>(find.byType(Slider)).first;
    expect(threshold.value, closeTo(-7.5, 0.001));
    // Limiter is now on, so the threshold slider is enabled.
    final resetIcons = find.byIcon(Icons.settings_backup_restore);
    expect(resetIcons, findsWidgets);
  });

  testWidgets('a PlayerState emission re-syncs the toggles', (tester) async {
    final cubit = StreamingPlayerCubit();
    addTearDown(cubit.controller.close);
    final manager = buildManager();
    await pumpSheet(tester, manager, cubit: cubit);

    // Turning the limiter on externally + notifying through the cubit stream
    // exercises the BlocListener -> _syncFromManager path.
    manager.isLimiterEnabled = true;
    manager.limiterThresholdDb = -12.0;
    cubit.controller
        .add(const PlayerState(dsp: DspSlice(isLimiterEnabled: true)));
    await tester.pumpAndSettle();

    final threshold = tester.widgetList<Slider>(find.byType(Slider)).first;
    expect(threshold.value, closeTo(-12.0, 0.001));
  });

  testWidgets('native mode reset icon restores a single parameter default',
      (tester) async {
    final manager = buildManager();
    var currentState = const PlayerState();
    final cubit = stubPlayerCubit();
    when(() => cubit.state).thenAnswer((_) => currentState);
    when(() => cubit.setLookaheadLimiter(
          any(),
          thresholdDb: any(named: 'thresholdDb'),
          releaseMs: any(named: 'releaseMs'),
        )).thenAnswer((inv) async {
      final enabled = inv.positionalArguments[0] as bool;
      final thresholdDb = inv.namedArguments[#thresholdDb] as double?;
      final releaseMs = inv.namedArguments[#releaseMs] as double?;
      currentState = currentState.copyWith(
        dsp: currentState.dsp.copyWith(
          isLimiterEnabled: enabled,
          limiterThresholdDb:
              thresholdDb ?? currentState.dsp.limiterThresholdDb,
          limiterReleaseMs: releaseMs ?? currentState.dsp.limiterReleaseMs,
        ),
      );
      await manager.setLookaheadLimiter(
        enabled,
        thresholdDb: thresholdDb,
        releaseMs: releaseMs,
      );
      return;
    });
    await pumpSheet(tester, manager, cubit: cubit);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    final threshold = tester.widgetList<Slider>(find.byType(Slider)).first;
    threshold.onChanged!(threshold.min);
    await tester.pumpAndSettle();
    expect(manager.limiterThresholdDb, -30.0);

    // The per-parameter reset icon (not the big reset button) restores -0.2.
    final icon = find.byIcon(Icons.settings_backup_restore).first;
    await tester.ensureVisible(icon);
    await tester.pumpAndSettle();
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(manager.limiterThresholdDb, -0.2);
  });

  group('drift guards (EqualizerManager is the source of truth)', () {
    testWidgets(
        'a refused write leaves the manager value on screen, not the dragged one',
        (tester) async {
      final manager = buildManager();
      manager.isLimiterEnabled = true;
      manager.limiterThresholdDb = -3.0;

      // The cubit state claims the write landed at -30 dB while the manager
      // still holds -3 dB, because the write below is a no-op (guard block or
      // rollback). Trusting either a local shadow or the cubit state is the
      // drift this sheet must not reproduce.
      final cubit = stubPlayerCubit(
        state: const PlayerState(
          dsp: DspSlice(isLimiterEnabled: true, limiterThresholdDb: -30.0),
        ),
      );
      await pumpSheet(tester, manager, cubit: cubit);
      expect(find.text('-3.0 dB'), findsOneWidget);

      final threshold = tester
          .widgetList<Slider>(find.byType(Slider))
          .firstWhere((s) => s.onChangeEnd != null);
      threshold.onChangeEnd!(threshold.min);
      await tester.pumpAndSettle();

      // The rejected value must not survive anywhere in the UI.
      expect(manager.limiterThresholdDb, -3.0);
      expect(find.text('-3.0 dB'), findsOneWidget);
      expect(find.text('-30.0 dB'), findsNothing);
      final after = tester
          .widgetList<Slider>(find.byType(Slider))
          .firstWhere((s) => s.onChangeEnd != null);
      expect(after.value, closeTo(-3.0, 0.001));
    });

    testWidgets('a throwing cubit write also reconciles to the manager value',
        (tester) async {
      final manager = buildManager();
      manager.isLimiterEnabled = true;
      manager.limiterReleaseMs = 50.0;

      final cubit = stubPlayerCubit();
      when(() => cubit.setLookaheadLimiter(
            any(),
            thresholdDb: any(named: 'thresholdDb'),
            releaseMs: any(named: 'releaseMs'),
          )).thenThrow(Exception('native write rejected'));
      await pumpSheet(tester, manager, cubit: cubit);

      final release = tester
          .widgetList<Slider>(find.byType(Slider))
          .firstWhere((s) => s.onChangeEnd != null && s.min == 10.0);
      release.onChangeEnd!(release.min);
      await tester.pumpAndSettle();

      expect(manager.limiterReleaseMs, 50.0);
      expect(find.text('50 ms'), findsOneWidget);
      expect(find.text('10 ms'), findsNothing);
    });

    testWidgets('reopening after an external manager change shows new values',
        (tester) async {
      final manager = buildManager();
      manager.isLimiterEnabled = true;
      manager.limiterThresholdDb = -6.0;
      final cubit = stubPlayerCubit();
      await pumpSheet(tester, manager, cubit: cubit);
      expect(find.text('-6.0 dB'), findsOneWidget);

      // Another screen (or a profile restore) moves the manager while the
      // sheet is closed; a fresh sheet must not reuse the previous snapshot.
      manager.limiterThresholdDb = -18.5;
      manager.isLimiterEnabled = false;
      await tester.pumpWidget(const SizedBox());

      await pumpSheet(tester, manager, cubit: cubit);
      expect(find.text('-18.5 dB'), findsOneWidget);
      expect(find.text('-6.0 dB'), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    });
  });
}
