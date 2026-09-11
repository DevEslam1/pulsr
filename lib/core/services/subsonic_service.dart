// lib/core/services/subsonic_service.dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../utils/error_logger.dart';
import '../config/app_config.dart';

/// Minimal read-only OpenSubsonic client (Subsonic / Jellyfin / Navidrome).
///
/// Scope is deliberate: ping + search + stream-url building only. Playback,
/// caching and offline logic stay in [MusicRepository]/download pipeline —
/// this service only proves reachability and resolves playable URLs, which is
/// the 80% Symfonium-killer (NAS streaming through Pulsr's DSP chain).
/// No persistence here; credentials live in SharedPreferences via caller.
class SubsonicSong {
  final String id;
  final String title;
  final String artist;
  final String album;
  final int? durationSecs;
  final String streamUrl;

  const SubsonicSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.streamUrl,
    this.durationSecs,
  });
}

@singleton
class SubsonicService {
  SubsonicService();

  static const _client = 'Pulsr';
  static const _apiVersion = '1.16.1';

  bool get isAllowed => AppConfig.isCloudSyncAllowed;

  String _authParams(String user, String pass) {
    // OpenSubsonic token auth: md5(password + salt).
    final salt = math.Random.secure().nextInt(1 << 31).toString();
    final token = _md5('$pass$salt');
    return 'u=${Uri.encodeComponent(user)}&t=$token&s=$salt&v=$_apiVersion&c=$_client&f=json';
  }

  // Minimal MD5 (RFC1321) to avoid adding crypto dependency for one call.
  String _md5(String input) {
    // Delegate to a compact pure-Dart implementation.
    final bytes = utf8.encode(input);
    return _Md5.hash(bytes);
  }

  Uri _uri(String base, String method, String auth) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$b/rest/$method?$auth');
  }

  /// True when server answers ping with ok status. Pure builds always false.
  Future<bool> ping({
    required String baseUrl,
    required String user,
    required String password,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!isAllowed) return false;
    try {
      final res = await http
          .get(_uri(baseUrl, 'ping', _authParams(user, password)))
          .timeout(timeout);
      if (res.statusCode != 200) return false;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final resp = json['subsonic-response'] as Map<String, dynamic>?;
      return resp?['status'] == 'ok';
    } catch (e) {
      ErrorLogger.log('Subsonic ping failed', error: e, category: 'Subsonic');
      return false;
    }
  }

  /// Read-only search (song results only). Returns stream-ready URLs.
  Future<List<SubsonicSong>> searchSongs(
    String query, {
    required String baseUrl,
    required String user,
    required String password,
    int count = 25,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!isAllowed || query.trim().isEmpty) return [];
    try {
      final auth = _authParams(user, password);
      final uri = _uri(baseUrl, 'search3', '$auth&query=${Uri.encodeComponent(query)}&songCount=$count');
      final res = await http.get(uri).timeout(timeout);
      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final resp = json['subsonic-response'] as Map<String, dynamic>?;
      if (resp?['status'] != 'ok') return [];
      final result = (resp?['searchResult3'] as Map<String, dynamic>?)?['song'];
      if (result is! List) return [];
      return [
        for (final s in result.whereType<Map<String, dynamic>>())
          SubsonicSong(
            id: '${s['id']}',
            title: '${s['title'] ?? 'Unknown'}',
            artist: '${s['artist'] ?? 'Unknown'}',
            album: '${s['album'] ?? ''}',
            durationSecs: (s['duration'] as num?)?.toInt(),
            streamUrl: _uri(baseUrl, 'stream', '$auth&id=${Uri.encodeComponent('${s['id']}')}').toString(),
          ),
      ];
    } catch (e) {
      ErrorLogger.log('Subsonic search failed', error: e, category: 'Subsonic');
      return [];
    }
  }
}

// --- Compact MD5 (public domain style, no external dep) ---
int _rotl(int x, int n) => ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF;

class _Md5 {
  static String hash(List<int> msg) {
    var msgLen = msg.length;
    var bitLen = msgLen * 8;
    final padded = List<int>.from(msg)..add(0x80);
    while ((padded.length % 64) != 56) {
      padded.add(0);
    }
    for (var i = 0; i < 8; i++) {
      padded.add((bitLen >> (8 * i)) & 0xFF);
    }
    var a0 = 0x67452301, b0 = 0xEFCDAB89, c0 = 0x98BADCFE, d0 = 0x10325476;
    const s = [
      7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
      5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
      4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
      6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ];
    const k = [
      0xD76AA478, 0xE8C7B756, 0x242070DB, 0xC1BDCEEE, 0xF57C0FAF, 0x4787C62A,
      0xA8304613, 0xFD469501, 0x698098D8, 0x8B44F7AF, 0xFFFF5BB1, 0x895CD7BE,
      0x6B901122, 0xFD987193, 0xA679438E, 0x49B40821, 0xF61E2562, 0xC040B340,
      0x265E5A51, 0xE9B6C7AA, 0xD62F105D, 0x02441453, 0xD8A1E681, 0xE7D3FBC8,
      0x21E1CDE6, 0xC33707D6, 0xF4D50D87, 0x455A14ED, 0xA9E3E905, 0xFCEFA3F8,
      0x676F02D9, 0x8D2A4C8A, 0xFFFA3942, 0x8771F681, 0x6D9D6122, 0xFDE5380C,
      0xA4BEEA44, 0x4BDECFA9, 0xF6BB4B60, 0xBEBFBC70, 0x289B7EC6, 0xEAA127FA,
      0xD4EF3085, 0x04881D05, 0xD9D4D039, 0xE6DB99E5, 0x1FA27CF8, 0xC4AC5665,
      0xF4292244, 0x432AFF97, 0xAB9423A7, 0xFC93A039, 0x655B59C3, 0x8F0CCC92,
      0xFFEFF47D, 0x85845DD1, 0x6FA87E4F, 0xFE2CE6E0, 0xA3014314, 0x4E0811A1,
      0xF7537E82, 0xBD3AF235, 0x2AD7D2BB, 0xEB86D391,
    ];
    for (var off = 0; off < padded.length; off += 64) {
      final m = List<int>.generate(16, (i) {
        final o = off + i * 4;
        return padded[o] | (padded[o + 1] << 8) | (padded[o + 2] << 16) | (padded[o + 3] << 24);
      });
      var a = a0, b = b0, c = c0, d = d0;
      for (var i = 0; i < 64; i++) {
        int f, g;
        if (i < 16) {
          f = (b & c) | ((~b) & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | ((~d) & c);
          g = (5 * i + 1) % 16;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) % 16;
        } else {
          f = c ^ (b | (~d));
          g = (7 * i) % 16;
        }
        f = (f + a + k[i] + m[g]) & 0xFFFFFFFF;
        a = d;
        d = c;
        c = b;
        b = (b + _rotl(f, s[i])) & 0xFFFFFFFF;
      }
      a0 = (a0 + a) & 0xFFFFFFFF;
      b0 = (b0 + b) & 0xFFFFFFFF;
      c0 = (c0 + c) & 0xFFFFFFFF;
      d0 = (d0 + d) & 0xFFFFFFFF;
    }
    String hex(int v) {
      final bytes = [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }
    return hex(a0) + hex(b0) + hex(c0) + hex(d0);
  }
}
