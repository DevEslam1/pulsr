import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_slider.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

/// The DSP surface must announce real units: an EQ gain of +6 dB was previously
/// announced as "50 %" because every slider hard-coded a percentage.
void main() {
  testWidgets('semanticFormatterCallback drives value and step readouts',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            child: PulsrSlider(
              value: 6,
              min: -12,
              max: 12,
              semanticLabel: 'Bass',
              semanticFormatterCallback: (v) => '${v.toStringAsFixed(1)} dB',
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    final slider = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.slider == true);
    expect(slider, findsOneWidget);

    final props = tester.widget<Semantics>(slider).properties;
    expect(props.value, '6.0 dB');
    // step = range / 20 = 1.2 dB
    expect(props.increasedValue, '7.2 dB');
    expect(props.decreasedValue, '4.8 dB');
  });
}
