// Covers lib/features/settings/presentation/sections/library_section.dart
// (scan progress, duration-filter dialog, maintenance actions).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../support/settings_section_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(stubSettingsChannels);
  tearDown(clearSettingsChannels);

  testWidgets('renders every library row', (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'library');
    addTearDown(h.cubit.close);

    expect(find.text(l10n.libraryAndScanning.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.hiddenAndExcludedFolders), findsOneWidget);
    expect(find.text(l10n.rescanLibrary), findsOneWidget);
    expect(find.text(l10n.shortAudioFilter), findsOneWidget);
    expect(find.text(l10n.settingsRebuildSearchIndexTitle), findsOneWidget);
    expect(find.text(l10n.removeMissingFiles), findsOneWidget);
    expect(find.text(l10n.fetchMissingArtworkTooltip), findsOneWidget);
  });

  testWidgets('auto-hide branch swaps the hidden-folders subtitle',
      (tester) async {
    final h = await pumpSettingsCategory(
      tester,
      category: 'library',
      seedState: const SettingsState(autoHideSystemMedia: false),
    );
    addTearDown(h.cubit.close);

    expect(find.text(l10n.manageExcludedDirectories), findsOneWidget);
    expect(find.text(l10n.autoFilteringVoiceMemos), findsNothing);
  });

  testWidgets('scanning state shows the progress affordances', (tester) async {
    final h = await pumpSettingsCategory(
      tester,
      category: 'library',
      seedState: const SettingsState(isScanning: true, scanResultCount: 5),
    );
    addTearDown(h.cubit.close);

    expect(find.text(l10n.scanningStorage), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // While scanning the row is inert.
    await tester.tap(find.text(l10n.scanningStorage));
    await tester.pump();
  });

  testWidgets('rescan runs the scanner and stores the result count',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'library');
    addTearDown(h.cubit.close);

    when(
      () => h.scanner.scanDeviceLibrary(
        ignoreShortFiles: true,
        minDurationSec: 30,
        minSizeKb: 0,
        autoHideSystemMedia: true,
      ),
    ).thenAnswer((_) async => 12);

    await tester.tap(find.text(l10n.rescanLibrary));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.cubit.state.scanResultCount, 12);
    expect(h.cubit.state.isScanning, isFalse);
  });

  testWidgets('duration filter dialog can save a new minimum',
      (tester) async {
    final h = await pumpSettingsCategory(
      tester,
      category: 'library',
      seedState: const SettingsState(minDurationSec: 15),
    );
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.shortAudioFilter));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.minDuration), findsOneWidget);

    // Reset-to-default then Save.
    await tester.tap(find.byTooltip(l10n.resetToDefault30s));
    await tester.pump();
    await tester.tap(find.text(l10n.save));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.cubit.state.minDurationSec, 30);
  });

  testWidgets('duration filter dialog can be cancelled', (tester) async {
    final h = await pumpSettingsCategory(
      tester,
      category: 'library',
      seedState: const SettingsState(minDurationSec: 15),
    );
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.shortAudioFilter));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text(l10n.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.cubit.state.minDurationSec, 15);
  });

  testWidgets('rebuild search index reports failure when the DB is absent',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'library');
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.settingsRebuildSearchIndexTitle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.settingsSearchIndexRebuildFailed), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('remove-missing-files flow: cancel then confirm',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'library');
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.removeMissingFiles));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.removeMissingFilesConfirmTitle), findsOneWidget);

    await tester.tap(find.text(l10n.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.removeMissingFilesConfirmTitle), findsNothing);

    await tester.tap(find.text(l10n.removeMissingFiles));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.remove));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.removedMissingTracks(0)), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('fetch-missing-artwork confirm path degrades gracefully',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'library');
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.fetchMissingArtworkTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.fetchMissingArtworkTitle), findsOneWidget);

    await tester.tap(find.text(l10n.fetchArtwork));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The service is unavailable in tests, so a snackbar must resolve it.
    expect(find.byType(SnackBar), findsWidgets);
    await tester.pump(const Duration(seconds: 10));
  });
}
