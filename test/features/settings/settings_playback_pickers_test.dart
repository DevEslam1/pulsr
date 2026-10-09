// Covers lib/features/settings/presentation/widgets/settings_playback_pickers.dart
// (mini-player swipe, double-tap, artwork-swipe and quality picker sheets).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_playback_pickers.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/settings_section_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late SettingsCubit cubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    stubSettingsChannels();
    cubit = SettingsCubit(scannerService: MockMediaScannerService());
  });

  tearDown(() {
    clearSettingsChannels();
    cubit.close();
  });

  Future<void> launch(
    WidgetTester tester,
    void Function(BuildContext context) open,
  ) async {
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

  Future<void> tapOption(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('left mini-player swipe picker selects the volume action',
      (tester) async {
    await launch(
      tester,
      (context) => showMiniPlayerSwipePickerSheet(
        context,
        cubit,
        isLeft: true,
        currentAction: cubit.state.miniPlayerSwipeLeft,
      ),
    );

    expect(find.text(l10n.settingsSwipeLeftAction), findsOneWidget);
    await tapOption(tester, l10n.settingsSwipeAdjustVolume);
    expect(cubit.state.miniPlayerSwipeLeft, MiniPlayerSwipeAction.volume);
  });

  testWidgets('right mini-player swipe picker selects the next-track action',
      (tester) async {
    await launch(
      tester,
      (context) => showMiniPlayerSwipePickerSheet(
        context,
        cubit,
        isLeft: false,
        currentAction: cubit.state.miniPlayerSwipeRight,
      ),
    );

    expect(find.text(l10n.settingsSwipeRightAction), findsOneWidget);
    await tapOption(tester, l10n.settingsSwipeNextTrack);
    expect(cubit.state.miniPlayerSwipeRight, MiniPlayerSwipeAction.next);
  });

  testWidgets('double-tap picker selects the lyrics action', (tester) async {
    await launch(
      tester,
      (context) => showNowPlayingDoubleTapPickerSheet(
        context,
        cubit,
        cubit.state.nowPlayingDoubleTap,
      ),
    );

    expect(find.text(l10n.npDoubleTap), findsOneWidget);
    await tapOption(tester, l10n.settingsDoubleTapToggleLyrics);
    expect(cubit.state.nowPlayingDoubleTap, NowPlayingDoubleTapAction.toggleLyrics);
  });

  testWidgets('artwork-swipe picker can disable the gesture', (tester) async {
    await launch(
      tester,
      (context) => showNowPlayingArtworkSwipePickerSheet(
        context,
        cubit,
        cubit.state.nowPlayingArtworkSwipe,
      ),
    );

    expect(find.text(l10n.npArtworkSwipe), findsOneWidget);
    await tapOption(tester, l10n.settingsArtworkSwipeDisabled);
    expect(cubit.state.nowPlayingArtworkSwipe, NowPlayingArtworkSwipeAction.none);
  });

  testWidgets('streaming quality picker writes streamingQuality',
      (tester) async {
    await launch(
      tester,
      (context) => showQualityPickerSheet(
        context,
        cubit,
        isStreaming: true,
        currentQuality: cubit.state.streamingQuality,
      ),
    );

    expect(find.text(l10n.streamingQuality), findsOneWidget);
    await tapOption(tester, l10n.settingsQualityMedium);
    expect(cubit.state.streamingQuality, YtmAudioQuality.medium);
  });

  testWidgets('download quality picker writes downloadQuality',
      (tester) async {
    await launch(
      tester,
      (context) => showQualityPickerSheet(
        context,
        cubit,
        isStreaming: false,
        currentQuality: cubit.state.downloadQuality,
      ),
    );

    expect(find.text(l10n.downloadQuality), findsOneWidget);
    await tapOption(tester, l10n.settingsQualityLow);
    expect(cubit.state.downloadQuality, YtmAudioQuality.low);
  });
}
