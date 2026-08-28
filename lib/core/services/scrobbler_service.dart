import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/channels.dart';
import '../utils/error_logger.dart';

@singleton
class ScrobblerService {
  static const MethodChannel _channel = MethodChannel(PulsrChannels.scrobbler);
  final http.Client _httpClient;
  final FlutterSecureStorage _secureStorage;

  ScrobblerService(
      [http.Client? httpClient, FlutterSecureStorage? secureStorage])
      : _httpClient = httpClient ?? http.Client(),
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                // ignore: deprecated_member_use
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  static const String keyLastFmApiKey = 'setting_lastfm_api_key';
  static const String keyLastFmSecret = 'setting_lastfm_secret';
  static const String keyLastFmSessionKey = 'setting_lastfm_session_key';
  static const String keyLastFmEnabled = 'setting_lastfm_enabled';

  static const String keyLibreFmSessionKey = 'setting_librefm_session_key';
  static const String keyLibreFmEnabled = 'setting_librefm_enabled';

  static const String keyCustomWebhookUrl = 'setting_custom_scrobbler_url';
  static const String keyCustomWebhookEnabled =
      'setting_custom_scrobbler_enabled';

  static const String keyListenBrainzToken = 'setting_listenbrainz_token';
  static const String keyListenBrainzEnabled = 'setting_listenbrainz_enabled';

  static const String keyLastFmApiKeySecure = 'lastfm_api_key_secure';
  static const String keyLastFmSecretSecure = 'lastfm_secret_secure';
  static const String keyLastFmSessionKeySecure = 'lastfm_session_key_secure';
  static const String keyLibreFmSessionKeySecure = 'librefm_session_key_secure';
  static const String keyListenBrainzTokenSecure = 'listenbrainz_token_secure';

  Future<String?> _getSecureOrMigrate(
      String secureKey, String legacyKey) async {
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
          final verifyVal = await _secureStorage.read(key: secureKey);
          if (verifyVal == legacyVal) {
            await prefs.remove(legacyKey);
          }
        } catch (_) {}
        return legacyVal;
      }
    } catch (_) {}
    return null;
  }

  static const String _keyLastScrobbleSong = 'scrobbler_last_song';
  static const String _keyLastScrobbleTime = 'scrobbler_last_time';
  static const String _keyLastScrobblePos = 'scrobbler_last_position';
  static const String _keyLastScrobbleArtist = 'scrobbler_last_artist';
  static const String _keyLastScrobbleTrack = 'scrobbler_last_track';
  static const String _keyLastScrobbleAlbum = 'scrobbler_last_album';
  static const String _keyLastScrobbleDuration = 'scrobbler_last_duration';
  static const String _keyOfflineQueue = 'scrobbler_offline_queue';

  int? _lastScrobbledTrackId;
  int? _nowPlayingTrackId;
  DateTime? _trackStartTime;
  final Map<String, DateTime> _lastScrobblePerService = {};
  bool _isFlushing = false;

  bool _canScrobbleService(String service) {
    final last = _lastScrobblePerService[service];
    if (last == null) return true;
    return DateTime.now().difference(last) >= const Duration(seconds: 30);
  }

  /// Checks for pending scrobble from previous session when app was terminated
  Future<void> checkPendingScrobble() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastId = prefs.getInt(_keyLastScrobbleSong);
      final lastTime = prefs.getInt(_keyLastScrobbleTime);
      final lastPos = prefs.getInt(_keyLastScrobblePos) ?? 0;
      final duration = prefs.getInt(_keyLastScrobbleDuration) ?? 0;
      final artist = prefs.getString(_keyLastScrobbleArtist);
      final track = prefs.getString(_keyLastScrobbleTrack);
      final album = prefs.getString(_keyLastScrobbleAlbum) ?? '';

      if (lastId != null &&
          lastTime != null &&
          artist != null &&
          track != null &&
          duration > 0) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - lastTime;
        final isThresholdReached = (lastPos >= 240000) ||
            (duration > 0 && (lastPos / duration) >= 0.5);

        if (isThresholdReached && elapsed < 86400000) {
          final lastScrobbledKey = prefs.getString('last_scrobble_key');
          final lastScrobbledTime = prefs.getInt('last_scrobble_time') ??
              prefs.getInt('last_scrobbled_timestamp') ??
              0;
          final pendingKey = '${artist}_$track';
          final isDuplicate = (lastScrobbledKey == pendingKey) &&
              (DateTime.now().millisecondsSinceEpoch - lastScrobbledTime <
                  300000);

          if (!isDuplicate) {
            final timestamp = DateTime.fromMillisecondsSinceEpoch(lastTime);
            await _submitScrobble(
              artist: artist,
              track: track,
              album: album,
              durationSec: (duration / 1000).round(),
              timestamp: timestamp,
            );
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            await prefs.setString('last_scrobble_key', pendingKey);
            await prefs.setInt('last_scrobble_time', nowMs);
            await prefs.setInt('last_scrobbled_id', lastId);
            await prefs.setInt('last_scrobbled_timestamp', nowMs);
          }
        }
      }

      await prefs.remove(_keyLastScrobbleSong);
      await prefs.remove(_keyLastScrobbleTime);
      await prefs.remove(_keyLastScrobblePos);
      await prefs.remove(_keyLastScrobbleArtist);
      await prefs.remove(_keyLastScrobbleTrack);
      await prefs.remove(_keyLastScrobbleAlbum);
      await prefs.remove(_keyLastScrobbleDuration);

      await flushOfflineQueue();
    } catch (e, st) {
      ErrorLogger.log('Failed checking pending scrobble from previous session',
          error: e, stackTrace: st, category: 'Scrobbler');
    }
  }

  /// Broadcasts playback state to both native Android scrobbler apps and direct REST APIs.
  Future<void> notifyPlaybackState({
    required int id,
    required String artist,
    required String track,
    required String album,
    required int durationMs,
    required int positionMs,
    required bool isPlaying,
    String? artworkUrl,
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
      ErrorLogger.log('Failed to broadcast scrobble intent: $e',
          category: 'Scrobbler');
    }

    // 2. Direct REST Scrobbler Logic
    try {
      if (artist.isEmpty || track.isEmpty || durationMs < 30000) {
        return; // Skip tracks < 30s
      }

      if (_nowPlayingTrackId != id && isPlaying) {
        _nowPlayingTrackId = id;
        _trackStartTime = DateTime.now();
        _lastScrobbledTrackId = null;

        // Persist session state for crash / kill recovery
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_keyLastScrobbleSong, id);
          await prefs.setInt(
              _keyLastScrobbleTime, DateTime.now().millisecondsSinceEpoch);
          await prefs.setInt(_keyLastScrobblePos, positionMs);
          await prefs.setInt(_keyLastScrobbleDuration, durationMs);
          await prefs.setString(_keyLastScrobbleArtist, artist);
          await prefs.setString(_keyLastScrobbleTrack, track);
          await prefs.setString(_keyLastScrobbleAlbum, album);
        } catch (_) {}

        // Send "Now Playing" update
        await _updateNowPlaying(
          artist: artist,
          track: track,
          album: album,
          durationSec: (durationMs / 1000).round(),
        );
      }

      if (isPlaying) {
        // Update last played position periodically
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_keyLastScrobblePos, positionMs);
        } catch (_) {}
      }

      // Check scrobble threshold (played >50% of duration or >4 minutes (240s))
      final playedSec = (positionMs / 1000).round();
      final totalSec = (durationMs / 1000).round();

      // Minimum 30 seconds of actual playback OR 80% of track (whichever is less)
      final minimumPlayback = totalSec < 60 ? totalSec * 0.8 : 30;
      if (playedSec < minimumPlayback) return;

      final isThresholdReached = playedSec >= 240 ||
          (totalSec > 0 && (positionMs / durationMs) >= 0.5);

      if (isPlaying && isThresholdReached && _lastScrobbledTrackId != id) {
        _lastScrobbledTrackId = id;
        final timestamp = _trackStartTime ??
            DateTime.now().subtract(Duration(milliseconds: positionMs));

        await _submitScrobble(
          artist: artist,
          track: track,
          album: album,
          durationSec: totalSec,
          timestamp: timestamp,
          artworkUrl: artworkUrl,
        );

        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('last_scrobbled_id', id);
          await prefs.setInt(
              'last_scrobble_time', DateTime.now().millisecondsSinceEpoch);
          // Clear active session since track scrobbled
          await prefs.remove(_keyLastScrobbleSong);
        } catch (_) {}
      }
    } catch (e, st) {
      ErrorLogger.log('Error during REST scrobbling: $e',
          error: e, stackTrace: st, category: 'Scrobbler');
    }
  }

  Future<void> _updateNowPlaying({
    required String artist,
    required String track,
    required String album,
    required int durationSec,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Last.fm Now Playing
    if (prefs.getBool(keyLastFmEnabled) == true) {
      final apiKey =
          await _getSecureOrMigrate(keyLastFmApiKeySecure, keyLastFmApiKey);
      final secret =
          await _getSecureOrMigrate(keyLastFmSecretSecure, keyLastFmSecret);
      final sessionKey = await _getSecureOrMigrate(
          keyLastFmSessionKeySecure, keyLastFmSessionKey);

      if (apiKey != null &&
          secret != null &&
          sessionKey != null &&
          apiKey.isNotEmpty &&
          sessionKey.isNotEmpty) {
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
          await _httpClient
              .post(
                Uri.parse('https://ws.audioscrobbler.com/2.0/'),
                body: params,
              )
              .timeout(const Duration(seconds: 8));
        } catch (_) {}
      }
    }

    // 2. ListenBrainz Playing Now
    if (prefs.getBool(keyListenBrainzEnabled) == true) {
      final token = await _getSecureOrMigrate(
          keyListenBrainzTokenSecure, keyListenBrainzToken);
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
          await _httpClient
              .post(
                Uri.parse('https://api.listenbrainz.org/1/submit-listens'),
                headers: {
                  'Authorization': 'Token $token',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 8));
        } catch (_) {}
      }
    }
  }

  Future<bool> _postWithRetry(Uri url,
      {Map<String, String>? headers, Object? body, int maxAttempts = 3}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final resp = await _httpClient
            .post(url, headers: headers, body: body)
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          return true;
        } else if (resp.statusCode == 429 || resp.statusCode >= 500) {
          if (attempt == maxAttempts) return false;
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        } else if (resp.statusCode >= 400 && resp.statusCode < 500) {
          return false;
        }
      } catch (e) {
        if (attempt == maxAttempts) return false;
        await Future.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
    return false;
  }

  Future<void> _enqueueOfflineScrobble({
    required String artist,
    required String track,
    required String album,
    required int durationSec,
    required DateTime timestamp,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString(_keyOfflineQueue);
      final list = <Map<String, dynamic>>[];
      if (queueJson != null && queueJson.isNotEmpty) {
        final decoded = jsonDecode(queueJson) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) list.add(item);
        }
      }
      list.add({
        'artist': artist,
        'track': track,
        'album': album,
        'durationSec': durationSec,
        'timestamp': timestamp.millisecondsSinceEpoch,
      });
      final trimmed =
          list.length > 200 ? list.sublist(list.length - 200) : list;
      await prefs.setString(_keyOfflineQueue, jsonEncode(trimmed));
    } catch (_) {}
  }

  Future<void> _submitScrobble({
    required String artist,
    required String track,
    required String album,
    required int durationSec,
    required DateTime timestamp,
    String? artworkUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Deduplication check
    final dedupKey = '${artist}_$track';
    final lastScrobbledKey = prefs.getString('last_scrobble_key');
    final lastScrobbledTime = prefs.getInt('last_scrobble_time') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (lastScrobbledKey == dedupKey && (now - lastScrobbledTime) < 300000) {
      return; // Already scrobbled within 5 minutes
    }

    bool anyFailure = false;

    // 1. Last.fm Scrobble
    if (prefs.getBool(keyLastFmEnabled) == true) {
      if (!_canScrobbleService('lastfm')) {
        await _enqueueOfflineScrobble(
            artist: artist,
            track: track,
            album: album,
            durationSec: durationSec,
            timestamp: timestamp);
      } else {
        final apiKey =
            await _getSecureOrMigrate(keyLastFmApiKeySecure, keyLastFmApiKey);
        final secret =
            await _getSecureOrMigrate(keyLastFmSecretSecure, keyLastFmSecret);
        final sessionKey = await _getSecureOrMigrate(
            keyLastFmSessionKeySecure, keyLastFmSessionKey);

        if (apiKey != null &&
            secret != null &&
            sessionKey != null &&
            apiKey.isNotEmpty &&
            sessionKey.isNotEmpty) {
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

          final ok = await _postWithRetry(
            Uri.parse('https://ws.audioscrobbler.com/2.0/'),
            body: params,
          );
          if (ok) {
            _lastScrobblePerService['lastfm'] = DateTime.now();
          } else {
            anyFailure = true;
          }
        }
      }
    }

    // 2. Libre.fm Scrobble
    if (prefs.getBool(keyLibreFmEnabled) == true) {
      if (!_canScrobbleService('librefm')) {
        await _enqueueOfflineScrobble(
            artist: artist,
            track: track,
            album: album,
            durationSec: durationSec,
            timestamp: timestamp);
      } else {
        final sessionKey = await _getSecureOrMigrate(
            keyLibreFmSessionKeySecure, keyLibreFmSessionKey);
        if (sessionKey != null && sessionKey.isNotEmpty) {
          final params = <String, String>{
            'method': 'track.scrobble',
            'artist': artist,
            'track': track,
            if (album.isNotEmpty) 'album': album,
            'duration': durationSec.toString(),
            'timestamp': (timestamp.millisecondsSinceEpoch ~/ 1000).toString(),
            'sk': sessionKey,
            'format': 'json',
          };
          final ok = await _postWithRetry(
            Uri.parse('https://libre.fm/2.0/'),
            body: params,
          );
          if (ok) {
            _lastScrobblePerService['librefm'] = DateTime.now();
          } else {
            anyFailure = true;
          }
        }
      }
    }

    // 3. Custom Webhook Scrobble
    if (prefs.getBool(keyCustomWebhookEnabled) == true) {
      if (!_canScrobbleService('webhook')) {
        await _enqueueOfflineScrobble(
            artist: artist,
            track: track,
            album: album,
            durationSec: durationSec,
            timestamp: timestamp);
      } else {
        final webhookUrl = prefs.getString(keyCustomWebhookUrl);
        if (webhookUrl != null && webhookUrl.isNotEmpty) {
          final ok = await _postWithRetry(
            Uri.parse(webhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'event': 'scrobble',
              'artist': artist,
              'track': track,
              'album': album,
              'durationSec': durationSec,
              'timestamp': timestamp.toIso8601String(),
              'artworkUrl': artworkUrl,
            }),
          );
          if (ok) {
            _lastScrobblePerService['webhook'] = DateTime.now();
          } else {
            anyFailure = true;
          }
        }
      }
    }

    // 4. ListenBrainz Single Listen Scrobble
    if (prefs.getBool(keyListenBrainzEnabled) == true) {
      if (!_canScrobbleService('listenbrainz')) {
        await _enqueueOfflineScrobble(
            artist: artist,
            track: track,
            album: album,
            durationSec: durationSec,
            timestamp: timestamp);
      } else {
        final token = await _getSecureOrMigrate(
            keyListenBrainzTokenSecure, keyListenBrainzToken);
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

          final ok = await _postWithRetry(
            Uri.parse('https://api.listenbrainz.org/1/submit-listens'),
            headers: {
              'Authorization': 'Token $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          );
          if (ok) {
            _lastScrobblePerService['listenbrainz'] = DateTime.now();
          } else {
            anyFailure = true;
          }
        }
      }
    }

    if (anyFailure) {
      await _enqueueOfflineScrobble(
        artist: artist,
        track: track,
        album: album,
        durationSec: durationSec,
        timestamp: timestamp,
      );
    } else {
      await prefs.setString('last_scrobble_key', dedupKey);
      await prefs.setInt('last_scrobble_time', now);
      await prefs.setInt('last_scrobbled_timestamp', now);
    }
  }

  Future<void> flushOfflineQueue() async {
    if (_isFlushing) return;
    _isFlushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString(_keyOfflineQueue);
      if (queueJson == null || queueJson.isEmpty) return;

      final List<dynamic> list = jsonDecode(queueJson);
      final remaining = <Map<String, dynamic>>[];
      const batchSize = 5;

      for (int i = 0; i < list.length; i += batchSize) {
        final end = (i + batchSize < list.length) ? i + batchSize : list.length;
        final batch = list.sublist(i, end);

        final results = await Future.wait(batch.map((item) async {
          if (item is! Map<String, dynamic>) return null;
          final artist = item['artist'] as String?;
          final track = item['track'] as String?;
          final album = item['album'] as String? ?? '';
          final durationSec = item['durationSec'] as int? ?? 0;
          final tsMillis = item['timestamp'] as int? ??
              DateTime.now().millisecondsSinceEpoch;

          if (artist != null && track != null) {
            try {
              await _submitScrobbleDirect(
                artist: artist,
                track: track,
                album: album,
                durationSec: durationSec,
                timestamp: DateTime.fromMillisecondsSinceEpoch(tsMillis),
              );
              return null;
            } catch (_) {
              return item;
            }
          }
          return null;
        }));

        for (final failed in results) {
          if (failed != null) remaining.add(failed);
        }

        if (end < list.length) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      if (remaining.isEmpty) {
        await prefs.remove(_keyOfflineQueue);
      } else {
        await prefs.setString(_keyOfflineQueue, jsonEncode(remaining));
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to flush offline scrobble queue',
          error: e, stackTrace: st, category: 'Scrobbler');
    } finally {
      _isFlushing = false;
    }
  }

  String _generateLastFmSignature(Map<String, String> params, String secret) {
    final sortedKeys = params.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final key in sortedKeys) {
      if (key == 'format' || key == 'api_sig' || key == 'callback') continue;
      buffer.write(key);
      buffer.write(params[key]);
    }
    buffer.write(secret);
    return md5.convert(utf8.encode(buffer.toString())).toString();
  }

  /// Submit scrobble without re-enqueueing on failure (used by flushOfflineQueue).
  Future<void> _submitScrobbleDirect({
    required String artist,
    required String track,
    required String album,
    required int durationSec,
    required DateTime timestamp,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final dedupKey = '${artist}_$track';
    final lastScrobbledKey = prefs.getString('last_scrobble_key');
    final lastScrobbledTime = prefs.getInt('last_scrobble_time') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (lastScrobbledKey == dedupKey && (now - lastScrobbledTime) < 300000) {
      return;
    }

    bool anySuccess = false;

    if (prefs.getBool(keyLastFmEnabled) == true) {
      final apiKey =
          await _getSecureOrMigrate(keyLastFmApiKeySecure, keyLastFmApiKey);
      final secret =
          await _getSecureOrMigrate(keyLastFmSecretSecure, keyLastFmSecret);
      final sessionKey = await _getSecureOrMigrate(
          keyLastFmSessionKeySecure, keyLastFmSessionKey);

      if (apiKey != null &&
          secret != null &&
          sessionKey != null &&
          apiKey.isNotEmpty &&
          sessionKey.isNotEmpty) {
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
        if (await _postWithRetry(
            Uri.parse('https://ws.audioscrobbler.com/2.0/'),
            body: params)) {
          anySuccess = true;
        }
      }
    }

    if (prefs.getBool(keyListenBrainzEnabled) == true) {
      final token = await _getSecureOrMigrate(
          keyListenBrainzTokenSecure, keyListenBrainzToken);
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
                  'duration_ms': durationSec * 1000
                },
              },
            }
          ],
        };
        if (await _postWithRetry(
          Uri.parse('https://api.listenbrainz.org/1/submit-listens'),
          headers: {
            'Authorization': 'Token $token',
            'Content-Type': 'application/json'
          },
          body: jsonEncode(payload),
        )) {
          anySuccess = true;
        }
      }
    }

    if (anySuccess) {
      await prefs.setString('last_scrobble_key', dedupKey);
      await prefs.setInt('last_scrobble_time', now);
    }
  }
}
