// test/core/config/configuration_error_screen_test.dart
//
// Invalid production configuration must block startup with a visible screen
// instead of being logged and ignored.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/main.dart';

void main() {
  testWidgets('renders the fatal configuration message', (tester) async {
    await tester.pumpWidget(const PulsrConfigurationErrorApp(
      title: 'Pulsr Music',
      message: 'CRITICAL: Production Play Store builds must not enable YTM',
    ));

    expect(
      find.text('Pulsr cannot start with this configuration'),
      findsOneWidget,
    );
    expect(
      find.text('CRITICAL: Production Play Store builds must not enable YTM'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });
}
