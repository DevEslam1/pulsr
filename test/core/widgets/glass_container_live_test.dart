import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/performance/gpu_budget.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/glass_container.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  late _MockSettingsCubit settings;
  late StreamController<SettingsState> controller;

  setUp(() {
    settings = _MockSettingsCubit();
    controller = StreamController<SettingsState>.broadcast();
    when(() => settings.stream).thenAnswer((_) => controller.stream);
  });

  tearDown(() async {
    await controller.close();
  });

  Widget buildApp({
    required SettingsState initial,
    bool highContrast = false,
  }) {
    when(() => settings.state).thenReturn(initial);
    return MediaQuery(
      data: MediaQueryData(highContrast: highContrast),
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        home: BlocProvider<SettingsCubit>.value(
          value: settings,
          child: const Scaffold(
            body: GlassContainer(
              blur: 16,
              child: Text('Glass'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('GlassContainer live-updates from SettingsCubit liquidGlassTint',
      (tester) async {
    await tester.pumpWidget(
      buildApp(initial: const SettingsState(liquidGlassTint: 0.8)),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);

    const zeroGlass = SettingsState(liquidGlassTint: 0.0);
    when(() => settings.state).thenReturn(zeroGlass);
    controller.add(zeroGlass);
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsNothing);

    const restored = SettingsState(liquidGlassTint: 0.6);
    when(() => settings.state).thenReturn(restored);
    controller.add(restored);
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('High contrast forces solid fallback in GlassContainer',
      (tester) async {
    await tester.pumpWidget(
      buildApp(
        initial: const SettingsState(liquidGlassTint: 0.8),
        highContrast: true,
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('GPU saver forces solid fallback in GlassContainer',
      (tester) async {
    GpuBudget.setEnabled(true);
    addTearDown(() => GpuBudget.setEnabled(false));

    await tester.pumpWidget(
      buildApp(initial: const SettingsState(liquidGlassTint: 0.8)),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
