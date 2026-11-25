// lib/data/party/listen_together_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/di/injection.dart';
import '../../core/network/remote_target_policy.dart';
import '../../core/services/ytm_account_service.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../../features/player/cubit/player_state.dart';
import '../../features/settings/cubit/settings_cubit.dart';
import '../db/app_database.dart';
import 'party_models.dart';
import 'party_sync_controller.dart';
import 'server_clock.dart';

enum PartyConnectionState { offline, connecting, live }

/// Service managing WebSocket connection and bidirectional synchronization
/// for listen-together parties.
@lazySingleton
class ListenTogetherService {
  static const String defaultServerUrl = 'https://party.pulsr.app';
  static const String prefCustomServerKey = 'setting_party_custom_server_url';
  static const String prefNicknameKey = 'setting_party_nickname';
  static const String prefSavedCodeKey = 'setting_party_saved_code';
  static const String prefSavedTokenKey = 'setting_party_saved_token';

  static const int pingIntervalMs = 10000; // 10s ping loop

  final ServerClock _clock = ServerClock();
  ServerClock get clock => _clock;

  /// Audible-time sync arithmetic. Thresholds live here, not in constants
  /// duplicated on this class.
  final PartySyncController _sync = PartySyncController();

  /// Resolved output latency of this device in ms, cached because it is read on
  /// every reconciliation tick.
  int _outputLatencyMs = 0;
  int _calibratedBluetoothLatencyMs = 0;
  Timer? _scheduledStartTimer;

  final ValueNotifier<PartyConnectionState> connectionState =
      ValueNotifier<PartyConnectionState>(PartyConnectionState.offline);

  final ValueNotifier<PartySnapshot?> partySnapshot =
      ValueNotifier<PartySnapshot?>(null);

  final ValueNotifier<PartyMember?> currentMember =
      ValueNotifier<PartyMember?>(null);

  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  int _reconnectAttempts = 0;
  int _connectGeneration = 0;
  bool _reconnectScheduled = false;
  bool _isCheckingDrift = false;

  final ValueNotifier<bool> clockSynced = ValueNotifier<bool>(false);

  final ValueNotifier<int> roundTripMs = ValueNotifier<int>(0);

  final http.Client _httpClient = http.Client();

  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  Timer? _pingTimer;
  Timer? _pingBurstTimer;
  Timer? _reconcileTimer;

  String? _activeCode;
  String? _activeToken;
  String? _activeServerBase;

  bool _isHost = false;
  bool get isHost => _isHost;
  bool get inParty => _activeCode != null;
  String? get currentPartyCode => _activeCode;

  // Drift correction state
  int _lastHandledSeq = -1;
  String? _activePartyTrackVideoId;
  int? _activePartyMatchedSongId;

  @visibleForTesting
  int get lastHandledSeq => _lastHandledSeq;

  @visibleForTesting
  set debugLastHandledSeq(int val) => _lastHandledSeq = val;

  @visibleForTesting
  String? get activePartyTrackVideoId => _activePartyTrackVideoId;

  @visibleForTesting
  int? get activePartyMatchedSongId => _activePartyMatchedSongId;

  @visibleForTesting
  void setMatchedLocalTrackForTesting({
    required String partyVideoId,
    required int localSongId,
  }) {
    _activePartyTrackVideoId = partyVideoId;
    _activePartyMatchedSongId = localSongId;
  }

  /// Local monotonic time before which reconciliation must stay quiet, so a
  /// track load or a seek is not immediately re-corrected by the next tick.
  int _reconcileQuietUntilMs = 0;

  // Subscriptions to local PlayerCubit
  StreamSubscription? _playerStateSub;
  bool _isReconcilingInbound = false;
  Future<void>? _initFuture;
  bool _initialized = false;
  bool _disposed = false;

  // Host outbound diff baseline (seeded on host creation and member->host promotion)
  DateTime? _hostLastAt;
  Duration _hostLastPosition = Duration.zero;
  String? _hostLastSongKey;
  bool? _hostLastPlaying;
  String? _hostLastQueueSignature;
  bool? _hostLastAutoplay;
  int _lastSyncedQueueSeq = -1;

  /// Initializes party session if persisted or registers listener.
  ///
  /// Idempotent and safe to invoke multiple times or concurrently with
  /// [createParty] / [joinParty].
  Future<void> init() {
    if (_disposed) return Future<void>.value();
    if (_initialized) {
      if (_playerStateSub == null) _bindPlayerCubitEvents();
      return Future<void>.value();
    }
    final existing = _initFuture;
    if (existing != null) return existing;
    final future = _initInternal();
    _initFuture = future;
    return future.whenComplete(() => _initFuture = null);
  }

  Future<void> _initInternal() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    final rawLatency = prefs.get(PrefsKeys.bluetoothLatencyOffsetMs);
    _calibratedBluetoothLatencyMs = rawLatency is num ? rawLatency.toInt() : 0;
    _refreshCachedOutputLatencyMs();

    final savedCode = prefs.getString(prefSavedCodeKey);
    String? savedToken;
    try {
      savedToken = await _secureStorage.read(key: prefSavedTokenKey);
      final legacyToken = prefs.getString(prefSavedTokenKey);
      if (legacyToken != null && legacyToken.isNotEmpty) {
        savedToken ??= legacyToken;
        await _secureStorage.write(key: prefSavedTokenKey, value: legacyToken);
        await prefs.remove(prefSavedTokenKey);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to read secure party token',
          error: e, stackTrace: st, category: 'PARTY');
      savedToken = prefs.getString(prefSavedTokenKey);
    }
    if (_disposed) return;
    final serverBase = await getServerUrl();
    if (_disposed) return;

    if (!inParty && savedCode != null && savedToken != null) {
      _activeCode = savedCode;
      _activeToken = savedToken;
      _activeServerBase = serverBase;
      unawaited(_connectWebSocket());
    }

    _bindPlayerCubitEvents();
    _initialized = true;
  }

  /// Normalizes a candidate party server URL, converting `ws://` -> `http://`
  /// and `wss://` -> `https://` and defaulting bare hosts to `https://`.
  static String normalizeServerUrl(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty) return '';
    final lower = url.toLowerCase();
    if (lower.startsWith('wss://')) {
      return 'https://${url.substring(6)}';
    }
    if (lower.startsWith('ws://')) {
      return 'http://${url.substring(5)}';
    }
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return url;
    }
    if (lower.contains('://')) {
      return url;
    }
    return 'https://$url';
  }

  /// Validates a candidate server URL against [RemoteTargetPolicy].
  ///
  /// Rejects insecure `http://` targets unless they target an explicit local or
  /// LAN address (such as localhost or private RFC-1918 space for local dev).
  static bool isValidServerUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    final normalized = normalizeServerUrl(trimmed);
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    final isLocal = RemoteTargetPolicy.isUnsafeHost(uri.host);
    final verdict = RemoteTargetPolicy.classify(
      normalized,
      requireHttps: !isLocal,
      allowedHostSuffixes: isLocal ? {uri.host} : const {},
    );
    return verdict == RemoteTargetVerdict.allowed;
  }

  /// Configured server URL (custom or fallback to default).
  Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(prefCustomServerKey)?.trim();
    if (custom != null && custom.isNotEmpty) {
      final normalized = normalizeServerUrl(custom);
      if (isValidServerUrl(normalized)) {
        return normalized;
      }
    }
    return defaultServerUrl;
  }

  Future<void> setCustomServerUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      await prefs.remove(prefCustomServerKey);
    } else {
      final normalized = normalizeServerUrl(url.trim());
      if (!isValidServerUrl(normalized)) {
        throw ArgumentError('The party server address is not allowed.');
      }
      await prefs.setString(prefCustomServerKey, normalized);
    }
  }

  String _resolveWsBase(String httpBase) {
    if (httpBase.startsWith('https://')) {
      return 'wss://${httpBase.substring(8)}';
    }
    if (httpBase.startsWith('http://')) {
      return 'ws://${httpBase.substring(7)}';
    }
    return 'wss://$httpBase';
  }

  Future<JoinPartyRequest> _buildIdentity([String? customNickname]) async {
    final prefs = await SharedPreferences.getInstance();
    final savedNick = prefs.getString(prefNicknameKey);
    String nickname = (customNickname ?? savedNick ?? '').trim();

    try {
      if (getIt.isRegistered<YtmAccountService>()) {
        final ytmAccount = getIt<YtmAccountService>();
        if (ytmAccount.isLoggedIn && nickname.isEmpty) {
          nickname = ytmAccount.accountName ?? '';
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to read YTM party nickname',
          error: e, stackTrace: st, category: 'PARTY');
    }

    if (nickname.isEmpty) {
      nickname = 'Pulsr Listener';
    }

    String? deviceId = prefs.getString('pulsr_device_unique_id');
    if (deviceId == null) {
      deviceId =
          'pulsr_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(999999)}';
      await prefs.setString('pulsr_device_unique_id', deviceId);
    }

    // Never broadcast a Google session-derived identifier or account avatar to
    // a third-party party server; the random per-install id is sufficient.
    return JoinPartyRequest(
      userId: deviceId,
      deviceId: deviceId,
      displayName: nickname,
    );
  }

  /// Create a new party on the party server.
  Future<String> createParty({String? nickname, int maxMembers = 5}) async {
    lastError.value = null;
    final serverBase = await getServerUrl();
    final identity = await _buildIdentity(nickname);

    final url = Uri.parse('$serverBase/api/parties');
    final resp = await _httpClient
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(JoinPartyRequest(
            userId: identity.userId,
            deviceId: identity.deviceId,
            displayName: identity.displayName,
            maxMembers: maxMembers,
            autoplayEnabled: false,
          ).toJson()),
        )
        .timeout(const Duration(seconds: 12));

    final respBody = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      final err = 'Failed to create party (${resp.statusCode}): $respBody';
      lastError.value = err;
      throw Exception(err);
    }

    final data = jsonDecode(respBody) as Map<String, dynamic>;
    final membership = PartyMembership.fromJson(data);

    await _saveSession(serverBase, membership.code, membership.token);
    _applyMembership(membership);
    _connectWebSocket();

    return membership.code;
  }

  /// Join an existing party with a 6-character room code.
  Future<String> joinParty(String code, {String? nickname}) async {
    lastError.value = null;
    final cleanedCode =
        code.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleanedCode.length != 6) {
      final err = 'Party code must be 6 alphanumeric characters';
      lastError.value = err;
      throw Exception(err);
    }

    final serverBase = await getServerUrl();
    final identity = await _buildIdentity(nickname);

    final url = Uri.parse('$serverBase/api/parties/$cleanedCode/join');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_activeCode == cleanedCode &&
        _activeToken != null &&
        _activeToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_activeToken';
    }
    final resp = await _httpClient
        .post(
          url,
          headers: headers,
          body: jsonEncode(identity.toJson()),
        )
        .timeout(const Duration(seconds: 12));

    final respBody = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode != 200) {
      final err = 'Failed to join party (${resp.statusCode}): $respBody';
      lastError.value = err;
      throw Exception(err);
    }

    final data = jsonDecode(respBody) as Map<String, dynamic>;
    final membership = PartyMembership.fromJson(data);

    await _saveSession(serverBase, membership.code, membership.token);
    _applyMembership(membership);
    _connectWebSocket();

    return membership.code;
  }

  /// Leave the active party.
  ///
  /// When [notifyServer] is `false` (e.g. after receiving a server `bye` frame
  /// or terminal 401/403/404 response), local session state and stored
  /// credentials are cleared without sending a redundant `POST /leave`.
  Future<void> leaveParty({bool notifyServer = true}) async {
    final code = _activeCode;
    final token = _activeToken;
    final serverBase = _activeServerBase ?? await getServerUrl();

    _connectGeneration++;
    _disconnectWebSocket();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectScheduled = false;
    _reconnectAttempts = 0;
    _lastHandledSeq = -1;
    _lastSyncedQueueSeq = -1;
    _activePartyTrackVideoId = null;
    _activePartyMatchedSongId = null;
    _resetHostBaseline();
    _clock.reset();
    clockSynced.value = false;
    roundTripMs.value = 0;
    _activeCode = null;
    _activeToken = null;
    _activeServerBase = null;
    partySnapshot.value = null;
    currentMember.value = null;
    _isHost = false;
    connectionState.value = PartyConnectionState.offline;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefSavedCodeKey);
    await prefs.remove(prefSavedTokenKey);
    try {
      await _secureStorage.delete(key: prefSavedTokenKey);
    } catch (e, st) {
      ErrorLogger.log('Failed to delete party token',
          error: e, stackTrace: st, category: 'PARTY');
    }

    if (notifyServer && code != null && token != null) {
      try {
        final url = Uri.parse('$serverBase/api/parties/$code/leave');
        await _httpClient.post(
          url,
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 10));
      } catch (e, st) {
        ErrorLogger.log('Party leave request failed',
            error: e, stackTrace: st, category: 'PARTY');
      }
    }
  }

  Future<void> _saveSession(
      String serverBase, String code, String token) async {
    _activeServerBase = serverBase;
    _activeCode = code;
    _activeToken = token;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefSavedCodeKey, code);
    await prefs.remove(prefSavedTokenKey);
    try {
      await _secureStorage.write(key: prefSavedTokenKey, value: token);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist party token securely',
          error: e, stackTrace: st, category: 'PARTY');
    }
  }

  void _applyMembership(PartyMembership membership) {
    final wasHost = _isHost;
    partySnapshot.value = membership.party;
    currentMember.value = membership.you;
    _isHost = membership.you.isHost;
    if (_isHost && !wasHost) {
      _seedHostBaselineFromPlayer();
    }
  }

  /// True when [error] or [closeCode] indicates an expired token, forbidden
  /// membership, or dissolved party room (401/403/404) where retrying is futile.
  @visibleForTesting
  static bool isTerminalSessionFailure(Object? error, [int? closeCode]) {
    if (closeCode == 4001 ||
        closeCode == 4003 ||
        closeCode == 4004 ||
        closeCode == 1008) {
      return true;
    }
    if (error == null) return false;
    final text = error.toString();
    return RegExp(
      r'HTTP status code:\s*(401|403|404)\b|\b(401|403|404)\b.*(unauthorized|forbidden|not found)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  Future<void> _handleTerminalSessionFailure(String message) async {
    await leaveParty(notifyServer: false);
    lastError.value = message;
  }

  // --------------------------------------------------------------------------
  // WebSocket Connection & Protocol
  // --------------------------------------------------------------------------

  Future<void> _connectWebSocket() async {
    _disconnectWebSocket();

    final code = _activeCode;
    final token = _activeToken;
    final serverBase = _activeServerBase;
    if (code == null || token == null || serverBase == null) return;

    final generation = ++_connectGeneration;
    connectionState.value = PartyConnectionState.connecting;
    unawaited(_resolveOutputLatencyMs());
    final wsBase = _resolveWsBase(serverBase);
    final wsUri = Uri.parse('$wsBase/ws/parties/$code');

    try {
      final channel = IOWebSocketChannel.connect(
        wsUri,
        headers: {'Authorization': 'Bearer $token'},
      );
      _channel = channel;
      // Do not claim "live" before the WebSocket handshake succeeds.
      await channel.ready.timeout(const Duration(seconds: 12));
      if (generation != _connectGeneration) {
        try {
          channel.sink.close();
        } catch (_) {}
        return;
      }
      _reconnectAttempts = 0;
      _reconnectScheduled = false;
      lastError.value = null;
      _channelSub = channel.stream.listen(
        _onWebSocketMessage,
        onError: (e, st) {
          ErrorLogger.log('Party WebSocket error',
              error: e, stackTrace: st, category: 'PARTY');
          if (isTerminalSessionFailure(e, channel.closeCode)) {
            unawaited(_handleTerminalSessionFailure(
              'Unable to reconnect to the party. Check your connection.',
            ));
            return;
          }
          _scheduleReconnect();
        },
        onDone: () {
          if (isTerminalSessionFailure(null, channel.closeCode)) {
            unawaited(_handleTerminalSessionFailure(
              'Unable to reconnect to the party. Check your connection.',
            ));
            return;
          }
          _scheduleReconnect();
        },
      );

      if (_playerStateSub == null) _bindPlayerCubitEvents();
      _startPingLoop();
      _startReconciliationTicker();
      connectionState.value = PartyConnectionState.live;
    } catch (e, st) {
      if (generation != _connectGeneration) return;
      ErrorLogger.log('Party WebSocket connect failed',
          error: e, stackTrace: st, category: 'PARTY');
      if (isTerminalSessionFailure(e, _channel?.closeCode)) {
        await _handleTerminalSessionFailure(
          'Unable to reconnect to the party. Check your connection.',
        );
        return;
      }
      _scheduleReconnect();
    }
  }

  void _disconnectWebSocket() {
    _lastHandledSeq = -1;
    _reconnectScheduled = false;
    _pingBurstTimer?.cancel();
    _pingBurstTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconcileTimer?.cancel();
    _reconcileTimer = null;
    // A pending anchored start must not fire into a room we just left.
    _scheduledStartTimer?.cancel();
    _scheduledStartTimer = null;
    _sync.reset();
    _channelSub?.cancel();
    _channelSub = null;
    try {
      _channel?.sink.close();
    } catch (e, st) {
      ErrorLogger.log('Failed to close party socket',
          error: e, stackTrace: st, category: 'PARTY');
    }
    _channel = null;
  }

  Timer? _reconnectTimer;
  void _scheduleReconnect() {
    if (_reconnectScheduled) return;
    _reconnectScheduled = true;
    _reconnectTimer?.cancel();
    if (_activeCode == null || _activeToken == null) {
      _reconnectScheduled = false;
      return;
    }
    _reconnectAttempts++;
    if (_reconnectAttempts > 5) {
      connectionState.value = PartyConnectionState.offline;
      lastError.value =
          'Unable to reconnect to the party. Check your connection.';
      _reconnectScheduled = false;
      return;
    }
    connectionState.value = PartyConnectionState.connecting;
    final delay =
        Duration(seconds: math.min(30, 3 * (1 << (_reconnectAttempts - 1))));
    _reconnectTimer = Timer(delay, () {
      _reconnectScheduled = false;
      if (_activeCode != null && _activeToken != null) {
        _connectWebSocket();
      }
    });
  }

  void _startPingLoop() {
    _pingBurstTimer?.cancel();
    _pingBurstTimer = null;
    _pingTimer?.cancel();
    // Burst 4 pings initially for instant accurate clock sync
    var burstCount = 0;
    _pingBurstTimer =
        Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (_channel == null) {
        timer.cancel();
        return;
      }
      if (burstCount >= 4 || _channel == null) {
        timer.cancel();
        // Regular heartbeat ping every 10s
        _pingTimer = Timer.periodic(
          Duration(milliseconds: pingIntervalMs),
          (_) => _sendPing(),
        );
        return;
      }
      burstCount++;
      _sendPing();
    });
  }

  void _sendPing() {
    final clientMs = _clock.nowMs();
    _clock.registerPing(clientMs);
    _sendFrame({
      'type': 'ping',
      'clientMs': clientMs,
    });
  }

  @visibleForTesting
  void sendPingForTesting() => _sendPing();

  @visibleForTesting
  void handleWebSocketMessageForTesting(String raw) => _onWebSocketMessage(raw);

  void _sendFrame(Map<String, dynamic> frame) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(frame));
    } catch (e) {
      ErrorLogger.log('Failed to send WebSocket frame',
          error: e, category: 'PARTY');
    }
  }

  void _onWebSocketMessage(dynamic data) {
    if (data is! String) return;
    final receivedAtLocalMs = _clock.nowMs();

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case 'welcome':
          final partyJson = json['party'] as Map<String, dynamic>?;
          final youJson = json['you'] as Map<String, dynamic>?;
          final wasHost = _isHost;
          PartySnapshot? welcomedSnap;
          if (partyJson != null) {
            welcomedSnap = PartySnapshot.fromJson(partyJson);
            partySnapshot.value = welcomedSnap;
          }
          if (youJson != null) {
            final you = PartyMember.fromJson(youJson);
            currentMember.value = you;
            _isHost = you.isHost;
          }
          if (_isHost && !wasHost) {
            _seedHostBaselineFromPlayer();
          }
          connectionState.value = PartyConnectionState.live;
          if (welcomedSnap != null && !_isHost) {
            unawaited(_onInboundPlaybackUpdate(welcomedSnap.playback));
            unawaited(_syncInboundQueue(welcomedSnap.queue));
          }
          break;

        case 'pong':
          final clientMs = (json['clientMs'] as num?)?.toInt();
          final serverMs = (json['serverMs'] as num?)?.toInt();
          if (clientMs != null && serverMs != null) {
            _clock.record(clientMs, serverMs, receivedAtLocalMs);
            clockSynced.value = _clock.synced;
            roundTripMs.value = _clock.roundTripMs;
          }
          break;

        case 'state':
          final playbackJson = json['playback'] as Map<String, dynamic>?;
          if (playbackJson != null) {
            final playback = PartyPlayback.fromJson(playbackJson);
            final currentSnap = partySnapshot.value ?? const PartySnapshot();
            partySnapshot.value = PartySnapshot(
              code: currentSnap.code,
              createdAtMs: currentSnap.createdAtMs,
              maxMembers: currentSnap.maxMembers,
              hostOnlyControl: currentSnap.hostOnlyControl,
              members: currentSnap.members,
              playback: playback,
              queue: currentSnap.queue,
              serverMs: currentSnap.serverMs,
            );
            _onInboundPlaybackUpdate(playback);
          }
          break;

        case 'queue':
          final queueJson = json['queue'] as Map<String, dynamic>?;
          if (queueJson != null) {
            final q = PartyQueue.fromJson(queueJson);
            final currentSnap = partySnapshot.value ?? const PartySnapshot();
            partySnapshot.value = PartySnapshot(
              code: currentSnap.code,
              createdAtMs: currentSnap.createdAtMs,
              maxMembers: currentSnap.maxMembers,
              hostOnlyControl: currentSnap.hostOnlyControl,
              members: currentSnap.members,
              playback: currentSnap.playback,
              queue: q,
              serverMs: currentSnap.serverMs,
            );
            if (!_isHost) {
              unawaited(_syncInboundQueue(q));
            }
          }
          break;

        case 'members':
          final membersList = json['members'] as List<dynamic>? ?? [];
          final members = membersList
              .whereType<Map<String, dynamic>>()
              .map((m) => PartyMember.fromJson(m))
              .toList();
          final currentSnap = partySnapshot.value ?? const PartySnapshot();
          partySnapshot.value = PartySnapshot(
            code: currentSnap.code,
            createdAtMs: currentSnap.createdAtMs,
            maxMembers:
                (json['maxMembers'] as num?)?.toInt() ?? currentSnap.maxMembers,
            hostOnlyControl:
                json['hostOnlyControl'] as bool? ?? currentSnap.hostOnlyControl,
            members: members,
            playback: currentSnap.playback,
            queue: currentSnap.queue,
            serverMs: currentSnap.serverMs,
          );

          // Update host status if member was promoted and sync host baseline so
          // the next player tick does not broadcast a spurious setTrack.
          final myId = currentMember.value?.memberId;
          if (myId != null) {
            final me = members.where((m) => m.memberId == myId).firstOrNull;
            if (me != null) {
              final wasHost = _isHost;
              currentMember.value = me;
              _isHost = me.isHost;
              if (_isHost && !wasHost) {
                _seedHostBaselineFromPlayer();
              }
            }
          }
          break;

        case 'bye':
          final byeReason =
              json['reason'] as String? ?? json['message'] as String?;
          if (byeReason != null && byeReason.isNotEmpty) {
            lastError.value = byeReason;
          }
          unawaited(leaveParty(notifyServer: false));
          break;

        case 'error':
          final msg = json['message'] as String? ?? json['error'] as String?;
          lastError.value = msg;
          break;
      }
    } catch (e, st) {
      ErrorLogger.log('Error processing party frame',
          error: e, stackTrace: st, category: 'PARTY');
    }
  }

  // --------------------------------------------------------------------------
  // Bidirectional Playback Synchronization
  // --------------------------------------------------------------------------

  void _resetHostBaseline() {
    _hostLastAt = null;
    _hostLastPosition = Duration.zero;
    _hostLastSongKey = null;
    _hostLastPlaying = null;
    _hostLastQueueSignature = null;
    _hostLastAutoplay = null;
  }

  void _seedHostBaselineFromPlayer() {
    _hostLastAt = DateTime.now();
    if (!getIt.isRegistered<PlayerCubit>()) return;
    final state = getIt<PlayerCubit>().state;
    _hostLastPosition = state.position;
    _hostLastSongKey = _songPartyKey(state.currentSong);
    _hostLastPlaying = state.isPlaying;
    _hostLastQueueSignature = _queueSignature(state.queue, state.currentIndex);
    _hostLastAutoplay = state.isAutoplayEnabled;
  }

  static String? _songPartyKey(SongsTableData? song) {
    if (song == null) return null;
    final remote = song.remoteId?.trim();
    if (remote != null && remote.isNotEmpty) return remote;
    return 'local:${song.id}';
  }

  static PartyTrack _partyTrackFromSong(SongsTableData song) {
    final remote = song.remoteId?.trim();
    final isLocal = remote == null || remote.isEmpty;
    return PartyTrack(
      videoId: isLocal ? 'local:${song.id}' : remote,
      title: song.title,
      artist: song.artist,
      thumbnailUrl: song.remoteArtworkUrl ?? song.artworkUri,
      durationMs: song.durationMs,
      fromAutoplay: song.isAutoplay,
      isLocalOnly: isLocal,
    );
  }

  static String _queueSignature(List<SongsTableData> queue, int currentIndex) {
    final keys = queue.map((s) => _songPartyKey(s) ?? '').join(',');
    return '$currentIndex|$keys';
  }

  void _bindPlayerCubitEvents() {
    _playerStateSub?.cancel();
    if (!getIt.isRegistered<PlayerCubit>()) return;

    final playerCubit = getIt<PlayerCubit>();
    if (_isHost) {
      _seedHostBaselineFromPlayer();
    }
    _playerStateSub = playerCubit.stream.listen((state) {
      if (!inParty || !_isHost) return;
      if (_isReconcilingInbound) return;

      final now = DateTime.now();
      final songKey = _songPartyKey(state.currentSong);
      final expectedPosition = _hostLastPlaying == true && _hostLastAt != null
          ? _hostLastPosition + now.difference(_hostLastAt!)
          : _hostLastPosition;
      final seeked = (state.position - expectedPosition).abs() >
          const Duration(seconds: 2);
      final trackChanged = songKey != _hostLastSongKey;
      final playingChanged = state.isPlaying != _hostLastPlaying;
      final queueSig = _queueSignature(state.queue, state.currentIndex);
      final queueChanged = queueSig != _hostLastQueueSignature;
      final autoplayChanged = state.isAutoplayEnabled != _hostLastAutoplay;
      final changed = trackChanged ||
          playingChanged ||
          seeked ||
          queueChanged ||
          autoplayChanged;
      final heartbeatDue = _hostLastAt == null ||
          now.difference(_hostLastAt!) >= const Duration(milliseconds: 1000);
      if (!changed && !(state.isPlaying && heartbeatDue)) return;
      _hostLastAt = now;
      _hostLastPosition = state.position;
      _hostLastSongKey = songKey;
      _hostLastPlaying = state.isPlaying;
      _hostLastQueueSignature = queueSig;
      _hostLastAutoplay = state.isAutoplayEnabled;
      unawaited(_syncHostPlayback(
        song: state.currentSong,
        isPlaying: state.isPlaying,
        position: state.position,
        trackChanged: trackChanged,
        playingChanged: playingChanged,
        seeked: seeked,
        queue: queueChanged ? state.queue : null,
        queueIndex: state.currentIndex,
        autoplayEnabled: autoplayChanged ? state.isAutoplayEnabled : null,
      ));
    });
  }

  Future<void> _syncHostPlayback({
    required SongsTableData? song,
    required bool isPlaying,
    required Duration position,
    required bool trackChanged,
    required bool playingChanged,
    required bool seeked,
    List<SongsTableData>? queue,
    int queueIndex = -1,
    bool? autoplayEnabled,
  }) async {
    if (!inParty) return;

    final latencyMs = _refreshCachedOutputLatencyMs();
    final audiblePosMs = PartySyncController.audibleAnchorPositionMs(
      hostRenderPositionMs: position.inMilliseconds,
      hostOutputLatencyMs: latencyMs,
    );

    if (autoplayEnabled != null) {
      _sendFrame({
        'type': 'control',
        'action': 'setAutoplay',
        'enabled': autoplayEnabled,
      });
    }

    if (queue != null) {
      _sendFrame({
        'type': 'control',
        'action': 'setQueue',
        'queue': queue
            .map(_partyTrackFromSong)
            .map((track) => track.toJson())
            .toList(),
        'queueIndex': queueIndex,
      });
    }

    if (trackChanged) {
      if (song == null) {
        _sendFrame({
          'type': 'control',
          'action': 'pause',
          'positionMs': 0,
        });
        return;
      }
      final track = _partyTrackFromSong(song);
      _sendFrame({
        'type': 'control',
        'action': 'setTrack',
        'track': track.toJson(),
        'isPlaying': isPlaying,
        // Publish AUDIBLE time, not the position this device rendered: followers
        // align to whatever this value says, so the host's own speaker delay has to
        // be part of the timeline rather than a private offset everyone inherits.
        'positionMs': audiblePosMs,
      });
      return;
    }

    if (playingChanged) {
      _sendFrame({
        'type': 'control',
        'action': isPlaying ? 'play' : 'pause',
        'positionMs': audiblePosMs,
      });
      return;
    }

    if (seeked) {
      _sendFrame({
        'type': 'control',
        'action': 'seek',
        'positionMs': audiblePosMs,
      });
      return;
    }

    if (queue != null || autoplayEnabled != null) {
      return;
    }

    // Periodic heartbeat when track and transport state have not changed:
    // emit lightweight report frame so server does not reset AnchorMs (+350ms)
    // or spam activity messages every second.
    _sendFrame({
      'type': 'report',
      'positionMs': audiblePosMs,
      'playing': isPlaying,
    });
  }

  /// Synchronously updates [_outputLatencyMs] from the cached Bluetooth offset
  /// and active audio output route so host/follower sync never awaits prefs I/O.
  int _refreshCachedOutputLatencyMs() {
    var onBluetooth = false;
    if (getIt.isRegistered<SettingsCubit>()) {
      onBluetooth =
          getIt<SettingsCubit>().state.currentOutputDevice?.isBluetooth ??
              false;
    }
    _outputLatencyMs = (onBluetooth && _calibratedBluetoothLatencyMs > 0)
        ? _calibratedBluetoothLatencyMs
        : 0;
    return _outputLatencyMs;
  }

  /// Refreshes the cached Bluetooth latency preference in the background.
  Future<void> _resolveOutputLatencyMs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.get(PrefsKeys.bluetoothLatencyOffsetMs);
      _calibratedBluetoothLatencyMs = raw is num ? raw.toInt() : 0;
      _refreshCachedOutputLatencyMs();
    } catch (e, st) {
      ErrorLogger.log('Failed to resolve party output latency',
          error: e, stackTrace: st, category: 'PARTY');
      _outputLatencyMs = 0;
    }
  }

  /// Starts on the server's anchor instant instead of on frame arrival. The
  /// server schedules PlayLeadMs into the future precisely so members whose state
  /// frames land at different times still begin together; playing on arrival
  /// threw that lead away and made network jitter part of the audible offset.
  Future<void> _startAtAnchor(PartyPlayback playback) async {
    _scheduledStartTimer?.cancel();
    final nowServer = _clock.serverNowMs();
    final plan = nowServer == null
        ? const StartPlan(wait: Duration.zero, applied: Duration.zero)
        : PartySyncController.planStart(
            anchorServerMs: playback.anchorMs, nowServerMs: nowServer);

    if (plan.startImmediately) {
      _isReconcilingInbound = true;
      try {
        await getIt<PlayerCubit>().play();
      } finally {
        _isReconcilingInbound = false;
      }
      return;
    }

    _scheduledStartTimer = Timer(plan.applied, () async {
      if (!inParty || _isHost) return;
      final snapshot = partySnapshot.value;
      if (snapshot == null || !snapshot.playback.isPlaying) return;
      _isReconcilingInbound = true;
      try {
        await getIt<PlayerCubit>().play();
      } finally {
        _isReconcilingInbound = false;
      }
    });
  }

  /// Calculates effective current playback position on the room timeline.
  int? effectivePartyPositionMs(PartyPlayback playback) {
    if (!playback.isPlaying) return playback.positionMs;
    final serverNow = _clock.serverNowMs();
    if (serverNow == null) return playback.effectivePositionMs;
    final elapsed = math.max(0, serverNow - playback.anchorMs);
    final pos = playback.positionMs + elapsed;
    final duration = playback.track?.durationMs;
    if (duration != null && duration > 0 && pos > duration) {
      return duration;
    }
    return pos;
  }

  void _startReconciliationTicker() {
    _reconcileTimer?.cancel();
    _reconcileTimer = Timer.periodic(
        const Duration(milliseconds: PartySyncController.reconcileTickMs), (_) {
      if (!inParty || _isHost) return;
      final snap = partySnapshot.value;
      if (snap == null) return;
      if (!snap.playback.isPlaying &&
          getIt.isRegistered<PlayerCubit>() &&
          !getIt<PlayerCubit>().state.isPlaying) {
        return;
      }
      _checkMemberDrift(snap.playback);
    });
  }

  Future<void> _onInboundPlaybackUpdate(PartyPlayback playback) async {
    if (!inParty || _isHost) return;
    if (playback.seq <= _lastHandledSeq) return;
    _lastHandledSeq = playback.seq;

    if (getIt.isRegistered<PlayerCubit>()) {
      final playerCubit = getIt<PlayerCubit>();
      if (playerCubit.state.isAutoplayEnabled != playback.autoplayEnabled) {
        _isReconcilingInbound = true;
        try {
          await playerCubit.setAutoplayEnabled(playback.autoplayEnabled);
        } finally {
          _isReconcilingInbound = false;
        }
      }
    }

    await _checkMemberDrift(playback, forceTrackReconciliation: true);
  }

  Future<void> _syncInboundQueue(PartyQueue partyQueue) async {
    if (!inParty || _isHost) return;
    if (partyQueue.seq < _lastSyncedQueueSeq) return;
    _lastSyncedQueueSeq = partyQueue.seq;
    if (!getIt.isRegistered<PlayerCubit>()) return;
    final playerCubit = getIt<PlayerCubit>();

    final startIdx = partyQueue.index >= 0 ? partyQueue.index + 1 : 0;
    final upcomingTracks = startIdx < partyQueue.items.length
        ? partyQueue.items.sublist(startIdx)
        : const <PartyTrack>[];

    final resolvedUpcoming = <SongsTableData>[];
    for (final track in upcomingTracks) {
      final song = await _resolvePartyTrackToSong(track);
      if (song != null) resolvedUpcoming.add(song);
    }

    final currentQueue = playerCubit.state.queue;
    final currentIdx = playerCubit.state.currentIndex;
    final currentUpcoming =
        (currentIdx >= 0 && currentIdx + 1 < currentQueue.length)
            ? currentQueue.sublist(currentIdx + 1)
            : const <SongsTableData>[];
    final existingKeys = currentUpcoming.map(_songPartyKey).toList();
    final targetKeys = resolvedUpcoming.map(_songPartyKey).toList();
    if (listEquals(existingKeys, targetKeys)) return;

    _isReconcilingInbound = true;
    try {
      for (var i = currentQueue.length - 1; i > currentIdx && i >= 0; i--) {
        await playerCubit.removeQueueItem(i);
      }
      if (resolvedUpcoming.isNotEmpty) {
        await playerCubit.addAllToQueue(resolvedUpcoming);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to sync inbound party queue',
          error: e, stackTrace: st, category: 'PARTY');
    } finally {
      _isReconcilingInbound = false;
    }
  }

  Future<void> _checkMemberDrift(
    PartyPlayback playback, {
    bool forceTrackReconciliation = false,
  }) async {
    if (_isCheckingDrift) return;
    _isCheckingDrift = true;
    try {
      if (!getIt.isRegistered<PlayerCubit>()) return;
      final playerCubit = getIt<PlayerCubit>();
      final playerState = playerCubit.state;

      if (!playback.isPlaying) {
        _scheduledStartTimer?.cancel();
        _scheduledStartTimer = null;
      }

      final targetTrack = playback.track;
      if (targetTrack == null) {
        if (!playback.isPlaying && playerState.isPlaying) {
          _isReconcilingInbound = true;
          try {
            await playerCubit.pause();
          } finally {
            _isReconcilingInbound = false;
          }
        }
        return;
      }

      final now = _clock.nowMs();
      if (now < _reconcileQuietUntilMs) return;

      final latencyMs = _refreshCachedOutputLatencyMs();

      // 1. Reconcile Track: verify current track matches target videoId
      final currentSong = playerState.currentSong;
      final isMatchedLocalSong = currentSong != null &&
          _activePartyTrackVideoId == targetTrack.videoId &&
          _activePartyMatchedSongId != null &&
          currentSong.id == _activePartyMatchedSongId;
      final currentVideoId =
          isMatchedLocalSong ? targetTrack.videoId : _songPartyKey(currentSong);

      if (forceTrackReconciliation || currentVideoId != targetTrack.videoId) {
        if (currentVideoId != targetTrack.videoId) {
          _scheduledStartTimer?.cancel();
          _scheduledStartTimer = null;
          _isReconcilingInbound = true;
          _reconcileQuietUntilMs = now + 2500;
          try {
            await _loadTrackForParty(targetTrack, playback);
          } finally {
            _isReconcilingInbound = false;
          }
          return;
        }
      }

      // 2. Play/Pause state alignment
      if (!playback.isPlaying && playerState.isPlaying) {
        _isReconcilingInbound = true;
        try {
          await playerCubit.pause();
        } finally {
          _isReconcilingInbound = false;
        }
        return;
      } else if (playback.isPlaying && !playerState.isPlaying) {
        if (_scheduledStartTimer?.isActive ?? false) {
          // A future anchor start is already armed; do not cancel or re-arm it.
          return;
        }
        await _startAtAnchor(playback);
        if (_scheduledStartTimer?.isActive ?? false) {
          return;
        }
      }

      // 3. Audible-time correction. Compared against the latency-compensated
      // target: matching raw positions is not enough when one member hears the
      // music 200 ms after it is rendered and another hears it immediately.
      if (!playback.isPlaying || !_clock.synced) return;
      if (_scheduledStartTimer?.isActive ?? false) return;

      final roomPosition = effectivePartyPositionMs(playback);
      if (roomPosition == null) return;

      final decision = _sync.evaluatePosition(
        localRenderMs: playerState.position.inMilliseconds,
        roomPositionMs: roomPosition,
        outputLatencyMs: latencyMs,
        durationMs: targetTrack.durationMs,
      );

      if (decision.action == SyncAction.seek) {
        _isReconcilingInbound = true;
        _reconcileQuietUntilMs = now + 1500;
        try {
          await playerCubit.seek(Duration(milliseconds: decision.seekToMs!));
        } finally {
          _isReconcilingInbound = false;
        }
      }
    } finally {
      _isCheckingDrift = false;
    }
  }

  Future<SongsTableData?> _resolvePartyTrackToSong(PartyTrack track) async {
    final isLocalOnly = track.isLocalOnly || track.videoId.startsWith('local:');
    SongsTableData? match;
    try {
      if (getIt.isRegistered<IMusicRepository>()) {
        final repo = getIt<IMusicRepository>();
        final matchedRes = await repo.findMatchingLocalSong(
          remoteId: isLocalOnly ? null : track.videoId,
          title: track.title,
          artist: track.artist,
        );
        match = matchedRes.fold((_) => null, (s) => s);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to match local party track',
          error: e, stackTrace: st, category: 'PARTY');
    }
    if (match != null) return match;
    if (isLocalOnly) return null;
    return YtmTrack(
      videoId: track.videoId,
      title: track.title,
      artist: track.artist,
      duration: Duration(milliseconds: track.durationMs ?? 0),
      artworkUrl: track.thumbnailUrl,
    ).toSongData();
  }

  Future<void> _loadTrackForParty(
      PartyTrack track, PartyPlayback playback) async {
    final playerCubit = getIt<PlayerCubit>();
    final match = await _resolvePartyTrackToSong(track);
    if (match == null) {
      // Local-only track on the host device with no local match on this device.
      _activePartyTrackVideoId = track.videoId;
      _activePartyMatchedSongId = null;
      lastError.value =
          'Local track "${track.title}" is unavailable on this device.';
      if (playerCubit.state.isPlaying) {
        await playerCubit.pause();
      }
      return;
    }

    if (lastError.value != null &&
        lastError.value!.startsWith('Local track "')) {
      lastError.value = null;
    }

    _activePartyTrackVideoId = track.videoId;
    _activePartyMatchedSongId = match.id;

    final nowServer = _clock.serverNowMs();
    final plan = (!playback.isPlaying || nowServer == null)
        ? null
        : PartySyncController.planStart(
            anchorServerMs: playback.anchorMs,
            nowServerMs: nowServer,
          );
    final deferForFutureAnchor = plan != null && !plan.startImmediately;
    final loadPaused = !playback.isPlaying || deferForFutureAnchor;
    final targetPos = deferForFutureAnchor
        ? playback.positionMs
        : (effectivePartyPositionMs(playback) ?? playback.positionMs);

    if (loadPaused) {
      // Pause before loading with preservePlaybackState: true so joining a
      // paused or future-anchored room produces zero audible blip.
      if (playerCubit.state.isPlaying) {
        await playerCubit.pause();
      }
      await playerCubit.playSong(
        match,
        initialPosition: Duration(milliseconds: targetPos),
        openPlayerIfPlaying: false,
        preservePlaybackState: true,
      );
      if (playerCubit.state.isPlaying) {
        await playerCubit.pause();
      }
      if (playback.isPlaying && deferForFutureAnchor) {
        await _startAtAnchor(playback);
      }
      return;
    }

    await playerCubit.playSong(
      match,
      initialPosition: Duration(milliseconds: targetPos),
      openPlayerIfPlaying: false,
    );
  }

  // --------------------------------------------------------------------------
  // Outbound Party Actions
  // --------------------------------------------------------------------------

  void sendPlay() {
    _sendFrame({'type': 'control', 'action': 'play'});
  }

  void sendPause() {
    _sendFrame({'type': 'control', 'action': 'pause'});
  }

  void sendSeek(int positionMs) {
    _sendFrame({'type': 'control', 'action': 'seek', 'positionMs': positionMs});
  }

  void sendNext() {
    _sendFrame({'type': 'control', 'action': 'next'});
  }

  void sendPrevious() {
    _sendFrame({'type': 'control', 'action': 'previous'});
  }

  void sendKick(String memberId) {
    _sendFrame({
      'type': 'control',
      'action': 'kick',
      'memberId': memberId,
    });
  }

  void sendSetHostOnlyControl(bool enabled) {
    _sendFrame({
      'type': 'control',
      'action': 'setHostOnlyControl',
      'enabled': enabled,
    });
  }

  void sendQueueRemove(String videoId, {int? index}) {
    _sendFrame({
      'type': 'control',
      'action': 'queueRemove',
      'videoId': videoId,
      if (index != null) 'index': index,
    });
  }

  void sendSetQueue(List<PartyTrack> tracks, {int queueIndex = 0}) {
    _sendFrame({
      'type': 'control',
      'action': 'setQueue',
      'queue': tracks.map((t) => t.toJson()).toList(),
      'queueIndex': queueIndex,
    });
  }

  void sendSetAutoplay(bool enabled) {
    _sendFrame({
      'type': 'control',
      'action': 'setAutoplay',
      'enabled': enabled,
    });
  }

  @disposeMethod
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _disconnectWebSocket();
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _httpClient.close();
    connectionState.dispose();
    partySnapshot.dispose();
    currentMember.dispose();
    lastError.dispose();
    clockSynced.dispose();
    roundTripMs.dispose();
  }
}
