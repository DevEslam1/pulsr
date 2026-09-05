// lib/core/services/lrclib_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:injectable/injectable.dart';
import '../../domain/models/lyrics_line.dart';
import '../utils/error_logger.dart';
import '../utils/lrc_parser.dart';

class _TrackCandidate {
  final String trackName;
  final String artistName;
  const _TrackCandidate(this.trackName, this.artistName);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TrackCandidate &&
          other.trackName.toLowerCase() == trackName.toLowerCase() &&
          other.artistName.toLowerCase() == artistName.toLowerCase();

  @override
  int get hashCode =>
      trackName.toLowerCase().hashCode ^ artistName.toLowerCase().hashCode;
}

@singleton
class LrclibService {
  final HttpClient _client;

  LrclibService({HttpClient? client})
      : _client = client ??
            (HttpClient()
              ..connectionTimeout = const Duration(seconds: 3)
              ..idleTimeout = const Duration(seconds: 15)
              ..maxConnectionsPerHost = 6);

  void dispose() {
    _client.close(force: false);
  }

  Future<LyricsResult?> fetchLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
  }) async {
    final candidates = _generateCandidates(
      trackName: trackName,
      artistName: artistName,
    );

    // 1. Try exact get for candidates
    for (final cand in candidates.take(3)) {
      var result = await _tryGetLyrics(
        trackName: cand.trackName,
        artistName: cand.artistName,
        albumName: albumName,
        durationSeconds: durationSeconds,
      );
      if (result != null && result.lines.isNotEmpty) return result;

      // Try exact get without strict album/duration restriction
      if (albumName != null || durationSeconds != null) {
        result = await _tryGetLyrics(
          trackName: cand.trackName,
          artistName: cand.artistName,
        );
        if (result != null && result.lines.isNotEmpty) return result;
      }
    }

    // 2. Fallback to fuzzy search on LRCLIB with candidate queries
    final searchQueries = <String>{};
    for (final cand in candidates.take(2)) {
      if (cand.artistName.isNotEmpty &&
          !cand.trackName.toLowerCase().contains(cand.artistName.toLowerCase())) {
        searchQueries.add('${cand.trackName} ${cand.artistName}');
      }
      searchQueries.add(cand.trackName);
    }

    for (final q in searchQueries.take(3)) {
      final result = await _trySearchLyrics(query: q);
      if (result != null && result.lines.isNotEmpty) return result;
    }

    return null;
  }

  List<_TrackCandidate> _generateCandidates({
    required String trackName,
    required String artistName,
  }) {
    final cleanArt = _cleanArtist(artistName);
    final candidates = <_TrackCandidate>[];

    void addCandidate(String track, String art) {
      final t = track.trim();
      final a = art.trim();
      if (t.isNotEmpty) {
        final c = _TrackCandidate(t, a);
        if (!candidates.contains(c)) {
          candidates.add(c);
        }
      }
    }

    // Split on common dividers like |, •, /, ~
    final segments = trackName
        .split(RegExp(r'\s*[|•/~]\s*'))
        .map((s) => _stripVideoNoise(s))
        .where((s) => s.isNotEmpty)
        .toList();

    for (final seg in segments) {
      // Check for "Artist - Title" or "Title - Artist" divider
      if (seg.contains(RegExp(r'\s*[-–—]\s*'))) {
        final parts = seg.split(RegExp(r'\s*[-–—]\s*'));
        if (parts.length >= 2) {
          final left = parts[0].trim();
          final right = parts.sublist(1).join(' - ').trim();

          // Check if left matches/contains provided artist name
          final leftMatchesArtist = cleanArt.isNotEmpty &&
              (cleanArt.toLowerCase().contains(left.toLowerCase()) ||
                  left.toLowerCase().contains(cleanArt.toLowerCase()));

          // Check if right matches/contains provided artist name
          final rightMatchesArtist = cleanArt.isNotEmpty &&
              (cleanArt.toLowerCase().contains(right.toLowerCase()) ||
                  right.toLowerCase().contains(cleanArt.toLowerCase()));

          if (leftMatchesArtist) {
            // e.g. "Hamaki - Adrenaline" with artist "Mohamed Hamaki" -> Track: "Adrenaline"
            addCandidate(right, cleanArt);
            addCandidate(right, left);
          } else if (rightMatchesArtist) {
            // e.g. "Adrenaline - Hamaki" with artist "Mohamed Hamaki" -> Track: "Adrenaline"
            addCandidate(left, cleanArt);
            addCandidate(left, right);
          } else {
            // YouTube standard "Artist - Title" even if channel is a publisher/label (Rotana, Mazzika, etc.)
            addCandidate(right, left);
            addCandidate(right, cleanArt);
            addCandidate(left, cleanArt);
          }
        }
      }

      // Check if segment starts with clean artist name
      if (cleanArt.isNotEmpty) {
        final escaped = RegExp.escape(cleanArt);
        final stripped = seg.replaceAll(
            RegExp('^\\s*$escaped\\s*[-–—:]?\\s*', caseSensitive: false), '');
        if (stripped.isNotEmpty && stripped != seg) {
          addCandidate(stripped, cleanArt);
        }
      }

      // Segment itself as candidate
      addCandidate(seg, cleanArt);
    }

    if (candidates.isEmpty) {
      addCandidate(trackName, cleanArt);
    }

    return candidates;
  }

  String _stripVideoNoise(String text) {
    var cleaned = text;

    // Strip common YouTube / release clutter inside brackets/parentheses
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*[\(\[\{].*?(official|video|audio|mv|lyrics|lyric|remix|version|hq|hd|4k|explicit|clean|visualizer|clip|حفل|كليب|فيديو|موسيقى|جلسة|لايف|بث|مهرجان).*?[\)\]\}]',
        caseSensitive: false,
      ),
      '',
    );

    // Strip trailing "- Official Video", etc.
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*-\s*(official|video|audio|mv|lyrics|lyric|remix|version|visualizer|clip|فيديو|كليب|حفل).*',
        caseSensitive: false,
      ),
      '',
    );

    // Strip standalone keywords
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(official\s+video|official\s+audio|lyric\s+video|4k|hd|hq)\b', caseSensitive: false),
      '',
    );

    // Strip common YouTube "feat." or "ft." in brackets or standalone
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*[\(\[\{]?\s*(feat\.|ft\.|with)\s+.*?[\)\]\}]?', caseSensitive: false),
      '',
    );

    // Strip remaining generic Arabic video labels
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*(فيديو كليب|حفل|مهرجان|جلسة|سهرة|كوكتيل|ميكس|حصري|حصرى).*', caseSensitive: false),
      '',
    );

    return cleaned.trim();
  }

  String _cleanArtist(String artist) {
    return artist
        .replaceAll(
          RegExp(r'\s*[\(\[\{].*?(topic|vevo).*?[\)\]\}]', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s*-\s*Topic', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*Vevo', caseSensitive: false), '')
        .trim();
  }

  Future<LyricsResult?> _tryGetLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
  }) async {
    try {
      final queryParams = <String, String>{
        'track_name': trackName,
        'artist_name': artistName,
      };
      if (albumName != null && albumName.isNotEmpty) {
        queryParams['album_name'] = albumName;
      }
      if (durationSeconds != null && durationSeconds > 0) {
        queryParams['duration'] = durationSeconds.toString();
      }

      final uri = Uri.https('lrclib.net', '/api/get', queryParams);
      final request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader,
          'PulsrMusic/1.0.0 (https://github.com/pulsr)');
      final response =
          await request.close().timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        return _extractLyricsFromJson(json);
      } else {
        await response.drain();
      }
    } catch (e) {
      ErrorLogger.log('LRCLIB get query skipped: $e', category: 'LRCLIB');
    }
    return null;
  }

  Future<LyricsResult?> _trySearchLyrics({required String query}) async {
    try {
      final uri = Uri.https('lrclib.net', '/api/search', {'q': query});
      final request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader,
          'PulsrMusic/1.0.0 (https://github.com/pulsr)');
      final response =
          await request.close().timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final list = jsonDecode(responseBody);
        if (list is List && list.isNotEmpty) {
          // Pass 1: Prioritize synced lyrics
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final synced = item['syncedLyrics'] as String?;
              if (synced != null && synced.trim().isNotEmpty) {
                final res = _extractLyricsFromJson(item);
                if (res != null && res.lines.isNotEmpty) return res;
              }
            }
          }
          // Pass 2: Fallback to plain lyrics
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final res = _extractLyricsFromJson(item);
              if (res != null && res.lines.isNotEmpty) return res;
            }
          }
        }
      } else {
        await response.drain();
      }
    } catch (e) {
      ErrorLogger.log('LRCLIB search query skipped: $e', category: 'LRCLIB');
    }
    return null;
  }

  LyricsResult? _extractLyricsFromJson(Map<String, dynamic> json) {
    final syncedLyrics = json['syncedLyrics'] as String?;
    final plainLyrics = json['plainLyrics'] as String?;

    if (syncedLyrics != null && syncedLyrics.trim().isNotEmpty) {
      final lines = LrcParser.parse(syncedLyrics, source: LyricsSource.lrclib);
      if (lines.isNotEmpty) {
        return LyricsResult(lines: lines, source: LyricsSource.lrclib);
      }
    }

    if (plainLyrics != null && plainLyrics.trim().isNotEmpty) {
      final lines =
          LrcParser.parsePlainText(plainLyrics, source: LyricsSource.lrclib);
      if (lines.isNotEmpty) {
        return LyricsResult(lines: lines, source: LyricsSource.lrclib);
      }
    }
    return null;
  }
}

