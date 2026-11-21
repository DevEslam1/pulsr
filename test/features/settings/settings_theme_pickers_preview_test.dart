// test/features/settings/settings_theme_pickers_preview_test.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_chrome.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/features/player/presentation/widgets/radio_now_playing_recommendations.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_theme_pickers.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockSettingsCubit settingsCubit;

  setUpAll(() {
    registerFallbackValue(PlayerThemeMode.classic);
  });

  setUp(() {
    AudioVisualizer.isTestingOverride = true;
    settingsCubit = _MockSettingsCubit();
    when(() => settingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => settingsCubit.setPlayerThemeMode(any()))
        .thenAnswer((_) async {});
  });

  tearDown(() {
    AudioVisualizer.isTestingOverride = null;
  });

  final surfaceModes = <String, ({ThemeData theme, AppThemeMode mode})>{
    'Light': (theme: AuraTheme.lightTheme, mode: AppThemeMode.light),
    'Dark': (theme: AuraTheme.darkTheme, mode: AppThemeMode.dark),
    'AMOLED': (theme: AuraTheme.amoledTheme, mode: AppThemeMode.amoled),
  };

  for (final entry in surfaceModes.entries) {
    testWidgets(
      'showThemePickerSheet renders live isPreview thumbnails without overflow in ${entry.key} mode',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        when(() => settingsCubit.state).thenReturn(
          SettingsState(
            themeMode: entry.value.mode,
            playerThemeMode: PlayerThemeMode.classic,
            reduceMotion: true,
          ),
        );

        final playerCubit = stubPlayerCubit(
          PlayerState(
            playback: PlaybackSlice(
              currentSong: createTestSong(
                id: 505,
                title: 'Live Broadcast Radio Session',
                artist: 'Studio FM',
                source: SongSource.radio,
              ),
              isPlaying: true,
              position: const Duration(seconds: 40),
              duration: const Duration(minutes: 3),
              bookmarkPosition: const Duration(seconds: 25),
            ),
            lyricsSlice: const LyricsSlice(isLyricsVisible: true),
          ),
        );

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: playerCubit),
              BlocProvider<SettingsCubit>.value(value: settingsCubit),
            ],
            child: MaterialApp(
              theme: entry.value.theme,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(390, 844),
                  textScaler: TextScaler.linear(1.3),
                ),
                child: Scaffold(
                  body: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => showThemePickerSheet(
                        context,
                        settingsCubit,
                        PlayerThemeMode.classic,
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          tester.takeException(),
          isNull,
          reason: 'Theme picker sheet overflowed in ${entry.key} mode',
        );
        expect(find.byType(RadioNowPlayingRecommendations), findsNothing);
        expect(find.byType(PlayerBookmarkPromptBanner), findsNothing);
        expect(find.byType(PlayerViewSwitcher), findsNothing);
      },
    );
  }
}
