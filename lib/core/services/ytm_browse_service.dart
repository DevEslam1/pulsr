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
    this.duration = const Duration(minutes: 3, seconds: 30),
  });

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
  final String title;
  final String? subtitle;
  final List<YtmBrowseItem> items;

  const YtmBrowseSection({
    required this.title,
    this.subtitle,
    required this.items,
  });
}

@singleton
class YtmBrowseService {
  final YtmService _ytmService;
  static const Duration _cacheTtl = Duration(hours: 6);
  DateTime? _lastFetchTime;
  List<YtmBrowseSection>? _cachedSections;
  Completer<List<YtmBrowseSection>>? _pendingFeed;

  YtmBrowseService(this._ytmService);

  /// Fetches Home feed sections including Quick Picks, Recommended, and Trending.
  Future<List<YtmBrowseSection>> getHomeFeed() async {
    if (_cachedSections != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!) < _cacheTtl) {
        return _cachedSections!;
      }
    }
    if (_pendingFeed != null) return _pendingFeed!.future;
    _pendingFeed = Completer<List<YtmBrowseSection>>();
    try {
      // Curated diverse showcase when offline/initial load with dynamic fallback
      final charts = await getTrendingCharts();
      final newReleases = await getNewReleases();
      final moods = await getMoodsAndGenres();

      final sections = [
        YtmBrowseSection(
          title: 'Top Charts & Trending',
          subtitle: 'Most played tracks right now',
          items: charts,
        ),
        YtmBrowseSection(
          title: 'New Releases',
          subtitle: 'Fresh albums & singles',
          items: newReleases,
        ),
        YtmBrowseSection(
          title: 'Moods & Genres',
          subtitle: 'Popular tracks from YouTube Music moods & genres',
          items: moods,
        ),
      ];
      _cachedSections = sections;
      _lastFetchTime = DateTime.now();
      _pendingFeed?.complete(sections);
      _pendingFeed = null;
      return sections;
    } catch (e, st) {
      ErrorLogger.log('Failed to fetch YTM home feed',
          error: e, stackTrace: st, category: 'YtmBrowseService');
      final fallback = _cachedSections ?? [];
      _pendingFeed?.complete(fallback);
      _pendingFeed = null;
      return fallback;
    }
  }

  /// Fetches Top Charts.
  Future<List<YtmBrowseItem>> getTrendingCharts() async {
    try {
      final trendingTracks = await _ytmService.trending(limit: 15);
      if (trendingTracks.isNotEmpty) {
        return trendingTracks
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
      }
    } catch (_) {}

    try {
      final onlineTracks = await _ytmService.search('Top Global Hits');
      if (onlineTracks.isNotEmpty) {
        return onlineTracks
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
      }
    } catch (_) {}

    return const [];
  }

  /// Fetches New Releases.
  Future<List<YtmBrowseItem>> getNewReleases() async {
    try {
      final onlineTracks = await _ytmService.search('New Music Releases');
      if (onlineTracks.isNotEmpty) {
        return onlineTracks
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
      }
    } catch (_) {}

    return const [];
  }

  /// Fetches Moods & Genres from the native YTM bridge.
  ///
  /// The native extractor browses `FEmusic_moods_and_genres` and returns real
  /// track items (`YtmExtractorPlugin.browseMusicSection`); there is no
  /// category-tile API, so results are surfaced as playable songs. Returns an
  /// empty list when the bridge is unavailable — never fabricated IDs/art.
  Future<List<YtmBrowseItem>> getMoodsAndGenres() async {
    try {
      final moods = await _ytmService.getMoods(limit: 15);
      if (moods.isNotEmpty) {
        return moods
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
      }
    } catch (_) {}

    return const [];
  }
}
