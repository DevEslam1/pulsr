// test/data/audio/collaborators_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/data/audio/collaborators/playback_position_persister.dart';
import 'package:pulsr/data/audio/collaborators/playback_volume_controller.dart';
import 'package:pulsr/data/audio/collaborators/playback_state_coordinator.dart';
import 'package:pulsr/data/audio/collaborators/playback_preload_orchestrator.dart';
import 'package:pulsr/data/audio/smart_preload_scheduler.dart';
import 'package:pulsr/data/audio/stream_pre_resolver.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';

import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/audio/collaborators/stream_resolution_pipeline.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

class MockSmartPreloadScheduler extends Mock implements SmartPreloadScheduler {}

class MockStreamPreResolver extends Mock implements StreamPreResolver {}

class MockYtmService extends Mock implements YtmService {}

class MockMusicRepository extends Mock implements IMusicRepository {}

SongsTableData _createMockSong(
  int id, {
  double? rgTrack,
  double? rgAlbum,
  double? rgTrackPeak,
  double? rgAlbumPeak,
  String? remoteId,
  String source = SongSource.local,
}) {
  return SongsTableData(
    id: id,
    title: 'Song $id',
    artist: 'Artist',
    album: 'Album',
    durationMs: 180000,
    path: '/path/to/$id.mp3',
    dateAdded: 0,
    source: source,
    remoteId: remoteId,
    replayGainTrack: rgTrack,
    replayGainAlbum: rgAlbum,
    replayGainTrackPeak: rgTrackPeak,
    replayGainAlbumPeak: rgAlbumPeak,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    lastPositionMs: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackVolumeController Tests', () {
    late PlaybackVolumeController controller;
    late MockAudioPlayer activePlayer;
    late MockAudioPlayer inactivePlayer;

    setUp(() {
      activePlayer = MockAudioPlayer();
      inactivePlayer = MockAudioPlayer();
      when(() => activePlayer.setVolume(any())).thenAnswer((_) async {});
      when(() => inactivePlayer.setVolume(any())).thenAnswer((_) async {});

      controller = PlaybackVolumeController(
        getActivePlayer: () => activePlayer,
        getInactivePlayer: () => inactivePlayer,
      );
    });

    test('Computes target volume without ReplayGain', () {
      controller.updateSettings(userVolume: 0.8, replayGainMode: 'off');
      final song = _createMockSong(1);
      final vol = controller.calculateTargetVolume(song);
      expect(vol, closeTo(0.8, 0.001));
    });

    test('Applies ducking reduction and restore', () async {
      controller.updateSettings(userVolume: 1.0, replayGainMode: 'off');
      final song = _createMockSong(1);
      when(() => activePlayer.volume).thenReturn(1.0);

      await controller.setDucked(true, song);
      expect(controller.isDucked, isTrue);
      final duckedVol = controller.calculateTargetVolume(song);
      expect(duckedVol, closeTo(0.2, 0.001));

      await controller.setDucked(false, song);
      expect(controller.isDucked, isFalse);
      final restoredVol = controller.calculateTargetVolume(song);
      expect(restoredVol, closeTo(1.0, 0.001));
    });

    test('Computes ReplayGain track mode', () {
      controller.updateSettings(
        userVolume: 1.0,
        replayGainMode: 'track',
        preampWithRg: 0.0,
      );
      // Track with -3dB gain
      final song = _createMockSong(1, rgTrack: -3.0, rgTrackPeak: 1.0);
      final vol = controller.calculateTargetVolume(song);
      // 10^(-3 / 20) ~ 0.7079
      expect(vol, closeTo(0.708, 0.01));
    });

    test('Computes ReplayGain auto mode with albumContext', () {
      controller.updateSettings(
        userVolume: 1.0,
        replayGainMode: 'auto',
        preampWithRg: 0.0,
      );
      final song = _createMockSong(1, rgTrack: -2.0, rgAlbum: -6.0);

      // Without album context -> track gain (-2dB -> ~0.794)
      final trackVol =
          controller.calculateTargetVolume(song, albumContext: false);
      expect(trackVol, closeTo(0.794, 0.01));

      // With album context -> album gain (-6dB -> ~0.501)
      final albumVol =
          controller.calculateTargetVolume(song, albumContext: true);
      expect(albumVol, closeTo(0.501, 0.01));
    });

    test('Applies volume immediately when smoothTransition is false', () async {
      await controller.applyVolume(activePlayer, 0.6, smoothTransition: false);
      verify(() => activePlayer.setVolume(0.6)).called(1);
    });

    test('Smooth 500ms volume transition reaches target volume', () async {
      when(() => activePlayer.volume).thenReturn(0.0);
      await controller.applyVolume(activePlayer, 1.0, smoothTransition: true);
      verify(() => activePlayer.setVolume(any()))
          .called(greaterThanOrEqualTo(1));
    });

    test('dispose cancels active transition timers and nulls player references',
        () async {
      when(() => activePlayer.volume).thenReturn(0.0);
      final future =
          controller.applyVolume(activePlayer, 1.0, smoothTransition: true);
      expect(controller.hasActiveTransitionTimer, isTrue);

      controller.dispose();

      expect(controller.isDisposed, isTrue);
      expect(controller.hasActiveTransitionTimer, isFalse);
      expect(controller.getActivePlayer, isNull);
      expect(controller.getInactivePlayer, isNull);
      await future;
    });

    test(
        'Calculate target volume across DoP, nativeRG, DVC, ducking, and per-song offset',
        () {
      final song = _createMockSong(1, rgTrack: -3.0, rgTrackPeak: 1.0);

      // 1. DoP active: strictly unity gain
      controller.updateSettings(
        userVolume: 0.7,
        isDopActive: true,
        replayGainMode: 'track',
      );
      expect(controller.calculateTargetVolume(song, perSongOffsetDb: 2.0),
          equals(1.0));

      // 2. Native RG active: mixer carries base volume, RG handled natively
      controller.updateSettings(
        isDopActive: false,
        userVolume: 0.8,
        nativeRgActive: true,
        dvcEnabled: false,
      );
      expect(controller.calculateTargetVolume(song), closeTo(0.8, 0.001));

      // 3. Native RG + DVC: user volume handled by native DVC stage -> mixer is 1.0
      controller.updateSettings(
        nativeRgActive: true,
        dvcEnabled: true,
      );
      expect(controller.calculateTargetVolume(song), closeTo(1.0, 0.001));

      // 4. Native RG + DVC with per-song offset: multiplier applied to 1.0
      // +3dB -> ~1.412 clamped to 1.0, -3dB -> ~0.7079
      expect(controller.calculateTargetVolume(song, perSongOffsetDb: -3.0),
          closeTo(0.7079, 0.01));

      // 5. Ducked state with DVC
      controller.updateSettings(
        isDucked: true,
        duckFactor: 0.25,
      );
      // DVC effective base = 1.0 * 0.25 = 0.25
      expect(controller.calculateTargetVolume(song), closeTo(0.25, 0.001));

      // 6. Untagged track default preamp is 0dB (does not attenuate)
      final untaggedSong = _createMockSong(2);
      controller.updateSettings(
        isDucked: false,
        nativeRgActive: false,
        dvcEnabled: false,
        userVolume: 0.9,
        replayGainMode: 'track',
      );
      expect(
          controller.calculateTargetVolume(untaggedSong), closeTo(0.9, 0.001));
    });

    test(
        'Gates YouTube loudnessDb normalization on replayGainMode and nativeRgActive',
        () async {
      final mockYtm = MockYtmService();
      when(() => mockYtm.getLoudnessDb('yt_vid_1')).thenReturn(-6.0);
      final hadPrevious = getIt.isRegistered<YtmService>();
      YtmService? previous;
      if (hadPrevious) {
        previous = getIt<YtmService>();
        await getIt.unregister<YtmService>();
      }
      getIt.registerSingleton<YtmService>(mockYtm);
      addTearDown(() async {
        if (getIt.isRegistered<YtmService>()) {
          await getIt.unregister<YtmService>();
        }
        if (hadPrevious && previous != null) {
          getIt.registerSingleton<YtmService>(previous);
        }
      });

      final ytSong = _createMockSong(
        99,
        remoteId: 'yt_vid_1',
        source: SongSource.youtube,
      );

      // replayGainMode == 'off': skips YouTube loudnessDb normalization.
      controller.updateSettings(
        userVolume: 0.4,
        replayGainMode: 'off',
        nativeRgActive: false,
      );
      expect(controller.calculateTargetVolume(ytSong), closeTo(0.4, 0.001));

      // replayGainMode == 'track' & !nativeRgActive: applies +6 dB (~1.995x).
      controller.updateSettings(
        userVolume: 0.4,
        replayGainMode: 'track',
        nativeRgActive: false,
      );
      expect(controller.calculateTargetVolume(ytSong), closeTo(0.798, 0.01));

      // nativeRgActive == true: native DSP handles normalization; skips Dart boost.
      controller.updateSettings(
        userVolume: 0.4,
        replayGainMode: 'track',
        nativeRgActive: true,
      );
      expect(controller.calculateTargetVolume(ytSong), closeTo(0.4, 0.001));
    });
  });

  group('PlaybackStateCoordinator Tests', () {
    late PlaybackStateCoordinator coordinator;
    int saveCalls = 0;

    setUp(() {
      saveCalls = 0;
      coordinator = PlaybackStateCoordinator(
        onSavePositionRequested: () async {
          saveCalls++;
        },
      );
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('Broadcasts position on standard and high-rate streams', () async {
      final standardEmits = <Duration>[];
      final highRateEmits = <Duration>[];

      final sub1 = coordinator.positionStream.listen(standardEmits.add);
      final sub2 = coordinator.highRatePositionStream.listen(highRateEmits.add);

      coordinator.onPositionTick(const Duration(seconds: 1));
      coordinator.onPositionTick(const Duration(seconds: 2));

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(highRateEmits, isNotEmpty);
      expect(coordinator.isPositionDirty, isTrue);

      await sub1.cancel();
      await sub2.cancel();
    });

    test('Triggers periodic save only when position is dirty', () async {
      expect(coordinator.isPositionDirty, isFalse);
      coordinator.markPositionDirty();
      expect(coordinator.isPositionDirty, isTrue);

      coordinator.triggerSaveIfDirty();
      expect(saveCalls, equals(1));
      expect(coordinator.isPositionDirty, isFalse);

      // Subsequent call does not save if not dirty
      coordinator.triggerSaveIfDirty();
      expect(saveCalls, equals(1));
    });
  });

  group('PlaybackPreloadOrchestrator Tests', () {
    late PlaybackPreloadOrchestrator orchestrator;
    late MockSmartPreloadScheduler scheduler;
    late MockStreamPreResolver preResolver;

    setUp(() {
      scheduler = MockSmartPreloadScheduler();
      preResolver = MockStreamPreResolver();

      when(() => preResolver.onTrackStarted(
            queue: any(named: 'queue'),
            currentIndex: any(named: 'currentIndex'),
            isShuffle: any(named: 'isShuffle'),
            shuffleIndices: any(named: 'shuffleIndices'),
            position: any(named: 'position'),
            duration: any(named: 'duration'),
          )).thenReturn(null);

      when(() => preResolver.onQueueMutated(
            queue: any(named: 'queue'),
            currentIndex: any(named: 'currentIndex'),
            isShuffle: any(named: 'isShuffle'),
            shuffleIndices: any(named: 'shuffleIndices'),
            position: any(named: 'position'),
            duration: any(named: 'duration'),
          )).thenReturn(null);

      orchestrator = PlaybackPreloadOrchestrator(
        scheduler: scheduler,
        preResolver: preResolver,
      );
    });

    test('Forwards onTrackStarted to preResolver', () {
      final queue = [_createMockSong(1)];
      orchestrator.onTrackStarted(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
      );

      verify(() => preResolver.onTrackStarted(
            queue: queue,
            currentIndex: 0,
            isShuffle: false,
            shuffleIndices: null,
            position: null,
            duration: null,
          )).called(1);
    });

    test('Forwards onQueueMutated to preResolver', () {
      final queue = [_createMockSong(1)];
      orchestrator.onQueueMutated(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
      );

      verify(() => preResolver.onQueueMutated(
            queue: queue,
            currentIndex: 0,
            isShuffle: false,
            shuffleIndices: null,
            position: null,
            duration: null,
          )).called(1);
    });
  });

  group('StreamResolutionPipeline Resolution Tests', () {
    test('Delegates every resolve to the shared YtmService URL cache',
        () async {
      SharedPreferences.setMockInitialValues({});
      final ytmService = MockYtmService();
      final pipeline = StreamResolutionPipeline(ytmService: ytmService);
      final song = _createMockSong(
        1,
        remoteId: 'abcdefghijk',
        source: SongSource.youtube,
      );

      when(() => ytmService.resolveStream(
            any(),
            quality: any(named: 'quality'),
            forceRefresh: any(named: 'forceRefresh'),
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            duration: any(named: 'duration'),
          )).thenAnswer((_) async => YtmStream(
            videoId: 'abcdefghijk',
            url: 'https://stream.url/audio',
            mimeType: 'audio/webm',
            container: 'webm',
            bitrateKbps: 256,
            duration: const Duration(minutes: 3),
            title: 'Track',
            artist: 'Artist',
          ));

      final first = await pipeline.resolveStreamUrl(song);
      final second = await pipeline.resolveStreamUrl(song);

      expect(first.url, 'https://stream.url/audio');
      expect(first.quality, 'high');
      expect(second.url, first.url);
      verify(() => ytmService.resolveStream(
            any(),
            quality: any(named: 'quality'),
            forceRefresh: any(named: 'forceRefresh'),
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            duration: any(named: 'duration'),
          )).called(2);
    });

    test('Leaves codec null when container and mimeType are unrecognized',
        () async {
      SharedPreferences.setMockInitialValues({});
      final ytmService = MockYtmService();
      String? reportedCodec = 'sentinel';
      int? reportedBitrate;
      final pipeline = StreamResolutionPipeline(
        ytmService: ytmService,
        onStreamResolved: (_, bitrate, codec) {
          reportedBitrate = bitrate;
          reportedCodec = codec;
        },
      );
      final song = _createMockSong(
        2,
        remoteId: 'xyz98765432',
        source: SongSource.youtube,
      );

      when(() => ytmService.resolveStream(
            any(),
            quality: any(named: 'quality'),
            forceRefresh: any(named: 'forceRefresh'),
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            duration: any(named: 'duration'),
          )).thenAnswer((_) async => YtmStream(
            videoId: 'xyz98765432',
            url: 'https://stream.url/unknown',
            mimeType: 'application/octet-stream',
            container: 'bin',
            bitrateKbps: 192,
            duration: const Duration(minutes: 3),
            title: 'Track',
            artist: 'Artist',
          ));

      await pipeline.resolveStreamUrl(song);
      expect(reportedBitrate, 192);
      expect(reportedCodec, isNull);
    });
  });

  group('PlaybackPositionPersister', () {
    test('Persists position, saves dirty queue, and writes recovery file',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('persister_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final repo = MockMusicRepository();
      when(() => repo.updateLastPosition(any(), any()))
          .thenAnswer((_) async => const Right(null));
      when(() => repo.saveQueue(any(), any(), any()))
          .thenAnswer((_) async => const Right(null));
      when(() => repo.updateQueuePosition(any()))
          .thenAnswer((_) async => const Right(null));

      var dirty = true;
      var savedQueueIndex = -1;
      var clearedCrash = false;

      final persister = PlaybackPositionPersister(
        repository: repo,
        readSnapshot: () => const PlaybackPositionSnapshot(
          songId: 42,
          queueIndex: 1,
          positionMs: 12345,
          queueIds: [41, 42, 43],
          isIdle: false,
          queueDirty: true,
          savedQueueIndex: 0,
        ),
        readCurrentPositionMs: () => 12345,
        isDisposed: () => false,
        clearDirty: () => dirty = false,
        markDirty: () => dirty = true,
        onQueueSaved: (idx) => savedQueueIndex = idx,
        getDocumentsDirectory: () async => tempDir,
        writeCrashSnapshot: ({
          required int songId,
          required int queueIndex,
          required int positionMs,
          required List<int> queueIds,
        }) async {},
        clearCrashSnapshot: () async => clearedCrash = true,
        nowMs: () => 1700000000000,
      );

      await persister.saveCurrentPositionImmediate();

      expect(dirty, isFalse);
      expect(savedQueueIndex, 1);
      expect(clearedCrash, isTrue);
      verify(() => repo.updateLastPosition(42, 12345)).called(1);
      verify(() => repo.saveQueue([41, 42, 43], 1, 12345)).called(1);

      final recovered = await persister.readCrashPositionRecovery();
      expect(recovered?['songId'], 42);
      expect(recovered?['positionMs'], 12345);
      expect(recovered?['queueIndex'], 1);
    });

    test('Skips idle zero-position overwrite for same song (B5 guard)',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('persister_b5_');
      addTearDown(() => tempDir.delete(recursive: true));
      final repo = MockMusicRepository();
      when(() => repo.updateLastPosition(any(), any()))
          .thenAnswer((_) async => const Right(null));
      when(() => repo.updateQueuePosition(any()))
          .thenAnswer((_) async => const Right(null));

      var snapshot = const PlaybackPositionSnapshot(
        songId: 9,
        queueIndex: 0,
        positionMs: 55000,
        queueIds: [9],
        isIdle: false,
        queueDirty: false,
        savedQueueIndex: 0,
      );
      var currentPosMs = 55000;
      var dirty = true;

      final persister = PlaybackPositionPersister(
        repository: repo,
        readSnapshot: () => snapshot,
        readCurrentPositionMs: () => currentPosMs,
        isDisposed: () => false,
        clearDirty: () => dirty = false,
        markDirty: () => dirty = true,
        onQueueSaved: (_) {},
        getDocumentsDirectory: () async => tempDir,
        writeCrashSnapshot: ({
          required int songId,
          required int queueIndex,
          required int positionMs,
          required List<int> queueIds,
        }) async {},
        clearCrashSnapshot: () async {},
      );

      await persister.saveCurrentPositionImmediate();
      dirty = true;
      currentPosMs = 0;
      snapshot = const PlaybackPositionSnapshot(
        songId: 9,
        queueIndex: 0,
        positionMs: 0,
        queueIds: [9],
        isIdle: true,
        queueDirty: false,
        savedQueueIndex: 0,
      );

      await persister.saveCurrentPositionImmediate();

      verify(() => repo.updateLastPosition(9, 55000)).called(1);
      verifyNever(() => repo.updateLastPosition(9, 0));
      expect(dirty, isFalse);
    });

    test('Coalesces concurrent saves and falls back to .tmp recovery file',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('persister_tmp_');
      addTearDown(() => tempDir.delete(recursive: true));
      final repo = MockMusicRepository();
      final firstWrite = Completer<void>();
      var writeCalls = 0;
      var posMs = 1000;

      when(() => repo.updateLastPosition(any(), any())).thenAnswer((_) async {
        writeCalls++;
        if (writeCalls == 1) {
          await firstWrite.future;
        }
        return const Right(null);
      });
      when(() => repo.updateQueuePosition(any()))
          .thenAnswer((_) async => const Right(null));

      final persister = PlaybackPositionPersister(
        repository: repo,
        readSnapshot: () => PlaybackPositionSnapshot(
          songId: 3,
          queueIndex: 0,
          positionMs: posMs,
          queueIds: const [3],
          isIdle: false,
          queueDirty: false,
          savedQueueIndex: 0,
        ),
        readCurrentPositionMs: () => posMs,
        isDisposed: () => false,
        clearDirty: () {},
        markDirty: () {},
        onQueueSaved: (_) {},
        getDocumentsDirectory: () async => tempDir,
        writeCrashSnapshot: ({
          required int songId,
          required int queueIndex,
          required int positionMs,
          required List<int> queueIds,
        }) async {},
        clearCrashSnapshot: () async {},
      );

      final f1 = persister.saveCurrentPositionImmediate();
      await Future<void>.delayed(Duration.zero);
      posMs = 2000;
      final f2 = persister.saveCurrentPositionImmediate();
      final f3 = persister.saveCurrentPositionImmediate();
      firstWrite.complete();
      await Future.wait([f1, f2, f3]);

      expect(writeCalls, 2);

      // Verify .tmp fallback when committed recovery file is absent.
      final committed = File(p.join(tempDir.path, 'last_position.json'));
      if (await committed.exists()) {
        await committed.delete();
      }
      await File('${committed.path}.tmp').writeAsString(jsonEncode({
        'songId': 77,
        'positionMs': 4444,
        'queueIndex': 2,
      }));
      final recovered = await persister.readCrashPositionRecovery();
      expect(recovered?['songId'], 77);
      expect(recovered?['positionMs'], 4444);
    });
  });
}
