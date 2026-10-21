// test/features/player/canvas_backdrop_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/presentation/widgets/canvas_backdrop.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/services/canvas/canvas_repository.dart';

class MockSettingsCubit extends Mock implements SettingsCubit {}

class MockCanvasRepository extends Mock implements CanvasRepository {}

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
  });
}
