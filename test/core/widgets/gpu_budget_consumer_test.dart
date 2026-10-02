// test/core/widgets/gpu_budget_consumer_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/performance/gpu_budget.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/glass_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => GpuBudget.setEnabled(false));

  Widget harness() => MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: GpuBudget.enabled,
            builder: (context, _, __) => GlassContainer(
              enableBlur: true,
              child: const SizedBox(width: 120, height: 48),
            ),
          ),
        ),
      );

  testWidgets(
      'toggling GpuBudget.isEnabled drops the BackdropFilter in GlassContainer',
      (tester) async {
    GpuBudget.setEnabled(false);
    expect(GpuBudget.isGpuSaverActive, isFalse);
    await tester.pumpWidget(harness());
    expect(find.byType(BackdropFilter), findsOneWidget);

    GpuBudget.setEnabled(true);
    expect(GpuBudget.isEnabled, isTrue);
    await tester.pump();
    expect(find.byType(BackdropFilter), findsNothing);

    GpuBudget.setEnabled(false);
    await tester.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
