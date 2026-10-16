// lib/services/canvas/apple_music_canvas.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/utils/error_logger.dart';
import 'canvas_artwork.dart';

/// Apple Music motion artwork search via catalog API (`editorialVideo`).
class AppleMusicCanvas {
  static const String ampBase = 'https://amp-api.music.apple.com/v1/catalog';
  static const String webPlayerUrl = 'https://music.apple.com/us/browse';
  static const int minScore = 12;

  AppleMusicCanvas({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String? _cachedToken;
  DateTime? _tokenExpiresAt;
  DateTime? _retryTokenAfter;
  final Set<String> _rejectedTokens = {};

  /// Searches Apple Music catalog for motion artwork.
  Future<CanvasArtwork?> search(
      String title, String artist, String? album) async {
    final bearer = await _getToken();
    if (bearer == null) return null;

    final cleanTitle = cleanNoise(title);
    final termBuffer = StringBuffer();
    if (!cleanTitle.toLowerCase().contains(artist.toLowerCase())) {
      termBuffer.write(artist);
      termBuffer.write(' ');
    }
    termBuffer.write(cleanTitle);
    if (album != null &&
        album.trim().isNotEmpty &&
        !cleanTitle.toLowerCase().contains(album.toLowerCase())) {
      termBuffer.write(' ');
      termBuffer.write(album);
    }
    final term = termBuffer.toString();

    final uri = Uri.parse('$ampBase/us/search').replace(queryParameters: {
      'term': term,
      'types': 'songs',
      'limit': '10',
      'extend': 'editorialVideo',
      'include': 'albums',
    });

    final body = await _getWithAuth(uri.toString(), bearer);
    if (body == null) return null;

    try {
      final Map<String, dynamic> root = jsonDecode(body);
      final results = root['results'] as Map<String, dynamic>?;
      final songsObj = results?['songs'] as Map<String, dynamic>?;
      final data = songsObj?['data'] as List<dynamic>?;
      if (data == null || data.isEmpty) return null;

      final List<Map<String, dynamic>> songs =
          data.whereType<Map<String, dynamic>>().toList();

      final List<MapEntry<int, Map<String, dynamic>>> ranked = [];
      for (final song in songs) {
        final scoreVal = _score(song, cleanTitle, artist, album);
        if (scoreVal != null) {
          ranked.add(MapEntry(scoreVal, song));
        }
      }
      ranked.sort((a, b) => b.key.compareTo(a.key));

      for (final entry in ranked) {
        if (entry.key < minScore) break;
        final song = entry.value;
        final attributes = song['attributes'] as Map<String, dynamic>? ?? {};
        final songName = attributes['name']?.toString();
        final songArtist = attributes['artistName']?.toString();
        final albumName = attributes['albumName']?.toString();

        // 1. Inline motion artwork on song
        final editorialVideo =
            attributes['editorialVideo'] as Map<String, dynamic>?;
        if (editorialVideo != null) {
          final urls = _motionUrls(editorialVideo);
          if (urls != null) {
            return CanvasArtwork(
              videoUrl: urls.$1,
              fallbackUrl: urls.$2,
              title: songName,
              artist: songArtist,
              album: albumName,
              source: 'apple_music',
            );
          }
        }

        // 2. Look up album
        final albumId = _albumId(song);
        if (albumId != null) {
          final albumCanvas =
              await _fetchAlbum(albumId, bearer, songName, songArtist);
          if (albumCanvas != null) return albumCanvas;
        }
      }
    } catch (e, st) {
      ErrorLogger.log('AppleMusicCanvas search parsing error',
          error: e, stackTrace: st, category: 'AppleMusicCanvas');
    }
    return null;
  }

  /// Searches Apple Music catalog for motion artwork for an album.
  Future<CanvasArtwork?> searchAlbum(String album, String artist) async {
    final bearer = await _getToken();
    if (bearer == null) return null;

    final term = album.toLowerCase().contains(artist.toLowerCase())
        ? album
        : '$artist $album';

    final uri = Uri.parse('$ampBase/us/search').replace(queryParameters: {
      'term': term,
      'types': 'albums',
      'limit': '10',
      'extend': 'editorialVideo',
    });

    final body = await _getWithAuth(uri.toString(), bearer);
    if (body == null) return null;

    try {
      final Map<String, dynamic> root = jsonDecode(body);
      final results = root['results'] as Map<String, dynamic>?;
      final albumsObj = results?['albums'] as Map<String, dynamic>?;
      final data = albumsObj?['data'] as List<dynamic>?;
      if (data == null || data.isEmpty) return null;

      final List<Map<String, dynamic>> records =
          data.whereType<Map<String, dynamic>>().toList();

      final List<MapEntry<int, Map<String, dynamic>>> ranked = [];
      for (final rec in records) {
        final scoreVal = _score(rec, album, artist, album, albumIsSelf: true);
        if (scoreVal != null) {
          ranked.add(MapEntry(scoreVal, rec));
        }
      }
      ranked.sort((a, b) => b.key.compareTo(a.key));

      for (final entry in ranked) {
        if (entry.key < minScore) break;
        final rec = entry.value;
        final attributes = rec['attributes'] as Map<String, dynamic>? ?? {};
        final name = attributes['name']?.toString();
        if (name != null && _isCompilation(name)) continue;

        final video = attributes['editorialVideo'] as Map<String, dynamic>?;
        if (video != null) {
          final urls = _motionUrls(video);
          if (urls != null) {
            return CanvasArtwork(
              videoUrl: urls.$1,
              fallbackUrl: urls.$2,
              title: name,
              artist: attributes['artistName']?.toString(),
              album: name,
              source: 'apple_music',
            );
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('AppleMusicCanvas searchAlbum parsing error',
          error: e, stackTrace: st, category: 'AppleMusicCanvas');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Scoring
  // ---------------------------------------------------------------------------

  int? _score(
    Map<String, dynamic> song,
    String title,
    String artist,
    String? album, {
    bool albumIsSelf = false,
  }) {
    final attributes = song['attributes'] as Map<String, dynamic>? ?? {};
    final hitName = attributes['name']?.toString() ?? '';
    final hitArtist = attributes['artistName']?.toString() ?? '';
    final hitAlbum =
        albumIsSelf ? hitName : (attributes['albumName']?.toString() ?? '');

    if (_isCompilation(hitName) || _isCompilation(hitAlbum)) return null;

    final wanted = splitArtists(artist);
    final credited = splitArtists(hitArtist);
    if (wanted.isEmpty || credited.isEmpty) return null;
    if (!wanted.every((w) => credited.any((c) => c == w))) return null;

    int score = 10;
    final wantTitle = normalizeForMatch(title);
    final hitTitle = normalizeForMatch(hitName);

    if (hitTitle == wantTitle) {
      score += 15;
    } else if (hitTitle.contains(wantTitle) || wantTitle.contains(hitTitle)) {
      score += 7;
    } else {
      score -= 10;
    }

    if (album != null && album.isNotEmpty && hitAlbum.isNotEmpty) {
      final wantAlbum = normalizeForMatch(album);
      final gotAlbum = normalizeForMatch(hitAlbum);
      if (gotAlbum == wantAlbum) {
        score += 20;
      } else if (gotAlbum.contains(wantAlbum) || wantAlbum.contains(gotAlbum)) {
        score += 10;
      }
    }

    const editionWords = [
      'deluxe',
      'expanded',
      'remastered',
      'remix',
      'version',
      'edit',
      'mix',
      'bonus'
    ];
    for (final word in editionWords) {
      final inWanted = title.toLowerCase().contains(word);
      final inHit = hitName.toLowerCase().contains(word);
      if (inWanted && inHit) {
        score += 5;
      } else if (inHit) {
        score -= 3;
      }
    }

    return score;
  }

  bool _isCompilation(String name) {
    final lower = name.toLowerCase();
    const markers = [
      'playlist',
      'set list',
      'essentials',
      'dj mix',
      'mixed',
      'apple music',
      "today's hits",
      'session',
    ];
    return markers.any((m) => lower.contains(m));
  }

  String? _albumId(Map<String, dynamic> song) {
    final relationships = song['relationships'] as Map<String, dynamic>?;
    final albums = relationships?['albums'] as Map<String, dynamic>?;
    final data = albums?['data'] as List<dynamic>?;
    if (data != null && data.isNotEmpty) {
      final id = data.first['id']?.toString();
      if (id != null && !id.startsWith('pl.')) return id;
    }

    final url = song['attributes']?['url']?.toString();
    if (url != null && url.contains('/album/')) {
      final after = url.substring(url.indexOf('/album/') + 7);
      final before = after.split('?').first;
      final last = before.split('/').last;
      if (last.isNotEmpty && int.tryParse(last) != null) return last;
    }
    return null;
  }

  Future<CanvasArtwork?> _fetchAlbum(
    String albumId,
    String bearer,
    String? songTitle,
    String? songArtist,
  ) async {
    final uri = Uri.parse('$ampBase/us/albums/$albumId')
        .replace(queryParameters: {'extend': 'editorialVideo'});
    final body = await _getWithAuth(uri.toString(), bearer);
    if (body == null) return null;

    try {
      final Map<String, dynamic> root = jsonDecode(body);
      final data = root['data'] as List<dynamic>?;
      if (data == null || data.isEmpty) return null;

      final album = data.first as Map<String, dynamic>;
      final attributes = album['attributes'] as Map<String, dynamic>? ?? {};
      final albumName = attributes['name']?.toString() ?? '';
      if (_isCompilation(albumName)) return null;

      final video = attributes['editorialVideo'] as Map<String, dynamic>?;
      if (video == null) return null;

      final urls = _motionUrls(video);
      if (urls == null) return null;

      return CanvasArtwork(
        videoUrl: urls.$1,
        fallbackUrl: urls.$2,
        title: songTitle,
        artist: songArtist ?? attributes['artistName']?.toString(),
        album: albumName,
        source: 'apple_music',
      );
    } catch (_) {
      return null;
    }
  }

  (String, String?)? _motionUrls(Map<String, dynamic> video) {
    String? extract(String key) {
      final asset = video[key] as Map<String, dynamic>?;
      if (asset == null) return null;
      final v = asset['video'] ??
          asset['videoUrl'] ??
          asset['hlsUrl'] ??
          asset['url'];
      final str = v?.toString();
      return (str != null && str.trim().isNotEmpty) ? str : null;
    }

    final square =
        extract('motionDetailSquare') ?? extract('motionSquareVideo1x1');
    final raw = extract('motionDetailRaw');
    final tall = extract('motionDetailTall') ?? extract('motionTallVideo3x4');
    final primary = square ?? raw ?? tall;
    if (primary == null) return null;

    final candidates = [square, raw, tall].whereType<String>().toList();
    final alternate =
        candidates.firstWhere((c) => c != primary, orElse: () => '');
    return (primary, alternate.isNotEmpty ? alternate : null);
  }

  // ---------------------------------------------------------------------------
  // Token Retrieval & Auth
  // ---------------------------------------------------------------------------

  Future<String?> _getToken() async {
    final now = DateTime.now();
    if (_cachedToken != null &&
        _tokenExpiresAt != null &&
        now.isBefore(_tokenExpiresAt!.subtract(const Duration(minutes: 1)))) {
      return _cachedToken;
    }

    if (_retryTokenAfter != null && now.isBefore(_retryTokenAfter!)) {
      return null;
    }

    try {
      final response = await _client.get(
        Uri.parse(webPlayerUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final html = response.body;
        final scriptRegex =
            RegExp(r'/assets/index(?:-legacy)?[~-][A-Za-z0-9_-]+\.js');
        final scriptMatches = scriptRegex
            .allMatches(html)
            .map((m) => m.group(0)!)
            .toSet()
            .toList();

        for (final scriptPath in scriptMatches) {
          final scriptResp = await _client.get(
            Uri.parse('https://music.apple.com$scriptPath'),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            },
          ).timeout(const Duration(seconds: 12));

          if (scriptResp.statusCode != 200) continue;
          final scriptText = scriptResp.body;

          final jwtRegex =
              RegExp(r'ey[A-Za-z0-9_-]+\.ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+');
          final candidates = jwtRegex
              .allMatches(scriptText)
              .map((m) => m.group(0)!)
              .toSet()
              .where((t) => !_rejectedTokens.contains(t))
              .map((jwt) {
                final exp = _extractExpiry(jwt);
                return exp != null ? (jwt, exp) : null;
              })
              .whereType<(String, DateTime)>()
              .where((pair) => pair.$2.isAfter(now))
              .toList();

          if (candidates.isEmpty) continue;

          final selected = candidates.firstWhere(
            (c) => _isWebPlayerToken(c.$1),
            orElse: () => candidates.first,
          );

          _cachedToken = selected.$1;
          _tokenExpiresAt = selected.$2;
          return _cachedToken;
        }
      }
    } catch (e, st) {
      ErrorLogger.log('AppleMusicCanvas token scraping error',
          error: e, stackTrace: st, category: 'AppleMusicCanvas');
    }

    _retryTokenAfter = now.add(const Duration(minutes: 30));
    return null;
  }

  bool _isWebPlayerToken(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return false;
      final header =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[0])));
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return header.contains('WebPlayKid') || payload.contains('AMPWebPlay');
    } catch (_) {
      return false;
    }
  }

  DateTime? _extractExpiry(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final match = RegExp(r'"exp"\s*:\s*(\d+)').firstMatch(payload);
      if (match != null) {
        final sec = int.tryParse(match.group(1)!);
        if (sec != null) return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _getWithAuth(String url, String bearer) async {
    try {
      final uri = Uri.parse(url);
      final response = await _client.get(
        uri,
        headers: {
          'Authorization': 'Bearer $bearer',
          'Origin': 'https://music.apple.com',
          'Referer': 'https://music.apple.com/',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        return response.body;
      } else if (response.statusCode == 401) {
        _rejectedTokens.add(bearer);
        if (_cachedToken == bearer) {
          _cachedToken = null;
          _tokenExpiresAt = null;
        }
      }
    } catch (_) {}
    return null;
  }
}
