// test/features/player/player_themes_preview_test.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/card_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/cassette_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/cd_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/clean_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/lyrics_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/milkdrop_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_chrome.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/player/presentation/themes/vinyl_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/waveform_player_theme.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/features/player/presentation/widgets/lyrics_view.dart';
import 'package:pulsr/features/player/presentation/widgets/now_playing_queue_view.dart';
import 'package:pulsr/features/player/presentation/widgets/radio_now_playing_recommendations.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/test_song_factory.dart';

class _FakePlayerCubit extends Fake implements PlayerCubit {}

class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ThemeRegistry.reset();
    AudioVisualizer.isTestingOverride = true;
  });

  tearDown(() {
    ThemeRegistry.reset();
    AudioVisualizer.isTestingOverride = null;
  });

  group('Player Themes Preview Suite (ThemeRegistry.preview)', () {
    final fakeCubit = _FakePlayerCubit();
    final dummyProps = PlayerThemeProps(
      state: const PlayerState(),
      cubit: fakeCubit,
      activeColor: const Color(0xFF6750A4),
      bgColor: const Color(0xFF1C1B1F),
    );

    test('preview() wraps built theme with IgnorePointer and 360x640 bounds',
        () {
      final previewWidget = ThemeRegistry.preview(
        PlayerThemeMode.clean,
        dummyProps,
        scale: 0.5,
      );

      expect(previewWidget, isA<IgnorePointer>());
      final ignorePointer = previewWidget as IgnorePointer;
      expect(ignorePointer.child, isA<SizedBox>());

      final bounds = ignorePointer.child! as SizedBox;
      expect(bounds.width, 180);
      expect(bounds.height, 320);
      final fitted = bounds.child! as FittedBox;
      final sizedBox = fitted.child! as SizedBox;
      expect(sizedBox.width, 360);
      expect(sizedBox.height, 640);
      expect(sizedBox.child, isA<PlayerThemePreviewHost>());
      final host = sizedBox.child! as PlayerThemePreviewHost;
      expect(host.child, isA<CleanPlayerTheme>());
    });

    test('preview() with isPreview: false exposes raw theme directly', () {
      final previewWidget = ThemeRegistry.preview(
        PlayerThemeMode.clean,
        dummyProps,
        scale: 0.5,
        isPreview: false,
      ) as IgnorePointer;

      final bounds = previewWidget.child! as SizedBox;
      final fitted = bounds.child! as FittedBox;
      final sizedBox = fitted.child! as SizedBox;
      expect(sizedBox.child, isA<CleanPlayerTheme>());
    });

    test('preview() correctly builds all 8 theme modes', () {
      final modes = <PlayerThemeMode, Type>{
        PlayerThemeMode.clean: CleanPlayerTheme,
        PlayerThemeMode.card: CardPlayerTheme,
        PlayerThemeMode.vinyl: VinylPlayerTheme,
        PlayerThemeMode.cd: CdPlayerTheme,
        PlayerThemeMode.cassette: CassettePlayerTheme,
        PlayerThemeMode.waveform: WaveformPlayerTheme,
        PlayerThemeMode.lyricsFocus: LyricsPlayerTheme,
        PlayerThemeMode.milkdrop: MilkdropPlayerTheme,
      };

      for (final entry in modes.entries) {
        final preview = ThemeRegistry.preview(
          entry.key,
          dummyProps,
          isPreview: true,
        );
        final ignorePointer = preview as IgnorePointer;
        final bounds = ignorePointer.child! as SizedBox;
        final fitted = bounds.child! as FittedBox;
        final sizedBox = fitted.child! as SizedBox;
        final host = sizedBox.child! as PlayerThemePreviewHost;
        expect(
          host.child.runtimeType,
          entry.value,
          reason: 'Expected ${entry.key} to build ${entry.value}',
        );
      }
    });

    test('preview() scale sets layout dimensions as well as visual size', () {
      const targetScale = 0.35;
      final preview = ThemeRegistry.preview(
              PlayerThemeMode.waveform, dummyProps, scale: targetScale)
          as IgnorePointer;
      final bounds = preview.child! as SizedBox;
      expect(bounds.width, closeTo(360 * targetScale, 0.001));
      expect(bounds.height, closeTo(640 * targetScale, 0.001));
      expect((bounds.child! as FittedBox).fit, BoxFit.contain);
    });

    test('preview() lays the theme out on the requested canvas size', () {
      const canvas = Size(392, 872);
      const targetScale = 0.125;
      final preview = ThemeRegistry.preview(
        PlayerThemeMode.clean,
        dummyProps,
        scale: targetScale,
        canvasSize: canvas,
      ) as IgnorePointer;

      final bounds = preview.child! as SizedBox;
      expect(bounds.width, closeTo(canvas.width * targetScale, 0.001));
      expect(bounds.height, closeTo(canvas.height * targetScale, 0.001));

      final inner = (bounds.child! as FittedBox).child! as SizedBox;
      expect(inner.width, canvas.width);
      expect(inner.height, canvas.height);
    });
  });

  group('ThemeRegistry.preview(isPreview: true) layout across all 8 themes',
      () {
    late _MockPlayerCubit playerCubit;
    late _MockSettingsCubit settingsCubit;

    final radioSong = createTestSong(
      id: 901,
      title: 'Late Night Radio Stream With Extra Long Broadcast Title',
      artist: 'FM 99.5 Live Studio',
      source: SongSource.radio,
    );

    setUp(() {
      playerCubit = _MockPlayerCubit();
      settingsCubit = _MockSettingsCubit();

      // Deliberately populate transient chrome: radio source, bookmark banner,
      // lyrics overlay, AB loop, and playing state. `isPreview: true` must
      // suppress every one of them and render cleanly without overflow.
      when(() => playerCubit.state).thenReturn(
        PlayerState(
          playback: PlaybackSlice(
            currentSong: radioSong,
            isPlaying: true,
            position: const Duration(minutes: 1, seconds: 20),
            duration: const Duration(minutes: 4, seconds: 10),
            bookmarkPosition: const Duration(seconds: 42),
            abLoopEnabled: true,
            abPointA: const Duration(seconds: 15),
            abPointB: const Duration(seconds: 90),
          ),
          lyricsSlice: const LyricsSlice(
            isLyricsVisible: true,
          ),
        ),
      );
      when(() => playerCubit.stream).thenAnswer((_) => const Stream.empty());
      when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
    });

    final surfaceModes = <String, ({ThemeData theme, AppThemeMode mode})>{
      'Light': (theme: AuraTheme.lightTheme, mode: AppThemeMode.light),
      'Dark': (theme: AuraTheme.darkTheme, mode: AppThemeMode.dark),
      'AMOLED': (theme: AuraTheme.amoledTheme, mode: AppThemeMode.amoled),
    };

    for (final surfaceEntry in surfaceModes.entries) {
      testWidgets(
        'renders all 8 themes cleanly with zero overflow in ${surfaceEntry.key} mode',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          when(() => settingsCubit.state).thenReturn(
            SettingsState(
              themeMode: surfaceEntry.value.mode,
              visualizerStyle: VisualizerStyle.milkdrop,
            ),
          );

          final palette = surfaceEntry.value.theme.extension<PulsrPalette>()!;

          for (final mode in PlayerThemeMode.values) {
            final props = PlayerThemeProps(
              state: playerCubit.state,
              cubit: playerCubit,
              activeColor: palette.accent,
              bgColor: palette.bg,
            );

            await tester.pumpWidget(
              MultiBlocProvider(
                providers: [
                  BlocProvider<PlayerCubit>.value(value: playerCubit),
                  BlocProvider<SettingsCubit>.value(value: settingsCubit),
                ],
                child: MaterialApp(
                  theme: surfaceEntry.value.theme,
                  localizationsDelegates: appLocalizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: MediaQuery(
                    data: const MediaQueryData(
                      size: Size(390, 844),
                      padding: EdgeInsets.only(top: 44, bottom: 34),
                      textScaler: TextScaler.linear(1.6),
                    ),
                    child: Scaffold(
                      body: Center(
                        child: ThemeRegistry.preview(
                          mode,
                          props,
                          scale: 0.25,
                          canvasSize: const Size(360, 640),
                          isPreview: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 50));

            expect(
              tester.takeException(),
              isNull,
              reason:
                  '${mode.name} overflowed or threw in ${surfaceEntry.key} preview',
            );
            expect(
              find.byType(RadioNowPlayingRecommendations),
              findsNothing,
              reason: '${mode.name} leaked radio card into preview',
            );
            expect(
              find.byType(PlayerBookmarkPromptBanner),
              findsNothing,
              reason: '${mode.name} leaked bookmark banner into preview',
            );
            expect(
              find.byType(LyricsView),
              findsNothing,
              reason: '${mode.name} leaked lyrics overlay into preview',
            );
            expect(
              find.byType(NowPlayingQueueView),
              findsNothing,
              reason: '${mode.name} leaked queue overlay into preview',
            );
            expect(
              find.byType(PlayerViewSwitcher),
              findsNothing,
              reason: '${mode.name} leaked view switcher chrome into preview',
            );
          }
        },
      );
    }
  });
}
