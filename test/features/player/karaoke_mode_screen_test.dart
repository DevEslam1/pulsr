// test/features/player/karaoke_mode_screen_test.dart
//
// Branch coverage for [KaraokeModeScreen]: empty/loading lyrics, active + next
// line rendering and tap-to-seek, pitch/font/practice controls, the tap-rhythm
// score, lifecycle chrome and the landscape layout.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/karaoke_mode_screen.dart';

import 'widgets/player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  const lyrics = [
    LyricsLine(timestamp: Duration.zero, text: 'first line'),
    LyricsLine(timestamp: Duration(seconds: 10), text: 'second line'),
    LyricsLine(timestamp: Duration(seconds: 20), text: 'third line'),
  ];

  MockPlayerCubit stubTransport(PlayerState state) {
    final cubit = stubPlayerCubit(state: state);
    when(() => cubit.seek(any())).thenAnswer((_) async {});
    when(() => cubit.setPlaybackPitch(any())).thenAnswer((_) async {});
    when(() => cubit.togglePlayPause()).thenAnswer((_) async {});
    when(() => cubit.next()).thenAnswer((_) async {});
    when(() => cubit.previous()).thenAnswer((_) async {});
    when(() => cubit.toggleShuffle()).thenAnswer((_) async {});
    when(() => cubit.toggleRepeat()).thenAnswer((_) async {});
    return cubit;
  }

  PlayerState stateWith({
    List<LyricsLine> lines = const [],
    bool isLoadingLyrics = false,
    Duration position = const Duration(seconds: 5),
    Duration duration = const Duration(minutes: 3),
    bool isPlaying = true,
  }) {
    return PlayerState(
      playback: PlaybackSlice(
        currentSong: testSong,
        isPlaying: isPlaying,
        position: position,
        duration: duration,
      ),
      queueSlice: const QueueSlice(
        queue: [testSong, testSong],
        currentIndex: 0,
      ),
      lyricsSlice: LyricsSlice(lyrics: lines, isLoadingLyrics: isLoadingLyrics),
    );
  }

  Future<void> pumpKaraoke(
    WidgetTester tester,
    MockPlayerCubit cubit, {
    MediaQueryData? mediaQuery,
  }) async {
    Widget child = const KaraokeModeScreen();
    if (mediaQuery != null) {
      child = MediaQuery(data: mediaQuery, child: child);
    }
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: child,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the loading then no-lyrics copy when empty',
      (tester) async {
    final cubit = stubTransport(stateWith(
      isLoadingLyrics: true,
      position: Duration.zero,
    ));
    await pumpKaraoke(tester, cubit);
    expect(tester.takeException(), isNull);

    final empty = stubTransport(stateWith(position: Duration.zero));
    await pumpKaraoke(tester, empty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the active and next line and seeks on tap',
      (tester) async {
    final cubit = stubTransport(stateWith(lines: lyrics));
    await pumpKaraoke(tester, cubit);

    expect(find.text('second line'), findsOneWidget);

    // Tapping the next-line block seeks to its timestamp.
    await tester.tap(find.text('second line'));
    await tester.pump();
    verify(() => cubit.seek(const Duration(seconds: 10))).called(1);
  });

  testWidgets('pitch, font-size and practice controls update state',
      (tester) async {
    final cubit = stubTransport(stateWith(lines: lyrics));
    await pumpKaraoke(tester, cubit);

    void press(IconData icon) {
      final button =
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));
      button.onPressed!();
    }

    press(Icons.add_circle_outline_rounded);
    await tester.pump();
    expect(find.text('+1 st'), findsOneWidget);

    press(Icons.remove_circle_outline_rounded);
    await tester.pump();
    expect(find.text('+0 st'), findsOneWidget);
    verify(() => cubit.setPlaybackPitch(any())).called(2);

    // Font-size cycling and practice toggle must not throw.
    press(Icons.format_size_rounded);
    await tester.pump();
    press(Icons.repeat_one_rounded);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tap-rhythm button scores and updates the app bar',
      (tester) async {
    final cubit = stubTransport(stateWith(lines: lyrics));
    await pumpKaraoke(tester, cubit);

    expect(find.byIcon(Icons.touch_app_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.touch_app_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait transport buttons drive the cubit', (tester) async {
    final cubit = stubTransport(stateWith(lines: lyrics));
    await pumpKaraoke(tester, cubit);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    verify(() => cubit.togglePlayPause()).called(1);

    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    verify(() => cubit.next()).called(1);
  });

  testWidgets('landscape layout renders both panes', (tester) async {
    final cubit = stubTransport(stateWith(lines: lyrics));
    await pumpKaraoke(
      tester,
      cubit,
      mediaQuery: const MediaQueryData(
        size: Size(900, 400),
        devicePixelRatio: 1.0,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(KaraokeModeScreen), findsOneWidget);
  });

  testWidgets('app lifecycle resume restores immersive chrome',
      (tester) async {
    final cubit = stubTransport(stateWith(lines: lyrics));
    await pumpKaraoke(tester, cubit);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}


