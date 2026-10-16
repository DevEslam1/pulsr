// lib/data/services/spotify_importer_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Value, InsertMode;
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import '../../core/di/injection.dart';
import '../../core/services/ytm_service.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/usecases/playlist_usecases.dart';
import '../db/app_database.dart';

/// Single track metadata extracted from a Spotify playlist.
class SpotifyImportTrack {
  final String title;
  final String artist;

  const SpotifyImportTrack({
    required this.title,
    required this.artist,
  });

  @override
  String toString() => '$title - $artist';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpotifyImportTrack &&
          other.title == title &&
          other.artist == artist;

  @override
  int get hashCode => Object.hash(title, artist);
}

/// The result of importing and resolving a Spotify playlist.
class SpotifyImportResult {
  final int playlistId;
  final String playlistTitle;
  final int totalTracks;
  final List<YtmTrack> resolvedTracks;
  final List<SpotifyImportTrack> unmatchedTracks;

  const SpotifyImportResult({
    required this.playlistId,
    required this.playlistTitle,
    required this.totalTracks,
    required this.resolvedTracks,
    required this.unmatchedTracks,
  });

  int get matchedCount => resolvedTracks.length;
  int get unmatchedCount => unmatchedTracks.length;
}

@lazySingleton
class SpotifyImporterService {
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static final RegExp _playlistIdRegex = RegExp(r'^[A-Za-z0-9]{22}$');
  static const int _embedTrackLimit = 100;
  static const String _pathfinderUrl =
      'https://api-partner.spotify.com/pathfinder/v1/query';
  static const String _fetchPlaylistHash =
      '19ff1327c29e99c208c86d7a9d8f1929cfdf3d3202a0ff4253c821f1901aa94d';

  final http.Client _httpClient;
  final YtmService? _ytmService;
  final PlaylistUseCases? _playlistUseCases;
  final AppDatabase? _db;

  SpotifyImporterService({
    http.Client? httpClient,
    YtmService? ytmService,
    PlaylistUseCases? playlistUseCases,
    AppDatabase? db,
  })  : _httpClient = httpClient ?? http.Client(),
        _ytmService = ytmService,
        _playlistUseCases = playlistUseCases,
        _db = db;

  YtmService get _effectiveYtmService =>
      _ytmService ??
      (getIt.isRegistered<YtmService>() ? getIt<YtmService>() : YtmService());

  PlaylistUseCases get _effectivePlaylistUseCases =>
      _playlistUseCases ?? getIt<PlaylistUseCases>();

  AppDatabase get _effectiveDb => _db ?? getIt<AppDatabase>();

  /// Parses a user input string or URL into a 22-character Spotify playlist ID.
  /// Supports:
  /// - `https://open.spotify.com/playlist/{id}` (with or without query parameters)
  /// - `spotify:playlist:{id}`
  /// - Raw 22-character base-62 playlist ID
  static String? extractPlaylistId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    if (_playlistIdRegex.hasMatch(trimmed)) {
      return trimmed;
    }

    if (trimmed.startsWith('spotify:playlist:')) {
      final stripped = trimmed.replaceFirst('spotify:playlist:', '');
      final id = stripped.split('?').first.split('/').first;
      return _playlistIdRegex.hasMatch(id) ? id : null;
    }

    try {
      final uri = Uri.parse(trimmed);
      final host = uri.host.toLowerCase();
      if (host != 'spotify.com' && !host.endsWith('.spotify.com')) {
        return null;
      }
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final playlistIdx = segments.indexOf('playlist');
      if (playlistIdx != -1 && playlistIdx + 1 < segments.length) {
        final id = segments[playlistIdx + 1];
        return _playlistIdRegex.hasMatch(id) ? id : null;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  /// Fetches track listing and metadata from Spotify's public embed page and oEmbed.
  Future<({String title, List<SpotifyImportTrack> tracks})> fetchPlaylistTracks(
      String playlistId) async {
    final embedUrl =
        Uri.parse('https://open.spotify.com/embed/playlist/$playlistId');
    http.Response response;
    try {
      response = await _httpClient.get(embedUrl, headers: {
        'User-Agent': userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      }).timeout(const Duration(seconds: 12));
    } catch (e, st) {
      ErrorLogger.log('Failed to fetch Spotify embed page: $playlistId',
          error: e, stackTrace: st, category: 'SpotifyImporter');
      throw Exception('Network error loading Spotify playlist: $e');
    }

    if (response.statusCode != 200 || response.body.trim().isEmpty) {
      throw Exception(
          'Failed to load Spotify playlist (HTTP ${response.statusCode})');
    }

    final html = response.body;

    // Extract NEXT_DATA script JSON
    final scriptRegex = RegExp(
      r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
      dotAll: true,
    );
    final match = scriptRegex.firstMatch(html);

    String? playlistTitle;
    final tracks = <SpotifyImportTrack>[];
    String? accessToken;

    if (match != null) {
      try {
        final jsonString = match.group(1)!;
        final root = jsonDecode(jsonString) as Map<String, dynamic>;
        final props = root['props'] as Map<String, dynamic>?;
        final pageProps = props?['pageProps'] as Map<String, dynamic>?;
        final state = pageProps?['state'] as Map<String, dynamic>?;
        final data = state?['data'] as Map<String, dynamic>?;
        final entity =
            (data?['entity'] ?? pageProps?['entity']) as Map<String, dynamic>?;

        playlistTitle = (entity?['name'] ?? entity?['title']) as String?;

        final rawTrackList =
            (entity?['trackList'] ?? entity?['tracks']) as List<dynamic>?;
        if (rawTrackList != null) {
          for (final item in rawTrackList) {
            if (item is Map<String, dynamic>) {
              final title = (item['title'] ?? item['name']) as String?;
              var subtitle = (item['subtitle']) as String?;
              if (subtitle == null && item['artists'] is List) {
                final artistList = (item['artists'] as List)
                    .whereType<Map<String, dynamic>>()
                    .map((a) => (a['name'] as String?)?.trim())
                    .where((n) => n != null && n.isNotEmpty)
                    .join(', ');
                subtitle = artistList;
              }
              if (title != null && title.trim().isNotEmpty) {
                tracks.add(SpotifyImportTrack(
                  title: title.trim(),
                  artist: (subtitle ?? '').trim(),
                ));
              }
            }
          }
        }

        // Check if access token is available for pagination beyond 100 tracks
        final settings = state?['settings'] as Map<String, dynamic>?;
        final session = settings?['session'] as Map<String, dynamic>?;
        accessToken = session?['accessToken'] as String?;
      } catch (e, st) {
        ErrorLogger.log('Error parsing Spotify __NEXT_DATA__: $playlistId',
            error: e, stackTrace: st, category: 'SpotifyImporter');
      }
    }

    // Try oEmbed as enhancement/fallback if title wasn't found
    if (playlistTitle == null || playlistTitle.isEmpty) {
      try {
        final oembedUrl = Uri.parse(
            'https://open.spotify.com/oembed?url=https://open.spotify.com/playlist/$playlistId');
        final oembedResp = await _httpClient.get(oembedUrl, headers: {
          'User-Agent': userAgent
        }).timeout(const Duration(seconds: 6));
        if (oembedResp.statusCode == 200) {
          final oembedData =
              jsonDecode(oembedResp.body) as Map<String, dynamic>;
          playlistTitle = oembedData['title'] as String?;
        }
      } catch (_) {}
    }

    playlistTitle ??= 'Imported Spotify Playlist';

    // Page remaining tracks if playlist has 100+ tracks and access token was provided
    if (tracks.length >= _embedTrackLimit &&
        accessToken != null &&
        accessToken.isNotEmpty) {
      try {
        final remaining = await _fetchRemainingTracks(
          playlistId: playlistId,
          token: accessToken,
          startOffset: tracks.length,
        );
        tracks.addAll(remaining);
      } catch (e) {
        ErrorLogger.log('Could not fetch remaining Spotify tracks: $e',
            category: 'SpotifyImporter');
      }
    }

    if (tracks.isEmpty) {
      throw Exception(
          'No tracks found in Spotify playlist. Ensure the playlist is public.');
    }

    return (title: playlistTitle, tracks: tracks);
  }

  /// Paginates remaining tracks via Spotify Partner Pathfinder API.
  Future<List<SpotifyImportTrack>> _fetchRemainingTracks({
    required String playlistId,
    required String token,
    required int startOffset,
  }) async {
    final out = <SpotifyImportTrack>[];
    var offset = startOffset;
    const pageSize = 100;

    while (true) {
      final variables = jsonEncode({
        'uri': 'spotify:playlist:$playlistId',
        'offset': offset,
        'limit': pageSize,
        'enableWatchFeedEntrypoint': false,
      });
      final extensions = jsonEncode({
        'persistedQuery': {
          'version': 1,
          'sha256Hash': _fetchPlaylistHash,
        }
      });

      final uri = Uri.parse(_pathfinderUrl).replace(queryParameters: {
        'operationName': 'fetchPlaylist',
        'variables': variables,
        'extensions': extensions,
      });

      final resp = await _httpClient.get(uri, headers: {
        'User-Agent': userAgent,
        'Authorization': 'Bearer $token',
        'App-platform': 'WebPlayer',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) break;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final playlistV2 = data['data']?['playlistV2'] as Map<String, dynamic>?;
      final content = playlistV2?['content'] as Map<String, dynamic>?;
      final items = content?['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) break;

      for (final item in items) {
        if (item is Map<String, dynamic>) {
          final itemData = item['itemV2']?['data'] as Map<String, dynamic>?;
          final name = itemData?['name'] as String?;
          if (name == null || name.trim().isEmpty) continue;

          final artistItems = itemData?['artists']?['items'] as List<dynamic>?;
          final artistNames = artistItems
                  ?.whereType<Map<String, dynamic>>()
                  .map((a) => a['profile']?['name'] as String?)
                  .where((n) => n != null && n.isNotEmpty)
                  .join(', ') ??
              '';

          out.add(SpotifyImportTrack(
            title: name.trim(),
            artist: artistNames.trim(),
          ));
        }
      }

      final total = (content?['totalCount'] as num?)?.toInt();
      offset += items.length;
      if (total == null || offset >= total) break;
    }

    return out;
  }

  /// Resolves Spotify tracks to YouTube Music tracks with bounded concurrency.
  Future<({List<YtmTrack> resolved, List<SpotifyImportTrack> unmatched})>
      resolveTracks(
    List<SpotifyImportTrack> tracks, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final ytm = _effectiveYtmService;
    final total = tracks.length;
    var completedCount = 0;

    final resolved = <YtmTrack>[];
    final unmatched = <SpotifyImportTrack>[];

    // Process in batches of 3 to avoid hammering YTM and triggering rate limits
    const concurrency = 3;
    for (var i = 0; i < tracks.length; i += concurrency) {
      final chunk = tracks.skip(i).take(concurrency).toList();
      final futures = chunk.map((track) async {
        try {
          final query = '${track.title} ${track.artist}'.trim();
          final results = await ytm.search(query, limit: 5);
          final match = _findBestMatch(track, results);
          return (track: track, match: match);
        } catch (e) {
          ErrorLogger.log('Error resolving track "${track.title}" on YTM',
              error: e, category: 'SpotifyImporter');
          return (track: track, match: null);
        }
      });

      final chunkResults = await Future.wait(futures);
      for (final r in chunkResults) {
        completedCount++;
        onProgress?.call(completedCount, total);
        if (r.match != null) {
          resolved.add(r.match!);
        } else {
          unmatched.add(r.track);
        }
      }
    }

    return (resolved: resolved, unmatched: unmatched);
  }

  /// Finds the best matching YtmTrack based on title and artist similarity.
  YtmTrack? _findBestMatch(
      SpotifyImportTrack target, List<YtmTrack> candidates) {
    if (candidates.isEmpty) return null;

    final targetTitle = target.title.toLowerCase().trim();
    final targetArtist = target.artist.toLowerCase().trim();

    // 1. Exact match on title and artist contains
    for (final c in candidates) {
      final cTitle = c.title.toLowerCase().trim();
      final cArtist = c.artist.toLowerCase().trim();
      if (cTitle == targetTitle &&
          (targetArtist.isEmpty ||
              cArtist.contains(targetArtist) ||
              targetArtist.contains(cArtist))) {
        return c;
      }
    }

    // 2. Title contains / contained
    for (final c in candidates) {
      final cTitle = c.title.toLowerCase().trim();
      if (cTitle.contains(targetTitle) || targetTitle.contains(cTitle)) {
        return c;
      }
    }

    // 3. Fallback to first search hit
    return candidates.first;
  }

  /// Executes full import flow:
  /// 1. Extracts ID
  /// 2. Fetches playlist tracks
  /// 3. Resolves tracks on YouTube Music
  /// 4. Creates a local Pulsr playlist
  /// 5. Saves resolved tracks into songs table
  /// 6. Adds songs to playlist
  Future<SpotifyImportResult> importPlaylist(
    String input, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final playlistId = extractPlaylistId(input);
    if (playlistId == null) {
      throw const FormatException('Invalid Spotify playlist URL or ID.');
    }

    final playlistData = await fetchPlaylistTracks(playlistId);
    final matchResult = await resolveTracks(
      playlistData.tracks,
      onProgress: onProgress,
    );

    if (matchResult.resolved.isEmpty) {
      throw Exception('Could not match any tracks on YouTube Music.');
    }

    // Create local Pulsr playlist
    final createRes =
        await _effectivePlaylistUseCases.createPlaylist(playlistData.title);
    final createdPlaylistId = createRes.fold(
      (f) => throw Exception('Failed to create playlist: ${f.message}'),
      (id) => id,
    );

    // Persist tracks in songsTable and gather IDs
    final db = _effectiveDb;
    final songIds = <int>[];

    for (final track in matchResult.resolved) {
      final existing = await (db.select(db.songsTable)
            ..where((t) => t.remoteId.equals(track.videoId))
            ..limit(1))
          .getSingleOrNull();

      if (existing != null) {
        songIds.add(existing.id);
      } else {
        final songData = track.toSongData();
        final id = await _resolveFreeSongId(db, songData.id);
        await db.into(db.songsTable).insert(
              SongsTableCompanion(
                id: Value(id),
                title: Value(songData.title),
                artist: Value(songData.artist),
                album: Value(songData.album),
                durationMs: Value(songData.durationMs),
                path: Value(songData.path),
                source: const Value(SongSource.youtube),
                remoteId: Value(track.videoId),
                remoteArtworkUrl: Value(track.artworkUrl),
                isFavorite: const Value(false),
                isMissing: const Value(false),
                dateAdded: Value(DateTime.now().millisecondsSinceEpoch),
              ),
              mode: InsertMode.insertOrReplace,
            );
        songIds.add(id);
      }
    }

    // Add songs to the playlist
    if (songIds.isNotEmpty) {
      await _effectivePlaylistUseCases.addSongsToPlaylist(
        createdPlaylistId,
        songIds,
      );
    }

    return SpotifyImportResult(
      playlistId: createdPlaylistId,
      playlistTitle: playlistData.title,
      totalTracks: playlistData.tracks.length,
      resolvedTracks: matchResult.resolved,
      unmatchedTracks: matchResult.unmatched,
    );
  }

  Future<int> _resolveFreeSongId(AppDatabase db, int preferred) async {
    var candidate = preferred;
    for (var i = 0; i < 4096; i++) {
      final clash = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(candidate))
            ..limit(1))
          .getSingleOrNull();
      if (clash == null) return candidate;
      candidate = candidate < 0 ? candidate - 1 : candidate + 1;
    }
    return -(DateTime.now().microsecondsSinceEpoch & 0x3FFFFFFFFFFFFFFF);
  }
}
