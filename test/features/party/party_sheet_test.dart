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
    when(() => partyService.connectionState).thenReturn(
        ValueNotifier<PartyConnectionState>(PartyConnectionState.offline));
    when(() => partyService.currentMember)
        .thenReturn(ValueNotifier<PartyMember?>(null));
    when(() => partyService.lastError).thenReturn(ValueNotifier<String?>(null));
    when(() => partyService.clockSynced).thenReturn(ValueNotifier<bool>(false));
    when(() => partyService.roundTripMs).thenReturn(ValueNotifier<int>(0));
    when(() => partyService.inParty).thenReturn(false);
    when(() => partyService.getServerUrl())
        .thenAnswer((_) async => ListenTogetherService.defaultServerUrl);
    when(() => partyService.setCustomServerUrl(any())).thenAnswer((_) async {});
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

  testWidgets('validates server URL in settings view and surfaces inline error',
      (tester) async {
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
    expect(find.text('Enter a valid URL (http, https, ws, or wss)'),
        findsOneWidget);
    verifyNever(
        () => partyService.setCustomServerUrl('ftp://invalid-party.server'));

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

    verify(() => partyService.setCustomServerUrl('https://my-party.pulsr.app'))
        .called(1);
  });

  testWidgets(
      'in-party host view wires host-only lock toggle, kick member, and shared queue remove',
      (tester) async {
    const host = PartyMember(
      memberId: 'm_host',
      displayName: 'Host User',
      isHost: true,
      connected: true,
    );
    const guest = PartyMember(
      memberId: 'm_guest',
      displayName: 'Guest User',
      isHost: false,
      connected: true,
    );
    const currentTrack = PartyTrack(
      videoId: 'vid_now',
      title: 'Now Playing Track',
      artist: 'Artist A',
    );
    const nextTrack = PartyTrack(
      videoId: 'vid_next',
      title: 'Upcoming Track',
      artist: 'Artist B',
    );
    const snap = PartySnapshot(
      code: 'ABC123',
      maxMembers: 5,
      hostOnlyControl: false,
      members: [host, guest],
      playback: PartyPlayback(track: currentTrack, isPlaying: true),
      queue: PartyQueue(index: 0, items: [currentTrack, nextTrack]),
    );

    when(() => partyService.inParty).thenReturn(true);
    when(() => partyService.isHost).thenReturn(true);
    when(() => partyService.partySnapshot)
        .thenReturn(ValueNotifier<PartySnapshot?>(snap));
    when(() => partyService.currentMember)
        .thenReturn(ValueNotifier<PartyMember?>(host));
    when(() => partyService.connectionState).thenReturn(
        ValueNotifier<PartyConnectionState>(PartyConnectionState.live));
    when(() => partyService.clockSynced).thenReturn(ValueNotifier<bool>(true));
    when(() => partyService.roundTripMs).thenReturn(ValueNotifier<int>(24));
    when(() => partyService.sendKick(any())).thenReturn(null);
    when(() => partyService.sendSetHostOnlyControl(any())).thenReturn(null);
    when(() => partyService.sendQueueRemove(any())).thenReturn(null);

    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    // 1. Kick button appears for guest, not for host
    expect(find.byKey(const ValueKey<String>('party_kick_m_guest')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('party_kick_m_host')), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('party_kick_m_guest')));
    await tester.pump();
    verify(() => partyService.sendKick('m_guest')).called(1);

    // 2. Host-only control lock toggle wires to sendSetHostOnlyControl
    final lockSwitch =
        find.byKey(const ValueKey<String>('party_host_only_switch'));
    expect(lockSwitch, findsOneWidget);
    await tester.tap(lockSwitch);
    await tester.pump();
    verify(() => partyService.sendSetHostOnlyControl(true)).called(1);

    // 3. Shared queue shows upcoming track and remove button wires to sendQueueRemove
    expect(find.text('Upcoming Track'), findsOneWidget);
    final removeBtn =
        find.byKey(const ValueKey<String>('party_queue_remove_vid_next'));
    expect(removeBtn, findsOneWidget);
    await tester.tap(removeBtn);
    await tester.pump();
    verify(() => partyService.sendQueueRemove('vid_next')).called(1);
  });

  testWidgets(
      'in-party guest view hides queue remove when hostOnlyControl is true',
      (tester) async {
    const host = PartyMember(
      memberId: 'm_host',
      displayName: 'Host User',
      isHost: true,
      connected: true,
    );
    const guest = PartyMember(
      memberId: 'm_guest',
      displayName: 'Guest User',
      isHost: false,
      connected: true,
    );
    const nextTrack = PartyTrack(
      videoId: 'vid_next',
      title: 'Locked Upcoming Track',
      artist: 'Artist B',
    );
    const snap = PartySnapshot(
      code: 'ABC123',
      maxMembers: 5,
      hostOnlyControl: true,
      members: [host, guest],
      queue: PartyQueue(index: -1, items: [nextTrack]),
    );

    when(() => partyService.inParty).thenReturn(true);
    when(() => partyService.isHost).thenReturn(false);
    when(() => partyService.partySnapshot)
        .thenReturn(ValueNotifier<PartySnapshot?>(snap));
    when(() => partyService.currentMember)
        .thenReturn(ValueNotifier<PartyMember?>(guest));
    when(() => partyService.connectionState).thenReturn(
        ValueNotifier<PartyConnectionState>(PartyConnectionState.live));

    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    expect(find.text('Locked Upcoming Track'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('party_host_only_switch')),
        findsNothing);
    expect(
        find.byKey(const ValueKey<String>('party_kick_m_host')), findsNothing);
    expect(find.byKey(const ValueKey<String>('party_queue_remove_vid_next')),
        findsNothing);
  });

  testWidgets(
      'H-43: strips hyphens before capping 6-char party code and awaits reset default server URL',
      (tester) async {
    when(() => partyService.joinParty(
          any(),
          nickname: any(named: 'nickname'),
        )).thenAnswer((_) async => 'ABC123');

    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    // Find the 6-character code TextField (second TextField in lobby: name is first, code is second)
    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(2));
    final codeField = textFields.at(1);

    // Paste hyphenated code 'abc-123' -> should normalize to 'ABC123', not truncate to 'ABC-12' -> 'ABC12'
    await tester.enterText(codeField, 'abc-123');
    await tester.pump();

    final codeWidget = tester.widget<TextField>(codeField);
    expect(codeWidget.controller?.text, equals('ABC123'));

    // Open settings and tap Reset to default
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    final resetBtn = find.byType(TextButton);
    expect(resetBtn, findsOneWidget);
    await tester.tap(resetBtn);
    await tester.pumpAndSettle();

    verify(() => partyService.setCustomServerUrl(null)).called(1);
  });
}
