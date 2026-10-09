// Covers lib/features/settings/presentation/widgets/settings_picker_sheets.dart
// (YTM web options, privacy guarantee, about and what's-new sheets).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/config/app_config.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_picker_sheets.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  Future<void> launch(
    WidgetTester tester,
    void Function(BuildContext context) open,
  ) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('YTM web options sheet lists every destination',
      (tester) async {
    await launch(tester, showYtmWebOptionsSheet);

    expect(find.text(l10n.youtubeMusicWeb), findsOneWidget);
    expect(find.text(l10n.homePage), findsOneWidget);
    expect(find.text(l10n.youtubeWeb), findsOneWidget);
    expect(find.text(l10n.exploreAndCharts), findsOneWidget);
    expect(find.text(l10n.yourLibrary), findsOneWidget);
    expect(find.text(l10n.likedMusic), findsOneWidget);
    expect(find.text(l10n.newReleases), findsOneWidget);
    expect(find.text(l10n.listeningHistory), findsOneWidget);
  });

  testWidgets('privacy guarantee sheet lists every privacy point',
      (tester) async {
    await launch(tester, showPrivacyGuaranteeSheet);

    expect(find.text(l10n.settingsPrivacyOfflineTitle), findsOneWidget);
    expect(find.text(l10n.settingsPrivacyNoTrackersTitle), findsOneWidget);
    expect(find.text(l10n.settingsPrivacyPermissionsTitle), findsOneWidget);
    expect(find.text(l10n.settingsPrivacyControlTitle), findsOneWidget);
  });

  testWidgets('about sheet renders identity and can open what\'s new',
      (tester) async {
    await launch(tester, showAboutSheet);

    expect(find.text(AppConfig.appTitle), findsOneWidget);
    expect(
      find.text('${l10n.version} ${AppConfig.appVersion}'),
      findsOneWidget,
    );
    expect(
      find.text(l10n.developerLabel(AppConfig.developerName)),
      findsOneWidget,
    );
    expect(find.text(l10n.aboutBlurb), findsOneWidget);

    await tester.tap(find.text(l10n.whatsNew));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.whatsNewInPulsr), findsOneWidget);
    expect(find.text(l10n.whatsNewBitPerfectTitle), findsOneWidget);
  });

  testWidgets('about sheet close button dismisses it', (tester) async {
    await launch(tester, showAboutSheet);

    await tester.tap(find.text(l10n.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.aboutBlurb), findsNothing);
  });

  testWidgets('what\'s-new sheet close button dismisses it', (tester) async {
    await launch(tester, showWhatsNewSheet);

    expect(find.text(l10n.whatsNewInPulsr), findsOneWidget);

    await tester.tap(find.text(l10n.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.whatsNewInPulsr), findsNothing);
  });
}
