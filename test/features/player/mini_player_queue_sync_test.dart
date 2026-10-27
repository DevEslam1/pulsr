import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/mini_player.dart';

import 'widgets/player_sheet_test_support.dart';

SongsTableData _song(int id) => SongsTableData(
      id: id,
      title: 'Song $id',
      artist: 'Artist $id',
      album: 'Album',
      durationMs: 180000,
      path: '/music/$id.flac',
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
      source: 'local',
      isDownloaded: true,
    );

PlayerState _stateAt(List<SongsTableData> queue, int index) => PlayerState(
      playback: PlaybackSlice(
        currentSong: queue[index],
        isPlaying: true,
        duration: const Duration(minutes: 3),
      ),
      queueSlice: QueueSlice(queue: queue, currentIndex: index),
    );

/// Drives the mini player from a mutable PlayerCubit mock: every [push] both
/// answers `state` and emits on `stream`, exactly as a real cubit would.
class _Harness {
  _Harness(List<SongsTableData> queue)
      : queue = queue,
        _states = StreamController<PlayerState>.broadcast() {
    _current = _stateAt(queue, 0);
    cubit = MockPlayerCubit();
    when(() => cubit.state).thenAnswer((_) => _current);
    when(() => cubit.stream).thenAnswer((_) => _states.stream);
    when(() => cubit.togglePlayPause()).thenAnswer((_) async {});
    when(() => cubit.next()).thenAnswer((_) async {});
    when(() => cubit.previous()).thenAnswer((_) async {});
    when(() => cubit.adjustVolume(any())).thenAnswer((_) async {});
    when(() => cubit.skipToQueueItem(any())).thenAnswer((_) async {});
  }

  List<SongsTableData> queue;
  final StreamController<PlayerState> _states;
  late PlayerState _current;
  late MockPlayerCubit cubit;

  Future<void> push(WidgetTester tester, PlayerState next) async {
    _current = next;
    _states.add(next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Emits without pumping, to model several cubit emissions inside one frame.
  void emit(PlayerState next) {
    _current = next;
    _states.add(next);
  }

  Future<void> dispose() => _states.close();
}

Future<void> _mount(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(sheetHost(
    playerCubit: harness.cubit,
    settingsCubit: stubSettingsCubit(),
    child: MiniPlayer(onTap: () {}),
  ));
  await tester.pumpAndSettle();
}

int? _page(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller?.page?.round();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'queue growing from one track keeps the carousel following the song',
      (tester) async {
    // Cold-start restore shape: the mini player mounts with the restored
    // current track before the full queue arrives.
    final harness = _Harness([_song(1)]);
    addTearDown(harness.dispose);
    await _mount(tester, harness);
    expect(find.text('Song 1'), findsWidgets);

    final restored = [for (var i = 1; i <= 8; i++) _song(i)];
    await harness.push(tester, _stateAt(restored, 3));

    expect(_page(tester), 3, reason: 'page follows the restored index');
    expect(find.text('Song 4'), findsWidgets);
    expect(find.text('Song 1'), findsNothing);

    await harness.push(tester, _stateAt(restored, 4));
    expect(_page(tester), 4);
    expect(find.text('Song 5'), findsWidgets);
  });

  testWidgets('carousel recovers after the queue shrinks then grows',
      (tester) async {
    final harness = _Harness([for (var i = 1; i <= 5; i++) _song(i)]);
    addTearDown(harness.dispose);
    await _mount(tester, harness);

    await harness.push(tester, _stateAt(harness.queue, 4));
    expect(_page(tester), 4);

    final small = [_song(21), _song(22)];
    await harness.push(tester, _stateAt(small, 1));
    expect(_page(tester), 1);
    expect(find.text('Song 22'), findsWidgets);

    final larger = [for (var i = 31; i <= 36; i++) _song(i)];
    await harness.push(tester, _stateAt(larger, 3));
    expect(_page(tester), 3);
    expect(find.text('Song 34'), findsWidgets);
  });

  testWidgets('a queue that empties then refills lands on the active track',
      (tester) async {
    final queue = [_song(1), _song(2), _song(3)];
    final harness = _Harness(queue);
    addTearDown(harness.dispose);
    await _mount(tester, harness);

    await harness.push(
      tester,
      const PlayerState(
        playback: PlaybackSlice(isPlaying: false),
        queueSlice: QueueSlice(),
      ),
    );
    expect(find.byType(PageView), findsNothing);

    await harness.push(tester, _stateAt(queue, 2));
    expect(_page(tester), 2);
    expect(find.text('Song 3'), findsWidgets);
  });

  testWidgets('a hung carousel skip cannot freeze later track changes',
      (tester) async {
    final queue = [_song(1), _song(2), _song(3)];
    final harness = _Harness(queue);
    addTearDown(harness.dispose);
    final neverCompletes = Completer<void>();
    when(() => harness.cubit.skipToQueueItem(any()))
        .thenAnswer((_) => neverCompletes.future);
    await _mount(tester, harness);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(_page(tester), 1);

    // Let the swipe latch time out; the carousel must accept syncs again even
    // though the audio handler never answered the skip.
    await tester.pump(const Duration(seconds: 11));

    await harness.push(tester, _stateAt(queue, 2));
    expect(_page(tester), 2);
    expect(find.text('Song 3'), findsWidgets);
  });

  testWidgets('a burst of track changes settles on the newest track',
      (tester) async {
    final queue = [_song(1), _song(2), _song(3), _song(4), _song(5)];
    final harness = _Harness(queue);
    addTearDown(harness.dispose);
    await _mount(tester, harness);

    // Three state emissions before a single frame: retries scheduled for the
    // intermediate tracks must not pull the carousel back.
    for (var i = 1; i <= 3; i++) {
      harness.emit(_stateAt(queue, i));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    expect(_page(tester), 3);
    expect(find.text('Song 4'), findsWidgets);
  });

  testWidgets('carousel still follows a queue replaced with equal length',
      (tester) async {
    final harness = _Harness([_song(1), _song(2), _song(3)]);
    addTearDown(harness.dispose);
    await _mount(tester, harness);

    final replacement = [_song(11), _song(12), _song(13)];
    await harness.push(tester, _stateAt(replacement, 1));
    expect(_page(tester), 1);
    expect(find.text('Song 12'), findsWidgets);
  });
}
