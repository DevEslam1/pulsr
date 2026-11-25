// lib/data/services/cast_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/platform_capabilities.dart';

/// A Google Cast device discovered over mDNS (fallback path).
class CastDevice {
  final String id;
  final String name;
  final String model;
  final String host;
  final int port;

  const CastDevice({
    required this.id,
    required this.name,
    this.model = '',
    this.host = '',
    this.port = 0,
  });

  static CastDevice? fromMap(Map<dynamic, dynamic> map) {
    final id = map['id'] as String?;
    if (id == null) return null;
    return CastDevice(
      id: id,
      name: (map['name'] as String?) ?? id,
      model: (map['model'] as String?) ?? '',
      host: (map['host'] as String?) ?? '',
      port: (map['port'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A Cast route from the Play Services MediaRouter (SDK path).
class CastRoute {
  final String id;
  final String name;
  final bool connected;
  final bool selected;

  const CastRoute({
    required this.id,
    required this.name,
    this.connected = false,
    this.selected = false,
  });

  static CastRoute? fromMap(Map<dynamic, dynamic> map) {
    final id = map['id'] as String?;
    if (id == null) return null;
    return CastRoute(
      id: id,
      name: (map['name'] as String?) ?? id,
      connected: map['connected'] == true,
      selected: map['selected'] == true,
    );
  }
}

/// Live Cast session state.
class CastSessionStatus {
  final bool available;
  final bool connected;
  final String? deviceName;
  final bool playing;
  final bool paused;
  final bool buffering;
  final String playerState;
  final int positionMs;
  final int durationMs;
  final String? title;
  final String? artist;
  final double? volume;
  final String? error;

  const CastSessionStatus({
    this.available = false,
    this.connected = false,
    this.deviceName,
    this.playing = false,
    this.paused = false,
    this.buffering = false,
    this.playerState = 'idle',
    this.positionMs = 0,
    this.durationMs = 0,
    this.title,
    this.artist,
    this.volume,
    this.error,
  });

  static const CastSessionStatus unavailable = CastSessionStatus();

  Duration get position =>
      Duration(milliseconds: positionMs < 0 ? 0 : positionMs);
  Duration get duration =>
      Duration(milliseconds: durationMs < 0 ? 0 : durationMs);

  factory CastSessionStatus.fromMap(Map<dynamic, dynamic> map) =>
      CastSessionStatus(
        available: map['available'] is bool ? map['available'] == true : true,
        connected: map['connected'] == true,
        deviceName: map['deviceName'] as String?,
        playing: map['playing'] == true,
        paused: map['paused'] == true,
        buffering: map['buffering'] == true,
        playerState: (map['playerState'] as String?) ??
            (map['playing'] == true
                ? 'playing'
                : (map['paused'] == true ? 'paused' : 'idle')),
        positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        title: map['title'] as String?,
        artist: map['artist'] as String?,
        volume: (map['volume'] as num?)?.toDouble().clamp(0.0, 1.0),
        error: map['error'] as String?,
      );
}

class CastResult {
  final bool success;
  final String? error;
  final String? message;

  const CastResult({required this.success, this.error, this.message});
}

/// Google Cast support.
///
/// Device discovery and session control use the Play Services Cast framework
/// (dev/ytm flavors) through [PulsrChannels.castSession]. When that plugin is
/// unavailable (prod "Pure" build or no Play Services) the service falls back
/// to native mDNS discovery on [PulsrChannels.cast]; sessions are then reported
/// as unavailable rather than silently ignored.
class CastService {
  static const MethodChannel _methodChannel = MethodChannel(PulsrChannels.cast);
  static const EventChannel _eventChannel =
      EventChannel(PulsrChannels.castEvents);

  static const MethodChannel _sessionChannel =
      MethodChannel(PulsrChannels.castSession);
  static const EventChannel _sessionEvents =
      EventChannel(PulsrChannels.castSessionEvents);

  static const String receiverAppId =
      String.fromEnvironment('CAST_RECEIVER_APP_ID');

  static CastService? _instance;
  factory CastService() => _instance ??= CastService._internal();
  CastService._internal();

  // ---- mDNS fallback ----
  final StreamController<List<CastDevice>> _devices =
      StreamController<List<CastDevice>>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  List<CastDevice> _current = const [];

  // ---- SDK session ----
  final StreamController<List<CastRoute>> _routes =
      StreamController<List<CastRoute>>.broadcast();
  final StreamController<CastSessionStatus> _session =
      StreamController<CastSessionStatus>.broadcast();
  StreamSubscription<dynamic>? _sessionSubscription;
  List<CastRoute> _currentRoutes = const [];
  CastSessionStatus _sessionStatus = CastSessionStatus.unavailable;
  // AUDIT-FIX (P3-24): Expose reactive Cast session status so player chrome
  // updates immediately when Cast connects or disconnects without polling.
  final ValueNotifier<CastSessionStatus> _sessionStatusNotifier =
      ValueNotifier<CastSessionStatus>(CastSessionStatus.unavailable);
  bool _sessionAvailable = false;

  Stream<List<CastDevice>> get devicesStream => _devices.stream;
  List<CastDevice> get devices => List.unmodifiable(_current);

  Stream<List<CastRoute>> get routesStream => _routes.stream;
  List<CastRoute> get routes => List.unmodifiable(_currentRoutes);

  Stream<CastSessionStatus> get sessionStream => _session.stream;
  CastSessionStatus get sessionStatus => _sessionStatus;
  ValueListenable<CastSessionStatus> get sessionStatusListenable =>
      _sessionStatusNotifier;

  void _setSessionStatus(CastSessionStatus status) {
    _sessionStatus = status;
    _sessionStatusNotifier.value = status;
    if (!_session.isClosed) _session.add(status);
  }

  /// Injects a Cast session status in tests to drive reactive chrome listeners.
  @visibleForTesting
  void debugSetSessionStatus(CastSessionStatus status) {
    _setSessionStatus(status);
  }

  bool get sessionAvailable => _sessionAvailable;

  bool get _isAndroid => PlatformCapabilities.isAndroid;

  // ---- SDK path ----

  Future<bool> isSessionAvailable() async {
    if (!_isAndroid) return false;
    _ensureSessionListening();
    try {
      _sessionAvailable =
          await _sessionChannel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (e, st) {
      if (e is! MissingPluginException) {
        ErrorLogger.log('Cast isSessionAvailable failed',
            error: e, stackTrace: st, category: 'Cast');
      }
      _sessionAvailable = false;
    }
    return _sessionAvailable;
  }

  void _ensureSessionListening() {
    if (!_isAndroid || _sessionSubscription != null) return;
    try {
      _sessionSubscription = _sessionEvents.receiveBroadcastStream().listen(
        (event) {
          if (event is! Map) return;
          if (event['type'] == 'routes' && event['routes'] is List) {
            final list = <CastRoute>[];
            for (final r in event['routes'] as List) {
              if (r is Map) {
                final route = CastRoute.fromMap(r);
                if (route != null) list.add(route);
              }
            }
            _currentRoutes = list;
            if (!_routes.isClosed) _routes.add(list);
          } else if (event['type'] == 'session') {
            _setSessionStatus(CastSessionStatus.fromMap(event));
          } else if (event['type'] == 'error') {
            ErrorLogger.log('Cast session error: ${event['error']}',
                category: 'Cast');
          }
        },
        onError: (Object e, StackTrace st) {
          if (e is! MissingPluginException) {
            ErrorLogger.log('Cast session stream error',
                error: e, stackTrace: st, category: 'Cast');
          }
        },
        cancelOnError: false,
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to attach cast session stream',
          error: e, stackTrace: st, category: 'Cast');
    }
  }

  Future<void> startSessionDiscovery() async {
    if (!_isAndroid) return;
    _ensureSessionListening();
    try {
      await _sessionChannel.invokeMethod<bool>('startDiscovery');
    } catch (e, st) {
      if (e is! MissingPluginException) {
        ErrorLogger.log('Cast startSessionDiscovery failed',
            error: e, stackTrace: st, category: 'Cast');
      }
    }
  }

  Future<void> stopSessionDiscovery() async {
    if (!_isAndroid) return;
    try {
      await _sessionChannel.invokeMethod<bool>('stopDiscovery');
    } catch (e, st) {
      if (e is! MissingPluginException) {
        ErrorLogger.log('Cast stopSessionDiscovery failed',
            error: e, stackTrace: st, category: 'Cast');
      }
    }
  }

  Future<bool> connect(String routeId) async {
    if (!_isAndroid || routeId.trim().isEmpty) return false;
    try {
      return await _sessionChannel.invokeMethod<bool>('connect',
              {'routeId': routeId}).timeout(const Duration(seconds: 8)) ??
          false;
    } catch (e, st) {
      ErrorLogger.log('Cast connect failed',
          error: e, stackTrace: st, category: 'Cast');
      return false;
    }
  }

  Future<bool> disconnect() async {
    if (!_isAndroid) return false;
    try {
      return await _sessionChannel.invokeMethod<bool>('disconnect') ?? false;
    } catch (e, st) {
      if (e is! MissingPluginException) {
        ErrorLogger.log('Cast disconnect failed',
            error: e, stackTrace: st, category: 'Cast');
      }
      return false;
    }
  }

  /// Stops the active cast session.
  Future<bool> stopCasting() => disconnect();

  /// Queries the live Cast session status from the platform plugin.
  Future<CastSessionStatus> getStatus() async {
    if (!_isAndroid) return CastSessionStatus.unavailable;
    try {
      final dynamic res =
          await _sessionChannel.invokeMethod<dynamic>('getStatus');
      if (res is Map) {
        final status = CastSessionStatus.fromMap(res);
        _setSessionStatus(status);
        return status;
      }
      return _sessionStatus;
    } catch (e, st) {
      ErrorLogger.log('Cast getStatus failed',
          error: e, stackTrace: st, category: 'Cast');
      return _sessionStatus;
    }
  }

  Future<CastResult> castLocalFile({
    required String path,
    String title = '',
    String artist = '',
    String album = '',
    String? artwork,
    String mime = 'audio/mpeg',
    int? durationMs,
    Duration? duration,
  }) async {
    if (!_isAndroid) {
      return const CastResult(success: false, error: 'unsupported_platform');
    }
    if (path.trim().isEmpty) {
      return const CastResult(
        success: false,
        error: 'invalid_path',
        message: 'A local file path is required to cast.',
      );
    }
    final resolvedDurationMs = duration?.inMilliseconds ?? durationMs;
    try {
      final dynamic res = await _sessionChannel.invokeMethod<dynamic>(
        'castLocalFile',
        {
          'path': path,
          'title': title,
          'artist': artist,
          'album': album,
          'artwork': artwork,
          'mime': mime,
          if (resolvedDurationMs != null && resolvedDurationMs > 0)
            'durationMs': resolvedDurationMs,
        },
      ).timeout(const Duration(seconds: 8));
      return _parseResult(res);
    } catch (e, st) {
      ErrorLogger.log('Cast castLocalFile failed',
          error: e, stackTrace: st, category: 'Cast');
      return const CastResult(success: false, error: 'channel_error');
    }
  }

  Future<CastResult> castUrl({
    required String url,
    String title = '',
    String artist = '',
    String album = '',
    String? artwork,
    String mime = 'audio/mpeg',
    int? durationMs,
    Duration? duration,
  }) async {
    if (!_isAndroid) {
      return const CastResult(success: false, error: 'unsupported_platform');
    }
    final parsed = Uri.tryParse(url.trim());
    final scheme = parsed?.scheme.toLowerCase();
    if (parsed == null ||
        (scheme != 'http' && scheme != 'https') ||
        parsed.host.isEmpty) {
      return const CastResult(
        success: false,
        error: 'invalid_url',
        message: 'A valid http(s) stream URL is required to cast.',
      );
    }
    final resolvedDurationMs = duration?.inMilliseconds ?? durationMs;
    try {
      final dynamic res = await _sessionChannel.invokeMethod<dynamic>(
        'castUrl',
        {
          'url': parsed.toString(),
          'title': title,
          'artist': artist,
          'album': album,
          'artwork': artwork,
          'mime': mime,
          if (resolvedDurationMs != null && resolvedDurationMs > 0)
            'durationMs': resolvedDurationMs,
        },
      ).timeout(const Duration(seconds: 8));
      return _parseResult(res);
    } catch (e, st) {
      ErrorLogger.log('Cast castUrl failed',
          error: e, stackTrace: st, category: 'Cast');
      return const CastResult(success: false, error: 'channel_error');
    }
  }

  Future<CastResult> setPlaybackStateResult(
    String action, {
    int? positionMs,
  }) async {
    if (!_isAndroid) {
      return const CastResult(success: false, error: 'unsupported_platform');
    }
    try {
      final dynamic res = await _sessionChannel.invokeMethod<dynamic>(
        'setPlaybackState',
        {'action': action, 'positionMs': positionMs},
      ).timeout(const Duration(seconds: 8));
      return _parseResult(res);
    } catch (e, st) {
      ErrorLogger.log('Cast setPlaybackState($action) failed',
          error: e, stackTrace: st, category: 'Cast');
      return const CastResult(success: false, error: 'channel_error');
    }
  }

  Future<bool> setPlaybackState(String action, {int? positionMs}) async {
    final result = await setPlaybackStateResult(action, positionMs: positionMs);
    return result.success;
  }

  Future<CastResult> play() => setPlaybackStateResult('play');

  Future<CastResult> pause() => setPlaybackStateResult('pause');

  Future<CastResult> stop() => setPlaybackStateResult('stop');

  Future<CastResult> seek(Duration position) {
    final ms = position.isNegative ? 0 : position.inMilliseconds;
    return setPlaybackStateResult('seek', positionMs: ms);
  }

  Future<CastResult> next() => setPlaybackStateResult('next');

  Future<CastResult> previous() => setPlaybackStateResult('previous');

  /// Sets the volume (0.0 to 1.0) on the active Cast device.
  Future<bool> setVolume(double volume) async {
    if (!_isAndroid || !_sessionStatus.connected) return false;
    try {
      final dynamic res = await _sessionChannel.invokeMethod<dynamic>(
        'setVolume',
        {'volume': volume.clamp(0.0, 1.0)},
      ).timeout(const Duration(seconds: 5));
      return res is Map && res['success'] == true;
    } catch (e, st) {
      ErrorLogger.log('Cast setVolume failed',
          error: e, stackTrace: st, category: 'Cast');
      return false;
    }
  }

  /// Reads the active Cast device volume (0.0 to 1.0).
  ///
  /// Returns `null` when there is no connected session or the platform build
  /// does not expose receiver volume, so callers never display a fabricated
  /// level.
  Future<double?> getVolume() async {
    if (!_isAndroid || !_sessionStatus.connected) return null;
    try {
      final dynamic res = await _sessionChannel
          .invokeMethod<dynamic>('getVolume')
          .timeout(const Duration(seconds: 5));
      if (res is Map && res['success'] == true && res['volume'] is num) {
        return (res['volume'] as num).toDouble().clamp(0.0, 1.0);
      }
      return null;
    } catch (e, st) {
      ErrorLogger.log('Cast getVolume failed',
          error: e, stackTrace: st, category: 'Cast');
      return null;
    }
  }

  /// Casts the entire playback queue to the receiver for continuous playback.
  Future<CastResult> castQueue({
    required List<Map<String, dynamic>> queueItems,
    int startIndex = 0,
    int startPositionMs = 0,
    bool repeatMode = false,
  }) async {
    if (!_isAndroid) {
      return const CastResult(success: false, error: 'unsupported_platform');
    }
    if (queueItems.isEmpty) {
      return const CastResult(
        success: false,
        error: 'empty_queue',
        message: 'Queue is empty.',
      );
    }
    try {
      final dynamic res = await _sessionChannel.invokeMethod<dynamic>(
        'castQueue',
        {
          'items': queueItems,
          'startIndex': startIndex,
          'startPositionMs': startPositionMs,
          'repeat': repeatMode,
        },
      ).timeout(const Duration(seconds: 8));
      return _parseResult(res);
    } catch (e, st) {
      ErrorLogger.log('Cast castQueue failed',
          error: e, stackTrace: st, category: 'Cast');
      return const CastResult(success: false, error: 'channel_error');
    }
  }

  CastResult _parseResult(dynamic res) {
    if (res is Map) {
      return CastResult(
        success: res['success'] == true,
        error: res['error'] as String?,
        message: res['message'] as String?,
      );
    }
    return const CastResult(success: false, error: 'unknown_response');
  }

  // ---- mDNS fallback path ----

  Future<bool> isSupported() async {
    if (!_isAndroid) return false;
    try {
      return await _methodChannel.invokeMethod<bool>('isSupported') ?? false;
    } catch (e, st) {
      if (e is! MissingPluginException) {
        ErrorLogger.log('Cast isSupported failed',
            error: e, stackTrace: st, category: 'Cast');
      }
      return false;
    }
  }

  void _ensureListening() {
    if (!_isAndroid || _subscription != null) return;
    try {
      _subscription = _eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is! Map) return;
          if (event['type'] == 'devices' && event['devices'] is List) {
            final list = <CastDevice>[];
            for (final d in event['devices'] as List) {
              if (d is Map) {
                final dev = CastDevice.fromMap(d);
                if (dev != null) list.add(dev);
              }
            }
            _current = list;
            if (!_devices.isClosed) _devices.add(list);
          } else if (event['type'] == 'error') {
            ErrorLogger.log('Cast discovery error: ${event['error']}',
                category: 'Cast');
          }
        },
        onError: (Object e, StackTrace st) {
          if (e is! MissingPluginException) {
            ErrorLogger.log('Cast stream error',
                error: e, stackTrace: st, category: 'Cast');
          }
        },
        cancelOnError: false,
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to attach cast stream',
          error: e, stackTrace: st, category: 'Cast');
    }
  }

  Future<void> startDiscovery() async {
    if (!_isAndroid) return;
    _ensureListening();
    try {
      await _methodChannel.invokeMethod<bool>('startDiscovery');
    } catch (e, st) {
      if (e is! MissingPluginException) {
        ErrorLogger.log('Cast startDiscovery failed',
            error: e, stackTrace: st, category: 'Cast');
      }
    }
  }

  Future<void> stopDiscovery() async {
    if (!_isAndroid) return;
    try {
      await _methodChannel.invokeMethod<bool>('stopDiscovery');
    } catch (e, st) {
      if (e is! MissingPluginException) {
        ErrorLogger.log('Cast stopDiscovery failed',
            error: e, stackTrace: st, category: 'Cast');
      }
    }
  }

  Future<CastResult> castTo(String deviceId) async {
    if (!_isAndroid) {
      return const CastResult(success: false, error: 'unsupported_platform');
    }
    try {
      final dynamic res = await _methodChannel.invokeMethod<dynamic>('castTo', {
        'deviceId': deviceId,
        'appId': receiverAppId,
      }).timeout(const Duration(seconds: 8));
      return _parseResult(res);
    } catch (e, st) {
      ErrorLogger.log('Cast castTo failed',
          error: e, stackTrace: st, category: 'Cast');
      return const CastResult(success: false, error: 'channel_error');
    }
  }

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (identical(_instance, this)) {
      _instance = null;
    }
    _subscription?.cancel();
    _subscription = null;
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
    if (!_devices.isClosed) _devices.close();
    if (!_routes.isClosed) _routes.close();
    if (!_session.isClosed) _session.close();
    try {
      _sessionStatusNotifier.dispose();
    } catch (e, st) {
      ErrorLogger.log('Error disposing Cast session status notifier',
          error: e, stackTrace: st, category: 'Cast');
    }
  }
}
