import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/shell/presentation/app_shell.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class FakeNavigationShell extends StatefulWidget implements StatefulNavigationShell {
  @override
  final int currentIndex;
  final void Function(int, {bool initialLocation})? onGoBranch;

  const FakeNavigationShell({
    super.key,
    this.currentIndex = 0,
    this.onGoBranch,
  });

  @override
  void goBranch(int index, {bool initialLocation = false}) {
    onGoBranch?.call(index, initialLocation: initialLocation);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  State<FakeNavigationShell> createState() => _FakeNavigationShellState();
}

class _FakeNavigationShellState extends State<FakeNavigationShell> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockPlayerCubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
      return null;
    });
    mockPlayerCubit = MockPlayerCubit();
    when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget buildWidget({
    int currentIndex = 0,
    void Function(int, {bool initialLocation})? onGoBranch,
  }) {
    return BlocProvider<PlayerCubit>.value(
      value: mockPlayerCubit,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
          ),
          child: AppShell(
            navigationShell: FakeNavigationShell(
              currentIndex: currentIndex,
              onGoBranch: onGoBranch,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('M-16: AppShell stopwatch lifecycle and back press reset', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(buildWidget(currentIndex: 0));
    await tester.pumpAndSettle();

    final state = tester.state<AppShellState>(find.byType(AppShell));
    expect(state.backPressStopwatch.isRunning, isFalse);

    // 1. First back press on Home tab starts stopwatch
    await state.handlePop(ignoreThrottle: true);
    expect(state.backPressStopwatch.isRunning, isTrue);

    // 2. Lifecycle pause/inactive resets stopwatch
    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(state.backPressStopwatch.isRunning, isFalse);
    expect(state.backPressStopwatch.elapsedMilliseconds, equals(0));

    // 3. Second sequence: start stopwatch again
    await state.handlePop(ignoreThrottle: true);
    expect(state.backPressStopwatch.isRunning, isTrue);

    // Second pop within 3 seconds attempts exit and resets stopwatch in finally
    await state.handlePop(ignoreThrottle: true);
    expect(state.backPressStopwatch.isRunning, isFalse);
    expect(state.backPressStopwatch.elapsedMilliseconds, equals(0));

    // 4. Dispose resets stopwatch
    await state.handlePop(ignoreThrottle: true);
    expect(state.backPressStopwatch.isRunning, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(state.backPressStopwatch.isRunning, isFalse);
    expect(state.backPressStopwatch.elapsedMilliseconds, equals(0));

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('M-16: AppShell stopwatch reset on non-home tab and inspector back navigation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    int navigatedBranch = -1;
    await tester.pumpWidget(buildWidget(
      currentIndex: 1,
      onGoBranch: (idx, {initialLocation = false}) {
        navigatedBranch = idx;
      },
    ));
    await tester.pumpAndSettle();

    final state = tester.state<AppShellState>(find.byType(AppShell));

    // Simulate stopwatch running
    state.backPressStopwatch.start();
    expect(state.backPressStopwatch.isRunning, isTrue);

    // Popping while on tab 1 goes to tab 0 and resets stopwatch
    await state.handlePop(ignoreThrottle: true);
    expect(navigatedBranch, equals(0));
    expect(state.backPressStopwatch.isRunning, isFalse);
    expect(state.backPressStopwatch.elapsedMilliseconds, equals(0));

    // Popping while side inspector is open closes it and resets stopwatch
    state.backPressStopwatch.start();
    expect(state.backPressStopwatch.isRunning, isTrue);
    await state.handlePop(ignoreThrottle: true, isInspectorOpenOverride: true);
    expect(state.backPressStopwatch.isRunning, isFalse);
    expect(state.backPressStopwatch.elapsedMilliseconds, equals(0));

    await tester.binding.setSurfaceSize(null);
  });
}
