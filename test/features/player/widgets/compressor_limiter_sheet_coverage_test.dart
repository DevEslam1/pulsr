// test/features/player/widgets/compressor_limiter_sheet_coverage_test.dart
//
// Extra branch coverage for [CompressorLimiterSheet] beyond the base suite:
// the lifecycle re-sync paths (didUpdateWidget and the PlayerCubit listener)
// and the native (non-advanced) limiter branches.
//
// The advanced multiband branch remains unreachable: its ExpansionTiles render
// ListTiles inside a decorated (colored) Container, so Flutter's debug-only
// "ListTile background color or ink splashes may be invisible" assertion fires
// during build and cannot be satisfied from a test without editing lib/.
import 'dart:async';

import 'package:flutter/material.dart';
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

  Future<void> pumpSheet(
      WidgetTester tester, FakeEqualizerManager manager,
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

    final threshold =
        tester.widgetList<Slider>(find.byType(Slider)).first;
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

    final threshold =
        tester.widgetList<Slider>(find.byType(Slider)).first;
    expect(threshold.value, closeTo(-12.0, 0.001));
  });

  testWidgets('native mode reset icon restores a single parameter default',
      (tester) async {
    final manager = buildManager();
    await pumpSheet(tester, manager);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    final threshold =
        tester.widgetList<Slider>(find.byType(Slider)).first;
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
}