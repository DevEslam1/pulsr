// Regression test for P0-1.9: the voice list must appear as soon as the TTS
// engine becomes available, without reopening the screen, and an empty list
// must say so instead of silently showing only "System default".
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/announcements/announcement_screen.dart';
import 'package:pulsr/features/announcements/announcement_settings.dart';
import 'package:pulsr/features/announcements/announcement_strings.dart';
import 'package:pulsr/features/announcements/tts_engine.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A channel engine whose availability can be flipped from the test, the way a
/// slow platform TTS service reports readiness after the first frame.
class _FlipEngine extends MethodChannelTtsEngine {
  _FlipEngine() : super(channel: const MethodChannel('test/flip_tts'));

  bool available = false;
  int initCalls = 0;
  List<TtsVoice> installed = const <TtsVoice>[];

  @override
  bool get isAvailable => available;

  @override
  Future<bool> init() async {
    initCalls += 1;
    return available;
  }

  @override
  Future<List<TtsVoice>> voices() async =>
      available ? installed : const <TtsVoice>[];

  void becomeAvailable(List<TtsVoice> voices) {
    installed = voices;
    available = true;
    availability.value = true;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AnnouncementSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = await AnnouncementSettings.load();
    settings.setEnabled(false);
  });

  tearDown(() => settings.dispose());

  Widget host(TtsEngine engine) => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AnnouncementScreen(settings: settings, engine: engine),
      );

  /// The voice section is the last one in the list, so scroll it into view
  /// before asserting on it.
  Future<void> scrollToVoices(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text(AnnouncementStrings.voiceLabel),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('voices appear when the engine becomes available', (tester) async {
    final engine = _FlipEngine();
    await tester.pumpWidget(host(engine));
    await tester.pumpAndSettle();
    await scrollToVoices(tester);

    // Unavailable at first frame: the sheet says so instead of listing voices.
    expect(engine.initCalls, greaterThanOrEqualTo(1));
    expect(find.text(AnnouncementStrings.unavailableTitle), findsWidgets);
    expect(find.text(AnnouncementStrings.voiceNoneInstalled), findsNothing);

    engine.becomeAvailable(const <TtsVoice>[
      TtsVoice(
        id: 'en-gb-1',
        name: 'British English',
        localeCode: 'en-GB',
        quality: 'high',
      ),
    ]);
    await tester.pumpAndSettle();

    // The dropdown replaces the empty/unavailable tile and carries the voice.
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdown.items, hasLength(2),
        reason: 'system default + the one installed voice');
    expect(
      dropdown.items!.any((item) =>
          item.child is Text &&
          ((item.child as Text).data ?? '').contains('British English')),
      isTrue,
      reason: 'the list must refresh without reopening the screen',
    );
    expect(find.text(AnnouncementStrings.voiceNoneInstalled), findsNothing);
  });

  testWidgets('an empty voice list shows the explicit empty state',
      (tester) async {
    final engine = _FlipEngine()
      ..available = true
      ..installed = const <TtsVoice>[];
    await tester.pumpWidget(host(engine));
    await tester.pumpAndSettle();
    await scrollToVoices(tester);

    expect(find.text(AnnouncementStrings.voiceNoneInstalled), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget,
        reason: 'the refresh action stays reachable when the list is empty');
  });

  testWidgets('the refresh action re-lists the voices', (tester) async {
    final engine = _FlipEngine()..available = true;
    await tester.pumpWidget(host(engine));
    await tester.pumpAndSettle();
    await scrollToVoices(tester);

    engine.installed = const <TtsVoice>[
      TtsVoice(
        id: 'en-us-1',
        name: 'American English',
        localeCode: 'en-US',
        quality: 'normal',
      ),
    ];
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(
      dropdown.items!.any((item) =>
          item.child is Text &&
          ((item.child as Text).data ?? '').contains('American English')),
      isTrue,
    );
  });
}
