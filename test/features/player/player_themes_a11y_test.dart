// Accessibility regression guard for the Now Playing themes.
//
// Every registered theme must (a) announce the current track (including the
// cover art, which is an image node rather than unlabelled decoration), (b)
// expose its progress as a slider reading "position / duration", and (c) keep
// labelled, tappable transport controls of at least 48x48 logical pixels.
import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/utils/formatters.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';
import '../../helpers/test_song_factory.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

/// The concrete themes registered by [ThemeRegistry], in registry order.
const List<PlayerThemeMode> _registeredThemes = <PlayerThemeMode>[
  PlayerThemeMode.clean,
  PlayerThemeMode.card,
  PlayerThemeMode.vinyl,
  PlayerThemeMode.cd,
  PlayerThemeMode.cassette,
  PlayerThemeMode.waveform,
  PlayerThemeMode.lyricsFocus,
  PlayerThemeMode.milkdrop,
];

/// Size of the tappable surface around [icon]: the theme controls wrap their
/// glyphs in InkWell / InkResponse / GestureDetector depending on the design.
Size _tapTargetSize(WidgetTester tester, Finder icon) {
  for (final Type type in <Type>[InkWell, InkResponse, GestureDetector]) {
    final Finder ancestor =
        find.ancestor(of: icon, matching: find.byType(type));
    if (ancestor.evaluate().isNotEmpty) return tester.getSize(ancestor.first);
  }
  final Finder button = find.ancestor(
    of: icon,
    matching: find.byWidgetPredicate((Widget widget) => widget is IconButton),
  );
  return tester.getSize(button.first);
}

void main() {
  late MockPlayerCubit playerCubit;
  late MockSettingsCubit settingsCubit;

  final song = createTestSong(
    id: 1,
    title: 'Solar Resonance',
    artist: 'Pulsr Ensemble',
    album: 'Audiophile Sessions',
    durationMs: 240000,
    path: '/music/solar.flac',
    bitrateKbps: 960,
  );

  setUp(() {
    playerCubit = MockPlayerCubit();
    settingsCubit = MockSettingsCubit();

    when(() => playerCubit.state).thenReturn(
      PlayerState(
        playback: PlaybackSlice(
          currentSong: song,
          isPlaying: false,
          duration: const Duration(minutes: 4),
          position: const Duration(minutes: 1),
        ),
      ),
    );
    when(() => playerCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget harness(PlayerThemeMode mode) {
    final props = PlayerThemeProps(
      state: playerCubit.state,
      cubit: playerCubit,
      activeColor: const Color(0xFF6750A4),
      bgColor: const Color(0xFF1C1B1F),
    );
    return MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: [AuraTheme.defaultDark]),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: playerCubit),
              BlocProvider<SettingsCubit>.value(value: settingsCubit),
            ],
            child: PlayerSplitViewScope(
              isInSplitView: false,
              child: SizedBox(
                width: 400,
                height: 800,
                child: ThemeRegistry.build(mode, props),
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final PlayerThemeMode mode in _registeredThemes) {
    testWidgets('${mode.name} theme announces artwork and progress',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(harness(mode));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester.takeException(),
        isNull,
        reason: '${mode.name} threw while rendering',
      );

      final List<SemanticsNode> nodes =
          tester.semantics.simulatedAccessibilityTraversal().toList();
      expect(nodes, isNotEmpty, reason: '${mode.name} exposes no semantics');

      // (a) The current track is announced somewhere on the screen.
      expect(
        nodes.where((SemanticsNode node) => node.label.contains(song.title)),
        isNotEmpty,
        reason: '${mode.name} never announces "${song.title}"',
      );

      // (a2) Cover art is announced as artwork carrying the track name. The
      // cassette theme paints a physical tape label instead of cover art, so it
      // relies on the plain title/artist text it prints on the shell.
      if (mode != PlayerThemeMode.cassette) {
        final Iterable<SemanticsNode> artwork = nodes.where(
          (SemanticsNode node) =>
              node.flagsCollection.isImage && node.label.contains(song.title),
        );
        expect(
          artwork,
          isNotEmpty,
          reason:
              '${mode.name} renders cover art without a labelled image node',
        );
      }

      // (b) No nameless buttons: an icon button may take its name from the
      // label, the value or the Material tooltip, but one of them must exist.
      final List<SemanticsNode> nameless = nodes
          .where((SemanticsNode node) =>
              node.flagsCollection.isButton &&
              node.label.trim().isEmpty &&
              node.value.trim().isEmpty &&
              node.tooltip.trim().isEmpty)
          .toList();
      expect(
        nameless,
        isEmpty,
        reason: '${mode.name} has unlabelled buttons at '
            '${nameless.map((SemanticsNode node) => node.rect).toList()}',
      );

      // (c) The play/pause control keeps a 48x48 tap target.
      final Finder playPause = find.byIcon(Icons.play_arrow_rounded);
      expect(
        playPause,
        findsOneWidget,
        reason: '${mode.name} must expose exactly one play control',
      );
      final Size target = _tapTargetSize(tester, playPause);
      expect(target.width, greaterThanOrEqualTo(48.0),
          reason: '${mode.name} play target is ${target.width} wide');
      expect(target.height, greaterThanOrEqualTo(48.0),
          reason: '${mode.name} play target is ${target.height} tall');

      // (d) Progress is a slider whose value reads position of duration.
      final String position =
          Formatters.formatDuration(const Duration(minutes: 1));
      final String duration =
          Formatters.formatDuration(const Duration(minutes: 4));
      final List<SemanticsNode> sliders = nodes
          .where((SemanticsNode node) => node.flagsCollection.isSlider)
          .toList();
      expect(sliders, isNotEmpty, reason: '${mode.name} exposes no slider');
      expect(
        sliders.where((SemanticsNode node) =>
            node.value.contains(position) && node.value.contains(duration)),
        isNotEmpty,
        reason: '${mode.name} slider values '
            '${sliders.map((SemanticsNode node) => node.value).toList()} '
            'do not read "$position of $duration"',
      );

      handle.dispose();
    });
  }
}
