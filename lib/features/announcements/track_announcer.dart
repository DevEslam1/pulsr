// lib/features/announcements/track_announcer.dart

import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../../core/utils/error_logger.dart';
import 'announcement_composer.dart';
import 'announcement_settings.dart';
import 'tts_engine.dart';

/// Maps an audio_service [MediaItem] onto the metadata an announcement needs.
///
/// Year, track and disc numbers are not part of [MediaItem] itself; they are
/// read from [MediaItem.extras] when the queue supplies them and simply omitted
/// from the announcement otherwise.
AnnouncementTrack announcementTrackForMediaItem(MediaItem item) {
  final extras = item.extras ?? const <String, dynamic>{};
  return AnnouncementTrack(
    title: item.title,
    artist: item.artist ?? '',
    album: item.album,
    year: _readInt(extras['year']),
    trackNumber: _readInt(extras['trackNumber']),
    discNumber: _readInt(extras['discNumber']),
    duration: item.duration,
  );
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Speaks a short announcement when playback moves to a new track.
///
/// Deliberately takes plain streams instead of the audio handler, so the whole
/// decision table (delay, skip rules, de-duplication, pause) is unit-testable
/// with two `StreamController`s and a fake [TtsEngine].
///
/// Behaviour:
/// * a new media id while playing schedules one announcement after
///   [AnnouncementSettings.delayMs];
/// * changing track again cancels the pending announcement, so quick skipping
///   never queues a queue of sentences;
/// * each media id is announced at most once, so repeat emits stay silent;
/// * pause, stop and [dispose] cancel the pending timer, and pause also stops
///   speech that is already playing;
/// * announcements are skipped while disabled, while the engine is unavailable,
///   while [shouldSkip] reports casting, and — when
///   [AnnouncementSettings.skipWhenBitPerfect] is set — while [isBitPerfect]
///   reports a bit-perfect output.
class TrackAnnouncer {
  /// Creates an announcer. Call [start] to subscribe to the streams.
  ///
  /// [shouldSkip] is the cast gate (true while casting); [isBitPerfect] is the
  /// bit-perfect gate; both default to "never". [now] is injectable so tests can
  /// pin [lastAnnouncementAt].
  TrackAnnouncer({
    required this.mediaItemStream,
    required this.playbackStateStream,
    required this.settings,
    required this.engine,
    bool Function()? shouldSkip,
    bool Function()? isBitPerfect,
    DateTime Function()? now,
  })  : _shouldSkip = shouldSkip ?? _neverSkip,
        _isBitPerfect = isBitPerfect ?? _neverBitPerfect,
        _now = now ?? DateTime.now;

  /// Stream of the currently playing media item.
  final Stream<MediaItem?> mediaItemStream;

  /// Stream of playback state changes (playing, paused, completed).
  final Stream<PlaybackState> playbackStateStream;

  /// Settings the announcer reads on every decision.
  final AnnouncementSettings settings;

  /// Engine that turns composed text into speech.
  final TtsEngine engine;

  final bool Function() _shouldSkip;
  final bool Function() _isBitPerfect;
  final DateTime Function() _now;

  StreamSubscription<MediaItem?>? _mediaSubscription;
  StreamSubscription<PlaybackState>? _stateSubscription;
  Timer? _pendingTimer;
  String? _pendingId;
  String? _announcedId;
  MediaItem? _currentItem;
  DateTime? _lastAnnouncementAt;
  bool _isPlaying = false;
  bool _started = false;
  bool _disposed = false;

  /// True from the moment speech is queued until it is stopped or replaced.
  ///
  /// The platform does not report completion through [TtsEngine], so this flag
  /// is conservative: it stays set after [TtsEngine.speak] returns and is
  /// cleared by stop, pause, a track change or dispose.
  bool _speechLive = false;

  /// The stop currently being delivered to the engine, if any.
  ///
  /// A track change schedules the new announcement immediately at `delayMs ==
  /// 0`, while the previous track's `stop()` is still in flight. Without this
  /// handle the two calls raced and the late stop could silence the new
  /// sentence; [_announce] awaits it before speaking.
  Future<void>? _pendingStop;

  /// Whether [start] has been called and [dispose] has not.
  bool get isStarted => _started && !_disposed;

  /// Whether a track announcement is waiting for the delay to elapse.
  bool get hasPendingAnnouncement => _pendingTimer != null;

  /// Whether the engine may still be speaking the last announcement.
  bool get isSpeechLive => _speechLive;

  /// When the last announcement was actually spoken, or `null`.
  DateTime? get lastAnnouncementAt => _lastAnnouncementAt;

  /// Media id of the last announced track, or `null`.
  String? get announcedMediaId => _announcedId;

  /// Subscribes to the media and playback streams.
  ///
  /// Call once, after the engine is initialised. Subscribing replays the
  /// current values of the audio handler's behaviour subjects, so starting
  /// mid-track announces that track.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _mediaSubscription = mediaItemStream.listen(
      _onMediaItem,
      onError: (Object error) => ErrorLogger.log(
        'Announcement media item stream failed',
        error: error,
        category: 'Announcements',
      ),
    );
    _stateSubscription = playbackStateStream.listen(
      _onPlaybackState,
      onError: (Object error) => ErrorLogger.log(
        'Announcement playback state stream failed',
        error: error,
        category: 'Announcements',
      ),
    );
  }

  /// Cancels subscriptions and the pending timer, and stops speech.
  ///
  /// Does not dispose [settings] or [engine]; their owner does that.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    _speechLive = false;
    _cancelPending();
    try {
      await _mediaSubscription?.cancel();
    } finally {
      _mediaSubscription = null;
      try {
        await _stateSubscription?.cancel();
      } finally {
        _stateSubscription = null;
      }
    }
    _currentItem = null;
    await _stopSpeech();
  }

  void _onMediaItem(MediaItem? item) {
    if (_disposed) return;
    final previousId = _currentItem?.id;
    _currentItem = item;
    final nextId = item?.id;
    if (nextId != previousId && _speechLive) {
      // The previous track's sentence is still in flight. Stop it before the
      // delay for the new track elapses, otherwise the user hears two titles.
      _speechLive = false;
      unawaited(_stopSpeech());
    }
    _evaluate();
  }

  void _onPlaybackState(PlaybackState state) {
    if (_disposed) return;
    final wasPlaying = _isPlaying;
    _isPlaying = state.playing &&
        state.processingState != AudioProcessingState.completed;
    if (!_isPlaying) {
      _cancelPending();
      if (wasPlaying) unawaited(_stopSpeech());
      return;
    }
    _evaluate();
  }

  /// Decides whether the current track needs an announcement scheduled.
  void _evaluate() {
    if (_disposed || !_started) return;
    final item = _currentItem;
    final id = item?.id;
    if (item == null || id == null || id.isEmpty) return;
    if (!_isPlaying) return;
    if (!_canAnnounce) {
      _cancelPending();
      return;
    }
    if (id == _announcedId) return;
    if (id == _pendingId) return;
    _cancelPending();
    _pendingId = id;
    _pendingTimer = Timer(
      Duration(milliseconds: settings.delayMs),
      () => _onDelayElapsed(item),
    );
  }

  void _onDelayElapsed(MediaItem item) {
    _pendingTimer = null;
    _pendingId = null;
    unawaited(_announce(item));
  }

  Future<void> _announce(MediaItem item) async {
    if (_disposed || !_isPlaying || !_canAnnounce) return;
    if (item.id == _announcedId) return;
    // Serialize against the stop the previous track change requested: a delay of
    // 0 ms used to let speak() and stop() overlap, so the new title could be cut
    // off by the old stop (or never heard at all).
    final Future<void>? pendingStop = _pendingStop;
    if (pendingStop != null) {
      await pendingStop;
      if (_disposed || !_isPlaying || !_canAnnounce) return;
      if (item.id == _announcedId) return;
    }
    final text = composeAnnouncement(
      settings.elements,
      announcementTrackForMediaItem(item),
      maxLength: settings.maxLength,
    );
    if (text.isEmpty) {
      // Nothing to say for this track (no elements selected, or every chosen
      // field is unknown). Mark it handled so every later playback-state emit
      // does not schedule another timer for the same silent track.
      _announcedId = item.id;
      return;
    }
    // Marked before awaiting so a burst of duplicate playback-state emits
    // cannot start a second utterance for the same track.
    _announcedId = item.id;
    _lastAnnouncementAt = _now();
    _speechLive = true;
    try {
      await engine.speak(
        text,
        volume: settings.volume,
        duckAudio: settings.duckAudio,
      );
    } on Exception catch (error, stackTrace) {
      _speechLive = false;
      ErrorLogger.log(
        'Announcement speech failed',
        error: error,
        stackTrace: stackTrace,
        category: 'Announcements',
      );
    }
  }

  bool get _canAnnounce {
    if (!settings.enabled) return false;
    if (!engine.isAvailable) return false;
    // The toggles decide whether each gate applies; the callbacks report the
    // live state those gates describe (casting, bit-perfect output).
    if (settings.skipWhenCasting && _shouldSkip()) return false;
    if (settings.skipWhenBitPerfect && _isBitPerfect()) return false;
    return true;
  }

  void _cancelPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingId = null;
  }

  Future<void> _stopSpeech() {
    _speechLive = false;
    // Remember the in-flight stop so the next [_announce] can await it. The
    // future never completes with an error (engine failures are logged below)
    // and is bounded inside [_stopEngine]: a wedged platform channel must not
    // block every later announcement forever. Clearing the handle on
    // completion keeps a future track change from waiting on a stale stop.
    final Future<void> stop = _stopEngine();
    _pendingStop = stop;
    unawaited(stop.whenComplete(() {
      if (identical(_pendingStop, stop)) _pendingStop = null;
    }));
    return stop;
  }

  Future<void> _stopEngine() async {
    try {
      // The engine contract has no completion callback for stop(); bound it so
      // a hung channel degrades to a logged failure instead of a deadlock.
      await engine.stop().timeout(const Duration(seconds: 2));
    } on Exception catch (error, stackTrace) {
      ErrorLogger.log(
        'Stopping announcement speech failed',
        error: error,
        stackTrace: stackTrace,
        category: 'Announcements',
      );
    }
  }

  static bool _neverSkip() => false;

  static bool _neverBitPerfect() => false;
}
