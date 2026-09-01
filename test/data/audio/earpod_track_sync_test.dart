// test/data/audio/earpod_track_sync_test.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}

class FakePulsrAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements PulsrAudioHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final List<SongsTableData> _queue = [];
  int _currentIdx = 0;

  @override
  SongsTableData? get currentSong =>
      (_queue.isNotEmpty && _currentIdx >= 0 && _currentIdx < _queue.length)
          ? _queue[_currentIdx]
          : null;

  @override
  int? get currentAudioSessionId => null;
  @override
  Future<void> get effectsReady => Future.value();
  @override
  double get volume => 1.0;
  @override
  bool get isEqualizerEnabled => false;
  @override
  EqPreset get currentPreset => EqPreset.defaultPresets.first;
  @override
  bool get isVirtualizerEnabled => false;
  @override
  double get virtualizerStrength => 0.0;
  @override
  bool get isDynamicsEnabled => false;
  @override
  DynamicsPreset get dynamicsPreset => DynamicsPreset.off;
  @override
  HeadphoneProfile? get selectedHeadphoneProfile => null;
  @override
  bool get isSpatializerEnabled => false;
  @override
  bool get isSpatializerSupported => false;
  @override
  double get volumeBoost => 0.0;
  @override
  bool get isCrossfeedEnabled => false;
  @override
  double get crossfeedDelayUs => 350.0;
  @override
  double get crossfeedFeedDb => -9.0;
  @override
  bool get isLimiterEnabled => false;
  @override
  double get limiterThresholdDb => -0.2;
  @override
  double get limiterReleaseMs => 50.0;
  @override
  bool get isReverbEnabled => false;
  @override
  int get reverbPreset => 0;
  @override
  double get reverbWetDry => 0.20;
  @override
  double get stereoBalance => 0.0;
  @override
  bool get monoMix => false;
  @override
  bool get isSincResamplerEnabled => true;
  @override
  bool get hasOemAudio => false;
  @override
  List<String> get detectedOemEngines => const [];
  @override
  bool get isSaturationEnabled => false;
  @override
  double get saturationDrive => 0.0;
  @override
  double get saturationMix => 0.0;
  @override
  double get saturationTilt => 0.0;
  @override
  bool get isStereoWidthEnabled => false;
  @override
  double get stereoWidth => 1.0;
  @override
  bool get isLoudnessContourEnabled => false;
  @override
  double get loudnessContourIntensity => 0.0;
  @override
  bool get isSubCrossoverEnabled => false;
  @override
  double get subCrossoverCornerHz => 80.0;
  @override
  double get subCrossoverSlopeDbPerOct => 12.0;
  @override
  double get subCrossoverGain => 0.0;
  @override
  bool get isDynamicEqEnabled => false;
  @override
  List<DynamicEqBandConfig> get dynamicEqBands => const [];
  @override
  Future<void> setCrossfadeDuration(Duration duration) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> validatePlayerState() async {}

  final StreamController<Duration> _posCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<String> _errCtrl =
      StreamController<String>.broadcast();

  @override
  Stream<Duration> get positionStream => _posCtrl.stream;
  @override
  Stream<String> get errorStream => _errCtrl.stream;
  @override
  Stream<int?> get audioSessionIdStream => const Stream.empty();
  @override
  Stream<Duration?> get sleepTimerRemainingStream => const Stream.empty();

  @override
  Future<void> loadQueue(List<SongsTableData> songs,
      {int initialIndex = 0, Duration? initialPosition}) async {
    _queue.clear();
    _queue.addAll(songs);
    _currentIdx = initialIndex.clamp(0, _queue.length - 1);
    final song = _queue[_currentIdx];
    mediaItem.add(MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(milliseconds: song.durationMs),
    ));
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: AudioProcessingState.ready,
      queueIndex: _currentIdx,
    ));
  }

  /// Simulates earpod button tap: next track
  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    _currentIdx = (_currentIdx + 1) % _queue.length;
    final song = _queue[_currentIdx];
    mediaItem.add(MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(milliseconds: song.durationMs),
    ));
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: AudioProcessingState.ready,
      queueIndex: _currentIdx,
    ));
  }

  /// Simulates earpod button tap: previous track
  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    _currentIdx = (_currentIdx - 1 + _queue.length) % _queue.length;
    final song = _queue[_currentIdx];
    mediaItem.add(MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(milliseconds: song.durationMs),
    ));
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: AudioProcessingState.ready,
      queueIndex: _currentIdx,
    ));
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIdx = index;
    final song = _queue[_currentIdx];
    mediaItem.add(MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(milliseconds: song.durationMs),
    ));
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: AudioProcessingState.ready,
      queueIndex: _currentIdx,
    ));
  }

  void simulateAutoAdvance(int nextIndex) {
    if (nextIndex < 0 || nextIndex >= _queue.length) return;
    _currentIdx = nextIndex;
    final song = _queue[_currentIdx];
    mediaItem.add(MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(milliseconds: song.durationMs),
    ));
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: AudioProcessingState.ready,
      queueIndex: _currentIdx,
    ));
  }

  @override
  void dispose() {
    _posCtrl.close();
    _errCtrl.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Earpods & Headset Playback Sync Tests', () {
    late MockMusicRepository mockRepository;
    late MockToggleFavoriteUseCase mockToggleFavoriteUseCase;
    late FakePulsrAudioHandler fakeHandler;
    late PlayerCubit cubit;

    final song1 = SongsTableData(
      id: 1,
      title: 'First Track',
      artist: 'Artist A',
      album: 'Album X',
      path: '/path/song1.mp3',
      source: SongSource.local,
      durationMs: 200000,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );

    final song2 = SongsTableData(
      id: 2,
      title: 'Second Track',
      artist: 'Artist B',
      album: 'Album X',
      path: '/path/song2.mp3',
      source: SongSource.local,
      durationMs: 220000,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );

    final song3 = SongsTableData(
      id: 3,
      title: 'Third Track',
      artist: 'Artist C',
      album: 'Album Y',
      path: '/path/song3.mp3',
      source: SongSource.local,
      durationMs: 180000,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );

    setUp(() {
      mockRepository = MockMusicRepository();
      mockToggleFavoriteUseCase = MockToggleFavoriteUseCase();
      fakeHandler = FakePulsrAudioHandler();

      when(() => mockRepository.getSongById(1))
          .thenAnswer((_) async => Right(song1));
      when(() => mockRepository.getSongById(2))
          .thenAnswer((_) async => Right(song2));
      when(() => mockRepository.getSongById(3))
          .thenAnswer((_) async => Right(song3));
      when(() => mockRepository.getSongsByIds(any()))
          .thenAnswer((_) async => Right([song1, song2, song3]));

      cubit = PlayerCubit(
        audioHandler: fakeHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavoriteUseCase,
      );
    });

    tearDown(() async {
      await cubit.close();
      fakeHandler.dispose();
    });

    test('natural track end in earpods immediately updates PlayerCubit and mediaItem', () async {
      // 1. Start queue at Track 1
      await cubit.playSong(song1, queue: [song1, song2, song3]);
      expect(cubit.state.currentIndex, 0);
      expect(cubit.state.currentSong?.id, 1);
      expect(fakeHandler.mediaItem.value?.id, '1');

      // 2. Track 1 finishes playing in earpods; ExoPlayer advances to Track 2
      fakeHandler.simulateAutoAdvance(1);
      await pumpEventQueue();

      // 3. UI and notification must both reflect Track 2 immediately
      expect(cubit.state.currentIndex, 1);
      expect(cubit.state.currentSong?.id, 2);
      expect(cubit.state.currentSong?.title, 'Second Track');
      expect(fakeHandler.mediaItem.value?.id, '2');
      expect(fakeHandler.mediaItem.value?.title, 'Second Track');
    });

    test('pressing Next on earpods advances song and prevents wrong subsequent skips', () async {
      // 1. Play queue starting at Track 1
      await cubit.playSong(song1, queue: [song1, song2, song3]);
      expect(cubit.state.currentIndex, 0);

      // 2. User presses Next on earpods
      await fakeHandler.skipToNext();
      await pumpEventQueue();

      // 3. Current track in Cubit and notification is now Track 2 (index 1)
      expect(cubit.state.currentIndex, 1);
      expect(cubit.state.currentSong?.id, 2);

      // 4. User immediately presses Next again on earpods or in UI
      await cubit.next();
      await pumpEventQueue();

      // 5. Must correctly advance to Track 3 (index 2) without repeating Track 2
      expect(cubit.state.currentIndex, 2);
      expect(cubit.state.currentSong?.id, 3);
      expect(cubit.state.currentSong?.title, 'Third Track');
    });

    test('pressing Previous on earpods goes to previous track accurately', () async {
      // 1. Start at Track 3 (index 2)
      await cubit.playSong(song3, queue: [song1, song2, song3]);
      expect(cubit.state.currentIndex, 2);

      // 2. User presses Previous on earpods
      await fakeHandler.skipToPrevious();
      await pumpEventQueue();

      // 3. Must move to Track 2 (index 1)
      expect(cubit.state.currentIndex, 1);
      expect(cubit.state.currentSong?.id, 2);

      // 4. User presses Previous again
      await fakeHandler.skipToPrevious();
      await pumpEventQueue();

      // 5. Must move to Track 1 (index 0)
      expect(cubit.state.currentIndex, 0);
      expect(cubit.state.currentSong?.id, 1);
    });

    test('skipToQueueItem from external controls (Android Auto, AVRCP) jumps correctly', () async {
      // 1. Start at Track 1
      await cubit.playSong(song1, queue: [song1, song2, song3]);
      expect(cubit.state.currentIndex, 0);

      // 2. External command jumps directly to index 2 (Track 3)
      await fakeHandler.skipToQueueItem(2);
      await pumpEventQueue();

      // 3. Both Cubit and mediaItem reflect Track 3
      expect(cubit.state.currentIndex, 2);
      expect(cubit.state.currentSong?.id, 3);
      expect(fakeHandler.mediaItem.value?.id, '3');
    });
  });
}
