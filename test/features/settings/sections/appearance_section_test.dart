// Covers lib/features/settings/presentation/sections/appearance_section.dart
// (theme selector, accent swatches, accessibility toggles) plus the picker
// sheets it opens, via the real SettingsScreen forced onto "look".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/services/sound_feedback_service.dart';
import 'package:pulsr/core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/shell/presentation/widgets/dock_style_controller.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../support/settings_section_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    stubSettingsChannels();
    DockStyleController.reset();
    SoundFeedbackService.resetForTesting();
  });
  tearDown(() {
    clearSettingsChannels();
    DockStyleController.reset();
    SoundFeedbackService.resetForTesting();
  });

  Finder inSheet(String text) => find.descendant(
        of: find.byType(PulsrBottomSheetContainer),
        matching: find.text(text),
      );

  testWidgets('renders appearance + accessibility sections and theme segments',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    expect(find.text(l10n.themeAndAppearance.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.themeModeLabel), findsOneWidget);
    expect(
      find.text(l10n.settingsAccessibilityAndComfort.toUpperCase()),
      findsOneWidget,
    );
    expect(find.text(l10n.accentColor), findsOneWidget);

    // Default mode is dark (index 2); switching to light fires setThemeMode.
    await tester.tap(find.text(l10n.themeLight));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(h.cubit.state.themeMode, AppThemeMode.light);
  });

  testWidgets('accent swatch tap updates the custom accent color',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    // Default accent is customAccents[0]; selecting index 5 (dark magenta)
    // exercises both the onTap and the light/dark check-icon luminance branch.
    final swatch = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == '${l10n.accentColor} 6',
    );
    expect(swatch, findsOneWidget);
    await tester.tap(swatch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      h.cubit.state.customAccentColorValue,
      AppColors.customAccents[5].toARGB32(),
    );
  });

  testWidgets('auto dark mode toggle reveals and hides the schedule row',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    expect(find.text(l10n.themeScheduleTitle), findsNothing);

    await tester.tap(find.text(l10n.settingsAutoDarkModeTitle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.cubit.state.autoThemeByTime, isTrue);
    expect(find.text(l10n.themeScheduleTitle), findsOneWidget);
    expect(find.byType(DropdownButton<int>), findsNWidgets(2));

    await tester.tap(find.text(l10n.settingsAutoDarkModeTitle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.cubit.state.autoThemeByTime, isFalse);
    expect(find.text(l10n.themeScheduleTitle), findsNothing);
  });

  testWidgets('accessibility switches drive their cubit setters',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.settingsHighContrastTitle));
    await tester.pump();
    expect(h.cubit.state.highContrast, isTrue);

    await tester.tap(find.text(l10n.settingsDimWhitePointTitle));
    await tester.pump();
    expect(h.cubit.state.dimWhitePoint, isTrue);

    await tester.tap(find.text(l10n.settingsReduceMotionTitle));
    await tester.pump();
    expect(h.cubit.state.reduceMotion, isTrue);

    // The UI-sound row is intentionally un-localized.
    await tester.tap(find.text('UI Sound Effects'));
    await tester.pump();
    expect(SoundFeedbackService.enabled, isTrue);
  });

  testWidgets('liquid glass slider moves the tint value', (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    final before = h.cubit.state.liquidGlassTint;
    expect(find.byType(Slider), findsOneWidget);

    await tester.drag(find.byType(Slider), const Offset(-120, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(h.cubit.state.liquidGlassTint, lessThan(before));
  });

  testWidgets('now playing theme picker selects a karaoke theme',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.nowPlayingTheme));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.selectPlayerTheme), findsOneWidget);
    await tester.tap(inSheet(l10n.settingsThemeKaraoke));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.cubit.state.playerThemeMode, PlayerThemeMode.lyricsFocus);
  });

  testWidgets('visualizer + color source pickers update their state',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.visualizerStyle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.visualizerStyleLabel), findsOneWidget);
    await tester.tap(inSheet(l10n.settingsVizLabelWave));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.cubit.state.visualizerStyle.name, 'wave');

    await tester.tap(find.text(l10n.colorSource));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.appColorSource), findsOneWidget);
    await tester.tap(inSheet(l10n.settingsColorSourceCustom));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.cubit.state.themeColorSource, ThemeColorSource.custom);
  });

  testWidgets('language picker persists the chosen language code',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.language));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.appLanguage), findsOneWidget);
    await tester.tap(inSheet(l10n.arabic));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.cubit.state.languageCode, 'ar');
  });

  testWidgets('dock style picker writes through DockStyleController',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.dockStyleTitle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text(l10n.dockStyleSystem));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(DockStyleController.mode.value, DockStackMode.system);
  });
}
