// Coverage for the uncovered branches of autoeq_search_sheet.dart.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/audio/headphone_profiles_repository.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/autoeq_search_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit cubit;
  late PlayerState currentState;
  late AppLocalizations l10n;

  setUpAll(() async {
    registerFallbackValue(const HeadphoneProfile(
      id: 'fallback',
      name: 'Fallback',
      brand: 'Brand',
      model: 'Model',
      category: 'Custom',
      gains: [0, 0, 0],
    ));
    SharedPreferences.setMockInitialValues({});
    // Load the real bundled AutoEQ dataset once, outside the fake-async zone.
    await HeadphoneProfilesRepository().loadProfiles();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    cubit = MockPlayerCubit();
    currentState = const PlayerState();
    when(() => cubit.state).thenAnswer((_) => currentState);
    when(() => cubit.stream).thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => cubit.applyHeadphoneProfile(any())).thenAnswer((invocation) async {
      final profile = invocation.positionalArguments[0] as HeadphoneProfile?;
      if (profile != null) {
        currentState = currentState.copyWith(
          dsp: currentState.dsp.copyWith(selectedHeadphoneProfile: profile),
        );
      }
    });
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 880,
                        height: 1400,
                        child: BlocProvider<PlayerCubit>.value(
                          value: cubit,
                          child: const AutoEqSearchSheet(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('renders the loaded profile database', (tester) async {
    await pumpSheet(tester);

    expect(find.textContaining('profiles'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.byType(AutoEqSearchSheet), findsOneWidget);
  });

  testWidgets('shows the empty state for a non-matching search',
      (tester) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'zzzzqqqxyz');
    await tester.pump();

    expect(find.text(l10n.noHpMatch), findsOneWidget);
  });

  testWidgets('filters results for a matching search', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump();

    expect(find.text(l10n.noHpMatch), findsNothing);
  });

  testWidgets('selecting a category chip re-filters without error',
      (tester) async {
    await pumpSheet(tester);

    final chips = find.byType(ChoiceChip);
    expect(chips.evaluate().length, greaterThan(1));
    await tester.tap(chips.at(1));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('applying a result updates the cubit and pops with a snackbar',
      (tester) async {
    await pumpSheet(tester);

    final resultTile = find
        .descendant(
            of: find.byType(ListView).last, matching: find.byType(InkWell))
        .first;
    await tester.tap(resultTile);
    await tester.pumpAndSettle();

    verify(() => cubit.applyHeadphoneProfile(any())).called(1);
    expect(find.byType(AutoEqSearchSheet), findsNothing);
    expect(find.textContaining(l10n.dspAppliedProfile), findsOneWidget);
  });

  testWidgets('the close button dismisses the sheet', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(AutoEqSearchSheet), findsNothing);
  });
}
