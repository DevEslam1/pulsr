import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:pulsr/services/updater/app_update_service.dart';
import 'package:pulsr/services/updater/update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders release metadata and surfaces download failure',
      (tester) async {
    SharedPreferences.setMockInitialValues({'setting_offline_only_mode': true});

    final info = UpdateInfo(
      version: '9.9.9',
      tagName: 'v9.9.9',
      releaseUrl: 'https://github.com/pulsr-audio/pulsr/releases/tag/v9.9.9',
      apkUrl:
          'https://github.com/pulsr-audio/pulsr/releases/download/v9.9.9/pulsr.apk',
      sha256: 'a' * 64,
      notes: 'Security and stability fixes',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: UpdateDialog(info: info),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('v9.9.9'), findsOneWidget);
    expect(find.text('Security and stability fixes'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.download_rounded));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('App updates are disabled in offline or Pure mode.'),
      findsOneWidget,
    );
  });
}
