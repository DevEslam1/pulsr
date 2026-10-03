// lib/features/player/cubit/controllers/player_playback_options_controller.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/services/earbud_optimization_service.dart';
import '../../../../core/services/hires_audio_service.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/lrc_parser.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/audio/per_song_eq_store.dart';
import '../../../../data/audio/per_song_playback_store.dart';
import '../../../../data/audio/per_song_volume_store.dart';
import '../../../../data/audio/playback_bookmark_store.dart';
import '../../../../data/audio/sleep_timer_manager.dart';
import '../../../../data/audio/song_rating_store.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../../../../domain/models/eq_preset.dart';
import '../../../../domain/models/quran_mode_profile.dart';
import '../managers/player_quran_manager.dart';
import '../player_state.dart';
import '../quran_restore_snapshot.dart';

part 'player_playback_options_lyrics.dart';
part 'player_playback_options_quran.dart';

/// Owns playback options: sleep timer, speed, pitch, ratings, per-track overrides, AB loop, and overlays.
class PlayerPlaybackOptionsController {
  final PulsrAudioHandler _audioHandler;
  final EarbudOptimizationService? _earbudOptimizationService;
  final HiResAudioService? _hiResAudioService;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final bool Function() _isClosed;
  final Future<void> Function(SongsTableData song, {bool isOfflineOnly})? _onLoadLyrics;
  final PerSongPlaybackStore _perSongPlaybackStore;
  final PerSongVolumeStore _perSongVolumeStore;
  final PerSongEqStore _perSongEqStore;
  final PlayerQuranManager _quranManager;
  final SongRatingStore _songRatingStore;

  final bool Function(String feature, {bool showError})? _guardDsp;
  bool _isTogglingQuranMode = false;
  int _reciterStyleGen = 0;

  bool get isClosed => _isClosed();

  PlayerPlaybackOptionsController({
    required PulsrAudioHandler audioHandler,
    EarbudOptimizationService? earbudOptimizationService,
    HiResAudioService? hiResAudioService,
    PerSongPlaybackStore? perSongPlaybackStore,
    PerSongVolumeStore? perSongVolumeStore,
    PerSongEqStore? perSongEqStore,
    PlayerQuranManager? quranManager,
    SongRatingStore? songRatingStore,
    bool Function(String feature, {bool showError})? guardDsp,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required bool Function() isClosed,
    Future<void> Function(SongsTableData song, {bool isOfflineOnly})? onLoadLyrics,
  })  : _audioHandler = audioHandler,
        _earbudOptimizationService = earbudOptimizationService,
        _hiResAudioService = hiResAudioService,
        _guardDsp = guardDsp,
        _getState = getState,
        _emit = emit,
        _isClosed = isClosed,
        _onLoadLyrics = onLoadLyrics,
        _perSongPlaybackStore = perSongPlaybackStore ?? PerSongPlaybackStore(),
        _perSongVolumeStore = perSongVolumeStore ?? PerSongVolumeStore(),
        _perSongEqStore = perSongEqStore ?? PerSongEqStore(),
        _quranManager = quranManager ?? PlayerQuranManager(),
        _songRatingStore = songRatingStore ?? SongRatingStore();

  bool checkDspGuard(String feature, {bool showError = true}) =>
      _guardDsp?.call(feature, showError: showError) ?? true;

  // ──────────────────────────────────────────────
  // Sleep Timer
  // ──────────────────────────────────────────────
  void startSleepTimer(int minutes) {
    if (minutes <= 0) return;
    final duration = Duration(minutes: minutes);
    _audioHandler.startSleepTimer(duration);
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        sleepTimerRemaining: duration,
        sleepTimerRemainingTracks: null,
      ),
    ));
  }

  void startAbsoluteSleepTimer(DateTime stopTime) {
    var effectiveStopTime = stopTime;
    final now = DateTime.now();
    var diff = stopTime.difference(now);
    if (diff.isNegative) {
      effectiveStopTime = stopTime.add(const Duration(days: 1));
      diff = effectiveStopTime.difference(now);
    }
    _audioHandler.startAbsoluteSleepTimer(effectiveStopTime);
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        sleepTimerRemaining: diff,
        sleepTimerRemainingTracks: null,
      ),
    ));
  }

  void startEndOfTrackTimer() {
    _audioHandler.startEndOfTrackTimer();
    final s = _getState();
    final remaining = s.duration > s.position
        ? s.duration - s.position
        : const Duration(minutes: 1);
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        sleepTimerRemaining: remaining,
        sleepTimerRemainingTracks: null,
      ),
    ));
  }

  void startAfterNTracksTimer(int trackCount) {
    if (trackCount <= 0) return;
    _audioHandler.startAfterNTracksTimer(trackCount);
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        sleepTimerRemaining: null,
        sleepTimerRemainingTracks: trackCount,
      ),
    ));
  }

  void startEndOfQueueTimer() {
    _audioHandler.startEndOfQueueTimer();
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        sleepTimerRemaining: null,
        sleepTimerRemainingTracks: null,
      ),
    ));
  }

  void cancelSleepTimer() {
    _audioHandler.cancelSleepTimer();
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        sleepTimerRemaining: null,
        sleepTimerRemainingTracks: null,
      ),
    ));
  }

  int? get sleepTimerRemainingTracks => _audioHandler.sleepTimerRemainingTracks;
  SleepTimerMode get sleepTimerMode => _audioHandler.sleepTimerMode;
  bool get isEndOfQueueSleepTimer => sleepTimerMode == SleepTimerMode.endOfQueue;
  Stream<int?> get sleepTimerRemainingTracksStream =>
      _audioHandler.sleepTimerRemainingTracksStream;

  // ──────────────────────────────────────────────
  // Speed & Pitch
  // ──────────────────────────────────────────────
  double get minPlaybackSpeed => _audioHandler.minPlaybackSpeed;
  double get maxPlaybackSpeed => _audioHandler.maxPlaybackSpeed;
  double get minPlaybackPitch => 0.5;
  double get maxPlaybackPitch => 2.0;

  Future<void> setPlaybackSpeed(double speed) async {
    final s = _getState();
    final prevSpeed = s.playbackSpeed;
    final clamped = speed.clamp(minPlaybackSpeed, maxPlaybackSpeed);
    _emit(s.copyWith(playback: s.playback.copyWith(playbackSpeed: clamped)));
    try {
      await _audioHandler.setSpeed(clamped);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(PrefsKeys.playbackSpeed, clamped);
      // A-01: remember this track's speed for its next resume.
      final songId = s.currentSong?.id;
      if (songId != null) {
        await _perSongPlaybackStore.setSpeed(songId.toString(), clamped);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set playback speed',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsController');
      final cur = _getState();
      _emit(cur.copyWith(
          playback: cur.playback.copyWith(
            playbackSpeed: prevSpeed,
            errorMessage: 'Speed change failed',
          )));
    }
  }

  Future<void> setPlaybackPitch(double pitch) async {
    final s = _getState();
    final prevPitch = s.playbackPitch;
    final clamped = pitch.clamp(minPlaybackPitch, maxPlaybackPitch);
    _emit(s.copyWith(playback: s.playback.copyWith(playbackPitch: clamped)));
    try {
      await _audioHandler.setPitch(clamped);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(PrefsKeys.playbackPitch, clamped);
      // A-01: remember this track's pitch for its next resume.
      final songId = s.currentSong?.id;
      if (songId != null) {
        await _perSongPlaybackStore.setPitch(songId.toString(), clamped);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set playback pitch',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsController');
      final cur = _getState();
      _emit(cur.copyWith(
          playback: cur.playback.copyWith(
            playbackPitch: prevPitch,
            errorMessage: 'Pitch change failed',
          )));
    }
  }

  // ──────────────────────────────────────────────
  // Overrides & Ratings
  // ──────────────────────────────────────────────
  Future<void> setSongRating(int songId, int rating) async {
    final clamped = rating.clamp(0, 5);
    await _songRatingStore.setRating(songId.toString(), clamped);
    final s = _getState();
    if (s.currentSong?.id == songId) {
      _emit(s.copyWith(playback: s.playback.copyWith(currentSongRating: clamped)));
    }
  }

  Future<void> setRating(int rating) async {
    final song = _getState().currentSong;
    if (song != null) {
      await setSongRating(song.id, rating);
    }
  }

  Future<void> setSongVolumeOverrideDb(double offsetDb, {int? songId}) async {
    final id = songId ?? _getState().currentSong?.id;
    if (id != null) {
      await setSongVolumeOverride(id, offsetDb);
    }
  }

  String exportCurrentEqPreset() =>
      _audioHandler.exportPresetToJson(_getState().eqPreset);

  Future<bool> importEqPreset(String jsonString) async {
    if (!checkDspGuard('Equalizer Preset')) return false;
    final success = await _audioHandler.importPresetFromJson(jsonString);
    if (success && !_isClosed()) {
      final preset = _audioHandler.currentPreset;
      final s = _getState();
      _emit(s.copyWith(
        dsp: s.dsp.copyWith(
          eqPreset: preset,
          selectedHeadphoneProfile: null,
        ),
      ));
    }
    return success;
  }

  Future<void> setSongEqOverrideById(int songId, String? presetName) async {
    await _perSongEqStore.setPresetForTrack(songId.toString(), presetName);
    final s = _getState();
    if (s.currentSong?.id == songId) {
      _emit(s.copyWith(
          playback: s.playback.copyWith(currentSongEqOverride: presetName)));
    }
  }

  Future<void> setCurrentSongEqOverride(String? presetName) async {
    final songId = _getState().currentSong?.id;
    if (songId != null) {
      await setSongEqOverrideById(songId, presetName);
    }
  }

  Future<void> setSongEqOverride(Object? songIdOrPreset,
      [String? presetName]) async {
    if (songIdOrPreset is int) {
      await setSongEqOverrideById(songIdOrPreset, presetName);
    } else if (songIdOrPreset is String) {
      await setCurrentSongEqOverride(songIdOrPreset);
    } else if (songIdOrPreset == null && presetName == null) {
      await setCurrentSongEqOverride(null);
    }
  }

  Future<void> setSongVolumeOverride(int songId, double gainDb) async {
    final clamped = gainDb.clamp(-24.0, 24.0);
    await _perSongVolumeStore.setGainDbForTrack(songId.toString(), clamped);
    final s = _getState();
    if (s.currentSong?.id == songId) {
      _emit(s.copyWith(
          playback: s.playback.copyWith(currentSongVolumeOverrideDb: clamped)));
    }
  }

  Future<void> setVolume(double volume) async {
    try {
      await _audioHandler.setVolume(volume);
      if (volume > 0.0) _muted = false;
    } catch (e, st) {
      ErrorLogger.log('Set volume failed',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsController');
      final s = _getState();
      _emit(s.copyWith(
          playback: s.playback.copyWith(errorMessage: 'Volume change failed')));
    }
  }

  Future<void> adjustVolume(double delta) async {
    try {
      final current = _audioHandler.volume;
      final target = (current + delta).clamp(0.0, 1.0);
      await _audioHandler.setVolume(target);
      if (target > 0.0) _muted = false;
    } catch (e, st) {
      ErrorLogger.log('Adjust volume failed',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsController');
      final s = _getState();
      _emit(s.copyWith(
          playback: s.playback.copyWith(errorMessage: 'Volume change failed')));
    }
  }

  bool _muted = false;
  double _volumeBeforeMute = 1.0;
  bool _isMuting = false;

  /// A-06: Toggle output mute, remembering the pre-mute volume so unmuting
  /// restores it. Exposed for the global keyboard-shortcut layer.
  Future<void> toggleMute() async {
    if (_isMuting) return;
    _isMuting = true;
    try {
      if (_muted) {
        final targetVol = _volumeBeforeMute > 0.0 ? _volumeBeforeMute : 1.0;
        await _audioHandler.setVolume(targetVol);
        _muted = false;
      } else {
        final currentVol = _audioHandler.volume;
        if (currentVol > 0.0) {
          _volumeBeforeMute = currentVol;
        }
        await _audioHandler.setVolume(0.0);
        _muted = true;
      }
    } catch (e, st) {
      ErrorLogger.log('Toggle mute failed',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsController');
    } finally {
      _isMuting = false;
    }
  }

  bool get isMuted => _muted;

  int _playbackMemoryGen = 0;

  /// A-01: Restore a track's remembered speed/pitch and reflect its persisted
  /// volume/EQ overrides in state when it is resumed from a bookmark or its
  /// last position. Volume gain is already applied dynamically by the audio
  /// handler from [PerSongVolumeStore]; EQ is applied by the EQ engine.
  Future<void> applyPerSongPlaybackMemory(SongsTableData song) async {
    final gen = ++_playbackMemoryGen;
    final key = song.id.toString();
    final speed = _perSongPlaybackStore.getSpeed(key);
    final pitch = _perSongPlaybackStore.getPitch(key);
    final gainDb = _perSongVolumeStore.getGainDbForTrack(key);
    final eqPreset = _perSongEqStore.getPresetForTrack(key);

    if (_isClosed() || gen != _playbackMemoryGen) return;
    if (_getState().currentSong?.id != song.id) return;
    if (_getState().isQuranModeEnabled) return;

    bool speedSucceeded = false;
    bool pitchSucceeded = false;

    try {
      if (speed != null) {
        if (_isClosed() || gen != _playbackMemoryGen || _getState().currentSong?.id != song.id) return;
        await _audioHandler.setSpeed(speed);
        speedSucceeded = true;
      }
      if (pitch != null) {
        if (_isClosed() || gen != _playbackMemoryGen || _getState().currentSong?.id != song.id) return;
        await _audioHandler.setPitch(pitch);
        pitchSucceeded = true;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to restore per-song playback memory',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsController');
    }

    if (_isClosed() || gen != _playbackMemoryGen || _getState().currentSong?.id != song.id) return;
    final s = _getState();
    if (s.currentSong?.id != song.id) return;
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        playbackSpeed: speedSucceeded ? speed! : s.playbackSpeed,
        playbackPitch: pitchSucceeded ? pitch! : s.playbackPitch,
        currentSongVolumeOverrideDb: gainDb,
        currentSongEqOverride: eqPreset,
      ),
    ));
  }

  // ──────────────────────────────────────────────
  // Overlays
  // ──────────────────────────────────────────────
  void toggleLyrics() => toggleLyricsVisibility();

  void toggleLyricsVisibility() {
    HapticFeedback.lightImpact();
    final s = _getState();
    _emit(s.copyWith(lyricsSlice: s.lyricsSlice.copyWith(isLyricsVisible: !s.isLyricsVisible, isQueueVisible: false)));
  }

  void toggleQueue() => toggleQueueVisibility();

  void toggleQueueVisibility() {
    HapticFeedback.lightImpact();
    final s = _getState();
    _emit(s.copyWith(lyricsSlice: s.lyricsSlice.copyWith(isQueueVisible: !s.isQueueVisible, isLyricsVisible: false)));
  }

  void resetOverlayViews() {
    final s = _getState();
    if (s.isLyricsVisible || s.isQueueVisible) {
      _emit(s.copyWith(lyricsSlice: s.lyricsSlice.copyWith(isLyricsVisible: false, isQueueVisible: false)));
    }
  }

  void setExpanded(bool expanded) => _emit(_getState().copyWith(playback: _getState().playback.copyWith(isExpanded: expanded)));
  Future<void> setTrackBpm(SongsTableData song, double? bpm) => _audioHandler.setTrackBpm(song, bpm);
  void setTrackDelayMs(int delayMs) => _emit(_getState().copyWith(playback: _getState().playback.copyWith(trackDelayMs: delayMs)));
  void setSilenceSkipSensitivity(int sensitivity) => _emit(_getState().copyWith(playback: _getState().playback.copyWith(silenceSkipSensitivity: sensitivity)));
  void dispose() {}
}
