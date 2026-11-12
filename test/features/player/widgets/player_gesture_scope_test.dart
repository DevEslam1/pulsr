import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/player_gesture_scope.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  late _MockSettingsCubit settings;
  late PlayerCubit player;

  setUp(() {
    settings = _MockSettingsCubit();
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());

    final song = createTestSong(id: 42);
    player = stubPlayerCubit(
      PlayerState(
        playback: PlaybackSlice(currentSong: song, isPlaying: true),
      ),
    );
    when(() => player.toggleFavorite(any())).thenAnswer((_) async {});
    when(() => player.toggleLyricsVisibility()).thenReturn(null);
    when(() => player.next()).thenAnswer((_) async {});
    when(() => player.previous()).thenAnswer((_) async {});
  });

  Widget wrapScope({
    required SettingsState settingsState,
    VoidCallback? onTap,
  }) {
    when(() => settings.state).thenReturn(settingsState);
    return MaterialApp(
      home: MultiBlocProvider(
        providers: <BlocProvider>[
          BlocProvider<PlayerCubit>.value(value: player),
          BlocProvider<SettingsCubit>.value(value: settings),
        ],
        child: Scaffold(
          body: SizedBox.expand(
            child: PlayerGestureScope(
              onTap: onTap,
              child: const Center(child: Text('Stage')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('double-tap toggles favorite when configured', (tester) async {
    await tester.pumpWidget(
      wrapScope(
        settingsState: const SettingsState(
          nowPlayingDoubleTap: NowPlayingDoubleTapAction.toggleFavorite,
        ),
      ),
    );

    final center = tester.getCenter(find.text('Stage'));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    verify(() => player.toggleFavorite(42)).called(1);
    verifyNever(() => player.toggleLyricsVisibility());
  });

  testWidgets('double-tap toggles lyrics when configured', (tester) async {
    await tester.pumpWidget(
      wrapScope(
        settingsState: const SettingsState(
          nowPlayingDoubleTap: NowPlayingDoubleTapAction.toggleLyrics,
        ),
      ),
    );

    final center = tester.getCenter(find.text('Stage'));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    verify(() => player.toggleLyricsVisibility()).called(1);
    verifyNever(() => player.toggleFavorite(any()));
  });

  testWidgets('double-tap does nothing when NowPlayingDoubleTapAction.none',
      (tester) async {
    await tester.pumpWidget(
      wrapScope(
        settingsState: const SettingsState(
          nowPlayingDoubleTap: NowPlayingDoubleTapAction.none,
        ),
      ),
    );

    final center = tester.getCenter(find.text('Stage'));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    verifyNever(() => player.toggleFavorite(any()));
    verifyNever(() => player.toggleLyricsVisibility());
  });

  testWidgets('horizontal fling left/right calls next/previous when enabled',
      (tester) async {
    await tester.pumpWidget(
      wrapScope(
        settingsState: const SettingsState(
          nowPlayingArtworkSwipe: NowPlayingArtworkSwipeAction.nextPrev,
        ),
      ),
    );

    await tester.fling(find.text('Stage'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    verify(() => player.next()).called(1);

    await tester.fling(find.text('Stage'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    verify(() => player.previous()).called(1);
  });

  testWidgets('horizontal fling does nothing when swipe is none',
      (tester) async {
    await tester.pumpWidget(
      wrapScope(
        settingsState: const SettingsState(
          nowPlayingArtworkSwipe: NowPlayingArtworkSwipeAction.none,
        ),
      ),
    );

    await tester.fling(find.text('Stage'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    verifyNever(() => player.next());
    verifyNever(() => player.previous());
  });

  testWidgets('single tap invokes onTap callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrapScope(
        settingsState: const SettingsState(),
        onTap: () => tapped = true,
      ),
    );

    await tester.tap(find.text('Stage'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tapped, isTrue);
  });
}
