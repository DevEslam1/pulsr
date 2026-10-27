import 'dart:async';
import 'package:injectable/injectable.dart';
import '../../domain/models/ytm_track.dart';
import '../utils/error_logger.dart';
import 'ytm_service.dart';

class YtmBrowseItem {
  final String id;
  final String title;
  final String subtitle;
  final String? artworkUrl;
  final String type; // 'song', 'playlist', 'album', 'artist'
  final Duration duration;

  const YtmBrowseItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.artworkUrl,
    required this.type,
    this.duration = Duration.zero,
  });

  bool get hasKnownDuration => duration > Duration.zero;

  YtmTrack toYtmTrack() {
    return YtmTrack(
      videoId: id,
      title: title,
      artist: subtitle,
      duration: duration,
      artworkUrl: artworkUrl,
    );
  }
}

class YtmBrowseSection {
  static const String chartsId = 'charts';
  static const String newReleasesId = 'newReleases';
  static const String moodsId = 'moods';

  /// Stable key for a section, used by per-section refresh. Empty for callers
  /// that only render a section and never refresh it (tests, previews).
  final String id;
  final String title;
  final String? subtitle;
  final List<YtmBrowseItem> items;

  const YtmBrowseSection({
    this.id = '',
    required this.title,
    this.subtitle,
    required this.items,
  });
}

typedef YtmClockFn = DateTime Function();

@lazySingleton
class YtmBrowseService {
  final YtmService _ytmService;
  final YtmClockFn _now;
  static const Duration _cacheTtl = Duration(hours: 6);
  DateTime? _lastFetchTime;
  List<YtmBrowseSection>? _cachedSections;
  Completer<List<YtmBrowseSection>>? _pendingFeed;

  @factoryMethod
  static YtmBrowseService create(YtmService ytmService) =>
      YtmBrowseService(ytmService);

  YtmBrowseService(this._ytmService, {YtmClockFn? clock})
      : _now = clock ?? DateTime.now;

  /// When the feed currently held in memory was fetched, or null when nothing
  /// is cached. The screen renders this as a "last updated" stamp.
  DateTime? get lastFetchTime => _lastFetchTime;

  /// Clears in-memory browse feed cache upon network/region changes.
  ///
  /// Any in-flight shared fetch must be completed before its completer is
  /// dropped; otherwise callers already awaiting [_pendingFeed] would hang
  /// forever once the reference is nulled.
  void clearCache() {
    _cachedSections = null;
    _lastFetchTime = null;
    final pending = _pendingFeed;
    _pendingFeed = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const []);
    }
  }

  /// Fetches Home feed sections including Quick Picks, Recommended, and Trending.
  ///
  /// [force] bypasses the 6-hour TTL for explicit refreshes. On failure the
  /// last cached feed is served when one exists; otherwise the error is
  /// rethrown so the screen can distinguish "offline" from "no recommendations".
  Future<List<YtmBrowseSection>> getHomeFeed({bool force = false}) async {
    if (!force && _cachedSections != null && _lastFetchTime != null) {
      if (_now().difference(_lastFetchTime!) < _cacheTtl) {
        return _cachedSections!;
      }
    }
    if (_pendingFeed != null) return _pendingFeed!.future;
    final completer = _pendingFeed = Completer<List<YtmBrowseSection>>();
    try {
      Object? firstError;
      StackTrace? firstStack;
      // A section that fails degrades to empty so the other sections still
      // render; the first error is kept so an all-empty feed can be reported
      // as a failure rather than "no recommendations".
      Future<List<YtmBrowseItem>> guarded(
          Future<List<YtmBrowseItem>> Function() fetch) async {
        try {
          return await fetch();
        } catch (e, st) {
          firstError ??= e;
          firstStack ??= st;
          return const [];
        }
      }

      // Curated diverse showcase when offline/initial load with dynamic
      // fallback. Fire all three requests concurrently: they are independent
      // network calls and awaiting them sequentially tripled first-paint time.
      final results = await Future.wait<List<YtmBrowseItem>>([
        guarded(() => _getTrendingCharts(strict: true)),
        guarded(() => _getNewReleases(strict: true)),
        guarded(() => _getMoodsAndGenres(strict: true)),
      ]);
      final charts = results[0];
      final newReleases = results[1];
      final moods = results[2];

      final rawSections = [
        YtmBrowseSection(
          id: YtmBrowseSection.chartsId,
          title: 'Top Charts & Trending',
          subtitle: 'Most played tracks right now',
          items: charts,
        ),
        YtmBrowseSection(
          id: YtmBrowseSection.newReleasesId,
          title: 'New Releases',
          subtitle: 'Fresh albums & singles',
          items: newReleases,
        ),
        YtmBrowseSection(
          id: YtmBrowseSection.moodsId,
          title: 'Moods & Genres',
          subtitle: 'Popular tracks from YouTube Music moods & genres',
          items: moods,
        ),
      ];
      final sections = rawSections.where((s) => s.items.isNotEmpty).toList();
      final error = firstError;
      if (sections.isEmpty && error != null) {
        Error.throwWithStackTrace(error, firstStack ?? StackTrace.current);
      }
      if (sections.isNotEmpty) {
        _cachedSections = sections;
        _lastFetchTime = _now();
      }
      // Complete the completer captured at fetch start, not the field: if
      // clearCache() (or a later getHomeFeed) swapped _pendingFeed meanwhile,
      // completing the field would resolve a successor with this stale result.
      if (!completer.isCompleted) completer.complete(sections);
      if (identical(_pendingFeed, completer)) _pendingFeed = null;
      return sections;
    } catch (e, st) {
      ErrorLogger.log('Failed to fetch YTM home feed',
          error: e, stackTrace: st, category: 'YtmBrowseService');
      final fallback = _cachedSections;
      if (fallback != null && fallback.isNotEmpty) {
        if (!completer.isCompleted) completer.complete(fallback);
        if (identical(_pendingFeed, completer)) _pendingFeed = null;
        return fallback;
      }
      // No cached feed to fall back to: surface the failure instead of an
      // empty list, so the UI can show an offline/retry state. Completing the
      // shared completer with the error keeps concurrent callers in sync.
      if (!completer.isCompleted) completer.completeError(e, st);
      if (identical(_pendingFeed, completer)) _pendingFeed = null;
      return completer.future;
    }
  }

  /// Refetches one section without touching the rest of the feed.
  ///
  /// A section that failed during the concurrent first load leaves a hole the
  /// user cannot fill without reloading everything (and losing the sections
  /// that did load). This fetches just that feed and replaces its slot in the
  /// in-memory cache.
  Future<YtmBrowseSection> refreshSection(YtmBrowseSection section) async {
    final id =
        section.id.isNotEmpty ? section.id : _sectionIdForTitle(section.title);
    if (id.isEmpty) {
      throw ArgumentError.value(section.title, 'section', 'Unknown section');
    }

    final items = switch (id) {
      YtmBrowseSection.chartsId => await _getTrendingCharts(strict: true),
      YtmBrowseSection.newReleasesId => await _getNewReleases(strict: true),
      YtmBrowseSection.moodsId => await _getMoodsAndGenres(strict: true),
      _ => throw ArgumentError.value(id, 'section', 'Unknown section id'),
    };

    final refreshed = YtmBrowseSection(
      id: id,
      title: section.title,
      subtitle: section.subtitle,
      items: items,
    );
    final cached = _cachedSections;
    if (cached != null) {
      _cachedSections = List<YtmBrowseSection>.unmodifiable([
        for (final existing in cached)
          if (existing.id == id) refreshed else existing,
      ]);
    }
    return refreshed;
  }

  String _sectionIdForTitle(String title) {
    switch (title) {
      case 'Top Charts & Trending':
        return YtmBrowseSection.chartsId;
      case 'New Releases':
        return YtmBrowseSection.newReleasesId;
      case 'Moods & Genres':
        return YtmBrowseSection.moodsId;
      default:
        return '';
    }
  }

  static List<YtmBrowseItem> _mapTracks(List<YtmTrack> tracks) => tracks
      .take(8)
      .map((t) => YtmBrowseItem(
            id: t.videoId,
            title: t.title,
            subtitle: t.artist,
            artworkUrl: t.artworkUrl,
            type: 'song',
            duration: t.duration,
          ))
      .toList();

  /// Fetches Top Charts.
  Future<List<YtmBrowseItem>> getTrendingCharts() => _getTrendingCharts();

  /// [strict] rethrows the last source error when no items were produced, so
  /// [getHomeFeed] can report an offline feed instead of a genuinely empty one.
  Future<List<YtmBrowseItem>> _getTrendingCharts({bool strict = false}) async {
    Object? lastError;
    StackTrace? lastStack;
    try {
      final chartTracks = await _ytmService.getCharts(limit: 15);
      if (chartTracks.isNotEmpty) return _mapTracks(chartTracks);
    } catch (e, st) {
      lastError = e;
      lastStack = st;
    }

    try {
      final trendingTracks = await _ytmService.trending(limit: 15);
      if (trendingTracks.isNotEmpty) return _mapTracks(trendingTracks);
    } catch (e, st) {
      lastError = e;
      lastStack = st;
    }

    try {
      final onlineTracks =
          await _ytmService.searchWithFallback('Top Global Hits', limit: 15);
      if (onlineTracks.isNotEmpty) return _mapTracks(onlineTracks);
    } catch (e, st) {
      lastError = e;
      lastStack = st;
    }

    if (strict && lastError != null) {
      Error.throwWithStackTrace(lastError, lastStack ?? StackTrace.current);
    }
    return const [];
  }

  /// Fetches New Releases.
  Future<List<YtmBrowseItem>> getNewReleases() => _getNewReleases();

  Future<List<YtmBrowseItem>> _getNewReleases({bool strict = false}) async {
    Object? lastError;
    StackTrace? lastStack;
    try {
      final onlineTracks =
          await _ytmService.searchWithFallback('New Music Releases', limit: 15);
      if (onlineTracks.isNotEmpty) return _mapTracks(onlineTracks);
    } catch (e, st) {
      lastError = e;
      lastStack = st;
    }

    if (strict && lastError != null) {
      Error.throwWithStackTrace(lastError, lastStack ?? StackTrace.current);
    }
    return const [];
  }

  /// Fetches Moods & Genres from the native YTM bridge.
  ///
  /// The native extractor browses `FEmusic_moods_and_genres` and returns real
  /// track items (`YtmExtractorPlugin.browseMusicSection`); there is no
  /// category-tile API, so results are surfaced as playable songs. Returns an
  /// empty list when the bridge is unavailable — never fabricated IDs/art.
  Future<List<YtmBrowseItem>> getMoodsAndGenres() => _getMoodsAndGenres();

  Future<List<YtmBrowseItem>> _getMoodsAndGenres({bool strict = false}) async {
    Object? lastError;
    StackTrace? lastStack;
    try {
      final moods = await _ytmService.getMoods(limit: 15);
      if (moods.isNotEmpty) return _mapTracks(moods);
    } catch (e, st) {
      lastError = e;
      lastStack = st;
    }

    try {
      final onlineTracks = await _ytmService
          .searchWithFallback('Popular Hits Playlist', limit: 15);
      if (onlineTracks.isNotEmpty) return _mapTracks(onlineTracks);
    } catch (e, st) {
      lastError = e;
      lastStack = st;
    }

    if (strict && lastError != null) {
      Error.throwWithStackTrace(lastError, lastStack ?? StackTrace.current);
    }
    return const [];
  }
}
