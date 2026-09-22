// test/features/player/vinyl_rpm_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/vinyl_player_theme.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}
class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;

  const testSong = SongsTableData(
    id: 42,
    title: 'Vinyl RPM Test Track',
    artist: 'Analog Master',
    album: 'Audiophile Edition',
    durationMs: 240000,
    path: '/music/track42.flac',
    dateAdded: 1600000000,
    playCount: 1,
    lastPositionMs: 0,
    isFavorite: true,
    isMissing: false,
    source: 'local',
    isDownloaded: true,
  );

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    mockSettingsCubit = MockSettingsCubit();

    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());

    when(() => mockPlayerCubit.state).thenReturn(
      const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          duration: Duration(minutes: 4),
        ),
      ),
    );
    when(() => mockPlayerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
  });

  Widget buildVinylTheme({required bool isPlaying}) {
    final state = PlayerState(
      playback: PlaybackSlice(
        currentSong: testSong,
        isPlaying: isPlaying,
        duration: const Duration(minutes: 4),
        position: const Duration(seconds: 30),
      ),
    );

    return MaterialApp(
      theme: AuraTheme.darkTheme,
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(500, 950),
          padding: EdgeInsets.zero,
        ),
        child: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
              BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
            ],
            child: VinylPlayerTheme(
              props: PlayerThemeProps(
                state: state,
                cubit: mockPlayerCubit,
                activeColor: Colors.cyanAccent,
                bgColor: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('VinylPlayerTheme RPM Badge Tests', () {
    testWidgets('shows 33⅓ RPM badge and speed icon when playing',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildVinylTheme(isPlaying: true));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('33⅓ RPM'), findsOneWidget);
      expect(find.text('STANDBY'), findsNothing);

      final badgeContainer = find.ancestor(
        of: find.text('33⅓ RPM'),
        matching: find.byType(Container),
      );
      expect(
        find.descendant(
          of: badgeContainer,
          matching: find.byIcon(Icons.speed_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows STANDBY badge and pause icon when paused',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildVinylTheme(isPlaying: false));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('STANDBY'), findsOneWidget);
      expect(find.text('33⅓ RPM'), findsNothing);

      final badgeContainer = find.ancestor(
        of: find.text('STANDBY'),
        matching: find.byType(Container),
      );
      expect(
        find.descendant(
          of: badgeContainer,
          matching: find.byIcon(Icons.pause_circle_outline_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('transitions RPM badge from 33⅓ RPM to STANDBY when playback pauses',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 1. Initially playing
      await tester.pumpWidget(buildVinylTheme(isPlaying: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('33⅓ RPM'), findsOneWidget);

      // 2. State transition to paused
      await tester.pumpWidget(buildVinylTheme(isPlaying: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('STANDBY'), findsOneWidget);
      expect(find.text('33⅓ RPM'), findsNothing);
    });
  });
}
