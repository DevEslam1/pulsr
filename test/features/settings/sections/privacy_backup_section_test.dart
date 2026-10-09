// Covers lib/features/settings/presentation/sections/privacy_backup_section.dart
// (backup + privacy entry points) and the privacy-guarantee sheet it opens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/settings/presentation/widgets/backup_section.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../support/settings_section_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(stubSettingsChannels);
  tearDown(clearSettingsChannels);

  testWidgets('renders the privacy section rows and the backup widget',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'privacy');
    addTearDown(h.cubit.close);

    expect(find.text(l10n.privacyAndData.toUpperCase()), findsOneWidget);
    expect(find.byType(BackupSection), findsOneWidget);
    expect(find.text(l10n.settingsScrobblingTitle), findsOneWidget);
    expect(find.text(l10n.settingsScrobbleStatsTitle), findsOneWidget);
    expect(find.text(l10n.privacyGuarantee), findsOneWidget);
  });

  testWidgets('privacy guarantee tile opens the explainer sheet',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'privacy');
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.privacyGuarantee));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.settingsPrivacyOfflineTitle), findsOneWidget);
    expect(find.text(l10n.settingsPrivacyNoTrackersTitle), findsOneWidget);
    expect(find.text(l10n.settingsPrivacyPermissionsTitle), findsOneWidget);
    expect(find.text(l10n.settingsPrivacyControlTitle), findsOneWidget);
  });
}
