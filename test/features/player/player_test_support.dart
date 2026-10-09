// Shared harness for the new Player coverage tests.
//
// Not a test file (no `_test` suffix): provides mocktail mocks, a recording
// audio handler that fills in the DSP/queue surface the shared helper leaves to
// noSuchMethod, canonical song builders, and helpers to assemble a real
// PlayerCubit / PlayerDspController / PlayerQueueController.
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/scrobbler_service.dart';
import 'package:pulsr/data/audio/comparison_slot.dart';
import 'package:pulsr/data/audio/stream_pre_resolver.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/widgets/widget_service.dart';

import '../../helpers/test_pulsr_audio_handler.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

class MockWidgetService extends Mock implements WidgetService {}

class MockScrobblerService extends Mock implements ScrobblerService {}

class MockStreamPreResolver extends Mock implements StreamPreResolver {}

/// The shared helper leaves several DSP/queue methods to `noSuchMethod`, which
/// throws. This subclass implements them as recording no-ops so the success
/// paths of the DSP/queue controllers are exercisable.
class RecordingAudioHandler extends TestPulsrAudioHandler {
  final List<String> calls = <String>[];

  /// Method names (as recorded) that should throw when invoked.
  final Set<String> throwCalls = <String>{};

  /// Optional predicate: return a non-null error to make the named call throw.
  Object? Function(String name)? failWhen;

  /// Result returned by [loadCustomImpulseResponse].
  bool irLoadResult = true;

  void _record(String name) {
    calls.add(name);
    final forced = failWhen?.call(name);
    if (forced != null) {
      throw forced;
    }
    if (throwCalls.contains(name)) {
      throw Exception('forced failure: $name');
    }
  }

  @override
  Future<bool> loadCustomImpulseResponse(List<double> irSamples) async {
    _record('loadCustomImpulseResponse');
    return irLoadResult;
  }

  @override
  Future<void> setLookaheadLimiter(bool enabled,
      {double? thresholdDb, double? releaseMs, double? lookaheadMs}) async {
    _record('setLookaheadLimiter');
  }

  @override
  Future<void> setBassBoost(double amount) async {
    _record('setBassBoost');
  }

  @override
  Future<void> setVolumeBoost(double value) async {
    _record('setVolumeBoost');
  }

  @override
  Future<void> setVirtualizerEnabled(bool enabled) async {
    _record('setVirtualizerEnabled');
  }

  @override
  Future<void> setVirtualizerStrength(double strength) async {
    _record('setVirtualizerStrength');
  }

  @override
  Future<void> setSpatializerEnabled(bool enabled) async {
    _record('setSpatializerEnabled');
  }

  @override
  Future<void> toggleDynamicsBypass() async {
    _record('toggleDynamicsBypass');
  }

  @override
  Future<void> switchComparisonSlot(ComparisonSlot slot) async {
    _record('switchComparisonSlot');
  }

  @override
  Future<void> setDither(bool enabled, {int? targetBitDepth}) async {
    _record('setDither');
  }

  @override
  Future<void> setStereoBalance(double balance) async {
    _record('setStereoBalance');
  }

  @override
  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) async {
    _record('setDynamicEqBand');
  }

  @override
  Future<void> setCrossfeedMode(int mode) async => _record('setCrossfeedMode');

  @override
  Future<void> setSaturationMultiband(bool multiband) async =>
      _record('setSaturationMultiband');

  @override
  Future<void> setViperDdc(bool enabled,
          {String? profileName, List<double>? coeffs, String? ddcContent}) async =>
      _record('setViperDdc');

  @override
  Future<void> setArbitraryEq(bool enabled,
          {String? eqString, bool? linearPhase}) async =>
      _record('setArbitraryEq');

  @override
  bool get arbitraryEqLinearPhase => false;

  @override
  Future<void> setLiveProg(bool enabled, {String? code}) async =>
      _record('setLiveProg');

  @override
  Future<void> setLiveProgSlider(int sliderIndex, double value) async =>
      _record('setLiveProgSlider');

  @override
  Future<void> addDynamicEqBand() async => _record('addDynamicEqBand');

  @override
  Future<void> removeDynamicEqBand(int index) async =>
      _record('removeDynamicEqBand');

  @override
  Future<void> setBypassCompare({
    required bool bypass,
    double gainCompensationDb = 0.0,
  }) async =>
      _record('setBypassCompare');

  @override
  Future<void> clearQueue() async => _record('clearQueue');

  @override
  void swapReconciledSong(int oldId, SongsTableData newSong) =>
      _record('swapReconciledSong');

  @override
  Future<void> addToQueueEnd(SongsTableData song) async =>
      _record('addToQueueEnd');

  @override
  Future<void> insertNextInQueue(SongsTableData song) async =>
      _record('insertNextInQueue');

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async =>
      _record('reorderQueue');

  @override
  Future<void> removeQueueItemAt(int index) async =>
      _record('removeQueueItemAt');

  StreamPreResolver? preResolver;

  @override
  StreamPreResolver get streamPreResolver =>
      preResolver ?? (throw UnimplementedError('no preResolver'));

  /// When true, [loadQueue] delegates to the shared helper's real
  /// implementation (emitting mediaItem/queue/onTrackChanged + play).
  bool realLoadQueue = false;

  @override
  Future<void> loadQueue(
    List<SongsTableData> songs, {
    int initialIndex = 0,
    Duration? initialPosition,
    bool autoPlay = true,
  }) {
    if (realLoadQueue) {
      return super.loadQueue(songs,
          initialIndex: initialIndex,
          initialPosition: initialPosition,
          autoPlay: autoPlay);
    }
    _record('loadQueue');
    return Future<void>.value();
  }

  /// When true, [seek] delegates to the shared helper (emitting a position).
  bool realSeek = false;

  @override
  Future<void> seek(Duration position) {
    if (realSeek) return super.seek(position);
    _record('seek');
    return Future<void>.value();
  }
}

SongsTableData buildSong(
  int id, {
  String? title,
  String source = SongSource.local,
  String? remoteId,
  String path = '',
  int durationMs = 180000,
  bool isDownloaded = false,
  bool isMissing = false,
  bool isFavorite = false,
  int? sampleRate,
  int? bitDepth,
}) {
  return SongsTableData(
    id: id,
    title: title ?? 'Song $id',
    artist: 'Artist $id',
    album: 'Album $id',
    durationMs: durationMs,
    path: path.isEmpty ? '/music/$id.mp3' : path,
    isFavorite: isFavorite,
    isMissing: isMissing,
    isDownloaded: isDownloaded,
    playCount: 0,
    lastPositionMs: 0,
    source: source,
    remoteId: remoteId,
    sampleRate: sampleRate,
    bitDepth: bitDepth,
  );
}

/// A settings state whose bit-perfect bypass is active (non-Bluetooth route),
/// so every DSP setter must be refused by the guard.
SettingsState bitPerfectBypassSettings() => const SettingsState(
      bitPerfectOutput: true,
      bypassDspOnBitPerfect: true,
    );

const EqPreset flatPreset = EqPreset(
  name: 'Flat',
  gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
);

const DynamicEqBandConfig sampleDynamicEqBand = DynamicEqBandConfig();
