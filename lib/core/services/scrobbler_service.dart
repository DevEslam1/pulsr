import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../constants/channels.dart';
import '../constants/prefs_keys.dart';
import '../network/remote_target_policy.dart';
import '../utils/error_logger.dart';
import '../utils/ytm_rate_limiter.dart';

@lazySingleton
class ScrobblerService {
  static const MethodChannel _channel = MethodChannel(PulsrChannels.scrobbler);
  final http.Client _httpClient;
  final bool _ownsClient;
  final FlutterSecureStorage _secureStorage;

  ScrobblerService(
      [http.Client? httpClient, FlutterSecureStorage? secureStorage])
      : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  @disposeMethod
  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  static const String keyLastFmApiKey = 'setting_lastfm_api_key';
  static const String keyLastFmSecret = 'setting_lastfm_secret';
  static const String keyLastFmSessionKey = 'setting_lastfm_session_key';
  static const String keyLastFmEnabled = 'setting_lastfm_enabled';

  static const String keyLibreFmApiKey = 'setting_librefm_api_key';
  static const String keyLibreFmSecret = 'setting_librefm_secret';
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
  static const String keyLibreFmApiKeySecure = 'librefm_api_key_secure';
  static const String keyLibreFmSecretSecure = 'librefm_secret_secure';
  static const String keyLibreFmSessionKeySecure = 'librefm_session_key_secure';
  static const String keyListenBrainzTokenSecure = 'listenbrainz_token_secure';

  Future<String?> _getSecureOrMigrate(
      String secureKey, String legacyKey) async {
    try {
      final val = await _secureStorage.read(key: secureKey);
      if (val != null && val.isNotEmpty) {
        // Single credential store (defect 23-01): best-effort wipe of any
        // leftover plaintext copy whenever the secure copy is authoritative.
        try {
          final prefs = await _getPrefs();
          await prefs.remove(legacyKey);
        } catch (_) {
          ErrorLogger.addBreadcrumb('Legacy credential wipe skipped',
              category: 'Scrobbler');
        }
        return val;
      }
    } catch (_) {
      ErrorLogger.addBreadcrumb('Secure credential read skipped',
          category: 'Scrobbler');
    }
    try {
      final prefs = await _getPrefs();
      final legacyVal = prefs.getString(legacyKey)?.trim();
      if (legacyVal != null && legacyVal.isNotEmpty) {
        try {
          await _secureStorage.write(key: secureKey, value: legacyVal);
          final verifyVal = await _secureStorage.read(key: secureKey);
          if (verifyVal == legacyVal) {
            await prefs.remove(legacyKey);
          }
        } catch (_) {
          ErrorLogger.addBreadcrumb('Credential migration verify skipped',
              category: 'Scrobbler');
        }
        return legacyVal;
      }
    } catch (_) {
      ErrorLogger.addBreadcrumb('Legacy credential read skipped',
          category: 'Scrobbler');
    }
    return null;
  }

  /// Proactively migrates every known plaintext credential into secure storage
  /// and wipes the prefs copies. Call once at startup. Single store (23-01).
  Future<void> migrateAllCredentialsToSecureStorage() async {
    const pairs = [
      (keyLastFmApiKeySecure, keyLastFmApiKey),
      (keyLastFmSecretSecure, keyLastFmSecret),
      (keyLastFmSessionKeySecure, keyLastFmSessionKey),
      (keyLibreFmApiKeySecure, keyLibreFmApiKey),
      (keyLibreFmSecretSecure, keyLibreFmSecret),
      (keyLibreFmSessionKeySecure, keyLibreFmSessionKey),
      (keyListenBrainzTokenSecure, keyListenBrainzToken),
    ];
    for (final pair in pairs) {
      try {
        await _getSecureOrMigrate(pair.$1, pair.$2);
      } catch (e, st) {
        ErrorLogger.log('Scrobbler credential migration failed for ${pair.$2}',
            error: e, stackTrace: st, category: 'Scrobbler');
      }
    }
  }

  // Key strings intentionally mirror PrefsKeys values (raw literals): the
  // settings-wiring ratchet accepts raw-string sites, and keeping the exact
  // historical values here guarantees existing installs keep pending state.
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
  int? _lastPositionMs;
  DateTime? _trackStartTime;
  final Map<String, DateTime> _lastScrobblePerService = {};
  static const int _maxScrobbleEntries = 10;
  bool _isFlushing = false;
  int _lastPosPersistEpochMs = 0;
  bool _lastWasPlaying = false;

  /// Serializes scrobble submissions (see [_submitScrobbleDirect]).
  final AsyncMutex _submitMutex = AsyncMutex();
  final AsyncMutex _queueMutex = AsyncMutex();
  int _enqueueEpoch = 0;

  SharedPreferences? _cachedPrefs;
  Future<SharedPreferences> _getPrefs() async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
    return _cachedPrefs!;
  }

  /// Fails closed if [PrefsKeys.offlineOnlyMode] cannot be read so offline
  /// preference or network isolation is never bypassed silently.
  Future<bool> _isNetworkAllowed() async {
    if (!AppConfig.isCloudSyncAllowed) return false;
    try {
      final prefs = await _getPrefs();
      return prefs.getBool(PrefsKeys.offlineOnlyMode) != true;
    } catch (e, st) {
      ErrorLogger.log('Scrobbler offline check failed; treating as offline',
          error: e, stackTrace: st, category: 'Scrobbler');
      return false;
    }
  }

  void _recordServiceScrobble(String service) {
    _lastScrobblePerService[service] = DateTime.now();
    if (_lastScrobblePerService.length > _maxScrobbleEntries) {
      final oldest = _lastScrobblePerService.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b);
      _lastScrobblePerService.remove(oldest.key);
    }
  }

  /// Minimum gap between submissions to the same service. Configurable for
  /// tests / power users; defaults to the Last.fm-friendly 30s.
  Duration scrobbleThrottle = const Duration(seconds: 30);

  bool _canScrobbleService(String service) {
    final last = _lastScrobblePerService[service];
    if (last == null) return true;
    return DateTime.now().difference(last) >= scrobbleThrottle;
  }

  /// Checks for pending scrobble from previous session when app was terminated
  Future<void> checkPendingScrobble() async {
    try {
      final prefs = await _getPrefs();
      if (!AppConfig.isCloudSyncAllowed) {
        await _clearPendingSessionPrefs(prefs);
        return;
      }
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
            final submitted = await _submitScrobble(
              artist: artist,
              track: track,
              album: album,
              durationSec: (duration / 1000).round(),
              timestamp: timestamp,
            );
            if (submitted) {
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              await prefs.setString('last_scrobble_key', pendingKey);
              await prefs.setInt('last_scrobble_time', nowMs);
              await prefs.setInt('last_scrobbled_id', lastId);
              await prefs.setInt('last_scrobbled_timestamp', nowMs);
            }
          }
        }
      }

      await _clearPendingSessionPrefs(prefs);
      _lastPosPersistEpochMs = 0;
      _lastWasPlaying = false;

      await flushOfflineQueue();
    } catch (e, st) {
      ErrorLogger.log('Failed checking pending scrobble from previous session',
          error: e, stackTrace: st, category: 'Scrobbler');
    }
  }

  Future<void> _clearPendingSessionPrefs(SharedPreferences prefs) async {
    await prefs.remove(_keyLastScrobbleSong);
    await prefs.remove(_keyLastScrobbleTime);
    await prefs.remove(_keyLastScrobblePos);
    await prefs.remove(_keyLastScrobbleArtist);
    await prefs.remove(_keyLastScrobbleTrack);
    await prefs.remove(_keyLastScrobbleAlbum);
    await prefs.remove(_keyLastScrobbleDuration);
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
    bool isQuran = false,
  }) async {
    // Quran recitation and Pure builds must never broadcast playback externally
    // to third-party scrobblers or REST endpoints.
    if (isQuran || !AppConfig.isCloudSyncAllowed) return;
    final isOnline = await _isNetworkAllowed();

    // 1. Android Broadcast Intent (only when online; offline playback queues REST)
    if (isOnline) {
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
    }

    // 2. Direct REST Scrobbler Logic
    try {
      if (artist.isEmpty || track.isEmpty || durationMs < 30000) {
        return; // Skip tracks < 30s
      }

      if (_nowPlayingTrackId != null && _nowPlayingTrackId != id) {
        _lastScrobbledTrackId = null;
        _lastPositionMs = null;
      }

      final restartThresholdMs =
          durationMs < 10000 ? (durationMs * 0.7).round() : 10000;
      final isTrackRestart = _nowPlayingTrackId == id &&
          isPlaying &&
          _lastPositionMs != null &&
          positionMs < 3000 &&
          _lastPositionMs! > restartThresholdMs;

      if ((_nowPlayingTrackId != id || isTrackRestart) && isPlaying) {
        _nowPlayingTrackId = id;
        _trackStartTime = DateTime.now();
        _lastScrobbledTrackId = null;

        // Persist session state for crash / kill recovery
        try {
          final prefs = await _getPrefs();
          await prefs.setInt(_keyLastScrobbleSong, id);
          await prefs.setInt(
              _keyLastScrobbleTime, DateTime.now().millisecondsSinceEpoch);
          await prefs.setInt(_keyLastScrobblePos, positionMs);
          await prefs.setInt(_keyLastScrobbleDuration, durationMs);
          await prefs.setString(_keyLastScrobbleArtist, artist);
          await prefs.setString(_keyLastScrobbleTrack, track);
          await prefs.setString(_keyLastScrobbleAlbum, album);
          _lastPosPersistEpochMs = DateTime.now().millisecondsSinceEpoch;
        } catch (_) {
          ErrorLogger.addBreadcrumb('Scrobble session persist skipped',
              category: 'Scrobbler');
        }

        // Send "Now Playing" update
        await _updateNowPlaying(
          artist: artist,
          track: track,
          album: album,
          durationSec: (durationMs / 1000).round(),
        );
      }
      _lastPositionMs = positionMs;

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final shouldPersistPos = isPlaying
          ? (nowMs - _lastPosPersistEpochMs >= 5000)
          : _lastWasPlaying; // Always persist on pause
      if (shouldPersistPos) {
        _lastPosPersistEpochMs = nowMs;
        try {
          final prefs = await _getPrefs();
          await prefs.setInt(_keyLastScrobblePos, positionMs);
        } catch (_) {
          ErrorLogger.addBreadcrumb('Scrobble position persist skipped',
              category: 'Scrobbler');
        }
      }
      _lastWasPlaying = isPlaying;

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
          final prefs = await _getPrefs();
          await prefs.setInt('last_scrobbled_id', id);
          await prefs.setInt(
              'last_scrobble_time', DateTime.now().millisecondsSinceEpoch);
          // Clear active session since track scrobbled
          await prefs.remove(_keyLastScrobbleSong);
        } catch (_) {
          ErrorLogger.addBreadcrumb('Scrobbled-id persist skipped',
              category: 'Scrobbler');
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Error during REST scrobbling: $e',
          error: e, stackTrace: st, category: 'Scrobbler');
    }
  }

  Future<({String apiKey, String secret, String sessionKey})?>
      _readAudioscrobblerCredentials({
    required String apiKeySecure,
    required String apiKeyLegacy,
    required String secretSecure,
    required String secretLegacy,
    required String sessionSecure,
    required String sessionLegacy,
  }) async {
    final apiKey = await _getSecureOrMigrate(apiKeySecure, apiKeyLegacy);
    final secret = await _getSecureOrMigrate(secretSecure, secretLegacy);
    final sessionKey = await _getSecureOrMigrate(sessionSecure, sessionLegacy);
    if (apiKey == null ||
        secret == null ||
        sessionKey == null ||
        apiKey.isEmpty ||
        secret.isEmpty ||
        sessionKey.isEmpty) {
      return null;
    }
    return (apiKey: apiKey, secret: secret, sessionKey: sessionKey);
  }

  Future<void> _postAudioscrobblerNowPlaying({
    required Uri endpoint,
    required String serviceLabel,
    required String apiKey,
    required String secret,
    required String sessionKey,
    required String artist,
    required String track,
    required String album,
    required int durationSec,
  }) async {
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
          .post(endpoint, body: params)
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      ErrorLogger.log('$serviceLabel now-playing post skipped: $e',
          category: 'Scrobbler');
    }
  }

  Future<void> _updateNowPlaying({
    required String artist,
    required String track,
    required String album,
    required int durationSec,
  }) async {
    if (!await _isNetworkAllowed()) return;
    final prefs = await _getPrefs();
    final tasks = <Future<void>>[];

    // 1. Last.fm Now Playing
    if (prefs.getBool(keyLastFmEnabled) == true) {
      final creds = await _readAudioscrobblerCredentials(
        apiKeySecure: keyLastFmApiKeySecure,
        apiKeyLegacy: keyLastFmApiKey,
        secretSecure: keyLastFmSecretSecure,
        secretLegacy: keyLastFmSecret,
        sessionSecure: keyLastFmSessionKeySecure,
        sessionLegacy: keyLastFmSessionKey,
      );
      if (creds != null) {
        tasks.add(_postAudioscrobblerNowPlaying(
          endpoint: Uri.parse('https://ws.audioscrobbler.com/2.0/'),
          serviceLabel: 'Last.fm',
          apiKey: creds.apiKey,
          secret: creds.secret,
          sessionKey: creds.sessionKey,
          artist: artist,
          track: track,
          album: album,
          durationSec: durationSec,
        ));
      }
    }

    // 2. Libre.fm Now Playing
    if (prefs.getBool(keyLibreFmEnabled) == true) {
      final creds = await _readAudioscrobblerCredentials(
        apiKeySecure: keyLibreFmApiKeySecure,
        apiKeyLegacy: keyLibreFmApiKey,
        secretSecure: keyLibreFmSecretSecure,
        secretLegacy: keyLibreFmSecret,
        sessionSecure: keyLibreFmSessionKeySecure,
        sessionLegacy: keyLibreFmSessionKey,
      );
      if (creds != null) {
        tasks.add(_postAudioscrobblerNowPlaying(
          endpoint: Uri.parse('https://libre.fm/2.0/'),
          serviceLabel: 'Libre.fm',
          apiKey: creds.apiKey,
          secret: creds.secret,
          sessionKey: creds.sessionKey,
          artist: artist,
          track: track,
          album: album,
          durationSec: durationSec,
        ));
      }
    }

    // 3. ListenBrainz Playing Now
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

        tasks.add(() async {
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
                .timeout(const Duration(seconds: 4));
          } catch (e) {
            ErrorLogger.log('ListenBrainz playing-now post skipped: $e',
                category: 'Scrobbler');
          }
        }());
      }
    }

    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
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
          final bodyTrimmed = resp.body.trimLeft();
          if (bodyTrimmed.startsWith('{')) {
            try {
              final decoded = jsonDecode(bodyTrimmed);
              if (decoded is Map && decoded.containsKey('error')) {
                final err = decoded['error'];
                if (err != null && err != 0) {
                  // Last.fm / Libre.fm transient error codes: 11 (offline),
                  // 16 (temporary), 29 (rate limit).
                  final isTransient = err == 11 || err == 16 || err == 29;
                  if (isTransient && attempt < maxAttempts) {
                    await Future.delayed(Duration(milliseconds: 500 * attempt));
                    continue;
                  }
                  ErrorLogger.log('Scrobble API returned JSON error: $err',
                      category: 'Scrobbler');
                  return false;
                }
              }
            } catch (_) {
              // Ignore non-JSON bodies on 2xx responses.
            }
          }
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

  Future<bool> _postWebhookSafe(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    int maxAttempts = 3,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        var currentUri = uri;
        bool retryable = false;
        for (var redirectCount = 0; redirectCount <= 3; redirectCount++) {
          final request = http.Request('POST', currentUri)
            ..headers.addAll(headers)
            ..body = body
            ..followRedirects = false;
          final response = await _httpClient
              .send(request)
              .timeout(const Duration(seconds: 10));

          final status = response.statusCode;
          await response.stream.listen((_) {}, onError: (_) {}).cancel();

          if (status >= 300 &&
              status < 400 &&
              response.headers.containsKey('location')) {
            if (redirectCount == 3) return false;
            final location = response.headers['location']!;
            final nextUri = currentUri.resolve(location);
            final nextUrl = nextUri.toString();
            if (!RemoteTargetPolicy.isAllowed(nextUrl)) return false;
            final isSafe = await RemoteTargetPolicy.isSafeHost(nextUri.host);
            if (!isSafe) return false;
            currentUri = nextUri;
            continue;
          }

          if (status >= 200 && status < 300) {
            return true;
          } else if (status == 429 || status >= 500) {
            retryable = true;
            break;
          } else {
            return false;
          }
        }
        if (!retryable || attempt == maxAttempts) return false;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
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
    List<String>? services,
  }) async {
    await _queueMutex.run(() async {
      try {
        _enqueueEpoch++;
        final prefs = await _getPrefs();
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
          // When set, limits later delivery to the services that still need this
          // scrobble so flushOfflineQueue can't double-send to delivered ones.
          if (services != null) 'services': services,
        });
        final trimmed =
            list.length > 200 ? list.sublist(list.length - 200) : list;
        await prefs.setString(_keyOfflineQueue, jsonEncode(trimmed));
      } catch (_) {
        ErrorLogger.addBreadcrumb('Offline scrobble queue persist skipped',
            category: 'Scrobbler');
      }
    });
  }

  Future<bool> _submitAudioscrobblerScrobble({
    required Uri endpoint,
    required String apiKey,
    required String secret,
    required String sessionKey,
    required String artist,
    required String track,
    required String album,
    required int durationSec,
    required DateTime timestamp,
  }) {
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
    return _postWithRetry(endpoint, body: params);
  }

  Future<bool> _submitScrobble({
    required String artist,
    required String track,
    required String album,
    required int durationSec,
    required DateTime timestamp,
    String? artworkUrl,
  }) {
    return _submitMutex.run(() => _submitScrobbleLocked(
          artist: artist,
          track: track,
          album: album,
          durationSec: durationSec,
          timestamp: timestamp,
          artworkUrl: artworkUrl,
        ));
  }

  Future<bool> _submitScrobbleLocked({
    required String artist,
    required String track,
    required String album,
    required int durationSec,
    required DateTime timestamp,
    String? artworkUrl,
  }) async {
    if (!AppConfig.isCloudSyncAllowed) return false;
    final prefs = await _getPrefs();
    // Offline-only mode: queue locally, never hit the network.
    if (!await _isNetworkAllowed()) {
      await _enqueueOfflineScrobble(
          artist: artist,
          track: track,
          album: album,
          durationSec: durationSec,
          timestamp: timestamp);
      return false;
    }

    // Deduplication check
    final dedupKey = '${artist}_$track';
    final lastScrobbledKey = prefs.getString('last_scrobble_key');
    final lastScrobbledTime = prefs.getInt('last_scrobble_time') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (lastScrobbledKey == dedupKey && (now - lastScrobbledTime) < 300000) {
      return false; // Already scrobbled within 5 minutes
    }

    final pending = <String>{};
    bool anySuccess = false;

    // 1. Last.fm Scrobble
    if (prefs.getBool(keyLastFmEnabled) == true) {
      if (!_canScrobbleService('lastfm')) {
        pending.add('lastfm');
      } else {
        final creds = await _readAudioscrobblerCredentials(
          apiKeySecure: keyLastFmApiKeySecure,
          apiKeyLegacy: keyLastFmApiKey,
          secretSecure: keyLastFmSecretSecure,
          secretLegacy: keyLastFmSecret,
          sessionSecure: keyLastFmSessionKeySecure,
          sessionLegacy: keyLastFmSessionKey,
        );
        if (creds != null) {
          final ok = await _submitAudioscrobblerScrobble(
            endpoint: Uri.parse('https://ws.audioscrobbler.com/2.0/'),
            apiKey: creds.apiKey,
            secret: creds.secret,
            sessionKey: creds.sessionKey,
            artist: artist,
            track: track,
            album: album,
            durationSec: durationSec,
            timestamp: timestamp,
          );
          if (ok) {
            anySuccess = true;
            _recordServiceScrobble('lastfm');
          } else {
            pending.add('lastfm');
          }
        }
      }
    }

    // 2. Libre.fm Scrobble
    if (prefs.getBool(keyLibreFmEnabled) == true) {
      if (!_canScrobbleService('librefm')) {
        pending.add('librefm');
      } else {
        final creds = await _readAudioscrobblerCredentials(
          apiKeySecure: keyLibreFmApiKeySecure,
          apiKeyLegacy: keyLibreFmApiKey,
          secretSecure: keyLibreFmSecretSecure,
          secretLegacy: keyLibreFmSecret,
          sessionSecure: keyLibreFmSessionKeySecure,
          sessionLegacy: keyLibreFmSessionKey,
        );
        if (creds != null) {
          final ok = await _submitAudioscrobblerScrobble(
            endpoint: Uri.parse('https://libre.fm/2.0/'),
            apiKey: creds.apiKey,
            secret: creds.secret,
            sessionKey: creds.sessionKey,
            artist: artist,
            track: track,
            album: album,
            durationSec: durationSec,
            timestamp: timestamp,
          );
          if (ok) {
            anySuccess = true;
            _recordServiceScrobble('librefm');
          } else {
            pending.add('librefm');
          }
        }
      }
    }

    // 3. Custom Webhook Scrobble
    if (prefs.getBool(keyCustomWebhookEnabled) == true) {
      if (!_canScrobbleService('webhook')) {
        pending.add('webhook');
      } else {
        final webhookUrl = prefs.getString(keyCustomWebhookUrl);
        if (webhookUrl != null &&
            webhookUrl.isNotEmpty &&
            RemoteTargetPolicy.isAllowed(webhookUrl)) {
          final uri = Uri.tryParse(webhookUrl);
          if (uri != null && await RemoteTargetPolicy.isSafeHost(uri.host)) {
            final ok = await _postWebhookSafe(
              uri,
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
              anySuccess = true;
              _recordServiceScrobble('webhook');
            } else {
              pending.add('webhook');
            }
          }
        }
      }
    }

    // 4. ListenBrainz Single Listen Scrobble
    if (prefs.getBool(keyListenBrainzEnabled) == true) {
      if (!_canScrobbleService('listenbrainz')) {
        pending.add('listenbrainz');
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
            anySuccess = true;
            _recordServiceScrobble('listenbrainz');
          } else {
            pending.add('listenbrainz');
          }
        }
      }
    }

    if (pending.isNotEmpty) {
      await _enqueueOfflineScrobble(
        artist: artist,
        track: track,
        album: album,
        durationSec: durationSec,
        timestamp: timestamp,
        services: pending.toList(),
      );
    }
    // Only record dedup keys when at least one remote submission actually
    // succeeded — never poison the 5-minute window when credentials are missing,
    // targets are SSRF-blocked, or all enabled services failed.
    if (anySuccess) {
      await prefs.setString('last_scrobble_key', dedupKey);
      await prefs.setInt('last_scrobble_time', now);
      await prefs.setInt('last_scrobbled_timestamp', now);
      if (pending.isEmpty) {
        await _recordSuccessfulScrobble(
            prefs, timestamp.millisecondsSinceEpoch);
      }
    }
    return anySuccess;
  }

  static const String keyTotalScrobbleCount = 'total_scrobble_count';
  static const String keyDailyScrobbleLog = 'scrobble_daily_log';

  Future<void> _recordSuccessfulScrobble(SharedPreferences prefs,
      [int? timestampMs]) async {
    try {
      final total = (prefs.getInt(keyTotalScrobbleCount) ?? 0) + 1;
      await prefs.setInt(keyTotalScrobbleCount, total);

      final date = DateTime.fromMillisecondsSinceEpoch(
          timestampMs ?? DateTime.now().millisecondsSinceEpoch);
      final dateKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      Map<String, dynamic> dailyLog = {};
      final raw = prefs.getString(keyDailyScrobbleLog);
      if (raw != null && raw.isNotEmpty) {
        try {
          dailyLog = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        } catch (_) {
          ErrorLogger.addBreadcrumb('Corrupt daily scrobble log reset',
              category: 'Scrobbler');
        }
      }
      dailyLog[dateKey] = ((dailyLog[dateKey] as int?) ?? 0) + 1;

      // Keep only last 30 days to keep SharedPreferences clean
      if (dailyLog.length > 30) {
        final sortedKeys = dailyLog.keys.toList()..sort();
        while (sortedKeys.length > 30) {
          final oldest = sortedKeys.removeAt(0);
          dailyLog.remove(oldest);
        }
      }
      await prefs.setString(keyDailyScrobbleLog, jsonEncode(dailyLog));
    } catch (e) {
      ErrorLogger.log('Daily scrobble stats persist skipped: $e',
          category: 'Scrobbler');
    }
  }

  Future<void> flushOfflineQueue() async {
    if (_isFlushing) return;
    _isFlushing = true;
    try {
      // Offline-only mode (and Pure builds): keep the queue stored, never hit
      // the network.
      if (!await _isNetworkAllowed()) {
        return;
      }
      final prefs = await _getPrefs();
      late List<dynamic> list;
      late int epochBefore;
      await _queueMutex.run(() async {
        epochBefore = _enqueueEpoch;
        final queueJson = prefs.getString(_keyOfflineQueue);
        if (queueJson == null || queueJson.isEmpty) {
          list = const [];
          return;
        }
        final decoded = jsonDecode(queueJson);
        list = decoded is List ? decoded : const [];
      });
      if (list.isEmpty) return;

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
          final rawServices = item['services'];
          final services = rawServices is List
              ? rawServices.whereType<String>().toList()
              : null;

          if (artist != null && track != null) {
            final stillPending = await _submitScrobbleDirect(
              artist: artist,
              track: track,
              album: album,
              durationSec: durationSec,
              timestamp: DateTime.fromMillisecondsSinceEpoch(tsMillis),
              requestedServices: services,
            );
            // Fully delivered (or nothing left that can receive it): drop.
            if (stillPending.isEmpty) return null;
            // Otherwise keep the entry but narrow it to the services that still
            // need it, so a later flush won't re-send to delivered ones.
            return <String, dynamic>{...item, 'services': stillPending};
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

      await _queueMutex.run(() async {
        final merged = <Map<String, dynamic>>[...remaining];
        final delta = _enqueueEpoch - epochBefore;
        if (delta > 0) {
          final latestRaw = prefs.getString(_keyOfflineQueue);
          if (latestRaw != null && latestRaw.isNotEmpty) {
            final latestDecoded = jsonDecode(latestRaw);
            if (latestDecoded is List) {
              final tailCount = delta.clamp(0, latestDecoded.length);
              final tail = latestDecoded.sublist(latestDecoded.length - tailCount);
              for (final item in tail) {
                if (item is Map<String, dynamic>) {
                  merged.add(item);
                } else if (item is Map) {
                  merged.add(Map<String, dynamic>.from(item));
                }
              }
            }
          }
        }
        final trimmed = merged.length > 200
            ? merged.sublist(merged.length - 200)
            : merged;
        if (trimmed.isEmpty) {
          await prefs.remove(_keyOfflineQueue);
        } else {
          await prefs.setString(_keyOfflineQueue, jsonEncode(trimmed));
        }
      });
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

  /// Submits a queued scrobble to the services that still need it, without
  /// re-enqueueing on failure (used by [flushOfflineQueue]). Returns the
  /// services STILL pending after this attempt: an empty list means the entry
  /// is fully handled (delivered, or no enabled/configured service can receive
  /// it) and may be dropped from the queue.
  ///
  /// [requestedServices] limits delivery to the services recorded on the queue
  /// entry; null targets every enabled service (legacy entries written before
  /// per-service tracking existed).
  ///
  /// Serialized: a flush batch submits in parallel, and every submission
  /// read-modifies the shared dedup keys and stats counters, so unsynchronized
  /// runs could double-count or drop dedup.
  Future<List<String>> _submitScrobbleDirect({
    required String artist,
    required String track,
    required String album,
    required int durationSec,
    required DateTime timestamp,
    List<String>? requestedServices,
  }) {
    return _submitMutex.run(() => _submitScrobbleDirectLocked(
          artist: artist,
          track: track,
          album: album,
          durationSec: durationSec,
          timestamp: timestamp,
          requestedServices: requestedServices,
        ));
  }

  Future<List<String>> _submitScrobbleDirectLocked({
    required String artist,
    required String track,
    required String album,
    required int durationSec,
    required DateTime timestamp,
    List<String>? requestedServices,
  }) async {
    final prefs = await _getPrefs();

    final dedupKey = '${artist}_$track';
    final now = DateTime.now().millisecondsSinceEpoch;

    // Legacy entries (no explicit service list) predate per-service tracking
    // and may duplicate a scrobble already delivered in real time, so keep the
    // original 5-minute dedup guard for them. Entries written with an explicit
    // service set deliver only to those services and skip this guard.
    if (requestedServices == null) {
      final lastScrobbledKey = prefs.getString('last_scrobble_key');
      final lastScrobbledTime = prefs.getInt('last_scrobble_time') ?? 0;
      if (lastScrobbledKey == dedupKey && (now - lastScrobbledTime) < 300000) {
        return const [];
      }
    }

    bool wants(String service) =>
        requestedServices == null || requestedServices.contains(service);

    final pending = <String>{};
    bool anySuccess = false;

    if (wants('lastfm') && prefs.getBool(keyLastFmEnabled) == true) {
      final creds = await _readAudioscrobblerCredentials(
        apiKeySecure: keyLastFmApiKeySecure,
        apiKeyLegacy: keyLastFmApiKey,
        secretSecure: keyLastFmSecretSecure,
        secretLegacy: keyLastFmSecret,
        sessionSecure: keyLastFmSessionKeySecure,
        sessionLegacy: keyLastFmSessionKey,
      );
      if (creds != null) {
        if (await _submitAudioscrobblerScrobble(
          endpoint: Uri.parse('https://ws.audioscrobbler.com/2.0/'),
          apiKey: creds.apiKey,
          secret: creds.secret,
          sessionKey: creds.sessionKey,
          artist: artist,
          track: track,
          album: album,
          durationSec: durationSec,
          timestamp: timestamp,
        )) {
          anySuccess = true;
        } else {
          pending.add('lastfm');
        }
      }
    }

    if (wants('librefm') && prefs.getBool(keyLibreFmEnabled) == true) {
      final creds = await _readAudioscrobblerCredentials(
        apiKeySecure: keyLibreFmApiKeySecure,
        apiKeyLegacy: keyLibreFmApiKey,
        secretSecure: keyLibreFmSecretSecure,
        secretLegacy: keyLibreFmSecret,
        sessionSecure: keyLibreFmSessionKeySecure,
        sessionLegacy: keyLibreFmSessionKey,
      );
      if (creds != null) {
        if (await _submitAudioscrobblerScrobble(
          endpoint: Uri.parse('https://libre.fm/2.0/'),
          apiKey: creds.apiKey,
          secret: creds.secret,
          sessionKey: creds.sessionKey,
          artist: artist,
          track: track,
          album: album,
          durationSec: durationSec,
          timestamp: timestamp,
        )) {
          anySuccess = true;
        } else {
          pending.add('librefm');
        }
      }
    }

    if (wants('webhook') && prefs.getBool(keyCustomWebhookEnabled) == true) {
      final webhookUrl = prefs.getString(keyCustomWebhookUrl);
      if (webhookUrl != null &&
          webhookUrl.isNotEmpty &&
          RemoteTargetPolicy.isAllowed(webhookUrl)) {
        final uri = Uri.tryParse(webhookUrl);
        if (uri != null && await RemoteTargetPolicy.isSafeHost(uri.host)) {
          if (await _postWebhookSafe(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'event': 'scrobble',
              'artist': artist,
              'track': track,
              'album': album,
              'durationSec': durationSec,
              'timestamp': timestamp.toIso8601String(),
            }),
          )) {
            anySuccess = true;
          } else {
            pending.add('webhook');
          }
        }
      }
    }

    if (wants('listenbrainz') &&
        prefs.getBool(keyListenBrainzEnabled) == true) {
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
        } else {
          pending.add('listenbrainz');
        }
      }
    }

    if (anySuccess) {
      await prefs.setString('last_scrobble_key', dedupKey);
      await prefs.setInt('last_scrobble_time', now);
      await _recordSuccessfulScrobble(prefs, timestamp.millisecondsSinceEpoch);
    }
    // Services requested but no longer enabled/configured can't receive the
    // scrobble and drop out of `pending`; only services that actively failed
    // this attempt remain, to be retried on a later flush.
    return pending.toList();
  }
}
