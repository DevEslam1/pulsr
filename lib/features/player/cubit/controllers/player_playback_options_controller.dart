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
import '../../../../domain/models/quran_mode_profile.dart';
import '../player_state.dart';
import '../quran_restore_snapshot.dart';

part 'player_playback_options_lyrics.dart';

/// Owns playback options: sleep timer, speed, pitch, ratings, per-track overrides, AB loop, and overlays.
class PlayerPlaybackOptionsController {
  final PulsrAudioHandler _audioHandler;
  final EarbudOptimizationService? _earbudOptimizationService;
  final HiResAudioService? _hiResAudioService;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final bool Function() _isClosed;

  bool get isClosed => _isClosed();

  PlayerPlaybackOptionsController({
    required PulsrAudioHandler audioHandler,
    EarbudOptimizationService? earbudOptimizationService,
    HiResAudioService? hiResAudioService,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required bool Function() isClosed,
  })  : _audioHandler = audioHandler,
        _earbudOptimizationService = earbudOptimizationService,
        _hiResAudioService = hiResAudioService,
        _getState = getState,
        _emit = emit,
        _isClosed = isClosed;

  // ──────────────────────────────────────────────
  // Sleep Timer
  // ──────────────────────────────────────────────
  void startSleepTimer(int minutes) {
    final duration = Duration(minutes: minutes);
    _audioHandler.startSleepTimer(duration);
    final s = _getState();
    _emit(s.copyWith(playback: s.playback.copyWith(sleepTimerRemaining: duration)));
  }

  void startAbsoluteSleepTimer(DateTime stopTime) {
    _audioHandler.startAbsoluteSleepTimer(stopTime);
    final diff = stopTime.difference(DateTime.now());
    final s = _getState();
    _emit(s.copyWith(
        playback: s.playback.copyWith(
            sleepTimerRemaining:
                diff.isNegative ? diff + const Duration(days: 1) : diff)));
  }

  void startEndOfTrackTimer() {
    _audioHandler.startEndOfTrackTimer();
    final s = _getState();
    final remaining = s.duration > s.position
        ? s.duration - s.position
        : const Duration(minutes: 1);
    _emit(s.copyWith(playback: s.playback.copyWith(sleepTimerRemaining: remaining)));
  }

  void startAfterNTracksTimer(int trackCount) {
    _audioHandler.startAfterNTracksTimer(trackCount);
    final s = _getState();
    _emit(s.copyWith(playback: s.playback.copyWith(sleepTimerRemaining: null)));
  }

  void startEndOfQueueTimer() {
    _audioHandler.startEndOfQueueTimer();
    final s = _getState();
    _emit(s.copyWith(playback: s.playback.copyWith(sleepTimerRemaining: null)));
  }

  void cancelSleepTimer() {
    _audioHandler.cancelSleepTimer();
    final s = _getState();
    _emit(s.copyWith(playback: s.playback.copyWith(sleepTimerRemaining: null)));
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

  Future<void> setPlaybackSpeed(double speed) async {
    final s = _getState();
    final clamped = speed.clamp(minPlaybackSpeed, maxPlaybackSpeed);
    _emit(s.copyWith(playback: s.playback.copyWith(playbackSpeed: clamped)));
    try {
      await _audioHandler.setSpeed(clamped);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(PrefsKeys.playbackSpeed, clamped);
      // A-01: remember this track's speed for its next resume.
      final songId = s.currentSong?.id;
      if (songId != null) {
        await PerSongPlaybackStore().setSpeed(songId.toString(), clamped);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set playback speed',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsController');
      final cur = _getState();
      _emit(cur.copyWith(
          playback: cur.playback.copyWith(errorMessage: 'Speed change failed')));
    }
  }

  Future<void> setPlaybackPitch(double pitch) async {
    final s = _getState();
    final clamped = pitch.clamp(0.5, 2.0);
    _emit(s.copyWith(playback: s.playback.copyWith(playbackPitch: clamped)));
    try {
      await _audioHandler.setPitch(clamped);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(PrefsKeys.playbackPitch, clamped);
      // A-01: remember this track's pitch for its next resume.
      final songId = s.currentSong?.id;
      if (songId != null) {
        await PerSongPlaybackStore().setPitch(songId.toString(), clamped);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set playback pitch',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsController');
      final cur = _getState();
      _emit(cur.copyWith(
          playback: cur.playback.copyWith(errorMessage: 'Pitch change failed')));
    }
  }

  // ──────────────────────────────────────────────
  // Overrides & Ratings
  // ──────────────────────────────────────────────
  Future<void> setSongRating(int songId, int rating) async {
    final store = SongRatingStore();
    await store.setRating(songId.toString(), rating);
    final s = _getState();
    if (s.currentSong?.id == songId) {
      _emit(s.copyWith(playback: s.playback.copyWith(currentSongRating: rating)));
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
    return _audioHandler.importPresetFromJson(jsonString);
  }

  Future<void> setSongEqOverride(dynamic songIdOrPreset,
      [String? presetName]) async {
    int? songId;
    String? name;
    if (songIdOrPreset is int) {
      songId = songIdOrPreset;
      name = presetName;
    } else if (songIdOrPreset is String?) {
      songId = _getState().currentSong?.id;
      name = songIdOrPreset;
    }
    if (songId != null) {
      final store = PerSongEqStore();
      await store.setPresetForTrack(songId.toString(), name);
      final s = _getState();
      if (s.currentSong?.id == songId) {
        _emit(s.copyWith(
            playback: s.playback.copyWith(currentSongEqOverride: name)));
      }
    }
  }

  Future<void> setSongVolumeOverride(int songId, double gainDb) async {
    final store = PerSongVolumeStore();
    await store.setGainDbForTrack(songId.toString(), gainDb);
    final s = _getState();
    if (s.currentSong?.id == songId) {
      _emit(s.copyWith(
          playback: s.playback.copyWith(currentSongVolumeOverrideDb: gainDb)));
    }
  }

  Future<void> setVolume(double volume) async {
    try {
      await _audioHandler.setVolume(volume);
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

  /// A-06: Toggle output mute, remembering the pre-mute volume so unmuting
  /// restores it. Exposed for the global keyboard-shortcut layer.
  Future<void> toggleMute() async {
    try {
      if (_muted) {
        await _audioHandler.setVolume(_volumeBeforeMute);
        _muted = false;
      } else {
        _volumeBeforeMute = _audioHandler.volume;
        await _audioHandler.setVolume(0.0);
        _muted = true;
      }
    } catch (e, st) {
      ErrorLogger.log('Toggle mute failed',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsController');
    }
  }

  bool get isMuted => _muted;

  /// A-01: Restore a track's remembered speed/pitch and reflect its persisted
  /// volume/EQ overrides in state when it is resumed from a bookmark or its
  /// last position. Volume gain is already applied dynamically by the audio
  /// handler from [PerSongVolumeStore]; EQ is applied by the EQ engine.
  Future<void> applyPerSongPlaybackMemory(SongsTableData song) async {
    final key = song.id.toString();
    final store = PerSongPlaybackStore();
    final speed = store.getSpeed(key);
    final pitch = store.getPitch(key);
    final gainDb = PerSongVolumeStore().getGainDbForTrack(key);
    final eqPreset = PerSongEqStore().getPresetForTrack(key);

    if (_isClosed()) return;
    if (_getState().currentSong?.id != song.id) return;

    try {
      if (speed != null) await _audioHandler.setSpeed(speed);
      if (pitch != null) await _audioHandler.setPitch(pitch);
    } catch (e, st) {
      ErrorLogger.log('Failed to restore per-song playback memory',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsController');
    }

    if (_isClosed()) return;
    final s = _getState();
    if (s.currentSong?.id != song.id) return;
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        playbackSpeed: speed ?? s.playbackSpeed,
        playbackPitch: pitch ?? s.playbackPitch,
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
    _emit(s.copyWith(
      lyricsSlice: s.lyricsSlice.copyWith(
        isLyricsVisible: !s.isLyricsVisible,
        isQueueVisible: false,
      ),
    ));
  }

  void toggleQueue() => toggleQueueVisibility();

  void toggleQueueVisibility() {
    HapticFeedback.lightImpact();
    final s = _getState();
    _emit(s.copyWith(
      lyricsSlice: s.lyricsSlice.copyWith(
        isQueueVisible: !s.isQueueVisible,
        isLyricsVisible: false,
      ),
    ));
  }

  void resetOverlayViews() {
    final s = _getState();
    if (s.isLyricsVisible || s.isQueueVisible) {
      _emit(s.copyWith(
        lyricsSlice: s.lyricsSlice.copyWith(
          isLyricsVisible: false,
          isQueueVisible: false,
        ),
      ));
    }
  }

  void setExpanded(bool expanded) {
    final s = _getState();
    _emit(s.copyWith(playback: s.playback.copyWith(isExpanded: expanded)));
  }

  Future<void> setTrackBpm(SongsTableData song, double? bpm) async {
    await _audioHandler.setTrackBpm(song, bpm);
  }

  void setTrackDelayMs(int delayMs) {
    final s = _getState();
    _emit(s.copyWith(playback: s.playback.copyWith(trackDelayMs: delayMs)));
  }

  void setSilenceSkipSensitivity(int sensitivity) {
    final s = _getState();
    _emit(s.copyWith(playback: s.playback.copyWith(silenceSkipSensitivity: sensitivity)));
  }

  // ──────────────────────────────────────────────
  // Quran Mode & Persistence
  // ──────────────────────────────────────────────
  Future<void> _persistQuranSnapshot(QuranRestoreSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          PrefsKeys.quranRestoreSnapshot, jsonEncode(snapshot.toJson()));
    } catch (e, st) {
      ErrorLogger.log('Failed to persist Quran Mode restore snapshot',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsController');
    }
  }

  Future<QuranRestoreSnapshot?> loadQuranSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PrefsKeys.quranRestoreSnapshot);
      if (raw == null || raw.isEmpty) return null;
      return QuranRestoreSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e, st) {
      ErrorLogger.log('Failed to load Quran Mode restore snapshot',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsController');
      return null;
    }
  }

  Future<void> _clearQuranSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PrefsKeys.quranRestoreSnapshot);
    } catch (_) {}
  }

  QuranRestoreSnapshot _captureQuranRestoreSnapshot(PlayerState s) {
    return QuranRestoreSnapshot(
      eqPreset: s.eqPreset,
      isEqEnabled: s.isEqEnabled,
      headphoneProfile: s.selectedHeadphoneProfile,
      isReverbEnabled: s.isReverbEnabled,
      reverbPreset: s.reverbPreset,
      reverbWetDry: s.reverbWetDry,
      isDynamicsEnabled: s.isDynamicsEnabled,
      dynamicsPreset: s.dynamicsPreset,
      isSaturationEnabled: s.isSaturationEnabled,
      saturationDrive: s.saturationDrive,
      saturationMix: s.saturationMix,
      saturationTilt: s.saturationTilt,
      playbackSpeed: s.playbackSpeed,
      isShuffle: s.isShuffle,
      preampDb: s.selectedHeadphoneProfile?.preampGain ?? 0.0,
    );
  }

  Future<void> setQuranModeEnabled(bool enabled) async {
    final s = _getState();
    if (enabled == s.isQuranModeEnabled) return;
    if (enabled) {
      final snapshot = _captureQuranRestoreSnapshot(s);
      await _persistQuranSnapshot(snapshot);
      _emit(s.copyWith(dsp: s.dsp.copyWith(isQuranModeEnabled: true)));
    } else {
      await _clearQuranSnapshot();
      _emit(s.copyWith(dsp: s.dsp.copyWith(isQuranModeEnabled: false)));
    }
  }

  void setQuranReciterStyle(QuranReciterStyle style) {
    final s = _getState();
    _emit(s.copyWith(dsp: s.dsp.copyWith(quranReciterStyle: style)));
  }

  Future<void> setQuranAmbience(double v) async {
    final s = _getState();
    _emit(s.copyWith(dsp: s.dsp.copyWith(reverbWetDry: v)));
    await _audioHandler.setReverb(s.isReverbEnabled, wetDry: v);
  }

  Future<void> reapplyQuranProfile() async {}
}
