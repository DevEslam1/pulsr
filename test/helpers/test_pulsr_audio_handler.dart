// test/helpers/test_pulsr_audio_handler.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:rxdart/rxdart.dart';

class TestPulsrAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements PulsrAudioHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  double _vol = 1.0;
  int setVolumeCallCount = 0;
  @override
  double get minPlaybackSpeed => 0.5;
  @override
  double get maxPlaybackSpeed => 3.0;
  @override
  double get volume => _vol;
  @override
  SongsTableData? get currentSong => _currentTrack;
  SongsTableData? _currentTrack;
  @override
  int? get currentAudioSessionId => 101;
  @override
  Future<void> setVolume(double volume) async {
    _vol = volume;
    setVolumeCallCount += 1;
  }

  bool eqEnabled = false;
  EqPreset currentEqPreset = EqPreset.defaultPresets.first;
  Duration? sleepTimerDuration;
  Duration currentCrossfadeDuration = Duration.zero;

  @override
  bool get isEqualizerEnabled => eqEnabled;

  @override
  EqPreset get currentPreset => currentEqPreset;

  @override
  Duration get crossfadeDuration => currentCrossfadeDuration;

  @override
  Stream<Duration> get positionStream => _positionController.stream;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  final StreamController<MediaItem?> _mediaItemController =
      StreamController<MediaItem?>.broadcast();
  @override
  BehaviorSubject<MediaItem?> get mediaItem =>
      BehaviorSubject<MediaItem?>.seeded(null)
        ..addStream(_mediaItemController.stream);

  final StreamController<List<MediaItem>> _queueController =
      StreamController<List<MediaItem>>.broadcast();
  @override
  BehaviorSubject<List<MediaItem>> get queue =>
      BehaviorSubject<List<MediaItem>>.seeded([])
        ..addStream(_queueController.stream);

  final StreamController<PlaybackState> _playbackStateController =
      StreamController<PlaybackState>.broadcast();
  @override
  BehaviorSubject<PlaybackState> get playbackState =>
      BehaviorSubject<PlaybackState>.seeded(PlaybackState())
        ..addStream(_playbackStateController.stream);

  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  @override
  Stream<String> get errorStream => _errorController.stream;

  final StreamController<Duration?> _sleepTimerController =
      StreamController<Duration?>.broadcast();
  @override
  Stream<Duration?> get sleepTimerRemainingStream =>
      _sleepTimerController.stream;

  final StreamController<int?> _audioSessionIdController =
      StreamController<int?>.broadcast();
  @override
  Stream<int?> get audioSessionIdStream => _audioSessionIdController.stream;

  final StreamController<SongsTableData> _onTrackChangedController =
      StreamController<SongsTableData>.broadcast();
  @override
  Stream<SongsTableData> get onTrackChanged => _onTrackChangedController.stream;

  void emitTrackChanged(SongsTableData song) {
    _currentTrack = song;
    _onTrackChangedController.add(song);
  }

  void emitQueue(List<MediaItem> items) {
    _queueController.add(items);
  }

  void emitMediaItem(MediaItem? item) {
    _mediaItemController.add(item);
  }

  void emitPlaybackState(PlaybackState state) {
    _playbackStateController.add(state);
  }

  @override
  void setCrossfadeDuration(Duration d) {
    currentCrossfadeDuration = d;
  }

  bool gaplessEnabled = true;
  @override
  bool get isGaplessEnabled => gaplessEnabled;

  @override
  void setGaplessEnabled(bool enabled) {
    gaplessEnabled = enabled;
  }

  @override
  Future<void> restoreLastPlaybackSession() async {}

  @override
  Future<void> saveCurrentPositionImmediate() async {}

  @override
  Future<void> setEqualizerEnabled(bool enabled) async {
    eqEnabled = enabled;
  }

  @override
  Future<void> applyPreset(EqPreset preset) async {
    currentEqPreset = preset;
  }

  @override
  Future<void> setBandGain(int bandIndex, double gainDb) async {}

  @override
  Future<void> setBassBoost(double amount) async {}

  @override
  bool get isVirtualizerEnabled => false;

  @override
  double get virtualizerStrength => 0.0;

  @override
  bool get isDynamicsEnabled => false;

  @override
  bool get isDynamicsEffectivelyEnabled => false;

  @override
  bool get isDynamicsSupported => true;

  @override
  DynamicsPreset get dynamicsPreset => DynamicsPreset.off;

  @override
  HeadphoneProfile? get selectedHeadphoneProfile => null;

  @override
  Future<void> setVirtualizerEnabled(bool enabled) async {}

  @override
  Future<void> setVirtualizerStrength(double strength) async {}

  @override
  Future<void> setDynamicsPreset(
    DynamicsPreset preset, {
    bool? enabled,
  }) async {}

  @override
  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) async {}

  @override
  bool get isSpatializerEnabled => false;

  @override
  bool get isSpatializerSupported => false;

  @override
  bool get isHeadTrackerAvailable => false;

  @override
  Future<void> setSpatializerEnabled(bool enabled) async {}

  @override
  double get volumeBoost => 0.0;

  @override
  Future<void> setVolumeBoost(double value) async {}

  @override
  Future<void> resetToFlat() async {}

  @override
  Future<void> startAbComparison() async {}

  @override
  Future<void> endAbComparison() async {}

  @override
  bool get isAbComparisonActive => false;

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
  bool get isVirtualizerSupported => true;
  @override
  bool get isBassBoostSupported => true;
  @override
  bool get isVolumeBoostSupported => true;
  @override
  bool get isSincResamplerEnabled => true;
  @override
  bool get isDitherEnabled => false;
  @override
  int get ditherTargetBitDepth => 16;
  @override
  bool get hasOemAudio => false;
  @override
  List<String> get detectedOemEngines => const [];

  bool persistedSaturationEnabled = false;

  @override
  bool get isSaturationEnabled => persistedSaturationEnabled;
  @override
  double get saturationDrive => 0.0;
  @override
  double get saturationMix => 0.5;
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
  double get subCrossoverSlopeDbPerOct => 24.0;
  @override
  double get subCrossoverGain => 0.8;
  @override
  bool get isDynamicEqEnabled => false;
  @override
  List<DynamicEqBandConfig> get dynamicEqBands => const [];
  @override
  int get crossfeedMode => 0;
  @override
  bool get saturationMultiband => false;
  @override
  bool get isViperDdcEnabled => false;
  @override
  String get viperDdcProfileName => '';
  @override
  bool get isArbitraryEqEnabled => false;
  @override
  String get arbitraryEqString => '';
  @override
  bool get isLiveProgEnabled => false;
  @override
  String get liveProgCode => '';
  @override
  bool get isDynamicBassEnabled => false;
  @override
  double get dynamicBassStrength => 1.0;
  @override
  int get dynamicBassPreset => 0;
  @override
  Future<void> setDynamicBass({
    required bool enabled,
    double? strength,
    int? preset,
    int? xLow,
    int? xHigh,
    int? yLow,
    int? yHigh,
    double? sideGainLow,
    double? sideGainHigh,
  }) async {}
  @override
  Future<void> setSaturation(
    bool enabled, {
    double? drive,
    double? mix,
    double? tilt,
    int? mode,
    bool? multiband,
  }) async {}
  @override
  Future<void> setStereoWidth(
    bool enabled, {
    double? width,
    bool? multiband,
    double? lowWidth,
    double? midWidth,
    double? highWidth,
    double? lowCrossoverHz,
    double? highCrossoverHz,
  }) async {}
  @override
  Future<void> setLoudnessContour(bool enabled, {double? intensity}) async {}
  @override
  Future<void> setSubCrossover(
    bool enabled, {
    double? cornerHz,
    double? slopeDbPerOct,
    double? gain,
    bool? bassMono,
    bool? antiPop,
  }) async {}
  @override
  Future<void> setDynamicEq(bool enabled) async {}
  @override
  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) async {}

  Completer<void>? readyGate;
  @override
  Future<void> get effectsReady => readyGate?.future ?? Future<void>.value();

  @override
  Future<void> setCrossfeed(
    bool enabled, {
    double? delayUs,
    double? feedDb,
    int? mode,
  }) async {}
  @override
  Future<void> setLookaheadLimiter(
    bool enabled, {
    double? thresholdDb,
    double? releaseMs,
    double? lookaheadMs,
  }) async {}
  @override
  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) async {}
  @override
  Future<bool> loadCustomImpulseResponse(List<double> irSamples) async => true;
  @override
  Future<void> setStereoBalance(double balance) async {}
  @override
  Future<void> setMonoMix(bool mono) async {}
  @override
  Future<void> setSincResampler(bool enabled) async {}
  @override
  Future<void> setDither(bool enabled, {int? targetBitDepth}) async {}

  @override
  Future<void> toggleDynamicsBypass() async {}

  @override
  Future<void> switchComparisonSlot(ComparisonSlot slot) async {}

  @override
  bool get isDynamicsBypassed => false;

  @override
  Future<void> setCustomFrequencies(List<double> frequencies) async {}

  @override
  Future<void> onAppPaused() async {}

  @override
  void startSleepTimer(Duration duration, {bool fadeOut = true}) {
    sleepTimerDuration = duration;
  }

  @override
  void startAbsoluteSleepTimer(DateTime stopTime, {bool fadeOut = true}) {
    sleepTimerDuration = stopTime.difference(DateTime.now());
  }

  int? sleepTimerTracks;
  @override
  int? get sleepTimerRemainingTracks => sleepTimerTracks;

  @override
  void startEndOfTrackTimer({bool fadeOut = true}) {
    sleepTimerDuration = const Duration(minutes: 1);
    sleepTimerTracks = 1;
  }

  @override
  void startAfterNTracksTimer(int trackCount, {bool fadeOut = true}) {
    sleepTimerDuration = Duration(minutes: trackCount * 3);
    sleepTimerTracks = trackCount;
  }

  @override
  void cancelSleepTimer() {
    sleepTimerDuration = null;
    sleepTimerTracks = null;
  }

  @override
  Future<void> insertNextInQueue(SongsTableData song) async {}

  @override
  Future<void> addToQueueEnd(SongsTableData song) async {}

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {}

  @override
  Future<void> removeQueueItemAt(int index) async {}

  @override
  Future<void> loadQueue(
    List<SongsTableData> songs, {
    int initialIndex = 0,
    Duration? initialPosition,
    bool autoPlay = true,
  }) async {
    if (songs.isNotEmpty && initialIndex >= 0 && initialIndex < songs.length) {
      _currentTrack = songs[initialIndex];
      final item = MediaItem(
        id: _currentTrack!.id.toString(),
        title: _currentTrack!.title,
        artist: _currentTrack!.artist,
      );
      _mediaItemController.add(item);
      _queueController.add(songs
          .map((s) => MediaItem(id: s.id.toString(), title: s.title, artist: s.artist))
          .toList());
      _onTrackChangedController.add(_currentTrack!);
      if (autoPlay) {
        await play();
      }
    }
  }

  double? lastSetSpeed;
  @override
  Future<void> setSpeed(double speed) async {
    lastSetSpeed = speed;
  }

  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _mediaItemController.close();
    await _queueController.close();
    await _playbackStateController.close();
    await _errorController.close();
    await _sleepTimerController.close();
    await _audioSessionIdController.close();
    await _onTrackChangedController.close();
  }

  @override
  Future<void> playSongAt(int index, {Duration? initialPosition}) async {}

  @override
  Future<void> validatePlayerState() async {}

  @override
  Future<void> play() async {
    playCalls++;
    _playbackStateController.add(PlaybackState(
      playing: true,
      processingState: AudioProcessingState.ready,
    ));
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _playbackStateController.add(PlaybackState(
      playing: false,
      processingState: AudioProcessingState.ready,
    ));
  }

  int playCalls = 0;
  int pauseCalls = 0;

  @override
  Future<void> stop() async {
    _playbackStateController.add(PlaybackState(
      playing: false,
      processingState: AudioProcessingState.idle,
    ));
  }

  @override
  Future<void> seek(Duration position) async {
    _positionController.add(position);
  }

  @override
  Future<void> seekDirect(Duration position) async {
    _positionController.add(position);
  }

  @override
  Future<void> skipToNext() async {}

  @override
  Future<void> skipToPrevious() async {}

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {}

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {}
}
