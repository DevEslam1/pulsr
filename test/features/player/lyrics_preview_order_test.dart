// test/features/player/lyrics_preview_order_test.dart
//
// The lyrics theme draws a three-line preview under the cover and finds the
// singing line by binary search. Binary search is only correct over a monotonic
// list, and LRC sheets exported by converters or hand-edited in a text editor
// are routinely out of order — so the theme has to repair the order before it
// searches. This test fails if that repair is dropped: with the unsorted sheet
// below, an unguarded binary search settles on "First" instead of "Second".
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
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

  const activeColor = Color(0xFF7C6BFF);

  testWidgets('lyric preview highlights the right line for an unsorted sheet',
      (tester) async {
    AudioVisualizer.isTestingOverride = true;
    addTearDown(() => AudioVisualizer.isTestingOverride = null);

    // A tall surface so the theme can afford the preview block under the cover.
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final playerCubit = _MockPlayerCubit();
    final settingsCubit = _MockSettingsCubit();
    final song = createTestSong(id: 7, title: 'Sorted', artist: 'Order');

    // Deliberately out of order: 2 s, 12 s, 6 s. At 7 s the singing line is the
    // third entry ("Second"), which a binary search over the raw list misses.
    final lyrics = <LyricsLine>[
      const LyricsLine(timestamp: Duration(seconds: 2), text: 'First'),
      const LyricsLine(timestamp: Duration(seconds: 12), text: 'Third'),
      const LyricsLine(timestamp: Duration(seconds: 6), text: 'Second'),
    ];

    when(() => playerCubit.state).thenReturn(
      PlayerState(
        playback: PlaybackSlice(
          currentSong: song,
          isPlaying: true,
          position: const Duration(seconds: 7),
          duration: const Duration(seconds: 200),
        ),
        lyricsSlice: LyricsSlice(lyrics: lyrics),
      ),
    );
    when(() => playerCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => settingsCubit.state).thenReturn(
      const SettingsState(playerThemeMode: PlayerThemeMode.lyricsFocus),
    );

    final props = PlayerThemeProps(
      state: playerCubit.state,
      cubit: playerCubit,
      activeColor: activeColor,
      bgColor: const Color(0xFF101014),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: playerCubit),
              BlocProvider<SettingsCubit>.value(value: settingsCubit),
            ],
            child: ThemeRegistry.build(PlayerThemeMode.lyricsFocus, props),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 320));

    Color? colorOf(String text) {
      final finder = find.text(text);
      if (finder.evaluate().isEmpty) return null;
      return tester.widget<Text>(finder.first).style?.color;
    }

    expect(colorOf('Second'), activeColor,
        reason:
            'the 6 s line is the one sounding at 7 s and must be highlighted');
    expect(colorOf('First'), isNot(activeColor),
        reason: 'the 2 s line has already been sung and must be dimmed');
    expect(colorOf('Third'), isNot(activeColor),
        reason: 'the 12 s line has not been reached yet');
  });
}
