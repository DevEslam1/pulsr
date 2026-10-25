// lib/data/party/listen_together_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/di/injection.dart';
import '../../core/services/ytm_account_service.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../db/app_database.dart';
import 'party_models.dart';
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

  static const double maxAllowedDriftSeconds = 1.2;
  static const int driftLimitMs = 1200; // 1.2 seconds
  static const int pingIntervalMs = 10000; // 10s ping loop
  static const int maxDriftStrikes = 2; // 2 consecutive ticks exceeding drift

  final ServerClock _clock = ServerClock();
  ServerClock get clock => _clock;

  final ValueNotifier<PartyConnectionState> connectionState =
      ValueNotifier<PartyConnectionState>(PartyConnectionState.offline);

  final ValueNotifier<PartySnapshot?> partySnapshot =
      ValueNotifier<PartySnapshot?>(null);

  final ValueNotifier<PartyMember?> currentMember =
      ValueNotifier<PartyMember?>(null);

  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  int _reconnectAttempts = 0;

  final ValueNotifier<bool> clockSynced = ValueNotifier<bool>(false);

  final ValueNotifier<int> roundTripMs = ValueNotifier<int>(0);

  final http.Client _httpClient = http.Client();

  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  Timer? _pingTimer;
  Timer? _reconcileTimer;

  String? _activeCode;
  String? _activeToken;
  String? _activeServerBase;

  bool _isHost = false;
  bool get isHost => _isHost;
  bool get inParty => _activeCode != null;
  String? get currentPartyCode => _activeCode;

  // Drift correction state
  int _consecutiveDriftStrikes = 0;
  int _lastHandledSeq = -1;
  int _reconcileQuietUntilMs = 0;

  // Subscriptions to local PlayerCubit
  StreamSubscription? _playerStateSub;
  bool _isReconcilingInbound = false;

  /// Initializes party session if persisted or registers listener.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
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
    } catch (_) {
      savedToken = prefs.getString(prefSavedTokenKey);
    }
    final serverBase = await getServerUrl();

    if (savedCode != null && savedToken != null) {
      _activeCode = savedCode;
      _activeToken = savedToken;
      _activeServerBase = serverBase;
      _connectWebSocket();
    }

    _bindPlayerCubitEvents();
  }

  /// Configured server URL (custom or fallback to default).
  Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(prefCustomServerKey)?.trim();
    if (custom != null && custom.isNotEmpty) {
      return _normalizeUrl(custom);
    }
    return defaultServerUrl;
  }

  Future<void> setCustomServerUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      await prefs.remove(prefCustomServerKey);
    } else {
      await prefs.setString(prefCustomServerKey, _normalizeUrl(url.trim()));
    }
  }

  String _normalizeUrl(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url;
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

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      final err = 'Failed to create party (${resp.statusCode}): ${resp.body}';
      lastError.value = err;
      throw Exception(err);
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
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
    final resp = await _httpClient
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(identity.toJson()),
        )
        .timeout(const Duration(seconds: 12));

    if (resp.statusCode != 200) {
      final err = 'Failed to join party (${resp.statusCode}): ${resp.body}';
      lastError.value = err;
      throw Exception(err);
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final membership = PartyMembership.fromJson(data);

    await _saveSession(serverBase, membership.code, membership.token);
    _applyMembership(membership);
    _connectWebSocket();

    return membership.code;
  }

  /// Leave the active party.
  Future<void> leaveParty() async {
    final code = _activeCode;
    final token = _activeToken;
    final serverBase = _activeServerBase ?? await getServerUrl();

    _disconnectWebSocket();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
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

    if (code != null && token != null) {
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
    partySnapshot.value = membership.party;
    currentMember.value = membership.you;
    _isHost = membership.you.isHost;
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

    connectionState.value = PartyConnectionState.connecting;
    final wsBase = _resolveWsBase(serverBase);
    final wsUri = Uri.parse('$wsBase/ws/parties/$code');

    try {
      _channel = WebSocketChannel.connect(
        wsUri,
        protocols: ['Bearer', token],
      );
      // Do not claim "live" before the WebSocket handshake succeeds.
      await _channel!.ready.timeout(const Duration(seconds: 12));
      _reconnectAttempts = 0;
      lastError.value = null;
      _channelSub = _channel!.stream.listen(
        _onWebSocketMessage,
        onError: (e, st) {
          ErrorLogger.log('Party WebSocket error',
              error: e, stackTrace: st, category: 'PARTY');
          _scheduleReconnect();
        },
        onDone: () {
          _scheduleReconnect();
        },
      );

      _startPingLoop();
      _startReconciliationTicker();
      connectionState.value = PartyConnectionState.live;
    } catch (e, st) {
      ErrorLogger.log('Party WebSocket connect failed',
          error: e, stackTrace: st, category: 'PARTY');
      _scheduleReconnect();
    }
  }

  void _disconnectWebSocket() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconcileTimer?.cancel();
    _reconcileTimer = null;
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
    _reconnectTimer?.cancel();
    if (_activeCode == null || _activeToken == null) return;
    _reconnectAttempts++;
    if (_reconnectAttempts > 5) {
      connectionState.value = PartyConnectionState.offline;
      lastError.value =
          'Unable to reconnect to the party. Check your connection.';
      return;
    }
    connectionState.value = PartyConnectionState.connecting;
    final delay =
        Duration(seconds: math.min(30, 3 * (1 << (_reconnectAttempts - 1))));
    _reconnectTimer = Timer(delay, () {
      if (_activeCode != null && _activeToken != null) {
        _connectWebSocket();
      }
    });
  }

  void _startPingLoop() {
    _pingTimer?.cancel();
    // Burst 4 pings initially for instant accurate clock sync
    var burstCount = 0;
    Timer.periodic(const Duration(milliseconds: 300), (timer) {
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
    _sendFrame({
      'type': 'ping',
      'clientMs': clientMs,
    });
  }

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
          if (partyJson != null) {
            final snap = PartySnapshot.fromJson(partyJson);
            partySnapshot.value = snap;
          }
          if (youJson != null) {
            final you = PartyMember.fromJson(youJson);
            currentMember.value = you;
            _isHost = you.isHost;
          }
          connectionState.value = PartyConnectionState.live;
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

          // Update host status if member was promoted
          final myId = currentMember.value?.memberId;
          if (myId != null) {
            final me = members.where((m) => m.memberId == myId).firstOrNull;
            if (me != null) {
              currentMember.value = me;
              _isHost = me.isHost;
            }
          }
          break;

        case 'bye':
          leaveParty();
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

  void _bindPlayerCubitEvents() {
    _playerStateSub?.cancel();
    if (!getIt.isRegistered<PlayerCubit>()) return;

    final playerCubit = getIt<PlayerCubit>();
    DateTime? lastAt;
    Duration lastPosition = Duration.zero;
    String? lastSongKey;
    bool? lastPlaying;
    _playerStateSub = playerCubit.stream.listen((state) {
      if (!inParty || !_isHost) return;
      if (_isReconcilingInbound) return;

      final now = DateTime.now();
      final songKey =
          state.currentSong?.remoteId ?? state.currentSong?.id.toString();
      final expectedPosition = lastPlaying == true && lastAt != null
          ? lastPosition + now.difference(lastAt!)
          : lastPosition;
      final seeked = (state.position - expectedPosition).abs() >
          const Duration(seconds: 2);
      final changed =
          songKey != lastSongKey || state.isPlaying != lastPlaying || seeked;
      final heartbeatDue = lastAt == null ||
          now.difference(lastAt!) >= const Duration(seconds: 2);
      if (!changed && !(state.isPlaying && heartbeatDue)) return;
      lastAt = now;
      lastPosition = state.position;
      lastSongKey = songKey;
      lastPlaying = state.isPlaying;
      _broadcastHostPlayback(
          state.currentSong, state.isPlaying, state.position);
    });
  }

  void _broadcastHostPlayback(
      SongsTableData? song, bool isPlaying, Duration position) {
    if (!inParty) return;

    final serverNow =
        _clock.serverNowMs() ?? DateTime.now().millisecondsSinceEpoch;
    final track = song != null
        ? PartyTrack(
            videoId: song.remoteId ?? song.id.toString(),
            title: song.title,
            artist: song.artist,
            thumbnailUrl: song.remoteArtworkUrl ?? song.artworkUri,
            durationMs: song.durationMs,
          )
        : null;

    _sendFrame({
      'type': 'control',
      'action': 'setTrack',
      'track': track?.toJson(),
      'isPlaying': isPlaying,
      'positionMs': position.inMilliseconds,
      'anchorMs': serverNow,
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
    _reconcileTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (!inParty || _isHost) return;
      final snap = partySnapshot.value;
      if (snap == null) return;
      _checkMemberDrift(snap.playback);
    });
  }

  Future<void> _onInboundPlaybackUpdate(PartyPlayback playback) async {
    if (!inParty || _isHost) return;
    if (playback.seq <= _lastHandledSeq) return;
    _lastHandledSeq = playback.seq;

    _checkMemberDrift(playback, forceTrackReconciliation: true);
  }

  Future<void> _checkMemberDrift(
    PartyPlayback playback, {
    bool forceTrackReconciliation = false,
  }) async {
    if (!getIt.isRegistered<PlayerCubit>()) return;
    final playerCubit = getIt<PlayerCubit>();
    final playerState = playerCubit.state;

    final targetTrack = playback.track;
    if (targetTrack == null) return;

    final now = _clock.nowMs();
    if (now < _reconcileQuietUntilMs) return;

    // 1. Reconcile Track: verify current track matches target videoId
    final currentSong = playerState.currentSong;
    final currentVideoId = currentSong?.remoteId ?? currentSong?.id.toString();

    if (forceTrackReconciliation || currentVideoId != targetTrack.videoId) {
      if (currentVideoId != targetTrack.videoId) {
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
      _isReconcilingInbound = true;
      try {
        await playerCubit.play();
      } finally {
        _isReconcilingInbound = false;
      }
    }

    // 3. Drift check
    if (!playback.isPlaying || !_clock.synced) return;

    final effectivePos = effectivePartyPositionMs(playback);
    if (effectivePos == null) return;

    final localPos = playerState.position.inMilliseconds;
    final drift = (localPos - effectivePos).abs();

    if (drift > driftLimitMs) {
      _consecutiveDriftStrikes++;
      if (_consecutiveDriftStrikes >= maxDriftStrikes) {
        _consecutiveDriftStrikes = 0;
        _isReconcilingInbound = true;
        _reconcileQuietUntilMs = now + 1500;
        try {
          await playerCubit.seek(Duration(milliseconds: effectivePos));
        } finally {
          _isReconcilingInbound = false;
        }
      }
    } else {
      _consecutiveDriftStrikes = 0;
    }
  }

  Future<void> _loadTrackForParty(
      PartyTrack track, PartyPlayback playback) async {
    final playerCubit = getIt<PlayerCubit>();

    // 1. Try matching local database first
    SongsTableData? match;
    try {
      final repo = getIt<IMusicRepository>();
      final localSongsResult = await repo.getAllSongs();
      final localSongs =
          localSongsResult.fold((_) => <SongsTableData>[], (s) => s);
      match = localSongs.where((s) => s.remoteId == track.videoId).firstOrNull;
      if (match == null && track.title.isNotEmpty) {
        match = localSongs
            .where((s) =>
                s.title.toLowerCase() == track.title.toLowerCase() &&
                s.artist.toLowerCase() == track.artist.toLowerCase())
            .firstOrNull;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to match local party track',
          error: e, stackTrace: st, category: 'PARTY');
    }

    // 2. If not in local library, create a YtmTrack
    match ??= YtmTrack(
      videoId: track.videoId,
      title: track.title,
      artist: track.artist,
      duration: Duration(milliseconds: track.durationMs ?? 0),
      artworkUrl: track.thumbnailUrl,
    ).toSongData();

    final targetPos = effectivePartyPositionMs(playback) ?? playback.positionMs;

    await playerCubit.playSong(
      match,
      initialPosition: Duration(milliseconds: targetPos),
    );

    if (!playback.isPlaying) {
      await playerCubit.pause();
    }
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
}
