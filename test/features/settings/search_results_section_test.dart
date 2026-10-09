// Covers lib/features/settings/presentation/sections/search_results_section.dart
// through the real SettingsScreen search flow: the empty-state suggestion
// chips, the PRO badge, and every search entry's onTap (category jumps, inline
// toggles and the equalizer fallback).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/sound_feedback_service.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'support/settings_section_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    stubSettingsChannels();
    SoundFeedbackService.resetForTesting();
  });
  tearDown(() {
    clearSettingsChannels();
    SoundFeedbackService.resetForTesting();
  });

  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> tapResult(WidgetTester tester, String title) async {
    // Restrict to the result tile so the search field's own text (which equals
    // the query) is not matched too.
    final finder = find
        .descendant(
          of: find.byType(ListTile),
          matching: find.text(title),
        )
        .first;
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('no-results state offers suggestion chips that seed the query',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'sound');
    addTearDown(h.cubit.close);

    await type(tester, 'zzzznotathing');

    expect(find.text(l10n.settingsNoSettingsFound('zzzznotathing')),
        findsOneWidget);
    expect(find.text('Equalizer'), findsOneWidget);

    // Tapping a suggestion writes it into the field and re-runs the search.
    await tester.tap(find.text('Equalizer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text(l10n.settingsNoSettingsFound('zzzznotathing')), findsNothing);
  });

  testWidgets('top-level destination entries jump to their category',
      (tester) async {
    final h = await pumpSettingsCategory(
      tester,
      category: 'sound',
      seedState: const SettingsState(experienceMode: ExperienceMode.professional),
    );
    addTearDown(h.cubit.close);

    for (final title in [
      l10n.settingsSectionSoundPlayback,
      l10n.settingsSectionAppearanceGestures,
      l10n.libraryAndScanning,
      l10n.networkAndProxy,
      l10n.privacyAndData,
      l10n.about,
    ]) {
      await type(tester, title);
      await tapResult(tester, title);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaf entries toggle their state and navigate',
      (tester) async {
    final h = await pumpSettingsCategory(
      tester,
      category: 'look',
      seedState: const SettingsState(experienceMode: ExperienceMode.professional),
    );
    addTearDown(h.cubit.close);

    await type(tester, l10n.settingsSearchThemeModeTitle);
    await tapResult(tester, l10n.settingsSearchThemeModeTitle);

    await type(tester, l10n.settingsSearchAccentColorTitle);
    await tapResult(tester, l10n.settingsSearchAccentColorTitle);

    await type(tester, l10n.settingsAutoDarkModeTitle);
    await tapResult(tester, l10n.settingsAutoDarkModeTitle);
    expect(h.cubit.state.autoThemeByTime, isTrue);
    // Stop the schedule's periodic timer before teardown.
    await h.cubit.setAutoThemeByTime(false);

    await type(tester, l10n.settingsSearchHighContrastTitle);
    await tapResult(tester, l10n.settingsSearchHighContrastTitle);
    expect(h.cubit.state.highContrast, isTrue);

    await type(tester, l10n.settingsDimWhitePointTitle);
    await tapResult(tester, l10n.settingsDimWhitePointTitle);
    expect(h.cubit.state.dimWhitePoint, isTrue);

    await type(tester, l10n.settingsReduceMotionTitle);
    await tapResult(tester, l10n.settingsReduceMotionTitle);
    expect(h.cubit.state.reduceMotion, isTrue);

    await type(tester, 'UI Sound Effects');
    await tapResult(tester, 'UI Sound Effects');
    expect(SoundFeedbackService.enabled, isTrue);
  });

  testWidgets('PRO entries surface the badge and the bit-perfect jump',
      (tester) async {
    final h = await pumpSettingsCategory(
      tester,
      category: 'sound',
      seedState: const SettingsState(experienceMode: ExperienceMode.professional),
    );
    addTearDown(h.cubit.close);

    await type(tester, l10n.settingsSearchBitPerfectTitle);
    expect(find.text('PRO'), findsWidgets);
    await tapResult(tester, l10n.settingsSearchBitPerfectTitle);
    expect(tester.takeException(), isNull);
  });

  testWidgets('equalizer, crossfade, swipe, rebuild and cache entries fire',
      (tester) async {
    final h = await pumpSettingsCategory(
      tester,
      category: 'sound',
      seedState: const SettingsState(experienceMode: ExperienceMode.professional),
    );
    addTearDown(h.cubit.close);

    await type(tester, l10n.equalizerAndSoundEffects);
    await tapResult(tester, l10n.equalizerAndSoundEffects);

    await type(tester, l10n.settingsSearchCrossfadeTitle);
    await tapResult(tester, l10n.settingsSearchCrossfadeTitle);

    await type(tester, l10n.settingsSearchSwipeTitle);
    await tapResult(tester, l10n.settingsSearchSwipeTitle);

    await type(tester, l10n.settingsRebuildSearchIndexTitle);
    await tapResult(tester, l10n.settingsRebuildSearchIndexTitle);

    await type(tester, l10n.settingsSearchCacheTitle);
    await tapResult(tester, l10n.settingsSearchCacheTitle);

    expect(tester.takeException(), isNull);
  });
}
