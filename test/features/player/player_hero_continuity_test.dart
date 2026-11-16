// test/features/player/player_hero_continuity_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/player/presentation/widgets/tablet_player_bar.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';
class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

const _testSong = SongsTableData(
  id: 42,
  title: 'Continuity Overture',
  artist: 'Audiophile Maestro',
  album: 'Continuity Suite',
  durationMs: 300000,
  path: '/music/continuity.flac',
  dateAdded: 0,
  playCount: 10,
  lastPositionMs: 50000,
  isFavorite: true,
  isMissing: false,
  source: 'local',
  isDownloaded: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    mockSettingsCubit = MockSettingsCubit();

    when(() => mockPlayerCubit.state).thenReturn(
      const PlayerState(
        playback: PlaybackSlice(
          currentSong: _testSong,
          isPlaying: true,
          duration: Duration(minutes: 5),
          position: Duration(seconds: 50),
        ),
      ),
    );
    when(() => mockPlayerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => mockPlayerCubit.isMuted).thenReturn(false);

    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
  });

  Widget buildHarness({
    required Widget child,
    Size size = const Size(400, 800),
    bool isInSplitView = false,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
        BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
      ],
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark().copyWith(
          extensions: [AuraTheme.defaultDark],
        ),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: PlayerSplitViewScope(
            isInSplitView: isInSplitView,
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      ),
    );
  }

  group('P7 Continuity & Delight — Hero Tag Verification across 11 Themes', () {
    for (final mode in PlayerThemeMode.values) {
      testWidgets(
          'Theme ${mode.name} renders full artwork Hero with tag nowPlayingArtHeroTag(${mode.name})',
          (tester) async {
        final expectedTag = nowPlayingArtHeroTag(mode);
        expect(expectedTag, 'now_playing_art_${mode.name}');

        final props = PlayerThemeProps(
          state: mockPlayerCubit.state,
          cubit: mockPlayerCubit,
          activeColor: const Color(0xFF00E5FF),
          bgColor: const Color(0xFF121212),
        );

        final themeWidget = ThemeRegistry.build(mode, props);

        await tester.pumpWidget(
          buildHarness(
            child: themeWidget,
            size: const Size(412, 892),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Must find Hero with the theme's expectedTag
        final heroFinder = find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == expectedTag,
        );
        expect(heroFinder, findsAtLeastNWidgets(1),
            reason:
                'Theme ${mode.name} must render Hero with tag $expectedTag');
      });

      testWidgets(
          'Theme ${mode.name} in Tablet Split View preserves Hero flight tag',
          (tester) async {
        final expectedTag = nowPlayingArtHeroTag(mode);

        final props = PlayerThemeProps(
          state: mockPlayerCubit.state,
          cubit: mockPlayerCubit,
          activeColor: const Color(0xFF00E5FF),
          bgColor: const Color(0xFF121212),
        );

        final themeWidget = ThemeRegistry.build(mode, props);

        await tester.pumpWidget(
          buildHarness(
            child: themeWidget,
            size: const Size(1280, 800),
            isInSplitView: true,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final heroFinder = find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == expectedTag,
        );
        expect(heroFinder, findsAtLeastNWidgets(1),
            reason:
                'Theme ${mode.name} in split view must render Hero with tag $expectedTag');
      });
    }

    testWidgets(
        'TabletPlayerBar renders matching Hero tag for active theme mode',
        (tester) async {
      for (final mode in [
        PlayerThemeMode.classic,
        PlayerThemeMode.card,
        PlayerThemeMode.milkdrop
      ]) {
        when(() => mockSettingsCubit.state).thenReturn(
          SettingsState(playerThemeMode: mode),
        );

        await tester.pumpWidget(
          buildHarness(
            child: TabletPlayerBar(
              onOpenNowPlaying: () {},
            ),
            size: const Size(1024, 768),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final expectedTag = nowPlayingArtHeroTag(mode);
        final heroFinder = find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == expectedTag,
        );
        expect(heroFinder, findsOneWidget,
            reason:
                'TabletPlayerBar must render Hero with tag $expectedTag when mode is ${mode.name}');
      }
    });
  });
}
