// test/features/player/widgets/arbitrary_eq_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/arbitrary_eq_sheet.dart';

import 'player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MockPlayerCubit buildCubit({String eqString = '', bool linearPhase = false}) {
    final cubit = stubPlayerCubit(
      state: PlayerState(dsp: DspSlice(arbitraryEqString: eqString)),
    );
    when(() => cubit.isArbitraryEqLinearPhase).thenReturn(linearPhase);
    when(() => cubit.setArbitraryEqEnabled(
          any(),
          eqString: any(named: 'eqString'),
          linearPhase: any(named: 'linearPhase'),
        )).thenAnswer((_) async {});
    return cubit;
  }

  testWidgets('renders, applies, toggles linear phase and selects presets',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = buildCubit();

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      child: const ArbitraryEqSheet(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Arbitrary Response EQ'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
    expect(find.text('512-tap FIR Filter'), findsOneWidget);

    // Top enable switch drives the cubit.
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    verify(() => cubit.setArbitraryEqEnabled(
          any(),
          eqString: any(named: 'eqString'),
          linearPhase: any(named: 'linearPhase'),
        )).called(1);

    // Linear-phase switch flips the description.
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    expect(
      find.text('Constant delay, exact phase (pre-ringing possible)'),
      findsOneWidget,
    );

    // Apply the current curve.
    await tester.tap(find.text('Apply Curve'));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Applied EqualizerAPO GraphicEq curve'), findsOneWidget);

    // Reset to flat rewrites the editor.
    await tester.tap(find.text('Reset to Flat'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'GraphicEq: 20 0; 1000 0; 20000 0');

    // Select a preset.
    await tester.tap(find.text('Harman Target Curve'));
    await tester.pump();
    final updated = tester.widget<TextField>(find.byType(TextField));
    expect(updated.controller!.text, contains('GraphicEq:'));

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('seeds the editor from an existing arbitrary EQ string',
      (tester) async {
    final cubit = buildCubit(eqString: 'GraphicEq: 500 3');
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      child: const ArbitraryEqSheet(),
    ));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'GraphicEq: 500 3');
  });
}
