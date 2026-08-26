import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_logger.dart';

@singleton
class ScrobblerService {
  static const MethodChannel _channel = MethodChannel('com.pulsr.music/scrobbler');
  final http.Client _httpClient;
  final FlutterSecureStorage _secureStorage;

  ScrobblerService([http.Client? httpClient, FlutterSecureStorage? secureStorage])
      : _httpClient = httpClient ?? http.Client(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String keyLastFmApiKey = 'setting_lastfm_api_key';
  static const String keyLastFmSecret = 'setting_lastfm_secret';
  static const String keyLastFmSessionKey = 'setting_lastfm_session_key';
  static const String keyLastFmEnabled = 'setting_lastfm_enabled';

  static const String keyListenBrainzToken = 'setting_listenbrainz_token';
  static const String keyListenBrainzEnabled = 'setting_listenbrainz_enabled';

  static const String keyLastFmApiKeySecure = 'lastfm_api_key_secure';
  static const String keyLastFmSecretSecure = 'lastfm_secret_secure';
  static const String keyLastFmSessionKeySecure = 'lastfm_session_key_secure';
  static const String keyListenBrainzTokenSecure = 'listenbrainz_token_secure';

  Future<String?> _getSecureOrMigrate(String secureKey, String legacyKey) async {
    try {
      final val = await _secureStorage.read(key: secureKey);
      if (val != null && val.isNotEmpty) return val;
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyVal = prefs.getString(legacyKey)?.trim();
      if (legacyVal != null && legacyVal.isNotEmpty) {
        try {
          await _secureStorage.write(key: secureKey, value: legacyVal);
          await prefs.remove(legacyKey);
        } catch (_) {}
        return legacyVal;
      }
    } catch (_) {}
    return null;
  }

  int? _lastScrobbledTrackId;
  int? _nowPlayingTrackId;
  DateTime? _trackStartTime;

  /// Broadcasts playback state to both native Android scrobbler apps (Pano Scrobbler, Simple Last.fm)
  /// and direct REST APIs (Last.fm & ListenBrainz).
  Future<void> notifyPlaybackState({
    required int id,
    required String artist,
    required String track,
    required String album,
    required int durationMs,
    required int positionMs,
    required bool isPlaying,
  }) async {
    // 1. Android Broadcast Intent
    try {
      await _channel.invokeMethod('broadcastPlaybackState', {
        'id': id,
        'artist': artist,
        'track': track,
        'album': album,
        'duration': durationMs,
        'position': positionMs,
        'isPlaying': isPlaying,
      });
    } catch (e) {
      ErrorLogger.log('Failed to broadcast scrobble intent: $e', category: 'Scrobbler');
    }

    // 2. Direct REST Scrobbler Logic
    try {
      if (artist.isEmpty || track.isEmpty || durationMs < 30000) return; // Skip tracks < 30s

      if (_nowPlayingTrackId != id && isPlaying) {
        _nowPlayingTrackId = id;
        _trackStartTime = DateTime.now();
        _lastScrobbledTrackId = null;

        // Send "Now Playing" update
        await _updateNowPlaying(
          artist: artist,
          track: track,
          album: album,
          durationSec: (durationMs / 1000).round(),
        );
      }

      // Check scrobble threshold (played >50% of duration or >4 minutes (240s))
      final playedSec = (positionMs / 1000).round();
      final totalSec = (durationMs / 1000).round();
      final isThresholdReached = playedSec >= 240 || (totalSec > 0 && (positionMs / durationMs) >= 0.5);

      if (isPlaying && isThresholdReached && _lastScrobbledTrackId != id) {
        _lastScrobbledTrackId = id;
        final timestamp = _trackStartTime ?? DateTime.now().subtract(Duration(milliseconds: positionMs));

        await _submitScrobble(
          artist: artist,
          track: track,
          album: album,
          durationSec: totalSec,
          timestamp: timestamp,
        );
      }
    } catch (e, st) {
      ErrorLogger.log('Error in direct REST scrobbling', error: e, stackTrace: st, category: 'Scrobbler');
    }
  }

  Future<void> _updateNowPlaying({
    required String artist,
    required String track,
    required String album,
    required int durationSec,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Last.fm Now Playing
    if (prefs.getBool(keyLastFmEnabled) == true) {
      final apiKey = await _getSecureOrMigrate(keyLastFmApiKeySecure, keyLastFmApiKey);
      final secret = await _getSecureOrMigrate(keyLastFmSecretSecure, keyLastFmSecret);
      final sessionKey = await _getSecureOrMigrate(keyLastFmSessionKeySecure, keyLastFmSessionKey);

      if (apiKey != null && secret != null && sessionKey != null && apiKey.isNotEmpty && sessionKey.isNotEmpty) {
        final params = <String, String>{
          'method': 'track.updateNowPlaying',
          'artist': artist,
          'track': track,
          if (album.isNotEmpty) 'album': album,
          'duration': durationSec.toString(),
          'api_key': apiKey,
          'sk': sessionKey,
        };
        params['api_sig'] = _generateLastFmSignature(params, secret);
        params['format'] = 'json';

        try {
          await _httpClient.post(
            Uri.parse('https://ws.audioscrobbler.com/2.0/'),
            body: params,
          ).timeout(const Duration(seconds: 8));
        } catch (_) {}
      }
    }

    // ListenBrainz Playing Now
    if (prefs.getBool(keyListenBrainzEnabled) == true) {
      final token = await _getSecureOrMigrate(keyListenBrainzTokenSecure, keyListenBrainzToken);
      if (token != null && token.isNotEmpty) {
        final payload = {
          'listen_type': 'playing_now',
          'payload': [
            {
              'track_metadata': {
                'artist_name': artist,
                'track_name': track,
                if (album.isNotEmpty) 'release_name': album,
                'additional_info': {
                  'media_player': 'Pulsr',
                  'submission_client': 'Pulsr Music',
                  'duration_ms': durationSec * 1000,
                },
              },
            }
          ],
        };

        try {
          await _httpClient.post(
            Uri.parse('https://api.listenbrainz.org/1/submit-listens'),
            headers: {
              'Authorization': 'Token $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 8));
        } catch (_) {}
      }
    }
  }

  Future<void> _submitScrobble({
    required String artist,
    required String track,
    required String album,
    required int durationSec,
    required DateTime timestamp,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Last.fm Scrobble
    if (prefs.getBool(keyLastFmEnabled) == true) {
      final apiKey = await _getSecureOrMigrate(keyLastFmApiKeySecure, keyLastFmApiKey);
      final secret = await _getSecureOrMigrate(keyLastFmSecretSecure, keyLastFmSecret);
      final sessionKey = await _getSecureOrMigrate(keyLastFmSessionKeySecure, keyLastFmSessionKey);

      if (apiKey != null && secret != null && sessionKey != null && apiKey.isNotEmpty && sessionKey.isNotEmpty) {
        final params = <String, String>{
          'method': 'track.scrobble',
          'artist': artist,
          'track': track,
          if (album.isNotEmpty) 'album': album,
          'duration': durationSec.toString(),
          'timestamp': (timestamp.millisecondsSinceEpoch ~/ 1000).toString(),
          'api_key': apiKey,
          'sk': sessionKey,
        };
        params['api_sig'] = _generateLastFmSignature(params, secret);
        params['format'] = 'json';

        try {
          await _httpClient.post(
            Uri.parse('https://ws.audioscrobbler.com/2.0/'),
            body: params,
          ).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
    }

    // ListenBrainz Single Listen Scrobble
    if (prefs.getBool(keyListenBrainzEnabled) == true) {
      final token = await _getSecureOrMigrate(keyListenBrainzTokenSecure, keyListenBrainzToken);
      if (token != null && token.isNotEmpty) {
        final payload = {
          'listen_type': 'single',
          'payload': [
            {
              'listened_at': timestamp.millisecondsSinceEpoch ~/ 1000,
              'track_metadata': {
                'artist_name': artist,
                'track_name': track,
                if (album.isNotEmpty) 'release_name': album,
                'additional_info': {
                  'media_player': 'Pulsr',
                  'submission_client': 'Pulsr Music',
                  'duration_ms': durationSec * 1000,
                },
              },
            }
          ],
        };

        try {
          await _httpClient.post(
            Uri.parse('https://api.listenbrainz.org/1/submit-listens'),
            headers: {
              'Authorization': 'Token $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
    }
  }

  String _generateLastFmSignature(Map<String, String> params, String secret) {
    final sortedKeys = params.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final key in sortedKeys) {
      if (key == 'format' || key == 'api_sig') continue;
      buffer.write(key);
      buffer.write(params[key]);
    }
    buffer.write(secret);
    return md5.convert(utf8.encode(buffer.toString())).toString();
  }
}
