// lib/data/audio/stream_pre_resolver.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../db/app_database.dart';
import '../../core/services/ytm_url_cache.dart';
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
class StreamPreResolver {
  static const int defaultPreResolveCount = 4;

  final StreamUrlResolver resolveUrl;
  final YtmUrlCache urlCache;
  final String Function() qualityProvider;
  final Duration debounceDuration;
  final bool Function(String videoId)? isAlreadyPrefetching;
  final int preResolveWindowSize;

  /// Optional live override for [preResolveWindowSize], evaluated on every
  /// plan so the host can bind the warm depth to the current buffer bucket and
  /// metered-connection policy instead of a value fixed at construction.
  final int Function()? windowSizeProvider;

  Timer? _debounceTimer;
  final Map<String, Object> _activeResolutionTokens = {};
  final Set<String> _inFlightVideoIds = {};
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
      );

  final bool Function()? repeatQueueProvider;

  static String _defaultQuality() => 'high';

  /// Current video ID actively resolving in background, if any.
  String? get inFlightVideoId =>
      _inFlightVideoIds.isEmpty ? null : _inFlightVideoIds.first;
  Set<String> get inFlightVideoIds => Set.unmodifiable(_inFlightVideoIds);

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
  void onTrackEnqueuedOrTapped(SongsTableData song) {
    if (_disposed) return;
    if (song.source != SongSource.youtube) return;
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

    _resolveNow(song, quality);
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

      _resolveNow(song, quality);
      // Bound background concurrency to 2 in-flight requests
      if (_inFlightVideoIds.length >= 2) break;
    }
  }

  void _resolveNow(SongsTableData song, String quality) {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;

    _inFlightVideoIds.add(videoId);
    final token = Object();
    _activeResolutionTokens[videoId] = token;

    resolveUrl(videoId,
            quality: quality, title: song.title, artist: song.artist)
        .then((stream) {
      if (_disposed || !identical(_activeResolutionTokens[videoId], token)) {
        return;
      }
      urlCache.putStream(stream, quality: quality);
      unawaited(PreconnectedSocketPool().preconnect(Uri.parse(stream.url)));
      debugPrint(
          '[StreamPreResolver] Successfully pre-resolved track ($videoId)');
    }).catchError((e) {
      if (_disposed || !identical(_activeResolutionTokens[videoId], token)) {
        return;
      }
      debugPrint(
          '[StreamPreResolver] Pre-resolution failed for $videoId non-fatally: $e');
    }).whenComplete(() {
      if (identical(_activeResolutionTokens[videoId], token)) {
        _inFlightVideoIds.remove(videoId);
        _activeResolutionTokens.remove(videoId);
      }
    });
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
    _cancelInFlight();
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
