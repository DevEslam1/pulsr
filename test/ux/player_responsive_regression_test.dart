import 'package:flutter/services.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/player/presentation/responsive_player_layout.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:audio_service/audio_service.dart';

import 'package:pulsr/core/theme/aura_theme.dart';

import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

class MockPulsrAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements PulsrAudioHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  MockPulsrAudioHandler() {
    playbackState.add(PlaybackState(
      controls: [],
      systemActions: const {},
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    queue.add([]);
  }

  @override
  double get volume => 1.0;

  @override
  Future<void> setVolume(double volume) async {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;
  late MockPulsrAudioHandler mockAudioHandler;

  const testSong = SongsTableData(
    id: 1,
    title: 'Test Song',
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
    mockAudioHandler = MockPulsrAudioHandler();

    when(() => mockPlayerCubit.state).thenReturn(
      const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          position: Duration(seconds: 45),
          duration: Duration(seconds: 180),
        ),
      ),
    );
    when(() => mockPlayerCubit.isMuted).thenReturn(false);
    when(() => mockPlayerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsState(),
    );
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(800, 1280),
    const Size(1280, 800)
  ]) {
    for (final textScale in [1.0, 2.0]) {
      for (final mode in PlayerThemeMode.values) {
        testWidgets('renders $mode at $size with text scale $textScale',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          await (FontLoader('Manrope')
                ..addFont(rootBundle
                    .load('assets/fonts/Manrope-VariableFont_wght.ttf')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          final props = PlayerThemeProps(
              state: mockPlayerCubit.state,
              cubit: mockPlayerCubit,
              activeColor: const Color(0xFF9B9EF5),
              bgColor: const Color(0xFF0B0B0F));
          await tester.pumpWidget(RepositoryProvider<PulsrAudioHandler>.value(
              value: mockAudioHandler,
              child: MultiBlocProvider(
                  providers: [
                    BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
                    BlocProvider<SettingsCubit>.value(value: mockSettingsCubit)
                  ],
                  child: MaterialApp(
                      theme: AuraTheme.darkTheme,
                      builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                              textScaler: TextScaler.linear(textScale)),
                          child: child!),
                      localizationsDelegates:
                          AppLocalizations.localizationsDelegates,
                      supportedLocales: AppLocalizations.supportedLocales,
                      home: Scaffold(
                          body: ResponsivePlayerLayout(
                              state: props.state,
                              cubit: props.cubit,
                              themeWidget: ThemeRegistry.build(mode, props),
                              activeColor: props.activeColor,
                              bgColor: props.bgColor))))));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
