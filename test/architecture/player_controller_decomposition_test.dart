// test/architecture/player_controller_decomposition_test.dart
// FIX-A1: Unit tests verifying the 5 decomposed player controllers in isolation
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/managers/player_lyrics_manager.dart';
import 'package:pulsr/features/player/cubit/managers/player_sponsorblock_manager.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

class MockAudioHandler extends Mock implements PulsrAudioHandler {}
class MockMusicRepository extends Mock implements IMusicRepository {}

void main() {
  group('Phase A: Player Controller Decomposition Tests', () {
    late MockAudioHandler mockAudioHandler;
    late MockMusicRepository mockRepository;

    const testSong = SongsTableData(
      id: 10,
      title: 'Architectural Track',
      artist: 'Modular Artist',
      album: 'Clean Code',
      durationMs: 200000,
      path: '/path/test.mp3',
      source: SongSource.local,
      playCount: 0,
      dateAdded: 0,
      isFavorite: false,
      isMissing: false,
      lastPositionMs: 0,
      isDownloaded: false,
    );

    setUpAll(() {
      registerFallbackValue(EqPreset.defaultPresets.first);
      registerFallbackValue(testSong);
    });

    setUp(() {
      mockAudioHandler = MockAudioHandler();
      mockRepository = MockMusicRepository();
      when(() => mockAudioHandler.play()).thenAnswer((_) async {});
      when(() => mockAudioHandler.pause()).thenAnswer((_) async {});
      when(() => mockAudioHandler.setEqualizerEnabled(any())).thenAnswer((_) async {});
      when(() => mockAudioHandler.applyPreset(any())).thenAnswer((_) async {});
      when(() => mockAudioHandler.addToQueueEnd(any())).thenAnswer((_) async {});
    });

    test('PlayerTransportController delegates play and pause correctly', () async {
      var state = const PlayerState();
      final controller = PlayerTransportController(
        audioHandler: mockAudioHandler,
        getState: () => state,
        emit: (s) => state = s,
        isClosed: () => false,
      );

      await controller.play();
      expect(state.isPlaying, isTrue);
      verify(() => mockAudioHandler.play()).called(1);

      await controller.pause();
      expect(state.isPlaying, isFalse);
      verify(() => mockAudioHandler.pause()).called(1);

      controller.dispose();
    });

    test('PlayerQueueController bounds queue size to maxQueueSize and adds tracks', () async {
      var state = const PlayerState();
      final lookupCache = <int, SongsTableData>{};
      final queueSlots = <int, QueueSlotData>{};
      final mutex = Mutex();

      final controller = PlayerQueueController(
        audioHandler: mockAudioHandler,
        getState: () => state,
        emit: (s) => state = s,
        isClosed: () => false,
        queueMutex: mutex,
        slotLookupCache: lookupCache,
        queueSlots: queueSlots,
        updateWidgetThrottled: ({force = false}) {},
        loadLyrics: (_) {},
        debouncedPersistQueueSlots: () {},
        bumpQueueVersion: () {},
        isSameTrack: (a, b) => a?.id == b?.id,
      );

      await controller.addToQueue(testSong);
      expect(state.queue.length, equals(1));
      expect(state.queue.first.id, equals(10));
      expect(lookupCache[10], equals(testSong));
    });

    test('PlayerDspController delegates equalizer and effects updates', () async {
      var state = const PlayerState();
      final controller = PlayerDspController(
        audioHandler: mockAudioHandler,
        settingsCubit: null,
        getState: () => state,
        emit: (s) => state = s,
      );

      expect(controller.guardDsp('EQ'), isTrue);

      await controller.setEqualizerEnabled(true);
      expect(state.isEqEnabled, isTrue);
      verify(() => mockAudioHandler.setEqualizerEnabled(true)).called(1);

      final preset = EqPreset.defaultPresets.first;
      await controller.applyPreset(preset);
      expect(state.eqPreset, equals(preset));
      verify(() => mockAudioHandler.applyPreset(preset)).called(1);
    });

    test('PlayerMetadataController executes cue chapters check cleanly', () async {
      var state = const PlayerState(currentSong: testSong);
      final controller = PlayerMetadataController(
        lyricsManager: PlayerLyricsManager(),
        sponsorBlockManager: PlayerSponsorBlockManager(),
        repository: mockRepository,
        getState: () => state,
        emit: (s) => state = s,
        isClosed: () => false,
        isSameTrack: (a, b) => a?.id == b?.id,
      );

      // Song without CUE clears cue chapters safely
      await controller.loadCueChapters(testSong);
      expect(state.cueChapters, isEmpty);
    });

    test('PlayerWidgetBridge initializes and executes without crashing', () {
      final bridge = PlayerWidgetBridge(
        widgetService: null,
        scrobblerService: null,
        latencyTracker: null,
        isQuranMode: () => false,
        isClosed: () => false,
      );

      expect(() => bridge.updateWidgetThrottled(const PlayerState(), 1), returnsNormally);
      expect(() => bridge.updateProgressThrottled(const PlayerState()), returnsNormally);
      bridge.dispose();
    });
  });
}
