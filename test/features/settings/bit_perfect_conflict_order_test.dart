import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/bit_perfect_conflict_dialog.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'conflicts are disabled only after the route accepted Bit-Perfect',
      (tester) async {
    final calls = <String>[];
    var current = const SettingsState(crossfadeSeconds: 3.0);

    final cubit = _MockSettingsCubit();
    when(() => cubit.state).thenAnswer((_) => current);
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => cubit.setBitPerfectOutput(any())).thenAnswer((invocation) async {
      calls.add('bitPerfect:${invocation.positionalArguments.first}');
      current = current.copyWith(bitPerfectOutput: true);
    });
    when(() => cubit.setCrossfade(any())).thenAnswer((invocation) async {
      calls.add('crossfade:${invocation.positionalArguments.first}');
      current = current.copyWith(crossfadeSeconds: 0.0);
    });

    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: cubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => requestBitPerfectOutput(context, true),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // Enable first: a native rejection must never leave the user with all
    // their DSP stages disabled and no bit-perfect output.
    expect(calls, ['bitPerfect:true', 'crossfade:0.0']);
  });

  testWidgets('a rejected Bit-Perfect leaves the DSP conflicts untouched',
      (tester) async {
    final calls = <String>[];
    var current = const SettingsState(crossfadeSeconds: 3.0);

    final cubit = _MockSettingsCubit();
    when(() => cubit.state).thenAnswer((_) => current);
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => cubit.setBitPerfectOutput(any())).thenAnswer((invocation) async {
      calls.add('bitPerfect:${invocation.positionalArguments.first}');
      // Route refused: the cubit keeps bitPerfectOutput false.
    });
    when(() => cubit.setCrossfade(any())).thenAnswer((invocation) async {
      calls.add('crossfade:${invocation.positionalArguments.first}');
      current = current.copyWith(crossfadeSeconds: 0.0);
    });

    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: cubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => requestBitPerfectOutput(context, true),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(calls, ['bitPerfect:true']);
    expect(current.crossfadeSeconds, 3.0);
  });
}
