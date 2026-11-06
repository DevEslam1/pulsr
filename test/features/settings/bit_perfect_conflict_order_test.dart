import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/bit_perfect_conflict_dialog.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _MockSettingsCubit extends Mock implements SettingsCubit {}

class _MockPlayerCubit extends Mock implements PlayerCubit {}

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

  testWidgets('the conflict list covers every active stage, not a subset',
      (tester) async {
    final disabled = <String>[];
    var current = const SettingsState();

    final settings = _MockSettingsCubit();
    when(() => settings.state).thenAnswer((_) => current);
    when(() => settings.stream).thenAnswer((_) => const Stream.empty());
    when(() => settings.setBitPerfectOutput(any())).thenAnswer((_) async {
      // The route accepted exclusive output, so the conflicts may now be torn
      // down.
      current = current.copyWith(bitPerfectOutput: true);
    });

    final player = _MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState(dsp: DspSlice(
          isLimiterEnabled: true,
          isDynamicEqEnabled: true,
          isSubCrossoverEnabled: true,
          isLiveProgEnabled: true,
          monoMix: true,
          volumeBoost: 0.4,
        )));
    when(() => player.stream).thenAnswer((_) => const Stream.empty());
    when(() => player.setLookaheadLimiter(any(),
        thresholdDb: any(named: 'thresholdDb'),
        releaseMs: any(named: 'releaseMs'),
        lookaheadMs: any(named: 'lookaheadMs'))).thenAnswer((_) async {
      disabled.add('limiter');
    });
    when(() => player.setDynamicEq(any())).thenAnswer((_) async {
      disabled.add('dynamicEq');
    });
    when(() => player.setSubCrossover(any())).thenAnswer((_) async {
      disabled.add('subCrossover');
    });
    when(() => player.setLiveProgEnabled(any())).thenAnswer((_) async {
      disabled.add('liveProg');
    });
    when(() => player.setMonoMix(any())).thenAnswer((_) async {
      disabled.add('monoMix');
    });
    when(() => player.setStereoBalance(any())).thenAnswer((_) async {
      disabled.add('balance');
    });
    when(() => player.setVolumeBoost(any())).thenAnswer((_) async {
      disabled.add('volumeBoost');
    });
    when(() => player.setDspEffectsEnabled(any())).thenAnswer((_) async {
      disabled.add('masterEffects');
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<PlayerCubit>.value(value: player),
        ],
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

    // Limiter, dynamic EQ, sub crossover, live programmable DSP, the panner,
    // volume boost and the master effects switch.
    expect(find.byIcon(Icons.block_rounded), findsNWidgets(7));

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(disabled, containsAll(['limiter', 'dynamicEq', 'subCrossover',
        'liveProg', 'monoMix', 'balance', 'volumeBoost']));
    // The multiband compressor is only reachable through the master switch, so
    // it has to run whenever anything effect-like is still active.
    expect(disabled, contains('masterEffects'));
  });
}
