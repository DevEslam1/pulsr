import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/bt_latency_tap_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSettingsCubit mockSettingsCubit;

  setUp(() {
    mockSettingsCubit = MockSettingsCubit();
    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget buildWidget() {
    return BlocProvider<SettingsCubit>.value(
      value: mockSettingsCubit,
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: BtLatencyTapSheet(),
        ),
      ),
    );
  }

  testWidgets('M-20: _initPlayer error prevents _start from running and disables start button', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pumpAndSettle();

    final state = tester.state<BtLatencyTapSheetState>(find.byType(BtLatencyTapSheet));

    // Simulate initPlayer error
    state.setInitErrorForTesting(true);
    await tester.pumpAndSettle();

    expect(state.initError, isTrue);
    expect(state.isRunning, isFalse);

    // Calling start() directly when initError is true is safely blocked
    state.start();
    expect(state.isRunning, isFalse);

    // Verify Start button is disabled
    final startButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(startButton.onPressed, isNull);

    // Verify error text is displayed
    expect(find.text('Failed'), findsOneWidget);
  });
}
