// lib/data/audio/stream_pre_resolver.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../db/app_database.dart';
import '../../core/services/ytm_url_cache.dart';
import '../../core/telemetry/clock.dart';
import '../../domain/models/ytm_track.dart';

typedef StreamUrlResolver = Future<YtmStream> Function(String videoId,
    {String quality, String? title, String? artist});

/// DNS warm-up pool for edge hosts about to be opened by the platform player.
///
/// Resolving the host ahead of playback warms the OS resolver cache that
/// ExoPlayer / just_audio later consult, removing DNS from the
/// start-of-stream critical path. The pool holds no sockets itself: one opened
/// here could not be handed to the platform player, so the DNS answer is the
/// part that carries over.
class PreconnectedSocketPool {
  static final PreconnectedSocketPool _instance = PreconnectedSocketPool._();
  factory PreconnectedSocketPool() => _instance;
  PreconnectedSocketPool._();

  /// How long a successful lookup counts as warm. Kept short so an aged answer
  /// (or a moved edge after a network switch) is re-resolved rather than
  /// treated as permanently warm.
  static const Duration warmTtl = Duration(minutes: 2);

  static const Duration _lookupTimeout = Duration(seconds: 3);

  final Map<String, DateTime> _warmedAt = {};
  final Map<String, Future<void>> _inFlight = {};

  /// Test seam replacing the real `InternetAddress.lookup`.
  @visibleForTesting
  Future<void> Function(String host)? debugLookupOverride;

  bool isPreconnected(String host) {
    final warmedAt = _warmedAt[host];
    if (warmedAt == null) return false;
    if (DateTime.now().difference(warmedAt) >= warmTtl) {
      _warmedAt.remove(host);
      return false;
    }
    return true;
  }

  /// Best-effort DNS warm-up for [uri]'s host. Never throws; concurrent calls
  /// for the same host share one lookup.
  Future<void> preconnect(Uri uri) {
    final host = uri.host;
    if (host.isEmpty || isPreconnected(host)) return Future<void>.value();
    final existing = _inFlight[host];
    if (existing != null) return existing;

    final lookup = debugLookupOverride ?? _lookupHost;
    final future = Future<void>.sync(() async {
      await lookup(host).timeout(_lookupTimeout);
      _warmedAt[host] = DateTime.now();
    }).catchError((Object _) {}).whenComplete(() {
      // Block body on purpose: returning the removed future here would make
      // whenComplete await the very future it is completing (self-deadlock).
      _inFlight.remove(host);
    });
    _inFlight[host] = future;
    return future;
  }

  static Future<void> _lookupHost(String host) =>
      InternetAddress.lookup(host).then((_) {});

  void clear() {
    _warmedAt.clear();
    _inFlight.clear();
  }
}

/// Task 3 — Next-Track Pre-Resolver for YouTube Music streams.
///
/// Features:
/// - Triggered whenever a track starts playing, pre-resolving the next item's stream URL
/// - Shuffle-aware: pre-resolves the head of upcoming queue per current player state
/// - Debounced re-plan (300ms) on queue mutations (add/remove/reorder/shuffle)
/// - Idempotent cache writes into [YtmUrlCache]
/// - Non-blocking, cancellable, and dispose-safe
/// - One global concurrency budget for every trigger, with a bounded queue and
///   foreground priority for the track the user actually tapped
class StreamPreResolver {
  static const int defaultPreResolveCount = 4;

  final StreamUrlResolver resolveUrl;
  final YtmUrlCache urlCache;
  final String Function() qualityProvider;
  final Duration debounceDuration;
  final bool Function(String videoId)? isAlreadyPrefetching;
  final int preResolveWindowSize;

  /// Global cap on resolution chains running at once, shared by every trigger.
  ///
  /// Each chain costs a Dart account pass plus a native Kotlin pass with a
  /// Rhino signature transform, so a handful started together competes with
  /// the track the user is waiting for. They cannot be cancelled once started,
  /// so the only cure is to start fewer of them.
  final int maxConcurrentResolutions;

  /// Bound on requests parked behind [maxConcurrentResolutions]. A request
  /// arriving with the queue full is dropped rather than parked: a stale
  /// lookahead is worth less than a bounded footprint.
  final int maxQueuedResolutions;

  /// How long a failed video id is skipped everywhere. A bot-challenged or
  /// age-gated egress answers every retry the same way, so a retry inside the
  /// window only burns CPU and data for the same answer.
  final Duration failureCooldown;

  /// Clock used for [failureCooldown] bookkeeping; the system clock in
  /// production, a fake clock in tests.
  final Clock clock;

  /// Optional live override for [preResolveWindowSize], evaluated on every
  /// plan so the host can bind the warm depth to the current buffer bucket and
  /// metered-connection policy instead of a value fixed at construction.
  final int Function()? windowSizeProvider;

  Timer? _debounceTimer;
  final Map<String, Object> _activeResolutionTokens = {};
  final Set<String> _inFlightVideoIds = {};
  final List<_PendingResolution> _pending = [];
  final Map<String, DateTime> _cooldownUntil = {};
  String? _foregroundVideoId;
  bool _disposed = false;

  StreamPreResolver({
    required this.resolveUrl,
    required this.urlCache,
    this.qualityProvider = _defaultQuality,
    this.debounceDuration = const Duration(milliseconds: 100),
    this.isAlreadyPrefetching,
    this.repeatQueueProvider,
    this.preResolveWindowSize = 1,
    this.windowSizeProvider,
    this.maxConcurrentResolutions = 2,
    this.maxQueuedResolutions = 8,
    this.failureCooldown = const Duration(seconds: 60),
    this.clock = const SystemClock(),
  });

  /// Test entry point mirroring the production constructor so unit tests can
  /// inject a deterministic URL resolver and cache.
  @visibleForTesting
  factory StreamPreResolver.forTesting({
    required StreamUrlResolver resolveUrl,
    required YtmUrlCache urlCache,
    String Function() qualityProvider = _defaultQuality,
    Duration debounceDuration = const Duration(milliseconds: 100),
    bool Function(String videoId)? isAlreadyPrefetching,
    bool Function()? repeatQueueProvider,
    int preResolveWindowSize = 1,
    int Function()? windowSizeProvider,
    int maxConcurrentResolutions = 2,
    int maxQueuedResolutions = 8,
    Duration failureCooldown = const Duration(seconds: 60),
    Clock clock = const SystemClock(),
  }) =>
      StreamPreResolver(
        resolveUrl: resolveUrl,
        urlCache: urlCache,
        qualityProvider: qualityProvider,
        debounceDuration: debounceDuration,
        isAlreadyPrefetching: isAlreadyPrefetching,
        repeatQueueProvider: repeatQueueProvider,
        preResolveWindowSize: preResolveWindowSize,
        windowSizeProvider: windowSizeProvider,
        maxConcurrentResolutions: maxConcurrentResolutions,
        maxQueuedResolutions: maxQueuedResolutions,
        failureCooldown: failureCooldown,
        clock: clock,
      );

  final bool Function()? repeatQueueProvider;

  static String _defaultQuality() => 'high';

  /// Current video ID actively resolving in background, if any.
  String? get inFlightVideoId =>
      _inFlightVideoIds.isEmpty ? null : _inFlightVideoIds.first;
  Set<String> get inFlightVideoIds => Set.unmodifiable(_inFlightVideoIds);

  /// Whether the foreground (user-tapped) resolution is still running.
  ///
  /// Background warming is held back while it is: the tap is the only stream
  /// anyone is waiting on, and a second chain started now would only compete
  /// with it for CPU and bandwidth. Already-running chains are left alone —
  /// they cannot be cancelled.
  bool get _foregroundInFlight =>
      _foregroundVideoId != null &&
      _inFlightVideoIds.contains(_foregroundVideoId);

  bool get _hasFreeSlot =>
      _inFlightVideoIds.length < maxConcurrentResolutions &&
      !_foregroundInFlight;

  /// Marks [videoId] as the track the user is waiting on.
  ///
  /// Queued background work for every other track is dropped rather than
  /// parked: a resolution chain cannot be cancelled once started, so the only
  /// way to stop the lookahead competing with the tap is to never start it.
  void prioritize(String videoId) {
    if (_disposed || videoId.isEmpty) return;
    _foregroundVideoId = videoId;

    var dropped = 0;
    for (var i = _pending.length - 1; i >= 0; i--) {
      if (_pending[i].videoId != videoId) {
        _pending.removeAt(i);
        dropped++;
      }
    }
    if (dropped > 0) {
      debugPrint('[StreamPreResolver] Dropped $dropped queued background '
          'pre-resolve(s) behind foreground $videoId');
    }

    _promotePending(videoId);
  }

  /// Moves a queued request for [videoId] to the head of the queue and marks it
  /// as user-priority. Returns false when the id is not queued.
  bool _promotePending(String videoId) {
    final index = _pending.indexWhere((r) => r.videoId == videoId);
    if (index < 0) return false;
    final promoted = _pending.removeAt(index);
    _pending.insert(0, promoted.asPriority());
    return true;
  }

  /// Called immediately when a track starts playing.
  ///
  /// [explicitNextSong] pins the single track to warm, overriding the queue
  /// lookahead. The non-gapless shuffle path uses it to warm the state
  /// machine's pre-committed next pick (which neither the linear fallback nor a
  /// fresh random guess would match).
  void onTrackStarted({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
    SongsTableData? explicitNextSong,
    Duration? position,
    Duration? duration,
  }) {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _planPreResolution(
      queue: queue,
      currentIndex: currentIndex,
      isShuffle: isShuffle,
      shuffleIndices: shuffleIndices,
      explicitNextSong: explicitNextSong,
    );
  }

  /// Called when queue is modified (add/remove/reorder/shuffle). Debounces re-plan.
  void onQueueMutated({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
    SongsTableData? explicitNextSong,
    Duration? position,
    Duration? duration,
  }) {
    if (_disposed) return;
    final timeRemaining =
        (duration != null && position != null && duration > position)
            ? duration - position
            : null;
    final urgent =
        timeRemaining != null && timeRemaining < const Duration(seconds: 15);
    _debounceTimer?.cancel();
    if (urgent) {
      _planPreResolution(
        queue: queue,
        currentIndex: currentIndex,
        isShuffle: isShuffle,
        shuffleIndices: shuffleIndices,
        explicitNextSong: explicitNextSong,
      );
    } else {
      _debounceTimer = Timer(debounceDuration, () {
        if (_disposed) return;
        _planPreResolution(
          queue: queue,
          currentIndex: currentIndex,
          isShuffle: isShuffle,
          shuffleIndices: shuffleIndices,
          explicitNextSong: explicitNextSong,
        );
      });
    }
  }

  /// Fire the moment a track is tapped or enqueued — not only on track start.
  ///
  /// A tap is what the user is waiting on, so it bypasses the queue whenever a
  /// slot is free and otherwise takes the next freed slot ahead of every
  /// background request.
  void onTrackEnqueuedOrTapped(SongsTableData song) {
    if (_disposed) return;
    if (song.source != SongSource.youtube || song.isDownloaded == true) return;
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;

    final quality = qualityProvider();
    if (!urlCache.needsRefresh(videoId,
        quality: quality, refreshThreshold: const Duration(minutes: 10))) {
      return;
    }
    if (_inFlightVideoIds.contains(videoId) ||
        isAlreadyPrefetching?.call(videoId) == true) {
      return;
    }
    if (_isCoolingDown(videoId)) return;

    if (_promotePending(videoId)) {
      _pump();
      return;
    }

    if (_hasFreeSlot && _pending.isEmpty) {
      _startResolution(song, quality);
      return;
    }
    _enqueue(_PendingResolution(song: song, quality: quality, priority: true));
    _pump();
  }

  void _planPreResolution({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
    SongsTableData? explicitNextSong,
  }) {
    if (queue.isEmpty || currentIndex < 0) return;

    final repeatQueue = repeatQueueProvider?.call() ?? false;
    final requestedWindow = windowSizeProvider?.call() ?? preResolveWindowSize;
    final window = requestedWindow < 1
        ? 1
        : (requestedWindow > defaultPreResolveCount
            ? defaultPreResolveCount
            : requestedWindow);
    final nextSongs = _determineNextSongs(
      queue: queue,
      currentIndex: currentIndex,
      isShuffle: isShuffle,
      shuffleIndices: shuffleIndices,
      explicitNextSong: explicitNextSong,
      repeatQueue: repeatQueue,
      count: window,
    );

    if (nextSongs.isEmpty) return;
    final quality = qualityProvider();

    for (final song in nextSongs) {
      final videoId = song.remoteId;
      if (song.source != SongSource.youtube ||
          song.isDownloaded == true ||
          videoId == null ||
          videoId.isEmpty) {
        continue;
      }

      // If already cached and fresh (>10 min remaining), no need to resolve
      if (urlCache.contains(videoId, quality: quality)) {
        bool shouldRefresh = false;
        try {
          shouldRefresh = urlCache.needsRefresh(
            videoId,
            quality: quality,
            refreshThreshold: const Duration(minutes: 10),
          );
        } catch (_) {
          shouldRefresh = false;
        }
        if (!shouldRefresh) {
          continue;
        }
      }

      if (_inFlightVideoIds.contains(videoId) ||
          isAlreadyPrefetching?.call(videoId) == true) {
        continue;
      }

      if (_isCoolingDown(videoId)) continue;

      _submitBackground(song, quality);
    }
  }

  void _startResolution(SongsTableData song, String quality) {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;

    _inFlightVideoIds.add(videoId);
    final token = Object();
    _activeResolutionTokens[videoId] = token;

    // `Future.sync` so a resolver that throws synchronously still lands in the
    // error path below and clears its in-flight entry.
    Future<YtmStream>.sync(() => resolveUrl(videoId,
            quality: quality, title: song.title, artist: song.artist))
        .then((stream) {
      if (_disposed || !identical(_activeResolutionTokens[videoId], token)) {
        return;
      }
      // A successful resolve clears any cooldown left by an earlier failure.
      _cooldownUntil.remove(videoId);
      urlCache.putStream(stream, quality: quality);
      unawaited(PreconnectedSocketPool().preconnect(Uri.parse(stream.url)));
      debugPrint(
          '[StreamPreResolver] Successfully pre-resolved track ($videoId)');
    }).catchError((e) {
      if (_disposed || !identical(_activeResolutionTokens[videoId], token)) {
        return;
      }
      _cooldownUntil[videoId] = clock.now().add(failureCooldown);
      debugPrint(
          '[StreamPreResolver] Pre-resolution failed for $videoId non-fatally: $e');
      debugPrint('[StreamPreResolver] Cooling down $videoId for '
          '${failureCooldown.inSeconds}s after failed pre-resolution');
    }).whenComplete(() {
      if (identical(_activeResolutionTokens[videoId], token)) {
        _inFlightVideoIds.remove(videoId);
        _activeResolutionTokens.remove(videoId);
        _pump();
      }
    });
  }

  /// Starts queued requests, priority first, while the shared budget allows.
  void _pump() {
    if (_disposed) return;
    while (_pending.isNotEmpty && _hasFreeSlot) {
      final request = _pending.removeAt(0);
      if (_inFlightVideoIds.contains(request.videoId)) continue;
      if (_isCoolingDown(request.videoId)) continue;
      _startResolution(request.song, request.quality);
    }
  }

  void _submitBackground(SongsTableData song, String quality) {
    if (_hasFreeSlot && _pending.isEmpty) {
      _startResolution(song, quality);
      return;
    }
    _enqueue(
        _PendingResolution(song: song, quality: quality, priority: false));
  }

  /// Queues [request] in priority-then-FIFO order, dropping it when the queue
  /// is full instead of parking it indefinitely.
  void _enqueue(_PendingResolution request) {
    if (_pending.length >= maxQueuedResolutions) {
      if (!request.priority) {
        debugPrint('[StreamPreResolver] Dropped background pre-resolve for '
            '${request.videoId}: queue full');
        return;
      }
      // A tapped track must never be parked behind background work: evict the
      // newest background request to make room. If every slot already holds a
      // priority request, this one is dropped instead.
      final evictIndex = _pending.lastIndexWhere((r) => !r.priority);
      if (evictIndex < 0) {
        debugPrint('[StreamPreResolver] Dropped priority pre-resolve for '
            '${request.videoId}: queue full');
        return;
      }
      _pending.removeAt(evictIndex);
    }
    if (!request.priority) {
      _pending.add(request);
      return;
    }
    final firstBackground = _pending.indexWhere((r) => !r.priority);
    _pending.insert(
        firstBackground < 0 ? _pending.length : firstBackground, request);
  }

  bool _isCoolingDown(String videoId) {
    final until = _cooldownUntil[videoId];
    if (until == null) return false;
    if (clock.now().isBefore(until)) return true;
    _cooldownUntil.remove(videoId);
    return false;
  }

  List<SongsTableData> _determineNextSongs({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
    SongsTableData? explicitNextSong,
    bool repeatQueue = false,
    int count = defaultPreResolveCount,
  }) {
    if (queue.isEmpty) return const [];

    // An explicit next pick (non-gapless shuffle's pre-committed successor)
    // overrides the queue lookahead: shuffle visits exactly this track next, so
    // the linear/random fallback below would warm the wrong one. Only one track
    // can be known ahead of a random shuffle advance.
    if (explicitNextSong != null) {
      return [explicitNextSong];
    }

    final results = <SongsTableData>[];

    if (isShuffle && shuffleIndices != null && shuffleIndices.isNotEmpty) {
      final currentPosInShuffle = shuffleIndices.indexOf(currentIndex);
      if (currentPosInShuffle >= 0) {
        for (var i = 1; i <= count; i++) {
          final nextPos = currentPosInShuffle + i;
          if (nextPos < shuffleIndices.length) {
            final nextOriginalIndex = shuffleIndices[nextPos];
            if (nextOriginalIndex >= 0 && nextOriginalIndex < queue.length) {
              results.add(queue[nextOriginalIndex]);
            }
          } else if (repeatQueue && shuffleIndices.isNotEmpty) {
            final wrappedPos =
                (nextPos - shuffleIndices.length) % shuffleIndices.length;
            final nextOriginalIndex = shuffleIndices[wrappedPos];
            if (nextOriginalIndex >= 0 && nextOriginalIndex < queue.length) {
              results.add(queue[nextOriginalIndex]);
            }
          }
        }
      }
    } else {
      for (var i = 1; i <= count; i++) {
        final nextIndex = currentIndex + i;
        if (nextIndex < queue.length) {
          results.add(queue[nextIndex]);
        } else if (queue.isNotEmpty && repeatQueue) {
          final wrappedIndex = nextIndex % queue.length;
          results.add(queue[wrappedIndex]);
        }
      }
    }
    return results;
  }

  void _cancelInFlight() {
    _inFlightVideoIds.clear();
    _activeResolutionTokens.clear();
  }

  void cancel() {
    _debounceTimer?.cancel();
    _pending.clear();
    _foregroundVideoId = null;
    _cancelInFlight();
  }

  void dispose() {
    _disposed = true;
    cancel();
    _cooldownUntil.clear();
  }
}

/// One queued pre-resolution request. [priority] marks a track the user
/// explicitly tapped or enqueued: it is served before any lookahead request.
class _PendingResolution {
  const _PendingResolution({
    required this.song,
    required this.quality,
    required this.priority,
  });

  final SongsTableData song;
  final String quality;
  final bool priority;

  String get videoId => song.remoteId ?? '';

  _PendingResolution asPriority() =>
      _PendingResolution(song: song, quality: quality, priority: true);
}
