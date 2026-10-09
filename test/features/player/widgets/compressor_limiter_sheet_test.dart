// test/features/player/widgets/compressor_limiter_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/features/player/presentation/widgets/compressor_limiter_sheet.dart';

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

  Future<void> pumpSheet(
      WidgetTester tester, FakeEqualizerManager manager) async {
    await tester.pumpWidget(sheetHost(
      playerCubit: stubPlayerCubit(),
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
  });
}