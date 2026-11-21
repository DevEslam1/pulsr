// test/features/party/party_sheet_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/party/listen_together_service.dart';
import 'package:pulsr/data/party/party_models.dart';
import 'package:pulsr/features/party/presentation/party_sheet.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockListenTogetherService extends Mock implements ListenTogetherService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockListenTogetherService partyService;

  setUp(() {
    partyService = MockListenTogetherService();
    when(() => partyService.partySnapshot)
        .thenReturn(ValueNotifier<PartySnapshot?>(null));
    when(() => partyService.connectionState)
        .thenReturn(ValueNotifier<PartyConnectionState>(PartyConnectionState.offline));
    when(() => partyService.currentMember)
        .thenReturn(ValueNotifier<PartyMember?>(null));
    when(() => partyService.lastError)
        .thenReturn(ValueNotifier<String?>(null));
    when(() => partyService.clockSynced)
        .thenReturn(ValueNotifier<bool>(false));
    when(() => partyService.roundTripMs)
        .thenReturn(ValueNotifier<int>(0));
    when(() => partyService.inParty).thenReturn(false);
    when(() => partyService.getServerUrl())
        .thenAnswer((_) async => ListenTogetherService.defaultServerUrl);
    when(() => partyService.setCustomServerUrl(any()))
        .thenAnswer((_) async {});
    when(() => partyService.leaveParty()).thenAnswer((_) async {});
    getIt.registerSingleton<ListenTogetherService>(partyService);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Widget buildHost() {
    return MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: PartySheet()),
    );
  }

  testWidgets('validates server URL in settings view and surfaces inline error', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    // Open settings view by tapping the settings icon
    final settingsButton = find.byIcon(Icons.settings_rounded);
    expect(settingsButton, findsOneWidget);
    await tester.tap(settingsButton);
    await tester.pumpAndSettle();

    // Verify settings fields are present
    final serverField = find.byType(TextField).first;
    expect(serverField, findsOneWidget);

    // Try entering an invalid URL (invalid scheme)
    await tester.enterText(serverField, 'ftp://invalid-party.server');
    await tester.pump();

    // Tap Save
    final saveButton = find.widgetWithText(FilledButton, 'Save');
    await tester.tap(saveButton);
    await tester.pump();

    // Verify inline validation error is shown
    expect(find.text('Enter a valid URL (http, https, ws, or wss)'), findsOneWidget);
    verifyNever(() => partyService.setCustomServerUrl('ftp://invalid-party.server'));

    // Try entering an empty URL
    await tester.enterText(serverField, '   ');
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pump();
    expect(find.text('Server URL cannot be empty'), findsOneWidget);

    // Enter valid URL
    await tester.enterText(serverField, 'https://my-party.pulsr.app');
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    verify(() => partyService.setCustomServerUrl('https://my-party.pulsr.app')).called(1);
  });
}
