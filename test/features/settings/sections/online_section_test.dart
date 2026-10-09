// Covers lib/features/settings/presentation/sections/online_section.dart.
//
// NOTE: every offline/wifi/quality/YTM row in this section sits behind the
// compile-time constant `AppConfig.ytmEnabled` (false in the default test
// build), so only the always-present proxy row has executable branches here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../support/settings_section_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(stubSettingsChannels);
  tearDown(clearSettingsChannels);

  testWidgets('renders the network section with proxy disabled',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'network');
    addTearDown(h.cubit.close);

    expect(find.text(l10n.networkAndProxy.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.proxySettings), findsOneWidget);
    expect(find.text(l10n.settingsProxyDisabledHint), findsOneWidget);
    expect(find.text(l10n.activeLabel), findsNothing);
  });

  testWidgets('an enabled proxy renders the Active badge and endpoint',
      (tester) async {
    final h = await pumpSettingsCategory(
      tester,
      category: 'network',
      seedState: const SettingsState(
        proxyEnabled: true,
        proxyHost: '127.0.0.1',
        proxyPort: 9050,
      ),
    );
    addTearDown(h.cubit.close);

    expect(find.text(l10n.activeLabel), findsOneWidget);
    expect(find.textContaining('127.0.0.1:9050'), findsOneWidget);
    expect(find.text(l10n.settingsProxyDisabledHint), findsNothing);
  });

  testWidgets('enabled proxy without a host falls back to the Enabled label',
      (tester) async {
    final h = await pumpSettingsCategory(
      tester,
      category: 'network',
      seedState: const SettingsState(proxyEnabled: true, proxyHost: ''),
    );
    addTearDown(h.cubit.close);

    expect(find.text(l10n.activeLabel), findsOneWidget);
    expect(find.textContaining(l10n.settingsProxyEnabled), findsOneWidget);
  });
}
