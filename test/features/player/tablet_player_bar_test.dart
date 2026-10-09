// test/features/player/tablet_player_bar_test.dart
//
// Branch coverage for [TabletPlayerBar]: modal/no-song collapse, transport and
// quick-action taps, slider callbacks, the DAC highlight, inspector toggle and
// the landscape/short-height dock layout.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:audio_service/audio_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_dock_tracker.dart';
import 'package:pulsr/core/widgets/pulsr_modal_tracker.dart';
import 'package:pulsr/core/widgets/pulsr_slider.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/tablet_player_bar.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  late MockPlayerCubit playerCubit;
  late MockSettingsCubit settingsCubit;
  late MockPulsrAudioHandler handler;

  const testSong = SongsTableData(
    id: 1,
    title: 'Test Track With Quite Long Title',
    artist: 'Test Artist With Long Name',
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

  PlayerState playingState({
    PlayerRepeatMode repeat = PlayerRepeatMode.off,
    bool isFavorite = false,
  }) {
    return PlayerState(
      playback: PlaybackSlice(
        currentSong: isFavorite
            ? SongsTableData(
                id: testSong.id,
                title: testSong.title,
                artist: testSong.artist,
                album: testSong.album,
                durationMs: testSong.durationMs,
                path: testSong.path,
                dateAdded: 0,
                playCount: 0,
                lastPositionMs: 0,
                isFavorite: true,
                isMissing: false,
                source: 'local',
                isDownloaded: true,
              )
            : testSong,
        isPlaying: true,
        position: const Duration(seconds: 45),
        duration: const Duration(seconds: 180),
        repeatMode: repeat,
      ),
      queueSlice: const QueueSlice(queue: [testSong], currentIndex: 0),
      dsp: const DspSlice(isEqEnabled: true),
    );
  }

  void stubPlayer(PlayerState state) {
    when(() => playerCubit.state).thenReturn(state);
    when(() => playerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => playerCubit.isMuted).thenReturn(false);
    when(() => playerCubit.toggleFavorite(any())).thenAnswer((_) async {});
    when(() => playerCubit.toggleShuffle()).thenAnswer((_) async {});
    when(() => playerCubit.toggleRepeat()).thenAnswer((_) async {});
    when(() => playerCubit.togglePlayPause()).thenAnswer((_) async {});
    when(() => playerCubit.next()).thenAnswer((_) async {});
    when(() => playerCubit.previous()).thenAnswer((_) async {});
    when(() => playerCubit.seek(any())).thenAnswer((_) async {});
    when(() => playerCubit.setVolume(any())).thenAnswer((_) async {});
    when(() => playerCubit.toggleMute()).thenAnswer((_) async {});
  }

  setUp(() {
    playerCubit = MockPlayerCubit();
    settingsCubit = MockSettingsCubit();
    handler = MockPulsrAudioHandler();
    PulsrModalTracker.isModalOpen.value = false;
    stubPlayer(playingState());
    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
  });

  tearDown(() {
    PulsrModalTracker.isModalOpen.value = false;
    PulsrDockTracker.updateDock(height: 0.0, miniPlayer: false);
  });

  Widget createSubject({
    double width = 1024,
    double height = 100.0,
    MediaQueryData? mediaQuery,
    VoidCallback? onToggleSideInspector,
    bool isInspectorOpen = false,
    VoidCallback? onOpenNowPlaying,
  }) {
    final theme = AuraTheme.customTheme(
      const Color(0xFF00E5FF),
      brightness: Brightness.dark,
    );

    Widget bar = TabletPlayerBar(
      onOpenNowPlaying: onOpenNowPlaying ?? () {},
      onToggleSideInspector: onToggleSideInspector,
      isInspectorOpen: isInspectorOpen,
    );
    if (mediaQuery != null) {
      bar = MediaQuery(data: mediaQuery, child: bar);
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider<PlayerCubit>.value(value: playerCubit),
        BlocProvider<SettingsCubit>.value(value: settingsCubit),
        RepositoryProvider<PulsrAudioHandler>.value(value: handler),
      ],
      child: MaterialApp(
        theme: theme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: width,
              height: height,
              child: bar,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('collapses to nothing while a modal is open', (tester) async {
    PulsrModalTracker.isModalOpen.value = true;
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();
    expect(find.text(testSong.title), findsNothing);
    expect(tester.takeException(), isNull);

    PulsrModalTracker.isModalOpen.value = false;
    await tester.pumpAndSettle();
    expect(find.text(testSong.title), findsOneWidget);
  });

  testWidgets('collapses when there is no current song', (tester) async {
    stubPlayer(const PlayerState());
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();
    expect(find.text(testSong.title), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transport and quick-action taps reach the cubit', (tester) async {
    var inspectorTaps = 0;
    var openTaps = 0;
    await tester.pumpWidget(createSubject(
      onToggleSideInspector: () => inspectorTaps++,
      onOpenNowPlaying: () => openTaps++,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();
    verify(() => playerCubit.toggleFavorite(testSong.id)).called(1);

    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    await tester.pump();
    verify(() => playerCubit.toggleShuffle()).called(1);

    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    await tester.pump();
    verify(() => playerCubit.previous()).called(1);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    verify(() => playerCubit.togglePlayPause()).called(1);

    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    verify(() => playerCubit.next()).called(1);

    await tester.tap(find.byIcon(Icons.repeat_rounded));
    await tester.pump();
    verify(() => playerCubit.toggleRepeat()).called(1);

    // The quick-action column is horizontally scrollable; invoke the buttons
    // directly so the tap is not swallowed by scroll geometry.
    void pressIcon(IconData icon) {
      final button = tester.widget<IconButton>(find
          .ancestor(of: find.byIcon(icon), matching: find.byType(IconButton))
          .first);
      button.onPressed!();
    }

    pressIcon(Icons.volume_up_rounded);
    await tester.pump();
    verify(() => playerCubit.toggleMute()).called(1);

    pressIcon(Icons.queue_music_rounded);
    await tester.pump();
    expect(inspectorTaps, 1);

    pressIcon(Icons.open_in_full_rounded);
    await tester.pump();
    expect(openTaps, 1);
  });

  testWidgets('repeat-one and favourite states render their variants',
      (tester) async {
    stubPlayer(playingState(
      repeat: PlayerRepeatMode.one,
      isFavorite: true,
    ));
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('seek and volume sliders delegate to the cubit', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    final sliders = tester.widgetList<PulsrSlider>(find.byType(PulsrSlider));
    expect(sliders.length, greaterThanOrEqualTo(2));

    // First slider is the seek bar, last is the volume control.
    sliders.first.onChangeStart!(10000);
    sliders.first.onChanged(20000);
    sliders.first.onChangeEnd!(90000);
    await tester.pump();
    verify(() => playerCubit.seek(const Duration(milliseconds: 90000)))
        .called(1);

    sliders.last.onChangeStart!(0.4);
    sliders.last.onChanged(0.4);
    sliders.last.onChangeEnd!(0.4);
    await tester.pump();
    verify(() => playerCubit.setVolume(0.4)).called(greaterThanOrEqualTo(1));
  });

  testWidgets('DAC output device highlights the output button', (tester) async {
    when(() => settingsCubit.state).thenReturn(const SettingsState(
      currentOutputDevice: AudioOutputInfo(
        deviceName: 'USB DAC',
        isUsbDac: true,
        sampleRate: 96000,
        bitDepth: 24,
        isBitPerfectActive: true,
      ),
    ));
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.settings_input_component_rounded), findsOneWidget);
  });

  testWidgets('short landscape layout with a bottom inset renders cleanly',
      (tester) async {
    await tester.pumpWidget(createSubject(
      width: 800,
      height: 400,
      mediaQuery: const MediaQueryData(
        size: Size(800, 400),
        padding: EdgeInsets.only(bottom: 24),
        devicePixelRatio: 1.0,
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(testSong.title), findsOneWidget);
  });

  testWidgets('inspector-open state colours the queue button', (tester) async {
    await tester.pumpWidget(createSubject(
      onToggleSideInspector: () {},
      isInspectorOpen: true,
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
  });
}
