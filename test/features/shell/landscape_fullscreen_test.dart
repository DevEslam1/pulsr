// test/features/shell/landscape_fullscreen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:audio_service/audio_service.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_dock_tracker.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/tablet_player_bar.dart';
import 'package:pulsr/features/player/presentation/themes/classic_player_theme.dart';
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

  Widget buildSubject({double width = 844, double height = 390}) {
    final theme = AuraTheme.customTheme(
      const Color(0xFF00E5FF),
      brightness: Brightness.dark,
    );

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<PulsrAudioHandler>.value(value: mockAudioHandler),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
          BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
        ],
        child: MaterialApp(
          theme: theme,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, height),
              padding: const EdgeInsets.only(left: 40, bottom: 20),
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: TabletPlayerBar(
                  onOpenNowPlaying: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('TabletPlayerBar renders with rounded corners in landscape dock', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.byType(TabletPlayerBar), findsOneWidget);

    // Verify container decoration has rounded corners
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(TabletPlayerBar),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(AppRadii.r20),
        ),
      ),
    );
    final boxDecor = container.decoration as BoxDecoration;
    expect(boxDecor.borderRadius, BorderRadius.circular(AppRadii.r20));

    // Verify dock tracker receives the updated dock height
    expect(PulsrDockTracker.hasMiniPlayer.value, isTrue);
    expect(PulsrDockTracker.dockHeight.value, greaterThan(0.0));
  });

  testWidgets('ClassicPlayerTheme renders controls cleanly without an added wrapper box in landscape mode', (tester) async {
    final theme = AuraTheme.customTheme(
      const Color(0xFF00E5FF),
      brightness: Brightness.dark,
    );

    final props = PlayerThemeProps(
      state: const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          position: Duration(seconds: 45),
          duration: Duration(seconds: 180),
        ),
      ),
      cubit: mockPlayerCubit,
      activeColor: const Color(0xFF00E5FF),
      bgColor: const Color(0xFF121212),
    );

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<PulsrAudioHandler>.value(value: mockAudioHandler),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
            BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
          ],
          child: MaterialApp(
            theme: theme,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(844, 390),
                padding: EdgeInsets.only(left: 40, right: 20),
              ),
              child: Scaffold(
                body: ClassicPlayerTheme(props: props),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ClassicPlayerTheme), findsOneWidget);

    // Verify right controls pane is clean and NOT wrapped in a Container box
    final controlsPane = find.byKey(const ValueKey('track_controls_pane'));
    expect(controlsPane, findsOneWidget);
    expect(controlsPane.evaluate().first.widget is! Container, isTrue);
  });
}
