// Regression test for P2-3.4: the announcements screen must let the user tune
// the maximum announcement length, and no slider interaction may push the
// persisted value outside the documented 40–600 character window.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_slider.dart';
import 'package:pulsr/features/announcements/announcement_screen.dart';
import 'package:pulsr/features/announcements/announcement_settings.dart';
import 'package:pulsr/features/announcements/announcement_strings.dart';
import 'package:pulsr/features/announcements/tts_engine.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_slider_row.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Always-available engine that never touches a platform channel, so the screen
/// renders its full settings list without native TTS.
class _SilentEngine implements TtsEngine {
  @override
  bool get isAvailable => true;

  @override
  Future<bool> init() async => true;

  @override
  Future<List<TtsVoice>> voices() async => const <TtsVoice>[];

  @override
  Future<void> speak(
    String text, {
    double volume = 1.0,
    bool duckAudio = false,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AnnouncementSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = await AnnouncementSettings.load();
  });

  tearDown(() => settings.dispose());

  Widget host() => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AnnouncementScreen(settings: settings, engine: _SilentEngine()),
      );

  /// Pumps the screen, scrolls the timing section into view and returns the
  /// max-length slider inside its own row.
  Future<Finder> revealMaxLengthSlider(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(AnnouncementStrings.maxLengthLabel),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text(AnnouncementStrings.maxLengthLabel),
      matching: find.byType(SettingSliderRow),
    );
    expect(row, findsOneWidget, reason: 'the timing section owns the row');

    final slider = find.descendant(of: row, matching: find.byType(PulsrSlider));
    expect(slider, findsOneWidget);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    return slider;
  }

  testWidgets('changing the max-length slider updates the settings',
      (tester) async {
    final slider = await revealMaxLengthSlider(tester);

    // Starts on the shared composer default and shows it through the string
    // helper rather than a hardcoded label.
    expect(settings.maxLength, AnnouncementSettings.defaultMaxLength);
    expect(tester.widget<PulsrSlider>(slider).value,
        AnnouncementSettings.defaultMaxLength.toDouble());
    expect(
      find.text(AnnouncementStrings.maxLengthValue(
          AnnouncementSettings.defaultMaxLength)),
      findsOneWidget,
    );

    // Tapping the middle of the track targets the middle of 40–600.
    final rect = tester.getRect(slider);
    await tester.tapAt(Offset(rect.left + rect.width * 0.5, rect.center.dy));
    await tester.pumpAndSettle();

    expect(settings.maxLength, isNot(AnnouncementSettings.defaultMaxLength));
    expect(settings.maxLength, 320,
        reason: '56 divisions of 10 characters each, halfway through 40–600');
    expect(
      settings.maxLength,
      inInclusiveRange(
        AnnouncementSettings.minMaxLength,
        AnnouncementSettings.maxMaxLength,
      ),
    );
    expect(
        tester.widget<PulsrSlider>(slider).value, settings.maxLength.toDouble(),
        reason: 'the row must show the persisted value, not a stale one');
    expect(find.text(AnnouncementStrings.maxLengthValue(320)), findsOneWidget);
  });

  testWidgets('dragging past either end keeps maxLength clamped to 40..600',
      (tester) async {
    final slider = await revealMaxLengthSlider(tester);

    // Far past the right end: the track ratio saturates at 1.0.
    await tester.drag(slider, const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(settings.maxLength, AnnouncementSettings.maxMaxLength);
    expect(tester.widget<PulsrSlider>(slider).value,
        AnnouncementSettings.maxMaxLength.toDouble());

    // Far past the left end: the track ratio saturates at 0.0.
    await tester.drag(slider, const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(settings.maxLength, AnnouncementSettings.minMaxLength);
    expect(tester.widget<PulsrSlider>(slider).value,
        AnnouncementSettings.minMaxLength.toDouble());
    expect(settings.maxLength,
        lessThanOrEqualTo(AnnouncementSettings.maxMaxLength));
    expect(settings.maxLength,
        greaterThanOrEqualTo(AnnouncementSettings.minMaxLength));
  });
}
