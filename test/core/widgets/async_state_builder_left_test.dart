import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/async_state_builder.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

/// DESIGN.md §10: a repository failure arrives as a `Left` *value*, not as a
/// stream error. Without this guard, a failed query rendered as "no results".
void main() {
  Widget harness(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('Left renders the error card, not the empty state',
      (tester) async {
    await tester.pumpWidget(harness(
      AsyncStateBuilder<Either<String, List<int>>>(
        snapshot: const AsyncSnapshot<Either<String, List<int>>>.withData(
          ConnectionState.done,
          Left<String, List<int>>('database unavailable'),
        ),
        onData: (_) => const Text('data'),
      ),
    ));
    await tester.pump();

    expect(find.text('data'), findsNothing);
    // The failure message is surfaced through the error card (not swallowed and
    // not mistaken for an empty library).
    expect(find.textContaining('database unavailable'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  testWidgets('Right still renders through onData', (tester) async {
    await tester.pumpWidget(harness(
      AsyncStateBuilder<Either<String, List<int>>>(
        snapshot: const AsyncSnapshot<Either<String, List<int>>>.withData(
          ConnectionState.done,
          Right<String, List<int>>(<int>[1, 2]),
        ),
        onData: (_) => const Text('data'),
      ),
    ));
    await tester.pump();

    expect(find.text('data'), findsOneWidget);
  });
}
