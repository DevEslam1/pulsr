import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/shell/presentation/widgets/tablet_side_inspector.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockPlayerCubit;

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget buildWidget({required Size screenSize}) {
    return BlocProvider<PlayerCubit>.value(
      value: mockPlayerCubit,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: screenSize,
          ),
          child: Scaffold(
            body: TabletSideInspector(
              onClose: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'H-08: TabletSideInspector customWidth scales proportionally on screen width/orientation change',
      (tester) async {
    // 1. Initial screen size (width 1000)
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    await tester.pumpWidget(buildWidget(screenSize: const Size(1000, 700)));
    await tester.pumpAndSettle();

    final state = tester
        .state<TabletSideInspectorState>(find.byType(TabletSideInspector));

    // 2. Set custom width to 300 (ratio = 300 / 1000 = 0.30)
    state.customWidth = 300.0;
    await tester.pump();
    expect(state.customWidth, equals(300.0));

    // 3. Screen expands on rotation to 1200
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    await tester.pumpWidget(buildWidget(screenSize: const Size(1200, 700)));
    await tester.pump();

    // 4. Custom width should scale proportionally: 0.30 * 1200 = 360.0
    expect(state.customWidth, closeTo(360.0, 0.01));

    // 5. Screen rotates to portrait (width 600): 0.30 * 600 = 180, clamped to min 280.0
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    await tester.pumpWidget(buildWidget(screenSize: const Size(600, 1000)));
    await tester.pump();

    expect(state.customWidth, equals(280.0));

    // Reset surface size
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
      'M-15: Drag handle accumulates sub-pixel deltas and prevents thrashing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    await tester.pumpWidget(buildWidget(screenSize: const Size(1000, 700)));
    await tester.pumpAndSettle();

    final state = tester
        .state<TabletSideInspectorState>(find.byType(TabletSideInspector));
    // Default width is 1000 * 0.35 = 350.0
    expect(state.customWidth, isNull);

    // Find drag handle GestureDetector
    final dragHandleFinder = find.byType(GestureDetector).last;
    expect(dragHandleFinder, findsOneWidget);

    // Start drag
    final gesture =
        await tester.startGesture(tester.getCenter(dragHandleFinder));
    await tester.pump();
    expect(state.dragDeltaAccumulator, equals(0.0));

    // Move by sub-pixel (-0.4 in LTR -> delta is -(-0.4) = +0.4)
    // Moving finger to the left (negative dx) expands width in LTR because handle is at start:0 (left edge of inspector on right side)
    await gesture.moveBy(const Offset(0.4, 0));
    await tester.pump();
    // Delta in LTR is -details.delta.dx = -0.4, abs < 1.0 -> no update yet
    expect(state.dragDeltaAccumulator, closeTo(-0.4, 0.01));
    expect(state.customWidth, isNull);

    // Move again by 0.7 -> accumulated delta is -1.1 (abs >= 1.0)
    await gesture.moveBy(const Offset(0.7, 0));
    await tester.pump();
    // 350 - 1.1 = 348.9, accumulator reset to 0.0
    expect(state.dragDeltaAccumulator, equals(0.0));
    expect(state.customWidth, closeTo(348.9, 0.01));

    // End drag resets accumulator
    await gesture.up();
    await tester.pump();
    expect(state.dragDeltaAccumulator, equals(0.0));

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
      'M-15: Drag handle does not update or thrash when clamped at boundaries',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    await tester.pumpWidget(buildWidget(screenSize: const Size(1000, 700)));
    await tester.pumpAndSettle();

    final state = tester
        .state<TabletSideInspectorState>(find.byType(TabletSideInspector));
    state.customWidth = 400.0;
    await tester.pump();

    final dragHandleFinder = find.byType(GestureDetector).last;
    final gesture =
        await tester.startGesture(tester.getCenter(dragHandleFinder));
    await tester.pump();

    // Drag further to expand (negative dx in LTR expands width)
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();

    // Clamped at 400.0, customWidth remains 400.0 and accumulator is reset
    expect(state.customWidth, equals(400.0));
    expect(state.dragDeltaAccumulator, equals(0.0));

    await gesture.up();
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
  });
}
