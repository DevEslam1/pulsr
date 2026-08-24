// lib/core/services/ytm_account_service.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/lyrics_line.dart';
import '../../domain/models/ytm_track.dart';
import '../utils/error_logger.dart';
import '../utils/lrc_parser.dart';

class YtmAccountPlaylist {
  final String playlistId;
  final String title;
  final String subtitle;
  final String? artworkUrl;

  const YtmAccountPlaylist({
    required this.playlistId,
    required this.title,
    required this.subtitle,
    this.artworkUrl,
  });

  String get cleanPlaylistId =>
      playlistId.startsWith('VL') ? playlistId.substring(2) : playlistId;

  String get shareUrl =>
      'https://music.youtube.com/playlist?list=$cleanPlaylistId';

  Map<String, dynamic> toJson() => {
        'playlistId': playlistId,
        'title': title,
        'subtitle': subtitle,
        'artworkUrl': artworkUrl,
      };

  factory YtmAccountPlaylist.fromJson(Map<String, dynamic> json) =>
      YtmAccountPlaylist(
        playlistId: json['playlistId'] as String? ?? '',
        title: json['title'] as String? ?? 'Playlist',
        subtitle: json['subtitle'] as String? ?? 'YouTube Music',
        artworkUrl: json['artworkUrl'] as String?,
      );
}

@singleton
class YtmAccountService {
  static const String _cookiePrefKey = 'ytm_session_cookies';
  static const String _accountNamePrefKey = 'ytm_account_name';
  static const String _accountAvatarPrefKey = 'ytm_account_avatar';
  static const String _innertubeBrowseUrl =
      'https://music.youtube.com/youtubei/v1/browse?prettyPrint=false';

  String? _cookies;
  String? _accountName;
  String? _accountAvatar;
  bool _isInitialized = false;

  /// Notifies listeners whenever the YTM login state changes (login/logout).
  /// UI widgets should listen to this to rebuild without a restart.
  final loginState = ValueNotifier<bool>(false);

  bool get isLoggedIn => _cookies != null && _cookies!.isNotEmpty;
  String? get accountName => _accountName;
  String? get accountAvatar => _accountAvatar;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _cookies = prefs.getString(_cookiePrefKey);
      _accountName = prefs.getString(_accountNamePrefKey);
      _accountAvatar = prefs.getString(_accountAvatarPrefKey);
      _isInitialized = true;
      loginState.value = isLoggedIn; // sync notifier with persisted state
    } catch (e, st) {
      ErrorLogger.log('Failed to initialize YtmAccountService',
          error: e, stackTrace: st, category: 'YTM_ACCOUNT');
    }
  }

  /// Returns cookies for a single URL from the native Android CookieManager.
  Future<String?> getNativeCookies([String url = 'https://music.youtube.com']) async {
    const channel = MethodChannel('com.pulsr.music/ytm');
    try {
      final cookies =
          await channel.invokeMethod<String>('getCookies', {'url': url});
      return cookies;
    } catch (_) {
      return null;
    }
  }

  /// Collects cookies from ALL Google/YouTube Music domains via the native
  /// Android CookieManager (which includes HttpOnly cookies that JS cannot
  /// read). The Kotlin `getCookies` handler already merges multiple domains;
  /// calling it without a URL argument returns the merged result.
  Future<String?> getNativeCookiesFromDomains() async {
    const channel = MethodChannel('com.pulsr.music/ytm');
    try {
      // The Kotlin handler for 'getCookies' always reads from all 4 domains:
      // music.youtube.com, www.youtube.com, accounts.google.com, youtube.com
      // and merges them — so we can call it with any (or no) url arg.
      final cookies =
          await channel.invokeMethod<String>('getCookies', {'url': 'https://music.youtube.com'});
      return cookies;
    } catch (_) {
      return null;
    }
  }

  /// Saves extracted web cookies and fetches profile info.
  Future<bool> saveSession(String rawCookies) async {
    _cookies = rawCookies;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookiePrefKey, rawCookies);

    // Attempt to extract SAPISID or account profile
    final name = _extractCookieValue(rawCookies, 'ACCOUNT_CHOOSER') ??
        _extractCookieValue(rawCookies, 'LOGIN_INFO') ??
        'YouTube Music User';
    _accountName = name;
    await prefs.setString(_accountNamePrefKey, name);

    loginState.value = true; // notify UI: now logged in
    return true;
  }

  Future<void> logout() async {
    _cookies = null;
    _accountName = null;
    _accountAvatar = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cookiePrefKey);
    await prefs.remove(_accountNamePrefKey);
    await prefs.remove(_accountAvatarPrefKey);
    loginState.value = false; // notify UI: now logged out
  }

  /// Builds authenticated Innertube request headers.
  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Origin': 'https://music.youtube.com',
      'Referer': 'https://music.youtube.com/',
      'x-origin': 'https://music.youtube.com',
      'x-youtube-client-name': '67',
      'x-youtube-client-version': '1.20240417.01.00',
      'x-goog-authuser': '0',
      // Required when not using the ?key= query param
      'X-Goog-Api-Key': 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30',
    };

    if (_cookies != null && _cookies!.isNotEmpty) {
      headers['Cookie'] = _cookies!;
      final sapisid = _extractCookieValue(_cookies!, 'SAPISID') ??
          _extractCookieValue(_cookies!, '__Secure-3PAPISID') ??
          _extractCookieValue(_cookies!, '__Secure-1PAPISID');

      if (sapisid != null && sapisid.isNotEmpty) {
        final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
        // SAPISIDHASH input is space-separated: "{ts} {SAPISID} {origin}".
        // Only the header value joins ts and hash with an underscore.
        final toHash = '$timestamp $sapisid https://music.youtube.com';
        final sha1Digest = sha1.convert(utf8.encode(toHash)).toString();
        headers['Authorization'] = 'SAPISIDHASH ${timestamp}_$sha1Digest';
      }
    }

    return headers;
  }

  String? _extractCookieValue(String cookieString, String key) {
    for (final pair in cookieString.split(';')) {
      final parts = pair.trim().split('=');
      if (parts.length >= 2 && parts[0].trim() == key) {
        return parts.sublist(1).join('=').trim();
      }
    }
    return null;
  }

  /// Fetches the user's library playlists from YouTube Music.
  Future<List<YtmAccountPlaylist>> fetchAccountPlaylists() async {
    if (!isLoggedIn) {
      throw Exception('Not signed in to YouTube Music');
    }

    final headers = _buildHeaders();
    final browseIds = [
      'FEmusic_library_playlists',
      'FEmusic_liked_playlists',
      'FEmusic_library_landing',
    ];

    for (final bId in browseIds) {
      try {
        final body = jsonEncode({
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': '1.20240417.01.00',
              'hl': 'en',
              'gl': 'US',
            }
          },
          'browseId': bId,
        });

        final response = await http
            .post(Uri.parse(_innertubeBrowseUrl), headers: headers, body: body)
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          if (_isUnauthenticatedResponse(json)) continue;

          final playlists = _parseInnertubeAccountPlaylists(json);
          if (playlists.isNotEmpty) {
            debugPrint(
              '[YTM_ACCOUNT] Found ${playlists.length} account playlists from $bId',
            );
            return playlists;
          }
        }
      } catch (e) {
        debugPrint('[YTM_ACCOUNT] Failed fetching account playlists ($bId): $e');
      }
    }
    return [];
  }

  /// Fetches personalized recommendations and home feed from YouTube Music (`FEmusic_home`).
  /// Includes Quick Picks, Mixed for You, and personalized artist radios.
  Future<List<YtmTrack>> fetchHomeRecommendations({int maxTracks = 50}) async {
    if (!isLoggedIn) return [];
    final headers = _buildHeaders();

    try {
      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240417.01.00',
            'hl': 'en',
            'gl': 'US',
          }
        },
        'browseId': 'FEmusic_home',
      });

      final response = await http
          .post(Uri.parse(_innertubeBrowseUrl), headers: headers, body: body)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (!_isUnauthenticatedResponse(json)) {
          final tracks = _parseInnertubePlaylistTracks(json);
          if (tracks.isNotEmpty) {
            final seen = <String>{};
            final unique = <YtmTrack>[];
            for (final t in tracks) {
              if (seen.add(t.videoId)) {
                unique.add(t);
              }
            }
            debugPrint('[YTM_ACCOUNT] Parsed ${unique.length} personalized home recommendations');
            return unique.take(maxTracks).toList();
          }
        }
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] Failed to fetch personalized home feed: $e');
    }
    return [];
  }

  /// Fetches native lyrics from YouTube Music for a given [videoId].
  Future<LyricsResult?> fetchYtmLyrics(String videoId) async {
    if (videoId.isEmpty) return null;
    final headers = _buildHeaders();

    try {
      // 1. Query Next endpoint to find lyrics browse ID
      final nextBody = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240417.01.00',
            'hl': 'en',
            'gl': 'US',
          }
        },
        'videoId': videoId,
      });

      final nextRes = await http
          .post(Uri.parse('https://music.youtube.com/youtubei/v1/next?prettyPrint=false'),
              headers: headers, body: nextBody)
          .timeout(const Duration(seconds: 8));

      if (nextRes.statusCode != 200) return null;
      final nextJson = jsonDecode(nextRes.body) as Map<String, dynamic>;

      String? lyricsBrowseId;
      void findLyricsBrowseId(dynamic node) {
        if (lyricsBrowseId != null) return;
        if (node is Map<String, dynamic>) {
          if (node.containsKey('tabRenderer')) {
            final tab = node['tabRenderer'] as Map<String, dynamic>;
            final title = tab['title'] as String? ?? '';
            final endpoint = tab['endpoint']?['browseEndpoint'] as Map<String, dynamic>?;
            final bId = endpoint?['browseId'] as String?;
            if (title.toLowerCase().contains('lyric') || (bId != null && bId.startsWith('MPLYt'))) {
              lyricsBrowseId = bId;
              return;
            }
          }
          for (final val in node.values) {
            findLyricsBrowseId(val);
          }
        } else if (node is List) {
          for (final item in node) {
            findLyricsBrowseId(item);
          }
        }
      }

      findLyricsBrowseId(nextJson);
      if (lyricsBrowseId == null) return null;

      // 2. Fetch the lyrics browse payload
      final browseBody = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240417.01.00',
            'hl': 'en',
            'gl': 'US',
          }
        },
        'browseId': lyricsBrowseId,
      });

      final browseRes = await http
          .post(Uri.parse(_innertubeBrowseUrl), headers: headers, body: browseBody)
          .timeout(const Duration(seconds: 8));

      if (browseRes.statusCode != 200) return null;
      final browseJson = jsonDecode(browseRes.body) as Map<String, dynamic>;

      final List<LyricsLine> lines = [];
      void parseLyrics(dynamic node) {
        if (node is Map<String, dynamic>) {
          if (node.containsKey('musicDescriptionShelfRenderer')) {
            final shelf = node['musicDescriptionShelfRenderer'] as Map<String, dynamic>;
            final desc = shelf['description'];
            String plainText = '';
            if (desc is Map && desc.containsKey('runs')) {
              final runs = desc['runs'] as List<dynamic>;
              plainText = runs.map((r) => r['text'] as String? ?? '').join();
            } else if (desc is String) {
              plainText = desc;
            }
            if (plainText.isNotEmpty) {
              lines.addAll(LrcParser.parsePlainText(plainText, source: LyricsSource.ytmusic));
            }
            return;
          }
          for (final val in node.values) {
            parseLyrics(val);
          }
        } else if (node is List) {
          for (final item in node) {
            parseLyrics(item);
          }
        }
      }

      parseLyrics(browseJson);
      if (lines.isNotEmpty) {
        return LyricsResult(lines: lines, source: LyricsSource.ytmusic);
      }
    } catch (e) {
      debugPrint('[YTM_LYRICS] Error fetching YTM lyrics: $e');
    }
    return null;
  }

  /// Fetches the user's private Liked Music playlist (`FEmusic_liked_videos`).
  Future<List<YtmTrack>> fetchLikedSongs({int maxTracks = 200}) async {
    if (!isLoggedIn) {
      throw Exception('Not signed in to YouTube Music');
    }

    final headers = _buildHeaders();

    // Diagnostics: confirm auth material actually made it into the request.
    final hasSapisid = _extractCookieValue(_cookies!, 'SAPISID') != null ||
        _extractCookieValue(_cookies!, '__Secure-3PAPISID') != null ||
        _extractCookieValue(_cookies!, '__Secure-1PAPISID') != null;
    debugPrint(
      '[YTM_ACCOUNT] fetchLikedSongs: cookieLen=${_cookies!.length} '
      'hasSAPISID=$hasSapisid hasAuthHeader=${headers.containsKey('Authorization')}',
    );

    // Try Innertube Web Remix browse IDs.
    // NOTE: 'LM' and 'VLSE' are NOT valid browse IDs — 'LM' is a YouTube
    // playlist ID (causes HTTP 400) and 'VLSE' is not a real endpoint.
    // Only 'FEmusic_liked_videos' and 'VLLM' are valid YTM browse IDs.
    final browseIds = ['FEmusic_liked_videos', 'VLLM'];
    for (final bId in browseIds) {
      try {
        final body = jsonEncode({
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': '1.20240417.01.00',
              'hl': 'en',
              'gl': 'US',
            }
          },
          'browseId': bId,
        });

        final response = await http
            .post(Uri.parse(_innertubeBrowseUrl), headers: headers, body: body)
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;

          // Detect silent auth failure: YouTube returns a sign-in prompt
          // as HTTP 200 with no content items when cookies are expired.
          if (_isUnauthenticatedResponse(json)) {
            debugPrint(
              '[YTM_ACCOUNT] Innertube browse $bId: session expired or cookies invalid',
            );
            continue;
          }

          final tracks = _parseInnertubePlaylistTracks(json);
          debugPrint(
            '[YTM_ACCOUNT] Innertube browse $bId: 200 OK, parsed ${tracks.length} tracks',
          );
          if (tracks.isNotEmpty) {
            return tracks;
          }

          // --- DIAGNOSTIC: log response structure so we can fix the parser ---
          final topKeys = json.keys.toList();
          debugPrint('[YTM_ACCOUNT] DIAG $bId top-level keys: $topKeys');
          // Log the shape one level deep to understand the response layout.
          for (final k in topKeys.take(5)) {
            final v = json[k];
            if (v is Map) {
              debugPrint('[YTM_ACCOUNT] DIAG $bId.$k keys: ${v.keys.toList()}');
            } else if (v is List) {
              debugPrint('[YTM_ACCOUNT] DIAG $bId.$k is List[${v.length}]');
            }
          }
          // Also dump a raw snippet for manual inspection.
          final snippet = response.body.length > 800
              ? response.body.substring(0, 800)
              : response.body;
          debugPrint('[YTM_ACCOUNT] DIAG $bId body snippet: $snippet');
          // --- END DIAGNOSTIC ---
        } else {
          final snippet = response.body.length > 300
              ? response.body.substring(0, 300)
              : response.body;
          debugPrint(
            '[YTM_ACCOUNT] Innertube browse $bId: HTTP ${response.statusCode} body=$snippet',
          );
        }
      } catch (e) {
        debugPrint('[YTM_ACCOUNT] Innertube browse failed for $bId: $e');
      }
    }

    // NOTE: The private playlist IDs 'LM' (Liked Music) and 'LL' (Liked Videos)
    // are NOT supported via NewPipe extractor — they require authenticated
    // cookies AND are rejected by NewPipe's URL validator. Do not attempt them.
    debugPrint('[YTM_ACCOUNT] fetchLikedSongs: all browse attempts exhausted. '
        'Cookies may be expired — please re-login to YouTube Music.');
    return [];
  }

  /// Returns true when YouTube returns an unauthenticated / sign-in-required
  /// page as HTTP 200 (which happens when cookies are missing or expired).
  bool _isUnauthenticatedResponse(Map<String, dynamic> json) {
    // A sign-in response has no 'contents' or 'header' at the root level,
    // but does contain 'responseContext'. An authenticated liked-songs response
    // always has either 'contents' or 'header'.
    final hasContents = json.containsKey('contents');
    final hasHeader = json.containsKey('header');
    final hasResponseContext = json.containsKey('responseContext');
    return hasResponseContext && !hasContents && !hasHeader;
  }

  List<YtmTrack> _parseInnertubePlaylistTracks(Map<String, dynamic> root) {
    final tracks = <YtmTrack>[];

    void traverse(dynamic node) {
      if (node is Map<String, dynamic>) {
        if (node.containsKey('musicResponsiveListItemRenderer')) {
          final renderer =
              node['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
          final track = _parseListItemRenderer(renderer);
          if (track != null) tracks.add(track);
          return;
        } else if (node.containsKey('playlistVideoRenderer')) {
          final renderer =
              node['playlistVideoRenderer'] as Map<String, dynamic>;
          final videoId = renderer['videoId'] as String?;
          final title = renderer['title']?['runs']?[0]?['text'] as String? ??
              'Unknown Title';
          final artist = renderer['shortBylineText']?['runs']?[0]?['text']
                  as String? ??
              'Unknown Artist';
          final lengthSeconds =
              int.tryParse(renderer['lengthSeconds']?.toString() ?? '0') ?? 0;
          final thumbnails =
              renderer['thumbnail']?['thumbnails'] as List<dynamic>?;
          final artwork = thumbnails?.isNotEmpty == true
              ? thumbnails!.last['url'] as String?
              : null;

          if (videoId != null && videoId.length == 11) {
            tracks.add(YtmTrack(
              videoId: videoId,
              title: title,
              artist: artist,
              duration: Duration(seconds: lengthSeconds),
              artworkUrl: artwork,
            ));
          }
          return;
        } else if (node.containsKey('musicTwoRowItemRenderer')) {
          final renderer =
              node['musicTwoRowItemRenderer'] as Map<String, dynamic>;
          final nav = renderer['navigationEndpoint'] as Map<String, dynamic>?;
          final vid = nav?['watchEndpoint']?['videoId'] as String?;
          final title = renderer['title']?['runs']?[0]?['text'] as String? ??
              'Unknown Title';
          final subtitle =
              renderer['subtitle']?['runs']?[0]?['text'] as String? ??
                  'Unknown Artist';
          if (vid != null && vid.length == 11) {
            tracks.add(YtmTrack(
              videoId: vid,
              title: title,
              artist: subtitle,
              duration: Duration.zero,
            ));
          }
          return;
        }
        for (final val in node.values) {
          traverse(val);
        }
      } else if (node is List) {
        for (final item in node) {
          traverse(item);
        }
      }
    }

    traverse(root);
    return tracks;
  }

  YtmTrack? _parseListItemRenderer(Map<String, dynamic> renderer) {
    try {
      // 1. Video ID
      final playlistItemData =
          renderer['playlistItemData'] as Map<String, dynamic>?;
      String? videoId = playlistItemData?['videoId'] as String?;

      if (videoId == null) {
        final flexColumns =
            renderer['flexColumns'] as List<dynamic>? ?? const [];
        for (final col in flexColumns) {
          final runs = col['musicResponsiveListItemFlexColumnRenderer']
              ?['text']?['runs'] as List<dynamic>?;
          if (runs != null) {
            for (final r in runs) {
              final nav = r['navigationEndpoint'] as Map<String, dynamic>?;
              final vid = nav?['watchEndpoint']?['videoId'] as String?;
              if (vid != null) {
                videoId = vid;
                break;
              }
            }
          }
          if (videoId != null) break;
        }
      }

      if (videoId == null || videoId.length != 11) return null;

      // 2. Title & Artist & Duration
      String title = 'Unknown Title';
      String artist = 'Unknown Artist';
      int durationMs = 0;

      final flexColumns =
          renderer['flexColumns'] as List<dynamic>? ?? const [];
      if (flexColumns.isNotEmpty) {
        final col0 = flexColumns[0]
            ['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
        if (col0 is List && col0.isNotEmpty) {
          title = col0[0]['text'] as String? ?? title;
        }
      }
      if (flexColumns.length > 1) {
        final col1 = flexColumns[1]
            ['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
        if (col1 is List && col1.isNotEmpty) {
          artist = col1[0]['text'] as String? ?? artist;
        }
      }

      // Fixed column: duration
      final fixedCols =
          renderer['fixedColumns'] as List<dynamic>? ?? const [];
      if (fixedCols.isNotEmpty) {
        final durText = fixedCols[0]
            ['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs']?[0]?['text'] as String?;
        if (durText != null) {
          final parts = durText.split(':').map((e) => int.tryParse(e) ?? 0).toList();
          if (parts.length == 2) {
            durationMs = (parts[0] * 60 + parts[1]) * 1000;
          } else if (parts.length == 3) {
            durationMs = (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
          }
        }
      }

      // Artwork
      String? artworkUrl;
      final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']
          ?['thumbnail']?['thumbnails'] as List<dynamic>?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        artworkUrl = thumbnails.last['url'] as String?;
        if (artworkUrl != null) {
          artworkUrl = artworkUrl.replaceAll(RegExp(r'=w\d+-h\d+[^?]*'), '=s1200');
          artworkUrl = artworkUrl.replaceAll(RegExp(r'=s\d+[^?]*'), '=s1200');
        }
      }

      return YtmTrack(
        videoId: videoId,
        title: title,
        artist: artist,
        duration: Duration(milliseconds: durationMs),
        artworkUrl: artworkUrl,
      );
    } catch (_) {
      return null;
    }
  }

  List<YtmAccountPlaylist> _parseInnertubeAccountPlaylists(
    Map<String, dynamic> root,
  ) {
    final results = <YtmAccountPlaylist>[];
    final seenIds = <String>{};

    void traverse(dynamic node) {
      if (node is Map<String, dynamic>) {
        // 1. musicTwoRowItemRenderer
        if (node.containsKey('musicTwoRowItemRenderer')) {
          final renderer =
              node['musicTwoRowItemRenderer'] as Map<String, dynamic>;
          final nav =
              renderer['navigationEndpoint'] as Map<String, dynamic>?;
          final browseId =
              nav?['browseEndpoint']?['browseId'] as String?;

          if (browseId != null &&
              (browseId.startsWith('VLPL') ||
                  browseId.startsWith('VL') ||
                  browseId.startsWith('PL') ||
                  browseId.startsWith('RDCLAK5uy_'))) {
            final cleanId =
                browseId.startsWith('VL') ? browseId.substring(2) : browseId;
            if (cleanId != 'LM' &&
                cleanId != 'SE' &&
                !seenIds.contains(cleanId)) {
              seenIds.add(cleanId);

              final titleRuns =
                  renderer['title']?['runs'] as List<dynamic>?;
              final title = titleRuns
                      ?.map((r) => r['text']?.toString() ?? '')
                      .join() ??
                  'Playlist';

              final subRuns =
                  renderer['subtitle']?['runs'] as List<dynamic>?;
              final subtitle = subRuns
                      ?.map((r) => r['text']?.toString() ?? '')
                      .join() ??
                  'YouTube Music';

              String? artwork;
              final thumbRenderer = renderer['thumbnailRenderer']
                  ?['musicThumbnailRenderer'];
              final thumbs = thumbRenderer?['thumbnail']?['thumbnails']
                  as List<dynamic>?;
              if (thumbs != null && thumbs.isNotEmpty) {
                artwork = thumbs.last['url'] as String?;
              }

              results.add(YtmAccountPlaylist(
                playlistId: cleanId,
                title: title.isNotEmpty ? title : 'Playlist',
                subtitle: subtitle,
                artworkUrl: artwork,
              ));
            }
          }
        }

        // 2. musicResponsiveListItemRenderer
        if (node.containsKey('musicResponsiveListItemRenderer')) {
          final renderer =
              node['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
          final nav =
              renderer['navigationEndpoint'] as Map<String, dynamic>?;
          final browseId =
              nav?['browseEndpoint']?['browseId'] as String?;
          if (browseId != null &&
              (browseId.startsWith('VLPL') ||
                  browseId.startsWith('VL') ||
                  browseId.startsWith('PL'))) {
            final cleanId =
                browseId.startsWith('VL') ? browseId.substring(2) : browseId;
            if (cleanId != 'LM' &&
                cleanId != 'SE' &&
                !seenIds.contains(cleanId)) {
              seenIds.add(cleanId);

              String title = 'Playlist';
              final flexCols =
                  renderer['flexColumns'] as List<dynamic>?;
              if (flexCols != null && flexCols.isNotEmpty) {
                final r = flexCols[0]
                        ['musicResponsiveListItemFlexColumnRenderer']?['text']
                    ?['runs'] as List<dynamic>?;
                if (r != null && r.isNotEmpty) {
                  title = r.map((e) => e['text']?.toString() ?? '').join();
                }
              }

              String subtitle = 'YouTube Music';
              if (flexCols != null && flexCols.length > 1) {
                final r = flexCols[1]
                        ['musicResponsiveListItemFlexColumnRenderer']?['text']
                    ?['runs'] as List<dynamic>?;
                if (r != null && r.isNotEmpty) {
                  subtitle = r.map((e) => e['text']?.toString() ?? '').join();
                }
              }

              String? artwork;
              final thumbs = renderer['thumbnail']?['musicThumbnailRenderer']
                  ?['thumbnail']?['thumbnails'] as List<dynamic>?;
              if (thumbs != null && thumbs.isNotEmpty) {
                artwork = thumbs.last['url'] as String?;
              }

              results.add(YtmAccountPlaylist(
                playlistId: cleanId,
                title: title,
                subtitle: subtitle,
                artworkUrl: artwork,
              ));
            }
          }
        }

        for (final val in node.values) {
          traverse(val);
        }
      } else if (node is List) {
        for (final item in node) {
          traverse(item);
        }
      }
    }

    traverse(root);
    return results;
  }
}

