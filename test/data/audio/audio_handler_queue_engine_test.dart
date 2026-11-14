// test/data/audio/audio_handler_queue_engine_test.dart
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';

import 'handler_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = JustAudioPlatform.instance;
  late FakeJustAudioPlatform platform;
  late MockMusicRepository repo;
  late MockYtmService ytm;
  PulsrAudioHandler? handler;

  setUp(() {
    platform = FakeJustAudioPlatform();
    JustAudioPlatform.instance = platform;
    installHandlerChannelStubs();
    repo = MockMusicRepository();
    stubDefaultRepository(repo);
    ytm = MockYtmService();
    stubDefaultYtm(ytm);
  });

  tearDown(() async {
    await handler?.dispose();
    handler = null;
    removeHandlerChannelStubs();
    JustAudioPlatform.instance = originalPlatform;
  });

  group('queue mutation', () {
    test('addToQueueEnd appends, dedupes and reorders existing entries',
        () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      final a = localSong(1);
      final b = localSong(2);
      final c = localSong(3);

      await handler!.addToQueueEnd(a);
      await handler!.addToQueueEnd(b);
      await handler!.addToQueueEnd(c);
      expect(handler!.queue.value.map((m) => m.id).toList(), ['1', '2', '3']);

      // Duplicate of a non-current, non-last track moves it to the end.
      await handler!.addToQueueEnd(b);
      expect(handler!.queue.value.map((m) => m.id).toList(), ['1', '3', '2']);

      // Duplicate of the last track is a no-op.
      await handler!.addToQueueEnd(b);
      expect(handler!.queue.value.map((m) => m.id).toList(), ['1', '3', '2']);

      // Duplicate of the current track is a no-op.
      await handler!.addToQueueEnd(a);
      expect(handler!.queue.value.map((m) => m.id).toList(), ['1', '3', '2']);
    });

    test('insertNextInQueue inserts after the current track', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.addToQueueEnd(localSong(1));
      await handler!.addToQueueEnd(localSong(2));
      await handler!.insertNextInQueue(localSong(9));
      expect(handler!.queue.value.map((m) => m.id).toList(), ['1', '9', '2']);
    });

    test('reorderQueue moves entries and ignores invalid indices', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.loadQueue([localSong(1), localSong(2), localSong(3)],
          autoPlay: false);

      await handler!.reorderQueue(0, 2);
      expect(handler!.queue.value.map((m) => m.id).toList(), ['2', '3', '1']);

      await handler!.reorderQueue(-1, 2);
      await handler!.reorderQueue(0, 99);
      expect(handler!.queue.value.map((m) => m.id).toList(), ['2', '3', '1']);
    });

    test('removeQueueItemAt removes entries and stops when emptied', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.loadQueue([localSong(1), localSong(2)], autoPlay: false);

      await handler!.removeQueueItemAt(0);
      expect(handler!.queue.value.map((m) => m.id).toList(), ['2']);

      await handler!.removeQueueItemAt(0);
      expect(handler!.queue.value, isEmpty);
      expect(handler!.mediaItem.value, isNull);
    });

    test('removeQueueItem resolves the index by media id', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.loadQueue([localSong(1), localSong(2)], autoPlay: false);

      await handler!.removeQueueItem(MediaItem(id: '1', title: 'Track 1'));
      expect(handler!.queue.value.map((m) => m.id).toList(), ['2']);
    });

    test('clearQueue keeps only the current track', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.loadQueue([localSong(1), localSong(2), localSong(3)],
          initialIndex: 1, autoPlay: false);

      await handler!.clearQueue();
      expect(handler!.queue.value.length, 1);
    });

    test('addQueueItem looks up the song and appends it', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      final song = localSong(7);
      when(() => repo.getSongById(7)).thenAnswer((_) async => Right(song));

      await handler!.addQueueItem(MediaItem(id: '7', title: 'Track 7'));
      expect(handler!.queue.value.map((m) => m.id).toList(), ['7']);
    });
  });

  group('loadQueue', () {
    for (final cancelDuringStartup in [false, true]) {
      test(
          cancelDuringStartup
              ? 'pause during startup cancels queued autoplay'
              : 'cold-start queue load waits for playback initialization',
          () async {
        final startupEntered = Completer<void>();
        final startupReleased = Completer<void>();
        installHandlerChannelStubs(beforeAudioEffectsCall: (call) async {
          if (call.method == 'setDacVoicingParams') {
            startupEntered.complete();
            await startupReleased.future;
          }
        });
        addTearDown(() {
          if (!startupReleased.isCompleted) startupReleased.complete();
        });
        final playerA = AudioPlayer(
          handleInterruptions: false,
          handleAudioSessionActivation: false,
        );
        handler = PulsrAudioHandler.forTesting(
          repository: repo,
          ytmService: ytm,
          playerA: playerA,
          playerB: AudioPlayer(
            handleInterruptions: false,
            handleAudioSessionActivation: false,
          ),
          prefetchPlayer: AudioPlayer(
            handleInterruptions: false,
            handleAudioSessionActivation: false,
          ),
        );

        await startupEntered.future;
        final load = handler!.loadQueue(
          [localSong(1, path: '/music/track.wav')],
          autoPlay: cancelDuringStartup,
        );
        final completed = expectLater(load, completes);
        await pumpEventQueue();
        expect(playerA.audioSources, isEmpty);
        if (cancelDuringStartup) await handler!.pause();
        startupReleased.complete();
        await completed;

        expect(playerA.audioSources, hasLength(cancelDuringStartup ? 0 : 1));
        expect(handler!.mediaItem.value?.title,
            cancelDuringStartup ? isNull : 'Track 1');
        expect(playerA.playing, isFalse);
      });
    }

    test('empty queue clears state and emits', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.loadQueue([localSong(1)], autoPlay: false);
      expect(handler!.queue.value, isNotEmpty);

      await handler!.loadQueue(const [], autoPlay: false);
      expect(handler!.queue.value, isEmpty);
    });

    test('same-list reload takes the gapless fast path and seeks', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      final songs = [localSong(1), localSong(2), localSong(3)];
      await handler!.loadQueue(songs, autoPlay: false);
      await handler!.loadQueue(songs, initialIndex: 2, autoPlay: false);

      expect(handler!.mediaItem.value?.title, 'Track 3');
    });

    test('swapReconciledSong replaces the matching row', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.loadQueue([localSong(1), localSong(2)], autoPlay: false);

      handler!.swapReconciledSong(1, localSong(1, title: 'Reconciled'));
      expect(handler!.queue.value.first.title, 'Reconciled');
    });

    test('updateFavorite mirrors the flag into queue and media item', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!
          .loadQueue([localSong(1, isFavorite: false)], autoPlay: false);

      handler!.updateFavorite(1, true);
      expect(handler!.queue.value.first.extras?['isFavorite'], isTrue);
      expect(handler!.mediaItem.value?.rating?.hasHeart(), isTrue);

      // Same value again is a no-op.
      handler!.updateFavorite(1, true);
      // Unknown id is ignored.
      handler!.updateFavorite(999, true);
    });
  });

  group('navigation', () {
    test('skipToNext advances through the per-track (non-gapless) queue',
        () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      handler!.setGaplessEnabled(false);
      await handler!.loadQueue([localSong(1), localSong(2)], autoPlay: false);

      await handler!.skipToNext();
      expect(handler!.mediaItem.value?.title, 'Track 2');
    });

    test('skipToNext advances the native gapless queue while playing',
        () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.loadQueue([localSong(1), localSong(2)], autoPlay: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await handler!.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(handler!.mediaItem.value?.title, 'Track 2');
    });

    test('skipToPrevious restarts then steps back', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.loadQueue([localSong(1), localSong(2)],
          initialIndex: 1, autoPlay: false);

      await handler!.skipToPrevious();
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('getPreviousIndex returns null for an empty queue', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      expect(handler!.getPreviousIndex(), isNull);
    });

    test('playSongAt loads the requested track', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.loadQueue([localSong(1), localSong(2)], autoPlay: false);

      await handler!.playSongAt(1);
      expect(handler!.mediaItem.value?.title, 'Track 2');
    });
  });

  group('restoreLastPlaybackSession', () {
    test('restores a persisted queue during init', () async {
      final songs = [localSong(1), localSong(2)];
      when(() => repo.getSavedQueue()).thenAnswer((_) async => Right([
            const QueueItemsTableData(
                id: 1,
                songId: 1,
                orderIndex: 0,
                isCurrent: false,
                positionMs: 0),
            const QueueItemsTableData(
                id: 2,
                songId: 2,
                orderIndex: 1,
                isCurrent: true,
                positionMs: 42000),
          ]));
      when(() => repo.getSongsByIds(any()))
          .thenAnswer((_) async => Right(songs));

      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      // Restore is asynchronous and does extra YTM-aware init work; poll
      // briefly instead of assuming a single 50 ms window.
      for (var i = 0; i < 50 && handler!.queue.value.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(handler!.queue.value.length, 2);
      expect(handler!.mediaItem.value?.title, 'Track 2');
    });
  });

  group('transition and coordinator hardening', () {
    test('setAutomixEnabled updates gapless vs dual-player mode when crossfade is 0',
        () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      handler!.setCrossfadeDuration(Duration.zero);
      handler!.setGaplessEnabled(true);
      await handler!.loadQueue([localSong(1), localSong(2)], autoPlay: false);

      await handler!.setAutomixEnabled(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(handler!.crossfadeDuration, Duration.zero);
      expect(handler!.isGaplessEnabled, isTrue);
    });

    test('concurrent loadQueue keeps only the latest queue', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      final first =
          handler!.loadQueue([localSong(1), localSong(2)], autoPlay: false);
      final second = handler!.loadQueue([localSong(10)], autoPlay: false);
      await Future.wait([first, second]);

      expect(handler!.queue.value.map((m) => m.id).toList(), ['10']);
      expect(handler!.mediaItem.value?.id, '10');
    });

    test('end-to-end _startCrossfade swaps active player and updates mediaItem',
        () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      handler!.setGaplessEnabled(false);
      handler!.setCrossfadeDuration(const Duration(milliseconds: 500));
      await handler!.loadQueue(
        [localSong(1, durationMs: 60000), localSong(2, durationMs: 60000)],
        autoPlay: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final outgoing = platform.players.values.first;
      outgoing.emitPlayback(
        processingState: ProcessingStateMessage.ready,
        updatePosition: const Duration(seconds: 59),
        durationOverride: const Duration(seconds: 60),
      );

      for (var i = 0; i < 150 && handler!.mediaItem.value?.id != '2'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      // Allow outgoing cleanup + stop() (80ms post-swap drain) to complete.
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(handler!.mediaItem.value?.id, '2');
      expect(outgoing.playing, isFalse);
      final incoming = platform.players.values.firstWhere((p) => p != outgoing);
      expect(incoming.volumeHistory.length, greaterThan(1));
      expect(incoming.lastVolume, greaterThan(0.0));
    });

    test(
        'automix 0s triggers _startCrossfade and manual skipToNext supersedes it cleanly',
        () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      handler!.setCrossfadeDuration(Duration.zero);
      await handler!.setAutomixEnabled(true);
      await handler!.loadQueue(
        [
          localSong(1, durationMs: 60000),
          localSong(2, durationMs: 60000),
          localSong(3, durationMs: 60000),
        ],
        autoPlay: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final outgoing = platform.players.values.first;
      // Automix 0s uses an 8s effective transition margin + triggerMargin (~1.75s),
      // so 53s reliably crosses the trigger threshold.
      outgoing.emitPlayback(
        processingState: ProcessingStateMessage.ready,
        updatePosition: const Duration(seconds: 53),
        durationOverride: const Duration(seconds: 60),
      );

      for (var i = 0;
          i < 100 &&
              !platform.players.values.any((p) => p != outgoing && p.playing);
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        platform.players.values.any((p) => p != outgoing && p.playing),
        isTrue,
      );

      await handler!.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(handler!.mediaItem.value?.id, '2');
      expect(outgoing.lastVolume, greaterThan(0.0));
    });
  });
}
