// test/data/audio/collaborators_test.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/collaborators/playback_queue_manager.dart';
import 'package:pulsr/data/audio/collaborators/playback_volume_controller.dart';
import 'package:pulsr/data/audio/collaborators/playback_state_coordinator.dart';
import 'package:pulsr/data/audio/collaborators/playback_preload_orchestrator.dart';
import 'package:pulsr/data/audio/smart_preload_scheduler.dart';
import 'package:pulsr/data/audio/stream_pre_resolver.dart';
import 'package:pulsr/data/db/app_database.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}
class MockSmartPreloadScheduler extends Mock implements SmartPreloadScheduler {}
class MockStreamPreResolver extends Mock implements StreamPreResolver {}

SongsTableData _createMockSong(int id, {
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

  group('PlaybackQueueManager Tests', () {
    late PlaybackQueueManager manager;
    final testQueue = List.generate(5, (i) => _createMockSong(i + 1));

    setUp(() {
      manager = PlaybackQueueManager();
      manager.setQueue(testQueue, initialIndex: 0);
    });

    test('Initializes queue and clamp index correctly', () {
      expect(manager.songs.length, equals(5));
      expect(manager.currentIndex, equals(0));
      expect(manager.currentSong?.id, equals(1));
    });

    test('Sequential next and previous navigation without repeat', () {
      manager.setRepeatMode(AudioServiceRepeatMode.none);
      
      expect(manager.getNextIndex(), equals(1));
      manager.setCurrentIndex(1);
      expect(manager.getNextIndex(), equals(2));
      expect(manager.getPreviousIndex(), equals(0));

      manager.setCurrentIndex(4); // Last song
      expect(manager.getNextIndex(), isNull); // Reached end
    });

    test('Repeat Mode: all wraps around', () {
      manager.setRepeatMode(AudioServiceRepeatMode.all);
      
      manager.setCurrentIndex(4); // Last song
      expect(manager.getNextIndex(), equals(0)); // Wraps to beginning

      manager.setCurrentIndex(0); // First song
      expect(manager.getPreviousIndex(), equals(4)); // Wraps to end
    });

    test('Repeat Mode: one repeats the current song', () {
      manager.setRepeatMode(AudioServiceRepeatMode.one);
      manager.setCurrentIndex(2);
      expect(manager.getNextIndex(), equals(2));
      expect(manager.getPreviousIndex(), equals(2));
    });

    test('Shuffle mode produces valid permutation and navigates', () {
      manager.setShuffle(true);
      expect(manager.isShuffle, isTrue);
      expect(manager.shuffleIndices.length, equals(5));
      expect(manager.shuffleIndices.toSet().length, equals(5)); // Unique

      final nextIdx = manager.getNextIndex();
      expect(nextIdx, isNotNull);
      expect(nextIdx! >= 0 && nextIdx < 5, isTrue);

      manager.setShuffle(false);
      expect(manager.isShuffle, isFalse);
    });

    test('Sliding window materialization calculates correct window bounds', () {
      // Current index 2, windowBefore 1, windowAfter 1 -> window [1, 4]
      manager.setCurrentIndex(2);
      final window = manager.getSlidingWindow(windowBefore: 1, windowAfter: 1);
      expect(window.start, equals(1));
      expect(window.end, equals(4));

      // Current index 0, windowBefore 2, windowAfter 2 -> window [0, 3]
      manager.setCurrentIndex(0);
      final edgeWindow = manager.getSlidingWindow(windowBefore: 2, windowAfter: 2);
      expect(edgeWindow.start, equals(0));
      expect(edgeWindow.end, equals(3));
    });

    test('Queue mutation: remove, insert, and move', () {
      manager.setCurrentIndex(2); // Song id 3
      manager.removeSongAt(0); // Remove Song 1
      expect(manager.songs.length, equals(4));
      expect(manager.currentIndex, equals(1)); // Shifted down
      expect(manager.currentSong?.id, equals(3));

      final newSong = _createMockSong(99);
      manager.insertSong(0, newSong);
      expect(manager.songs.length, equals(5));
      expect(manager.currentIndex, equals(2)); // Shifted up
      expect(manager.songs[0].id, equals(99));

      manager.moveSong(0, 4);
      expect(manager.songs.last.id, equals(99));
    });
  });

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
      final trackVol = controller.calculateTargetVolume(song, albumContext: false);
      expect(trackVol, closeTo(0.794, 0.01));

      // With album context -> album gain (-6dB -> ~0.501)
      final albumVol = controller.calculateTargetVolume(song, albumContext: true);
      expect(albumVol, closeTo(0.501, 0.01));
    });

    test('Applies volume immediately when smoothTransition is false', () async {
      await controller.applyVolume(activePlayer, 0.6, smoothTransition: false);
      verify(() => activePlayer.setVolume(0.6)).called(1);
    });

    test('Smooth 500ms volume transition reaches target volume', () async {
      when(() => activePlayer.volume).thenReturn(0.0);
      await controller.applyVolume(activePlayer, 1.0, smoothTransition: true);
      verify(() => activePlayer.setVolume(any())).called(greaterThanOrEqualTo(1));
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
}
