// test/features/player/tablet_player_bar_overflow_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:audio_service/audio_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
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
  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;
  late MockPulsrAudioHandler mockAudioHandler;

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
    when(() => mockPlayerCubit.toggleFavorite(any())).thenAnswer((_) async {});
    when(() => mockPlayerCubit.toggleShuffle()).thenAnswer((_) async {});
    when(() => mockPlayerCubit.toggleRepeat()).thenAnswer((_) async {});
    when(() => mockPlayerCubit.togglePlayPause()).thenAnswer((_) async {});
    when(() => mockPlayerCubit.next()).thenAnswer((_) async {});
    when(() => mockPlayerCubit.previous()).thenAnswer((_) async {});
    when(() => mockPlayerCubit.seek(any())).thenAnswer((_) async {});
    when(() => mockPlayerCubit.setVolume(any())).thenAnswer((_) async {});
    when(() => mockPlayerCubit.toggleMute()).thenAnswer((_) async {});
    when(() => mockPlayerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsState(),
    );
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
  });

  Widget createSubject({required double width, double height = 100.0}) {
    final theme = AuraTheme.customTheme(
      const Color(0xFF00E5FF),
      brightness: Brightness.dark,
    );

    return MultiBlocProvider(
      providers: [
        BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
        BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
        RepositoryProvider<PulsrAudioHandler>.value(value: mockAudioHandler),
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
              child: TabletPlayerBar(
                onOpenNowPlaying: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'TabletPlayerBar renders without overflow on 1024px standard tablet width',
      (tester) async {
    await tester.pumpWidget(createSubject(width: 1024));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TabletPlayerBar), findsOneWidget);
  });

  testWidgets(
      'TabletPlayerBar renders without overflow on 600px narrow tablet width',
      (tester) async {
    await tester.pumpWidget(createSubject(width: 600));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TabletPlayerBar), findsOneWidget);
  });

  testWidgets(
      'TabletPlayerBar renders without overflow on constrained 420px width',
      (tester) async {
    await tester.pumpWidget(createSubject(width: 420));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TabletPlayerBar), findsOneWidget);
  });

  testWidgets(
      'TabletPlayerBar renders without overflow on extremely narrow 320px width',
      (tester) async {
    await tester.pumpWidget(createSubject(width: 320));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TabletPlayerBar), findsOneWidget);
  });

  testWidgets(
      'TabletPlayerBar handles height constraint 77px cleanly without vertical overflow',
      (tester) async {
    await tester.pumpWidget(createSubject(width: 600, height: 77.0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TabletPlayerBar), findsOneWidget);
  });
}
