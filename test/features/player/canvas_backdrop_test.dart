// test/features/player/canvas_backdrop_test.dart
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/presentation/widgets/canvas_backdrop.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/services/canvas/canvas_repository.dart';
import 'package:video_player/video_player.dart';

class MockSettingsCubit extends Mock implements SettingsCubit {}

class MockCanvasRepository extends Mock implements CanvasRepository {}

class MockVideoPlayerController extends Mock implements VideoPlayerController {}

void main() {
  late MockSettingsCubit mockSettingsCubit;

  setUp(() {
    mockSettingsCubit = MockSettingsCubit();
    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsState(
        canvasEnabled: true,
        canvasAsBackdrop: false,
      ),
    );
    when(() => mockSettingsCubit.stream).thenAnswer(
      (_) => Stream.value(
        const SettingsState(
          canvasEnabled: true,
          canvasAsBackdrop: false,
        ),
      ),
    );
  });

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: BlocProvider<SettingsCubit>.value(
          value: mockSettingsCubit,
          child: child,
        ),
      ),
    );
  }

  group('CanvasToggleChip', () {
    testWidgets('renders CANVAS label and toggles when tapped', (tester) async {
      when(() => mockSettingsCubit.toggleCanvasEnabled(any()))
          .thenAnswer((_) async {});

      await tester.pumpWidget(
        buildTestableWidget(
          const CanvasToggleChip(activeColor: Colors.blueAccent),
        ),
      );

      expect(find.text('CANVAS'), findsOneWidget);
      expect(find.byIcon(Icons.motion_photos_on_rounded), findsOneWidget);

      await tester.tap(find.byType(CanvasToggleChip));
      await tester.pumpAndSettle();

      verify(() => mockSettingsCubit.toggleCanvasEnabled(false)).called(1);
    });
  });

  group('CanvasBackdrop', () {
    testWidgets(
        'renders fallback artwork when song has no canvas or while loading',
        (tester) async {
      const fallbackKey = ValueKey('fallback_art');
      final dummySong = SongsTableData(
        id: 1,
        title: 'Unknown Title',
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        path: '/storage/music/song.mp3',
        source: 'local',
        isDownloaded: false,
        durationMs: 180000,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      await tester.pumpWidget(
        buildTestableWidget(
          CanvasBackdrop(
            song: dummySong,
            isPlaying: true,
            isBackdropMode: false,
            fallbackArtwork: Container(
              key: fallbackKey,
              color: Colors.red,
            ),
          ),
        ),
      );

      expect(find.byKey(fallbackKey), findsOneWidget);
    });

    testWidgets('does not resolve canvas while Canvas is disabled',
        (tester) async {
      const disabled = SettingsState(canvasEnabled: false);
      when(() => mockSettingsCubit.state).thenReturn(disabled);
      when(() => mockSettingsCubit.stream)
          .thenAnswer((_) => Stream.value(disabled));

      final repository = MockCanvasRepository();
      final dummySong = SongsTableData(
        id: 2,
        title: 'Disabled Canvas',
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        path: '/storage/music/song.mp3',
        source: 'local',
        isDownloaded: false,
        durationMs: 180000,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
      );
      registerFallbackValue(dummySong);
      when(() => repository.cached(any())).thenReturn(null);

      await tester.pumpWidget(
        buildTestableWidget(
          CanvasBackdrop(
            song: dummySong,
            isPlaying: true,
            repository: repository,
          ),
        ),
      );
      await tester.pump();

      verifyNever(() => repository.cached(any()));
      verifyNever(() => repository.canvasFor(any()));
    });

    testWidgets(
        '0.9 toggling canvasEnabled to false stops and disposes controller and shows fallback',
        (tester) async {
      final streamController = StreamController<SettingsState>.broadcast();
      addTearDown(streamController.close);

      var currentState = const SettingsState(canvasEnabled: true);
      when(() => mockSettingsCubit.state).thenAnswer((_) => currentState);
      when(() => mockSettingsCubit.stream)
          .thenAnswer((_) => streamController.stream);

      const fallbackKey = ValueKey('fallback_art');
      const dummySong = SongsTableData(
        id: 3,
        title: 'Canvas Track',
        artist: 'Artist',
        album: 'Album',
        path: '/storage/music/song.mp3',
        source: 'local',
        isDownloaded: false,
        durationMs: 180000,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      final repository = MockCanvasRepository();
      when(() => repository.cached(any())).thenReturn(null);
      when(() => repository.canvasFor(any())).thenAnswer((_) async => null);

      await tester.pumpWidget(
        buildTestableWidget(
          CanvasBackdrop(
            song: dummySong,
            isPlaying: true,
            fallbackArtwork: Container(key: fallbackKey, color: Colors.blue),
            repository: repository,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(fallbackKey), findsOneWidget);

      // Toggle canvasEnabled to false during playback
      currentState = const SettingsState(canvasEnabled: false);
      streamController.add(currentState);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(fallbackKey), findsOneWidget);
      final stateFinder = find.byType(CanvasBackdrop);
      final backdropState = tester.state(stateFinder) as dynamic;
      expect(backdropState.canvas, isNull);
    });

    testWidgets(
        'P2-13 disposes local VideoPlayerController when initialize() throws',
        (tester) async {
      const dummySong = SongsTableData(
        id: 4,
        title: 'Fail Init Track',
        artist: 'Artist',
        album: 'Album',
        path: '/storage/music/song4.mp3',
        source: 'local',
        isDownloaded: false,
        durationMs: 180000,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
      );
      const artwork = CanvasArtwork(
        videoUrl: 'https://example.com/canvas.mp4',
        source: 'test',
      );
      final repository = MockCanvasRepository();
      when(() => repository.cached(dummySong)).thenReturn(artwork);

      final mockController = MockVideoPlayerController();
      when(() => mockController.value)
          .thenReturn(const VideoPlayerValue.uninitialized());
      when(() => mockController.initialize())
          .thenThrow(Exception('decoder failed'));
      when(() => mockController.dispose()).thenAnswer((_) async {});

      await tester.pumpWidget(
        buildTestableWidget(
          CanvasBackdrop(
            song: dummySong,
            isPlaying: true,
            repository: repository,
            controllerFactory: (_) => mockController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      verify(() => mockController.dispose()).called(1);
    });

    testWidgets(
        'P2-13 disposes local VideoPlayerController when setVolume() throws after initialize()',
        (tester) async {
      const dummySong = SongsTableData(
        id: 5,
        title: 'Fail Volume Track',
        artist: 'Artist',
        album: 'Album',
        path: '/storage/music/song5.mp3',
        source: 'local',
        isDownloaded: false,
        durationMs: 180000,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
      );
      const artwork = CanvasArtwork(
        videoUrl: 'https://example.com/canvas2.mp4',
        source: 'test',
      );
      final repository = MockCanvasRepository();
      when(() => repository.cached(dummySong)).thenReturn(artwork);

      final mockController = MockVideoPlayerController();
      when(() => mockController.value)
          .thenReturn(const VideoPlayerValue.uninitialized());
      when(() => mockController.initialize()).thenAnswer((_) async {});
      when(() => mockController.setLooping(true)).thenAnswer((_) async {});
      when(() => mockController.setVolume(0.0))
          .thenThrow(Exception('audio sink failed'));
      when(() => mockController.dispose()).thenAnswer((_) async {});

      await tester.pumpWidget(
        buildTestableWidget(
          CanvasBackdrop(
            song: dummySong,
            isPlaying: false,
            repository: repository,
            controllerFactory: (_) => mockController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      verify(() => mockController.dispose()).called(1);
    });
  });
}
