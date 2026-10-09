// Covers lib/features/settings/presentation/widgets/scrobbler_settings_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/scrobbler_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/settings/presentation/widgets/scrobbler_settings_modal.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockSecureStorage storage;
  late Map<String, String> secureValues;

  setUp(() {
    secureValues = {};
    storage = MockSecureStorage();
    when(() => storage.read(key: any(named: 'key'))).thenAnswer((inv) async {
      final key = inv.namedArguments[#key] as String;
      return secureValues[key];
    });
    when(() => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((inv) async {
      secureValues[inv.namedArguments[#key] as String] =
          inv.namedArguments[#value] as String;
    });
    when(() => storage.delete(key: any(named: 'key')))
        .thenAnswer((inv) async {
      secureValues.remove(inv.namedArguments[#key] as String);
    });

    if (getIt.isRegistered<FlutterSecureStorage>()) {
      getIt.unregister<FlutterSecureStorage>();
    }
    getIt.registerSingleton<FlutterSecureStorage>(storage);
  });

  tearDown(() async {
    if (getIt.isRegistered<FlutterSecureStorage>()) {
      getIt.unregister<FlutterSecureStorage>();
    }
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1600);
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
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Material(
                      child: ScrobblerConfigSheet(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('shows a loading spinner, then the configuration form',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSheet(tester);

    expect(find.text(l10n.scrobblerSettings), findsOneWidget);
    expect(find.text(l10n.listenBrainzRestScrobbler), findsOneWidget);
    expect(find.text(l10n.lastFmRestScrobbler), findsOneWidget);
    expect(find.text(l10n.saveSettings), findsOneWidget);
    expect(find.text(l10n.enterListenBrainzUserToken), findsNothing);
  });

  testWidgets('enabling scrobblers reveals their credential fields',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSheet(tester);

    await tester.tap(find.text(l10n.enableListenBrainz));
    await tester.pump();
    expect(find.text(l10n.enterListenBrainzUserToken), findsOneWidget);

    await tester.tap(find.text(l10n.enableLastFmDirectScrobbling));
    await tester.pump();
    expect(find.text(l10n.lastFmApiKey), findsOneWidget);
    expect(find.text(l10n.lastFmSharedSecret), findsOneWidget);
    expect(find.text(l10n.lastFmSessionKey), findsOneWidget);
  });

  testWidgets('hydrates fields from secure storage on load', (tester) async {
    secureValues = {
      ScrobblerService.keyListenBrainzTokenSecure: 'lb-token',
      ScrobblerService.keyLastFmApiKeySecure: 'api-key',
      ScrobblerService.keyLastFmSecretSecure: 'secret',
      ScrobblerService.keyLastFmSessionKeySecure: 'session',
    };
    SharedPreferences.setMockInitialValues({
      ScrobblerService.keyListenBrainzEnabled: true,
      ScrobblerService.keyLastFmEnabled: true,
    });

    await pumpSheet(tester);

    expect(find.text('lb-token'), findsOneWidget);
    expect(find.text('api-key'), findsOneWidget);
    expect(find.text('secret'), findsOneWidget);
    expect(find.text('session'), findsOneWidget);
  });

  testWidgets('falls back to legacy plaintext prefs when secure store empty',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ScrobblerService.keyListenBrainzEnabled: true,
      ScrobblerService.keyLastFmEnabled: true,
      ScrobblerService.keyListenBrainzToken: 'legacy-lb',
      ScrobblerService.keyLastFmApiKey: 'legacy-key',
      ScrobblerService.keyLastFmSecret: 'legacy-secret',
      ScrobblerService.keyLastFmSessionKey: 'legacy-session',
    });

    await pumpSheet(tester);

    expect(find.text('legacy-lb'), findsOneWidget);
    expect(find.text('legacy-key'), findsOneWidget);
    expect(find.text('legacy-secret'), findsOneWidget);
    expect(find.text('legacy-session'), findsOneWidget);
  });

  testWidgets('saving non-empty credentials writes to secure storage',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSheet(tester);

    await tester.tap(find.text(l10n.enableListenBrainz));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, l10n.enterListenBrainzUserToken),
        'my-token');
    await tester.pump();

    await tester.tap(find.text(l10n.saveSettings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
        secureValues[ScrobblerService.keyListenBrainzTokenSecure], 'my-token');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ScrobblerService.keyListenBrainzEnabled), true);
    expect(find.text(l10n.scrobblerSaved), findsOneWidget);
  });

  testWidgets('saving empty credentials deletes the secure entries',
      (tester) async {
    secureValues = {
      ScrobblerService.keyListenBrainzTokenSecure: 'stale',
    };
    SharedPreferences.setMockInitialValues({
      ScrobblerService.keyListenBrainzEnabled: true,
    });
    await pumpSheet(tester);

    await tester.enterText(
        find.widgetWithText(TextField, l10n.enterListenBrainzUserToken), '');
    await tester.pump();

    await tester.tap(find.text(l10n.saveSettings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(secureValues.containsKey(
        ScrobblerService.keyListenBrainzTokenSecure), isFalse);
  });
}
