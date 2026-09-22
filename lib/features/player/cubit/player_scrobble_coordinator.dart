// lib/features/player/cubit/player_scrobble_coordinator.dart
import 'dart:async';

import '../../../core/services/scrobbler_service.dart';
import '../../../data/db/app_database.dart';

/// Owns the scrobble debounce/heartbeat state machine so [PlayerCubit] only
/// supplies the current song, position and play-state (I1). Behaviour matches
/// the previous inline implementation: immediate flush on song/play-state
/// changes or a >=5s seek, otherwise a debounced flush that reads the latest
/// pending snapshot at fire time.
class PlayerScrobbleCoordinator {
  PlayerScrobbleCoordinator({
    required ScrobblerService? Function() service,
    required bool Function() isQuranMode,
    required bool Function() isClosed,
    required Duration interval,
  })  : _service = service,
        _isQuranMode = isQuranMode,
        _isClosed = isClosed,
        _interval = interval;

  final ScrobblerService? Function() _service;
  final bool Function() _isQuranMode;
  final bool Function() _isClosed;
  final Duration _interval;

  Timer? _debounce;
  int? _lastSongId;
  bool? _lastIsPlaying;
  // Track position in milliseconds to avoid precision loss on sub-second seeks.
  int? _lastPosMs;
  // FIX-G3: Monotonic clock for ordering & throttle timing
  static final Stopwatch _monotonicClock = Stopwatch()..start();
  int? _lastScrobbleElapsedMs;
  int? get lastScrobbleElapsedMs => _lastScrobbleElapsedMs;
  // FIX-C06: Track last scrobble notification time
  DateTime? _lastScrobbleTime;
  DateTime? get lastScrobbleTime => _lastScrobbleTime;
  // Latest pending values for the debounced minor-tick flush. Read at fire
  // time so the flush reports the newest position, not the first tick's.
  SongsTableData? _pendingSong;
  int _pendingPosMs = 0;
  bool _pendingIsPlaying = false;

  void debouncedScrobble(
      SongsTableData song, Duration position, bool isPlaying) {
    if (_isClosed()) return;
    final posMs = position.inMilliseconds;
    // FIX-C06: Detect same-song replay/restart (position went backwards)
    final isSongRestart =
        _lastSongId == song.id && _lastPosMs != null && posMs < _lastPosMs!;
    final isSongChange = _lastSongId != song.id || isSongRestart;
    final isPlayStateChange = _lastIsPlaying != isPlaying;
    final isMajorSeek =
        !isSongRestart && _lastPosMs != null && (posMs - _lastPosMs!).abs() >= 5000;

    _lastSongId = song.id;
    _lastIsPlaying = isPlaying;
    _lastPosMs = posMs;

    if (isSongChange || isPlayStateChange || isMajorSeek) {
      _debounce?.cancel();
      _debounce = null;
      _pendingSong = null;
      _lastScrobbleTime = DateTime.now();
      _lastScrobbleElapsedMs = _monotonicClock.elapsedMilliseconds;
      _service()?.notifyPlaybackState(
        id: song.id,
        artist: song.artist,
        track: song.title,
        album: song.album,
        durationMs: song.durationMs,
        positionMs: position.inMilliseconds,
        isPlaying: isPlaying,
        isQuran: _isQuranMode(),
      );
      return;
    }

    _pendingSong = song;
    _pendingPosMs = posMs;
    _pendingIsPlaying = isPlaying;
    _debounce ??= Timer(_interval, () {
      if (_isClosed()) return;
      final pendingSong = _pendingSong;
      if (pendingSong != null) {
        _lastScrobbleTime = DateTime.now();
        _lastScrobbleElapsedMs = _monotonicClock.elapsedMilliseconds;
        _service()?.notifyPlaybackState(
          id: pendingSong.id,
          artist: pendingSong.artist,
          track: pendingSong.title,
          album: pendingSong.album,
          durationMs: pendingSong.durationMs,
          positionMs: _pendingPosMs,
          isPlaying: _pendingIsPlaying,
          isQuran: _isQuranMode(),
        );
      }
      _pendingSong = null;
      _debounce = null;
    });
  }

  void dispose() {
    _debounce?.cancel();
    _debounce = null;
  }
}
