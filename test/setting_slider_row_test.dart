import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_slider_row.dart';

Widget _wrap(SettingSliderRow row) => MaterialApp(
      theme: AuraTheme.darkTheme,
      home: Scaffold(
        body: ListView(children: [row]),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingSliderRow restore-default affordance', () {
    testWidgets('tooltip advertises the default value', (tester) async {
      await tester.pumpWidget(_wrap(SettingSliderRow(
        label: 'Crossfade',
        value: 4,
        min: 0,
        max: 12,
        divisions: 24,
        defaultValue: 0,
        formatValue: (v) => '${v.toStringAsFixed(1)}s',
        onChanged: (_) {},
      )));
      expect(find.byTooltip('Reset to default (0.0s)'), findsOneWidget);
    });

    testWidgets('reset button is disabled while value equals default',
        (tester) async {
      await tester.pumpWidget(_wrap(SettingSliderRow(
        label: 'Crossfade',
        value: 0,
        min: 0,
        max: 12,
        divisions: 24,
        defaultValue: 0,
        formatValue: (v) => '${v.toStringAsFixed(1)}s',
        onChanged: (_) {},
      )));
      final button = tester.widget<IconButton>(find.widgetWithIcon(
          IconButton, Icons.settings_backup_restore));
      expect(button.onPressed, isNull);
    });

    testWidgets('tapping reset restores the default via onChanged',
        (tester) async {
      double? changedTo;
      await tester.pumpWidget(_wrap(SettingSliderRow(
        label: 'Crossfade',
        value: 6,
        min: 0,
        max: 12,
        divisions: 24,
        defaultValue: 0,
        formatValue: (v) => '${v.toStringAsFixed(1)}s',
        onChanged: (v) => changedTo = v,
      )));
      await tester.tap(find.byTooltip('Reset to default (0.0s)'));
      await tester.pump();
      expect(changedTo, 0.0);
    });

    testWidgets('tapping reset on the RG preamp row restores -3.0 dB default',
        (tester) async {
      double? changedTo;
      await tester.pumpWidget(_wrap(SettingSliderRow(
        label: 'Preamp (Without RG tag fallback)',
        value: 5,
        min: -12,
        max: 12,
        divisions: 48,
        defaultValue: -3,
        formatValue: (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
        onChanged: (v) => changedTo = v,
      )));
      await tester.tap(find.byTooltip('Reset to default (-3.0 dB)'));
      await tester.pump();
      expect(changedTo, -3.0);
    });
  });
}
