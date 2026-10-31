import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/home/presentation/widgets/quick_card.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

/// Row/tile controls used to be bare `InkWell`s with no role, so a screen
/// reader announced the text but not that it was actionable.
void main() {
  testWidgets('quick card exposes a button role and its label', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 200,
          child: QuickCard(
            title: 'Favorites',
            subtitle: '12 songs',
            icon: Icons.favorite_rounded,
            color: const Color(0xFF7C4DFF),
            onTap: () {},
          ),
        ),
      ),
    ));
    await tester.pump();

    final data = tester.getSemantics(find.byType(QuickCard)).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.label, contains('Favorites'));
    handle.dispose();
  });
}
