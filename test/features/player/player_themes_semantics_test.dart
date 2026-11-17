// test/features/player/player_themes_semantics_test.dart
//
// Bar 2 of the Now Playing theme contract: a scrub surface is a slider and
// nothing else. When the `Semantics(slider: true)` wrapper is missing its
// merge boundary, Flutter folds the deck's stage node into it, and the reader
// is handed one node that is a slider *and* answers a single tap (which the
// stage binds to lyrics). The existing a11y suite only looks at `isSlider` and
// the announced value, so it passes either way — this test looks at the
// combination that actually breaks the reading experience.
import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/test_song_factory.dart';

class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockPlayerCubit playerCubit;
  late _MockSettingsCubit settingsCubit;

  final song = createTestSong(
    id: 4242,
    title: 'A Very Long Track Title That Must Ellipsise Gracefully Everywhere',
    artist: 'The Audiophile Ensemble',
  );

  setUp(() {
    AudioVisualizer.isTestingOverride = true;
    playerCubit = _MockPlayerCubit();
    settingsCubit = _MockSettingsCubit();

    when(() => playerCubit.state).thenReturn(
      PlayerState(
        playback: PlaybackSlice(
          currentSong: song,
          isPlaying: true,
          position: const Duration(seconds: 61),
          duration: const Duration(seconds: 402),
        ),
      ),
    );
    when(() => playerCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  tearDown(() {
    AudioVisualizer.isTestingOverride = null;
  });

  Widget host(PlayerThemeMode mode) {
    when(() => settingsCubit.state).thenReturn(
      SettingsState(playerThemeMode: mode),
    );

    final props = PlayerThemeProps(
      state: playerCubit.state,
      cubit: playerCubit,
      activeColor: const Color(0xFF7C6BFF),
      bgColor: const Color(0xFF101014),
    );

    return MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: playerCubit),
              BlocProvider<SettingsCubit>.value(value: settingsCubit),
            ],
            child: ThemeRegistry.build(mode, props),
          ),
        ),
      ),
    );
  }

  for (final mode in PlayerThemeMode.values) {
    testWidgets('${mode.name} never fuses a slider with the stage tap',
        (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(host(mode));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 320));

      final List<SemanticsNode> nodes =
          tester.semantics.simulatedAccessibilityTraversal().toList();

      final List<SemanticsNode> fused = nodes.where((SemanticsNode node) {
        final SemanticsData data = node.getSemanticsData();
        return node.flagsCollection.isSlider &&
            (data.hasAction(SemanticsAction.tap) ||
                node.flagsCollection.isButton);
      }).toList();

      expect(
        fused,
        isEmpty,
        reason: '${mode.name} merges a scrub slider with a tap/button node: '
            '${fused.map((SemanticsNode n) => "label=${n.label} value=${n.value}").toList()}',
      );

      // A scrub surface must still be announced as a slider, otherwise the
      // merge boundary was "fixed" by removing the control altogether.
      final List<SemanticsNode> sliders = nodes
          .where((SemanticsNode node) => node.flagsCollection.isSlider)
          .toList();
      expect(
        sliders,
        isNotEmpty,
        reason: '${mode.name} exposes no slider at all',
      );

      handle.dispose();
    });
  }
}
