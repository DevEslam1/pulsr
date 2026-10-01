import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/now_playing_screen.dart';
import 'package:pulsr/features/player/presentation/themes/classic_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/lyrics_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/widgets/player_controls.dart';
import 'package:pulsr/features/player/presentation/widgets/player_seek_bar.dart';
import 'package:pulsr/features/player/presentation/widgets/karaoke_mode_screen.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}
class MockSettingsCubit extends Mock implements SettingsCubit {}
class MockDynamicThemeCubit extends Mock implements DynamicThemeCubit {}

void main() {
  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;
  late MockDynamicThemeCubit mockDynamicThemeCubit;

  const testSong = SongsTableData(
    id: 1,
    title: 'Test Track',
    artist: 'Test Artist',
    album: 'Test Album',
    durationMs: 180000,
    path: '/path/to/song.mp3',
    dateAdded: 0,
    playCount: 0,
    lastPositionMs: 0,
    isFavorite: false,
    isMissing: false,
    source: 'local',
    isDownloaded: true,
  );

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    mockSettingsCubit = MockSettingsCubit();
    mockDynamicThemeCubit = MockDynamicThemeCubit();

    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => mockDynamicThemeCubit.state).thenReturn(const DynamicThemeState());
    when(() => mockDynamicThemeCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget createSubject({
    required Size size,
    required Widget child,
    required PlayerState playerState,
  }) {
    when(() => mockPlayerCubit.state).thenReturn(playerState);
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());

    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
              BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
              BlocProvider<DynamicThemeCubit>.value(value: mockDynamicThemeCubit),
            ],
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('ClassicPlayerTheme in landscape phone with lyrics visible', (tester) async {
    const size = Size(844, 390);
    final state = PlayerState(
      playback: const PlaybackSlice(
        currentSong: testSong,
        isPlaying: true,
        duration: Duration(minutes: 3),
        position: Duration(seconds: 30),
      ),
      lyricsSlice: const LyricsSlice(
        isLyricsVisible: true,
        lyrics: [LyricsLine(timestamp: Duration(seconds: 5), text: 'Hello')],
      ),
    );

    final props = PlayerThemeProps(
      state: state,
      cubit: mockPlayerCubit,
      activeColor: Colors.deepPurple,
      bgColor: Colors.black,
    );

    await tester.pumpWidget(createSubject(
      size: size,
      playerState: state,
      child: ClassicPlayerTheme(props: props),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(PlayerControls), findsOneWidget);
    expect(find.byType(PlayerSeekBar), findsOneWidget);

    final controlsRect = tester.getRect(find.byType(PlayerControls));
    final seekRect = tester.getRect(find.byType(PlayerSeekBar));
    expect(controlsRect.bottom, lessThanOrEqualTo(size.height));
    expect(controlsRect.top, greaterThanOrEqualTo(0));
    expect(seekRect.bottom, lessThanOrEqualTo(size.height));
    expect(seekRect.top, greaterThanOrEqualTo(0));
  });

  testWidgets('LyricsPlayerTheme in landscape phone 800x360 with lyrics visible', (tester) async {
    const size = Size(800, 360);
    final state = PlayerState(
      playback: const PlaybackSlice(
        currentSong: testSong,
        isPlaying: true,
        duration: Duration(minutes: 3),
        position: Duration(seconds: 30),
      ),
      lyricsSlice: const LyricsSlice(
        isLyricsVisible: true,
        lyrics: [LyricsLine(timestamp: Duration(seconds: 5), text: 'Hello')],
      ),
    );

    final props = PlayerThemeProps(
      state: state,
      cubit: mockPlayerCubit,
      activeColor: Colors.deepPurple,
      bgColor: Colors.black,
    );

    await tester.pumpWidget(createSubject(
      size: size,
      playerState: state,
      child: LyricsPlayerTheme(props: props),
    ));
    await tester.pumpAndSettle();
  });

  for (final themeMode in PlayerThemeMode.values) {
    testWidgets('NowPlayingScreen with $themeMode rotate from landscape to portrait with lyrics visible', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(SettingsState(playerThemeMode: themeMode));

      final state = PlayerState(
        playback: const PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          duration: Duration(minutes: 3),
          position: Duration(seconds: 30),
        ),
        lyricsSlice: const LyricsSlice(
          isLyricsVisible: true,
          lyrics: [LyricsLine(timestamp: Duration(seconds: 5), text: 'Hello')],
        ),
      );

      // Start in landscape phone (844x390)
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createSubject(
        size: const Size(844, 390),
        playerState: state,
        child: const NowPlayingScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull, reason: '$themeMode threw exception in landscape');
      expect(find.byType(PlayerControls), findsOneWidget, reason: '$themeMode missing controls in landscape');
      expect(find.byType(PlayerSeekBar), findsOneWidget, reason: '$themeMode missing seekbar in landscape');

      // Rotate to portrait phone (390x844)
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(createSubject(
        size: const Size(390, 844),
        playerState: state,
        child: const NowPlayingScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull, reason: '$themeMode threw exception in portrait');
      expect(find.byType(PlayerControls), findsOneWidget, reason: '$themeMode missing controls in portrait');
      expect(find.byType(PlayerSeekBar), findsOneWidget, reason: '$themeMode missing seekbar in portrait');

      final portraitControlsRect = tester.getRect(find.byType(PlayerControls));
      expect(portraitControlsRect.bottom, lessThanOrEqualTo(844.0), reason: '$themeMode controls pushed below screen bottom in portrait');
      expect(portraitControlsRect.top, greaterThanOrEqualTo(0.0), reason: '$themeMode controls pushed above screen top in portrait');
    });
  }

  testWidgets('KaraokeModeScreen has controls in landscape and retains them in portrait', (tester) async {
    final state = PlayerState(
      playback: const PlaybackSlice(
        currentSong: testSong,
        isPlaying: true,
        duration: Duration(minutes: 3),
        position: Duration(seconds: 45),
      ),
      lyricsSlice: const LyricsSlice(
        isLyricsVisible: true,
        lyrics: [
          LyricsLine(timestamp: Duration(seconds: 10), text: 'First line'),
          LyricsLine(timestamp: Duration(seconds: 40), text: 'Second active line'),
          LyricsLine(timestamp: Duration(seconds: 70), text: 'Third line'),
        ],
      ),
    );

    // 1. Open KaraokeModeScreen in Landscape Phone
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(createSubject(
      size: const Size(844, 390),
      playerState: state,
      child: const KaraokeModeScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull, reason: 'KaraokeModeScreen threw exception in landscape');
    expect(find.byType(PlayerControls), findsOneWidget, reason: 'KaraokeModeScreen missing controls in landscape');
    expect(find.byType(PlayerSeekBar), findsOneWidget, reason: 'KaraokeModeScreen missing seekbar in landscape');

    // 2. Rotate to Portrait Phone
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(createSubject(
      size: const Size(390, 844),
      playerState: state,
      child: const KaraokeModeScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull, reason: 'KaraokeModeScreen threw exception in portrait');
    expect(find.byType(PlayerControls), findsOneWidget, reason: 'KaraokeModeScreen lost controls when rotating back to portrait');
    expect(find.byType(PlayerSeekBar), findsOneWidget, reason: 'KaraokeModeScreen lost seekbar when rotating back to portrait');
  });
}

