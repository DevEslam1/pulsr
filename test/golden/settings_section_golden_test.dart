// test/golden/settings_section_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_section.dart';

void main() {
  testWidgets('SettingsSection golden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              child: SizedBox(
                width: 380,
                child: SettingsSection(
                  icon: Icons.equalizer_rounded,
                  title: 'Audio & Sound',
                  subtitle: 'Output, DSP and gain',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  children: const [
                    ListTile(title: Text('Equalizer')),
                    ListTile(title: Text('Output quality')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SettingsSection),
      matchesGoldenFile('goldens/settings_section.png'),
    );
  });
}
