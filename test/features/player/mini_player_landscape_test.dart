import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/mini_player.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}
class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;

  const testSong = SongsTableData(
    id: 101,
    title: 'Landscape Song',
    artist: 'Artist',
    album: 'Album',
    durationMs: 180000,
    path: '/path/101.mp3',
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    lastPositionMs: 0,
    source: 'local',
  );

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    mockSettingsCubit = MockSettingsCubit();
    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockPlayerCubit.state).thenReturn(
      const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          duration: Duration(minutes: 3),
        ),
        queueSlice: QueueSlice(
          queue: [testSong],
          currentIndex: 0,
        ),
      ),
    );
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget buildWidget() {
    return MultiBlocProvider(
      providers: [
        BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
        BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 360,
            child: MiniPlayer(onTap: () {}, onSwipeDown: () {}),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'landscape phone keeps the full mini player (track time + carousel)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildWidget());
    await tester.pump(const Duration(milliseconds: 400));

    // The stripped-down horizontal bar has no carousel and no progress bar.
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(MiniPlayerHorizontal), findsNothing);

    // Play/pause and skip-next are always present; the progress bar (track
    // time) is what the horizontal variant used to drop.
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
