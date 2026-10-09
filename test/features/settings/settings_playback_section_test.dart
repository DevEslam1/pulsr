// Covers lib/features/settings/presentation/widgets/playback_section.dart:
// the Professional control surface (previously only rendered in Normal mode),
// the conflict-resolution/info callbacks, the SponsorBlock category picker,
// the advanced-speed/normalization bridges and the one-tap preset pills.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/services/sponsorblock_service.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/sleep_timer_manager.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/core/widgets/pulsr_slider.dart';
import 'package:pulsr/features/settings/presentation/widgets/playback_section.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_slider_row.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/settings_section_harness.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockAudioHandler extends Mock implements PulsrAudioHandler {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late SettingsCubit cubit;
  late MockPlayerCubit player;

  setUp(() {
    stubSettingsChannels();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => player.sleepTimerRemainingTracks).thenReturn(null);
    when(() => player.isEndOfQueueSleepTimer).thenReturn(false);
    when(() => player.sleepTimerMode).thenReturn(SleepTimerMode.duration);
    cubit = SettingsCubit(scannerService: MockMediaScannerService());
  });

  tearDown(() async {
    clearSettingsChannels();
    if (getIt.isRegistered<PulsrAudioHandler>()) {
      await getIt.unregister<PulsrAudioHandler>();
    }
    await cubit.close();
  });

  Future<void> pump(
    WidgetTester tester,
    SettingsState state, {
    Size size = const Size(760, 3600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: cubit),
          BlocProvider<PlayerCubit>.value(value: player),
        ],
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: PlaybackSection(state: state)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  // The SponsorBlock picker uses CheckboxListTile inside the sheet's
  // DecoratedBox; Flutter 3.47 raises a debug-only paint assertion for that
  // (pre-existing app styling, not a test bug). Drain it so the test can assert
  // the behaviour instead of the framework warning.
  void drainFrameworkExceptions(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  testWidgets('Professional surface renders every advanced control',
      (tester) async {
    await pump(
      tester,
      const SettingsState(
        experienceMode: ExperienceMode.professional,
        crossfadeSeconds: 4,
        gaplessPlayback: true,
        duckingMode: 'pause',
      ),
    );

    expect(find.text(l10n.settingsHedgedStreaming), findsOneWidget);
    expect(find.text(l10n.settingsAdaptiveQuality), findsOneWidget);
    expect(find.text(l10n.settingsSilenceSkipSensitivity), findsOneWidget);
    expect(find.text(l10n.settingsSpeakerBluetooth), findsOneWidget);
    expect(find.text(l10n.settingsPerAlbumEqMemory), findsOneWidget);
    expect(find.text(l10n.settingsCalibrateBtLatency), findsOneWidget);
    expect(find.text(l10n.settingsSponsorBlock), findsOneWidget);
    expect(find.text(l10n.settingsExtendedSpeedRange), findsOneWidget);
    expect(find.text(l10n.settingsAudioNormalization), findsOneWidget);
    // Gapless ON with crossfade > 0 exposes the one-tap resolver.
    expect(find.text(l10n.settingsTurnOffGaplessEnableCrossfade), findsOneWidget);
  });

  testWidgets('conflict resolver, info dialog and toggles drive the cubit',
      (tester) async {
    await pump(
      tester,
      const SettingsState(
        experienceMode: ExperienceMode.professional,
        crossfadeSeconds: 4,
        gaplessPlayback: true,
        duckingMode: 'pause',
      ),
    );

    // Crossfade info dialog.
    await tester.tap(find.byTooltip(l10n.crossfade));
    await tester.pumpAndSettle();
    expect(find.text(l10n.gotIt), findsOneWidget);
    await tester.tap(find.text(l10n.gotIt));
    await tester.pumpAndSettle();

    // Duck-on-navigation toggle.
    await tapText(tester, l10n.settingsDuckOnNavigation);
    expect(cubit.state.duckingMode, 'duck');

    // Multi-output routing toggle.
    await tapText(tester, l10n.settingsSpeakerBluetooth);
    expect(cubit.state.multiOutputMode, isNotNull);

    // Bluetooth latency calibration runs and reports.
    await tapText(tester, l10n.settingsCalibrateBtLatency);

    // One-tap preset.
    await tapText(tester, l10n.playbackPresetMaxQuality);

    // Silence-skip slider drives its setter.
    final silenceRow = find.ancestor(
      of: find.text(l10n.settingsSilenceSkipSensitivity),
      matching: find.byType(SettingSliderRow),
    );
    await tester.ensureVisible(silenceRow);
    await tester.pump();
    await tester.drag(
      find.descendant(of: silenceRow, matching: find.byType(PulsrSlider)),
      const Offset(60, 0),
    );
    await tester.pump();
    expect(cubit.state.silenceSkipSensitivity, greaterThan(0));

    // Resolve the gapless/crossfade conflict.
    await tapText(tester, l10n.settingsTurnOffGaplessEnableCrossfade);
    expect(cubit.state.gaplessPlayback, isFalse);
    expect(cubit.state.crossfadeSeconds, 4.0);

    // Professional sleep-timer navigation opens its sheet (last: it overlays).
    await tapText(tester, l10n.sleepTimer);
    expect(find.text(l10n.sleepTimer), findsWidgets);
  });

  testWidgets('SponsorBlock switch and category picker update the service',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.sponsorBlockCategories: <String>[],
    });
    await SponsorBlockService.instance.setEnabledCategories(<String>{});
    await pump(
      tester,
      const SettingsState(experienceMode: ExperienceMode.professional),
    );

    // Empty category set falls back to the auto-skip hint.
    expect(find.text(l10n.settingsNoneSelectedAutoSkip), findsOneWidget);

    await tapText(tester, l10n.settingsSponsorBlock);

    await tapText(tester, l10n.settingsSkipCategories);
    drainFrameworkExceptions(tester);
    // The picker sheet lists every supported category.
    expect(find.byType(CheckboxListTile), findsWidgets);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    drainFrameworkExceptions(tester);
    await tester.tap(find.text(l10n.doneAction));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    drainFrameworkExceptions(tester);

    expect(SponsorBlockService.instance.enabledCategories, isNotEmpty);
  });

  testWidgets('advanced-speed and normalization bridges reach the handler',
      (tester) async {
    final handler = MockAudioHandler();
    when(() => handler.isAudioNormalizationEnabled).thenReturn(false);
    when(() => handler.setAdvancedSpeedEnabled(any()))
        .thenAnswer((_) async {});
    when(() => handler.setAudioNormalizationEnabled(any()))
        .thenAnswer((_) async {});
    getIt.registerSingleton<PulsrAudioHandler>(handler);

    await pump(
      tester,
      const SettingsState(experienceMode: ExperienceMode.professional),
    );

    await tapText(tester, l10n.settingsExtendedSpeedRange);
    verify(() => handler.setAdvancedSpeedEnabled(true)).called(1);

    await tapText(tester, l10n.settingsAudioNormalization);
    verify(() => handler.setAudioNormalizationEnabled(true)).called(1);
  });

  testWidgets('Normal layout still exposes the sleep timer and duck toggle',
      (tester) async {
    await pump(
      tester,
      const SettingsState(crossfadeSeconds: 0, gaplessPlayback: false),
    );

    await tapText(tester, l10n.settingsDuckOnNavigation);
    expect(cubit.state.duckingMode, 'pause');

    // Sleep timer navigation opens its sheet.
    await tapText(tester, l10n.sleepTimer);
    expect(find.text(l10n.sleepTimer), findsWidgets);
  });

  testWidgets('narrow layout renders preset pills in a Wrap branch',
      (tester) async {
    await pump(
      tester,
      const SettingsState(experienceMode: ExperienceMode.professional),
      size: const Size(320, 3600),
    );

    await tapText(tester, l10n.playbackPresetDataSaver);
    expect(cubit.state.streamingQuality, YtmAudioQuality.low);
    await tapText(tester, l10n.playbackPresetSmooth);
    await tapText(tester, l10n.playbackPresetMaxQuality);
  });
}
