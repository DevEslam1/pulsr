import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/network/remote_target_policy.dart';
import '../../core/utils/error_logger.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/audio_quality_info.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../../features/player/cubit/player_state.dart';

/// Discord Gateway opcodes as defined by the Discord Real-time Gateway v9.
abstract class DiscordOpcode {
  static const int dispatch = 0;
  static const int heartbeat = 1;
  static const int identify = 2;
  static const int presenceUpdate = 3;
  static const int resume = 6;
  static const int reconnect = 7;
  static const int invalidSession = 9;
  static const int hello = 10;
  static const int heartbeatAck = 11;
}

/// Discord Android client super properties mimicking the official Discord Android client.
/// This prevents external asset 401s and gateway rejections.
class DiscordSuperProperties {
  static const String clientVersion = '314.13 - Stable';
  static const int clientBuildNumber = 314013;
  static const String releaseChannel = 'googleRelease';
  static const String userAgent = 'Discord-Android/314013;RNA';

  static Map<String, dynamic> createProperties({
    String? vendorId,
    String? clientUuid,
    String? launchId,
  }) {
    return {
      'os': 'Android',
      'browser': 'Discord Android',
      'device': 'Generic Android Device',
      'system_locale': 'en-US',
      'client_version': clientVersion,
      'release_channel': releaseChannel,
      'device_vendor_id': vendorId ?? '3a87fbb0-4d98-4c12-921a-6df2b672cb7b',
      'client_uuid': clientUuid ?? '6a27e31c-d784-469b-8255-bfadfc821c33',
      'client_launch_id': launchId ?? '8b417e04-d531-4876-b659-1e35a092823a',
      'os_version': '14',
      'os_sdk_version': '34',
      'client_build_number': clientBuildNumber,
      'client_event_source': null,
      'design_id': 0,
    };
  }

  static String getBase64() {
    final jsonStr = jsonEncode(createProperties());
    return base64.encode(utf8.encode(jsonStr));
  }
}

/// Represents the authenticated Discord user.
class DiscordUser {
  final String id;
  final String username;
  final String globalName;
  final String? avatarUrl;

  const DiscordUser({
    required this.id,
    required this.username,
    required this.globalName,
    this.avatarUrl,
  });

  factory DiscordUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final username = json['username'] as String? ?? '';
    final globalName = (json['global_name'] as String?) ?? username;
    final avatarHash = json['avatar'] as String?;
    final avatarUrl = (avatarHash != null && avatarHash.isNotEmpty)
        ? 'https://cdn.discordapp.com/avatars/$id/$avatarHash.png'
        : null;
    return DiscordUser(
      id: id,
      username: username,
      globalName: globalName,
      avatarUrl: avatarUrl,
    );
  }
}

/// Manages Discord Rich Presence (RPC) over the Discord Gateway WebSocket.
class DiscordRpcService {
  static final DiscordRpcService instance = DiscordRpcService._internal();

  DiscordRpcService._internal({
    http.Client? httpClient,
    FlutterSecureStorage? secureStorage,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  factory DiscordRpcService({
    http.Client? httpClient,
    FlutterSecureStorage? secureStorage,
  }) {
    if (httpClient != null || secureStorage != null) {
      return DiscordRpcService._internal(
        httpClient: httpClient,
        secureStorage: secureStorage,
      );
    }
    return instance;
  }

  static const String defaultApplicationId = '1411019391843172514';
  static const String defaultGatewayUrl =
      'wss://gateway.discord.gg/?v=9&encoding=json';
  static const String fallbackArtUrl =
      'https://raw.githubusercontent.com/pulsr-audio/pulsr/main/assets/app_icon/app_icon_plus.png';
  static const String githubRepoUrl = 'https://github.com/pulsr-audio/pulsr';
  static const int maxAssetCacheEntries = 256;
  static const Duration httpTimeout = Duration(seconds: 10);
  static const int maxReconnectAttempts = 8;

  final http.Client _httpClient;
  final bool _ownsClient;
  final FlutterSecureStorage _secureStorage;
  final Map<String, String> _externalAssetCache = {};

  SharedPreferences? _prefs;
  WebSocket? _webSocket;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  StreamSubscription<PlayerState>? _playerSub;

  bool _enabled = false;
  String _token = '';
  String _applicationId = defaultApplicationId;
  DiscordUser? _currentUser;

  bool _isConnecting = false;
  bool _isConnected = false;
  bool _sessionReady = false;
  bool _awaitingAck = false;
  int _sequence = 0;
  int _connectGeneration = 0;
  int _presenceEpoch = 0;
  int _reconnectAttempts = 0;
  String? _sessionId;
  String? _resumeGatewayUrl;
  int _heartbeatInterval = 41250;
  int get heartbeatInterval => _heartbeatInterval;
  bool _disposed = false;

  bool get _isNetworkBlocked =>
      !AppConfig.isCloudSyncAllowed ||
      (_prefs?.getBool(PrefsKeys.offlineOnlyMode) == true);

  @visibleForTesting
  int get externalAssetCacheSize => _externalAssetCache.length;

  @visibleForTesting
  void insertExternalAssetCacheForTesting(String key, String value) {
    _putExternalAssetCache(key, value);
  }

  void _putExternalAssetCache(String key, String value) {
    _externalAssetCache.remove(key);
    if (_externalAssetCache.length >= maxAssetCacheEntries) {
      _externalAssetCache.remove(_externalAssetCache.keys.first);
    }
    _externalAssetCache[key] = value;
  }

  static bool isFatalCloseCode(int? code) =>
      code == 4004 ||
      code == 4010 ||
      code == 4011 ||
      code == 4012 ||
      code == 4013 ||
      code == 4014;

  static bool isSafeRemoteArtworkUrl(String? rawUrl) {
    if (rawUrl == null) return false;
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('file:') ||
        lower.startsWith('content:') ||
        lower.startsWith('/')) {
      return false;
    }
    if (lower.startsWith('mp:')) return true;
    return RemoteTargetPolicy.isAllowed(trimmed);
  }

  Map<String, dynamic>? _lastPresencePayload;
  SongsTableData? _lastSong;
  bool? _lastIsPlaying;
  double? _lastSpeed;
  DateTime? _lastTimestamp;
  Duration? _lastPosition;

  bool get isEnabled => _enabled;
  String get token => _token;
  String get applicationId => _applicationId;
  DiscordUser? get currentUser => _currentUser;
  bool get isConnected => _isConnected && _sessionReady;

  /// Initializes configuration from [SharedPreferences] and [FlutterSecureStorage].
  Future<void> init(SharedPreferences prefs) async {
    _disposed = false;
    _prefs = prefs;
    _enabled = prefs.getBool(PrefsKeys.discordRpcEnabled) ?? false;
    String? secureToken;
    try {
      secureToken = await _secureStorage.read(key: PrefsKeys.discordRpcToken);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to read Discord token from secure storage',
        error: e,
        stackTrace: st,
        category: 'DiscordRPC',
      );
    }
    final legacyToken = prefs.getString(PrefsKeys.discordRpcToken);
    if (legacyToken != null) {
      if (legacyToken.isNotEmpty &&
          (secureToken == null || secureToken.isEmpty)) {
        secureToken = legacyToken;
        try {
          await _secureStorage.write(
            key: PrefsKeys.discordRpcToken,
            value: legacyToken,
          );
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to migrate Discord token to secure storage',
            error: e,
            stackTrace: st,
            category: 'DiscordRPC',
          );
        }
      }
      await prefs.remove(PrefsKeys.discordRpcToken);
    }
    _token = secureToken ?? '';
    _applicationId =
        prefs.getString(PrefsKeys.discordApplicationId) ?? defaultApplicationId;

    if (!_isNetworkBlocked && _token.isNotEmpty) {
      unawaited(fetchUserInfo());
    }

    if (!_isNetworkBlocked && _enabled && _token.isNotEmpty) {
      connect();
    }
  }

  /// Sets Discord RPC enabled/disabled flag.
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await _prefs?.setBool(PrefsKeys.discordRpcEnabled, enabled);
    if (enabled && !_isNetworkBlocked) {
      _reconnectAttempts = 0;
      if (_token.isNotEmpty) {
        connect();
      }
    } else {
      await clearPresence();
      disconnect();
    }
  }

  /// Updates Discord user token.
  Future<void> setToken(String token) async {
    final clean = token.trim();
    _token = clean;
    _reconnectAttempts = 0;
    await _prefs?.remove(PrefsKeys.discordRpcToken);
    try {
      if (clean.isEmpty) {
        await _secureStorage.delete(key: PrefsKeys.discordRpcToken);
      } else {
        await _secureStorage.write(
          key: PrefsKeys.discordRpcToken,
          value: clean,
        );
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to persist Discord token in secure storage',
        error: e,
        stackTrace: st,
        category: 'DiscordRPC',
      );
    }
    _currentUser = null;

    if (clean.isNotEmpty && !_isNetworkBlocked) {
      await fetchUserInfo();
      if (_enabled) {
        reconnect();
      }
    } else {
      disconnect();
    }
  }

  /// Updates Discord Application ID used for assets & buttons.
  Future<void> setApplicationId(String id) async {
    final clean = id.trim().isEmpty ? defaultApplicationId : id.trim();
    _applicationId = clean;
    await _prefs?.setString(PrefsKeys.discordApplicationId, clean);
    _externalAssetCache.clear();
  }

  /// Clears stored Discord account credentials and disconnects.
  Future<void> clearAccount() async {
    _token = '';
    _currentUser = null;
    await _prefs?.remove(PrefsKeys.discordRpcToken);
    try {
      await _secureStorage.delete(key: PrefsKeys.discordRpcToken);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to delete Discord token from secure storage',
        error: e,
        stackTrace: st,
        category: 'DiscordRPC',
      );
    }
    await clearPresence();
    disconnect();
  }

  /// Validates the token and fetches user identity from Discord REST API.
  Future<DiscordUser?> fetchUserInfo() async {
    if (_token.isEmpty || _isNetworkBlocked) return null;
    final user = await getUserInfo(_token, client: _httpClient);
    if (user != null) {
      _currentUser = user;
    }
    return user;
  }

  /// Static helper to check token credentials against Discord API.
  static Future<DiscordUser?> getUserInfo(
    String token, {
    http.Client? client,
  }) async {
    if (!AppConfig.isCloudSyncAllowed) return null;
    final c = client ?? http.Client();
    try {
      final res = await c.get(
        Uri.parse('https://discord.com/api/v9/users/@me'),
        headers: {
          'Authorization': token,
          'User-Agent': DiscordSuperProperties.userAgent,
          'X-Super-Properties': DiscordSuperProperties.getBase64(),
        },
      ).timeout(httpTimeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        return DiscordUser.fromJson(json);
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Discord getUserInfo failed',
        error: e,
        stackTrace: st,
        category: 'DiscordRPC',
      );
    } finally {
      if (client == null) c.close();
    }
    return null;
  }

  /// Establishes the Gateway WebSocket connection.
  Future<void> connect() async {
    if (_disposed ||
        !_enabled ||
        _isNetworkBlocked ||
        _isConnecting ||
        _isConnected) {
      return;
    }
    if (_token.isEmpty) return;

    _isConnecting = true;
    _reconnectTimer?.cancel();
    final generation = ++_connectGeneration;

    final url = _resumeGatewayUrl ?? defaultGatewayUrl;
    try {
      debugPrint('[DiscordRPC] Connecting to Discord Gateway at $url');
      final socket = await WebSocket.connect(
        url,
        headers: {
          'User-Agent': DiscordSuperProperties.userAgent,
          'Accept-Language': 'en-US',
        },
      ).timeout(const Duration(seconds: 15));

      if (_disposed ||
          !_enabled ||
          _token.isEmpty ||
          generation != _connectGeneration) {
        _isConnecting = false;
        try {
          await socket.close();
        } catch (e) {
          ErrorLogger.logSwallowed('DiscordRpcService.closeStaleSocket', e);
        }
        return;
      }

      _webSocket = socket;
      _isConnected = true;
      _isConnecting = false;

      socket.listen(
        _onMessage,
        onError: (e) {
          if (generation != _connectGeneration) return;
          debugPrint('[DiscordRPC] WebSocket error: $e');
          _onDisconnect(closeCode: socket.closeCode);
        },
        onDone: () {
          if (generation != _connectGeneration) return;
          debugPrint(
              '[DiscordRPC] WebSocket closed (code=${socket.closeCode}).');
          _onDisconnect(closeCode: socket.closeCode);
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (generation != _connectGeneration) return;
      debugPrint('[DiscordRPC] Connection failed: $e');
      _isConnecting = false;
      _onDisconnect();
    }
  }

  void _onDisconnect({int? closeCode}) {
    _isConnected = false;
    _sessionReady = false;
    _awaitingAck = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    unawaited(_webSocket?.close().catchError((Object _) {}));
    _webSocket = null;

    if (isFatalCloseCode(closeCode)) {
      debugPrint(
          '[DiscordRPC] Fatal close code $closeCode; halting auto-reconnect.');
      return;
    }

    if (_enabled && !_disposed && !_isNetworkBlocked && _token.isNotEmpty) {
      _reconnectAttempts++;
      if (_reconnectAttempts > maxReconnectAttempts) {
        debugPrint(
            '[DiscordRPC] Max reconnect attempts ($maxReconnectAttempts) reached.');
        return;
      }
      _reconnectTimer?.cancel();
      final delaySeconds = math.min(60, 5 * (1 << (_reconnectAttempts - 1)));
      _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
        if (_enabled && !_disposed && !_isNetworkBlocked && !_isConnected) {
          connect();
        }
      });
    }
  }

  /// Force a reconnect.
  void reconnect() {
    disconnect();
    _reconnectAttempts = 0;
    if (_enabled && !_isNetworkBlocked && _token.isNotEmpty) {
      connect();
    }
  }

  /// Disconnects the socket without erasing credentials.
  void disconnect() {
    _connectGeneration++;
    _isConnecting = false;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isConnected = false;
    _sessionReady = false;
    unawaited(_webSocket?.close().catchError((Object _) {}));
    _webSocket = null;
  }

  void _onMessage(dynamic raw) {
    try {
      final Map<String, dynamic> data = jsonDecode(raw as String);
      final op = data['op'] as int?;
      final seq = data['s'] as int?;
      final t = data['t'] as String?;
      final d = data['d'];

      if (seq != null) _sequence = seq;

      switch (op) {
        case DiscordOpcode.hello:
          final interval =
              (d is Map ? d['heartbeat_interval'] as num? : null)?.toInt() ??
                  41250;
          _handleHello(interval);
          break;

        case DiscordOpcode.heartbeat:
          _sendHeartbeat();
          break;

        case DiscordOpcode.heartbeatAck:
          _awaitingAck = false;
          break;

        case DiscordOpcode.reconnect:
          reconnect();
          break;

        case DiscordOpcode.invalidSession:
          _sequence = 0;
          _sessionId = null;
          _resumeGatewayUrl = null;
          final gen = _connectGeneration;
          Future.delayed(const Duration(milliseconds: 150), () {
            if (!_disposed &&
                _isConnected &&
                gen == _connectGeneration &&
                !_isNetworkBlocked) {
              _sendIdentify();
            }
          });
          break;

        case DiscordOpcode.dispatch:
          if (t == 'READY') {
            if (d is Map) {
              _sessionId = d['session_id'] as String?;
              final resumeUrl = d['resume_gateway_url'] as String?;
              if (resumeUrl != null && resumeUrl.isNotEmpty) {
                _resumeGatewayUrl = '$resumeUrl/?v=9&encoding=json';
              }
            }
            _reconnectAttempts = 0;
            _sessionReady = true;
            _replayLastPresence();
          } else if (t == 'RESUMED') {
            _reconnectAttempts = 0;
            _sessionReady = true;
            _replayLastPresence();
          }
          break;
      }
    } catch (e) {
      debugPrint('[DiscordRPC] Error decoding frame: $e');
    }
  }

  void _handleHello(int interval) {
    _heartbeatInterval = interval;
    if (_sequence > 0 && _sessionId != null && _sessionId!.isNotEmpty) {
      _sendResume();
    } else {
      _sendIdentify();
    }
    _startHeartbeat(interval);
  }

  void _startHeartbeat(int intervalMs) {
    _heartbeatTimer?.cancel();
    _awaitingAck = false;
    _heartbeatTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (_awaitingAck) {
        debugPrint(
            '[DiscordRPC] Heartbeat ACK missing; reconnecting zombie socket.');
        reconnect();
        return;
      }
      _awaitingAck = true;
      _sendHeartbeat();
    });
  }

  void _sendHeartbeat() {
    _send(DiscordOpcode.heartbeat, _sequence == 0 ? null : _sequence);
  }

  void _sendIdentify() {
    final payload = {
      'token': _token,
      'capabilities': 16381,
      'properties': DiscordSuperProperties.createProperties(),
      'presence': {
        'status': 'online',
        'since': 0,
        'activities': [],
        'afk': false,
      },
      'compress': false,
      'client_state': {
        'guild_versions': {},
        'highest_last_message_id': '0',
        'read_state_version': 0,
        'user_guild_settings_version': -1,
        'user_settings_version': -1,
        'private_channels_version': '0',
        'api_code_version': 0,
      },
    };
    _send(DiscordOpcode.identify, payload);
  }

  void _sendResume() {
    final payload = {
      'token': _token,
      'session_id': _sessionId,
      'seq': _sequence,
    };
    _send(DiscordOpcode.resume, payload);
  }

  void _send(int op, dynamic d) {
    if (_webSocket == null || !_isConnected) return;
    try {
      final msg = jsonEncode({'op': op, 'd': d});
      _webSocket!.add(msg);
    } catch (e) {
      debugPrint('[DiscordRPC] Error sending frame op=$op: $e');
    }
  }

  void _replayLastPresence() {
    final payload = _lastPresencePayload;
    if (payload != null && _sessionReady) {
      _send(DiscordOpcode.presenceUpdate, payload);
    }
  }

  /// Proxies external image URLs onto Discord CDN via external-assets API.
  Future<String?> fetchExternalAsset(String imageUrl) async {
    if (_isNetworkBlocked) return null;
    if (imageUrl.startsWith('mp:')) return imageUrl;
    if (!isSafeRemoteArtworkUrl(imageUrl)) {
      return null;
    }
    final cached = _externalAssetCache.remove(imageUrl);
    if (cached != null) {
      _externalAssetCache[imageUrl] = cached;
      return cached;
    }

    try {
      final res = await _httpClient
          .post(
            Uri.parse(
                'https://discord.com/api/v9/applications/$_applicationId/external-assets'),
            headers: {
              'Authorization': _token,
              'User-Agent': DiscordSuperProperties.userAgent,
              'X-Super-Properties': DiscordSuperProperties.getBase64(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'urls': [imageUrl],
            }),
          )
          .timeout(httpTimeout);

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List && decoded.isNotEmpty) {
          final first = decoded.first as Map<String, dynamic>;
          final path = first['external_asset_path'] as String?;
          if (path != null && path.isNotEmpty) {
            final asset = 'mp:$path';
            _putExternalAssetCache(imageUrl, asset);
            return asset;
          }
        }
      }
    } catch (e) {
      debugPrint('[DiscordRPC] fetchExternalAsset failed for $imageUrl: $e');
    }
    return null;
  }

  /// Pushes updated playback info to Discord presence.
  Future<void> updateSong({
    required SongsTableData song,
    required Duration position,
    required Duration duration,
    double playbackSpeed = 1.0,
    bool isPlaying = true,
  }) async {
    if (_disposed || !_enabled || _token.isEmpty || _isNetworkBlocked) return;

    final epoch = ++_presenceEpoch;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final speed =
        (playbackSpeed.isFinite && playbackSpeed > 0) ? playbackSpeed : 1.0;

    final adjustedPosMs = (position.inMilliseconds / speed).round();
    final startTime = nowMs - adjustedPosMs;

    final durationMs = duration.inMilliseconds;
    final remainingMs =
        (durationMs - position.inMilliseconds).clamp(0, durationMs);
    final adjustedRemainingMs = (remainingMs / speed).round();
    final endTime = durationMs > 0 ? nowMs + adjustedRemainingMs : null;

    final speedSuffix = (speed != 1.0) ? ' [${speed.toStringAsFixed(2)}x]' : '';
    final details = '${song.title}$speedSuffix';
    final state = song.artist.isNotEmpty ? song.artist : 'Unknown Artist';

    String largeImage = fallbackArtUrl;
    final artUrl = song.remoteArtworkUrl ?? song.artworkUri;
    if (artUrl != null && artUrl.isNotEmpty && isSafeRemoteArtworkUrl(artUrl)) {
      final proxied = await fetchExternalAsset(artUrl);
      if (_disposed || epoch != _presenceEpoch || _isNetworkBlocked) return;
      if (proxied != null) {
        largeImage = proxied;
      } else {
        largeImage = artUrl;
      }
    }

    final audioQuality = formatAudioQuality(song);
    final watchUrl = getWatchUrl(song);

    final activity = {
      'name': 'Pulsr',
      'type': 2, // LISTENING
      'details': details,
      'state': state,
      'timestamps': {
        'start': startTime,
        if (endTime != null) 'end': endTime,
      },
      'assets': {
        'large_image': largeImage,
        if (audioQuality != null && audioQuality.isNotEmpty)
          'large_text': audioQuality,
        'small_image': fallbackArtUrl,
        'small_text': isPlaying ? 'Playing' : 'Paused',
      },
      'buttons': [
        'Listen on YouTube Music',
        'Download Pulsr',
      ],
      'metadata': {
        'button_urls': [
          watchUrl,
          githubRepoUrl,
        ],
      },
      'application_id': _applicationId,
      'status_display_type': 1,
    };

    final presencePayload = {
      'since': nowMs,
      'activities': [activity],
      'status': 'online',
      'afk': true,
    };

    if (_disposed ||
        epoch != _presenceEpoch ||
        !_enabled ||
        _isNetworkBlocked) {
      return;
    }

    _lastPresencePayload = presencePayload;

    if (!_isConnected) {
      connect();
      return;
    }

    if (_sessionReady) {
      _send(DiscordOpcode.presenceUpdate, presencePayload);
    }
  }

  /// Clears user activity from Discord presence.
  Future<void> clearPresence() async {
    ++_presenceEpoch;
    final clearPayload = {
      'since': 0,
      'activities': [],
      'status': 'online',
      'afk': true,
    };
    _lastPresencePayload = clearPayload;
    if (_isConnected && _sessionReady) {
      _send(DiscordOpcode.presenceUpdate, clearPayload);
    }
  }

  /// Formats the audio quality line from track metadata.
  static String? formatAudioQuality(SongsTableData? song) {
    if (song == null) return null;
    final info = AudioQualityInfo.fromSong(song);

    final isAtmos = (song.codec?.toLowerCase().contains('atmos') ?? false) ||
        song.title.toLowerCase().contains('dolby atmos') ||
        song.album.toLowerCase().contains('dolby atmos');

    final isHiRes = info.tier == AudioQualityTier.hiResLossless;
    final isLossless = info.tier == AudioQualityTier.lossless;

    if (!isAtmos && !isHiRes && !isLossless) return null;

    final parts = <String>[];
    if (isAtmos) {
      parts.add('◗◖ Dolby Atmos');
    } else if (isHiRes) {
      parts.add('Hi-Res Lossless');
    } else if (isLossless) {
      parts.add('Lossless');
    }

    if (info.format.isNotEmpty && info.format != 'AUDIO') {
      parts.add(info.format.toUpperCase());
    }
    if (info.bitrateKbps != null && info.bitrateKbps! > 0) {
      parts.add('${info.bitrateKbps} kbps');
    }
    if (info.bitDepth.isNotEmpty && info.bitDepth != 'Unknown') {
      parts.add(info.bitDepth);
    }
    if (info.sampleRate.isNotEmpty && info.sampleRate != 'Unknown') {
      parts.add(info.sampleRate);
    }

    if (parts.isEmpty) return null;
    final line = parts.join(' · ');
    return line.length > 128 ? line.substring(0, 128).trim() : line;
  }

  /// Returns YouTube Music watch URL or search URL for the song.
  static String getWatchUrl(SongsTableData song) {
    if (song.remoteId != null && song.remoteId!.isNotEmpty) {
      return 'https://music.youtube.com/watch?v=${song.remoteId}';
    }
    if (song.source == SongSource.youtube) {
      final uri = Uri.tryParse(song.path);
      final v = uri?.queryParameters['v'];
      if (v != null && v.isNotEmpty) {
        return 'https://music.youtube.com/watch?v=$v';
      }
    }
    final query = Uri.encodeComponent('${song.title} ${song.artist}');
    return 'https://music.youtube.com/search?q=$query';
  }

  /// Attaches presence listener to [PlayerCubit].
  void bindToPlayerCubit(PlayerCubit playerCubit) {
    _playerSub?.cancel();
    _playerSub = playerCubit.stream.listen((state) {
      if (!_enabled || _token.isEmpty) return;
      _handlePlayerState(state);
    });

    if (_enabled && _token.isNotEmpty) {
      _handlePlayerState(playerCubit.state);
    }
  }

  void _handlePlayerState(PlayerState state) {
    final song = state.currentSong;
    final isPlaying = state.isPlaying;
    final speed = state.playbackSpeed;
    final position = state.position;
    final duration = state.duration;

    // Privacy/Pure/offline gate: never broadcast Quran recitation or offline/Pure playback.
    if (!isPlaying ||
        song == null ||
        state.isQuranModeEnabled ||
        _isNetworkBlocked) {
      if (_lastIsPlaying == true) {
        unawaited(clearPresence());
      }
      _lastSong = song;
      _lastIsPlaying = false;
      return;
    }

    final trackChanged =
        _lastSong?.id != song.id || _lastSong?.path != song.path;
    final playStateChanged = _lastIsPlaying != isPlaying;
    final speedChanged = _lastSpeed != speed;

    bool seeked = false;
    if (_lastTimestamp != null && _lastPosition != null && !trackChanged) {
      final elapsedMs =
          DateTime.now().difference(_lastTimestamp!).inMilliseconds;
      final expectedPosMs =
          _lastPosition!.inMilliseconds + (elapsedMs * speed).round();
      if ((position.inMilliseconds - expectedPosMs).abs() > 3000) {
        seeked = true;
      }
    }

    if (trackChanged ||
        playStateChanged ||
        speedChanged ||
        seeked ||
        _lastPresencePayload == null) {
      _lastSong = song;
      _lastIsPlaying = isPlaying;
      _lastSpeed = speed;
      _lastTimestamp = DateTime.now();
      _lastPosition = position;

      unawaited(updateSong(
        song: song,
        position: position,
        duration: duration,
        playbackSpeed: speed,
        isPlaying: isPlaying,
      ));
    }
  }

  void dispose() {
    _disposed = true;
    ++_presenceEpoch;
    _playerSub?.cancel();
    _playerSub = null;
    disconnect();
    if (_ownsClient && !identical(this, instance)) {
      _httpClient.close();
    }
  }
}
