// test/features/player/widgets/live_prog_sheet_test.dart
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/live_prog_slider_persistence.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/live_prog_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders, toggles, compiles and selects a preset',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      PrefsKeys.liveProgSliders: encodeLiveProgSliders({1: 3.0}),
    });
    final cubit = stubPlayerCubit();
    when(() => cubit.setLiveProgEnabled(any(), code: any(named: 'code')))
        .thenAnswer((_) async {});
    when(() => cubit.setLiveProgSlider(any(), any())).thenAnswer((_) async {});

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      child: const LiveProgSheet(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Live Programmable DSP'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(8));

    // Restored slider value is reflected in the label.
    expect(find.text('3.00'), findsAtLeastNWidgets(1));

    // Toggle the enable switch.
    await tester.tap(find.byType(Switch));
    await tester.pump();
    verify(() => cubit.setLiveProgEnabled(any(), code: any(named: 'code')))
        .called(1);

    // Compile & Run pushes the editor contents and shows a snackbar.
    await tester.tap(find.text('Compile & Run'));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);

    // Select an example script.
    await tester.tap(find.text('Stereo Sine Tremolo'));
    await tester.pump();
    verify(() => cubit.setLiveProgEnabled(true, code: any(named: 'code')))
        .called(greaterThanOrEqualTo(1));

    // Let the snackbar's auto-dismiss timer elapse before teardown.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('falls back to the first preset when no code is stored',
      (tester) async {
    final cubit = stubPlayerCubit();
    when(() => cubit.setLiveProgEnabled(any(), code: any(named: 'code')))
        .thenAnswer((_) async {});
    when(() => cubit.setLiveProgSlider(any(), any())).thenAnswer((_) async {});

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      child: const LiveProgSheet(),
    ));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains('@init'));
  });

  testWidgets('surfaces liveProgStatus changes and compile errors reactively',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = StreamController<PlayerState>.broadcast();
    addTearDown(controller.close);
    var currentState = const PlayerState();
    final cubit = stubPlayerCubit(state: currentState);
    when(() => cubit.state).thenAnswer((_) => currentState);
    when(() => cubit.stream).thenAnswer((_) => controller.stream);
    when(() => cubit.setLiveProgEnabled(any(), code: any(named: 'code')))
        .thenAnswer((_) async {});

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      child: const LiveProgSheet(),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('live_prog_status_banner')), findsNothing);

    currentState = const PlayerState(
      dsp:
          DspSlice(liveProgStatus: 'Compile error: unexpected token at line 2'),
    );
    controller.add(currentState);
    await tester.pump();
    await tester.pump();

    expect(
        find.byKey(const ValueKey('live_prog_status_banner')), findsOneWidget);
    expect(
        find.text('Compile error: unexpected token at line 2'), findsOneWidget);
  });
}
