// lib/core/services/playlist_suggestions_service.dart
import 'package:injectable/injectable.dart';
import '../../data/db/app_database.dart';

class PlaylistSuggestion {
  final String title;
  final String description;
  final List<SongsTableData> songs;

  const PlaylistSuggestion({
    required this.title,
    required this.description,
    required this.songs,
  });
}

@singleton
class PlaylistSuggestionsService {
  List<PlaylistSuggestion>? _cachedSuggestions;
  DateTime? _lastGeneratedTime;
  int? _lastSongCount;
  static const Duration _cacheTtl = Duration(minutes: 30);

  /// Invalidates the suggestion cache (e.g. after library scan or playlist changes).
  void invalidateCache() {
    _cachedSuggestions = null;
    _lastGeneratedTime = null;
    _lastSongCount = null;
  }

  /// Generates smart suggested mixes based on library tracks and playback history.
  /// Uses a single-pass traversal over [allSongs] and caches results for 30 minutes.
  List<PlaylistSuggestion> generateSuggestions(List<SongsTableData> allSongs, {bool forceRefresh = false}) {
    if (allSongs.isEmpty) return [];

    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedSuggestions != null &&
        _lastGeneratedTime != null &&
        _lastSongCount == allSongs.length &&
        now.difference(_lastGeneratedTime!) < _cacheTtl) {
      return _cachedSuggestions!;
    }

    final heavyRotationCandidates = <SongsTableData>[];
    final forgotten = <SongsTableData>[];
    final audiophile = <SongsTableData>[];
    final upbeat = <SongsTableData>[];

    // P0-3: Single pass through allSongs, avoiding multiple 50k object allocations
    for (final song in allSongs) {
      if (song.playCount > 0) {
        heavyRotationCandidates.add(song);
      }
      if (forgotten.length < 20 && song.isFavorite && song.playCount < 3) {
        forgotten.add(song);
      }
      if (audiophile.length < 30 &&
          (song.codec == 'FLAC' ||
           song.codec == 'ALAC' ||
           (song.bitDepth != null && song.bitDepth! >= 24))) {
        audiophile.add(song);
      }
      if (upbeat.length < 25 &&
          song.durationMs > 120000 &&
          song.durationMs < 240000) {
        upbeat.add(song);
      }
    }

    // Sort only the heavy rotation subset by playCount
    heavyRotationCandidates.sort((a, b) => b.playCount.compareTo(a.playCount));
    final heavyRotation = heavyRotationCandidates.take(25).toList();

    final suggestions = <PlaylistSuggestion>[
      if (heavyRotation.isNotEmpty)
        PlaylistSuggestion(
          title: 'Heavy Rotation Mix',
          description: 'Your most played tracks on repeat',
          songs: heavyRotation,
        ),
      if (forgotten.isNotEmpty)
        PlaylistSuggestion(
          title: 'Forgotten Favorites',
          description: 'Starred gems you haven\'t heard in a while',
          songs: forgotten,
        ),
      if (audiophile.isNotEmpty)
        PlaylistSuggestion(
          title: 'Hi-Res Audiophile Showcase',
          description: 'Studio master 24-bit lossless fidelity',
          songs: audiophile,
        ),
      if (upbeat.isNotEmpty)
        PlaylistSuggestion(
          title: 'Quick Energy Boost',
          description: 'High-energy fast tracks to power your day',
          songs: upbeat,
        ),
    ];

    _cachedSuggestions = suggestions;
    _lastGeneratedTime = now;
    _lastSongCount = allSongs.length;

    return suggestions;
  }

  /// Seed-based similarity for Auto-DJ / Up Next.
  /// Scores same-artist > same-album > same-genre, boosts favorites and
  /// near-duration tracks, excludes the seed itself.
  List<SongsTableData> suggestForSeed(
    SongsTableData seed,
    List<SongsTableData> allSongs, {
    int limit = 10,
  }) {
    final scored = <({SongsTableData song, int score})>[];
    for (final s in allSongs) {
      if (s.id == seed.id) continue;
      var score = 0;
      if (s.artist == seed.artist && s.artist.isNotEmpty) score += 30;
      if (s.album == seed.album && s.album.isNotEmpty) score += 20;
      if (s.genre == seed.genre && (s.genre?.isNotEmpty ?? false)) score += 15;
      if (s.isFavorite) score += 8;
      final durDiff = (s.durationMs - seed.durationMs).abs();
      if (durDiff < 30000) score += 5;
      score += s.playCount.clamp(0, 10);
      if (score > 0) scored.add((song: s, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.song).toList();
  }

  /// Auto-DJ queue: seed + similar tracks, de-duplicated against [excludeIds].
  List<SongsTableData> buildAutoDjQueue(
    SongsTableData seed,
    List<SongsTableData> allSongs, {
    int limit = 10,
    Set<int> excludeIds = const {},
  }) {
    final similar = suggestForSeed(seed, allSongs, limit: limit * 2);
    final out = <SongsTableData>[];
    for (final s in similar) {
      if (excludeIds.contains(s.id)) continue;
      out.add(s);
      if (out.length >= limit) break;
    }
    return out;
  }
}
