// lib/domain/services/cast_service.dart
import 'dart:async';
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
  final int positionMs;
  final String? error;

  const CastSessionStatus({
    this.available = false,
    this.connected = false,
    this.deviceName,
    this.playing = false,
    this.positionMs = 0,
    this.error,
  });

  static const CastSessionStatus unavailable = CastSessionStatus();

  factory CastSessionStatus.fromMap(Map<dynamic, dynamic> map) => CastSessionStatus(
        available: true,
        connected: map['connected'] == true,
        deviceName: map['deviceName'] as String?,
        playing: map['playing'] == true,
        positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
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

  static final CastService _instance = CastService._internal();
  factory CastService() => _instance;
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
  bool _sessionAvailable = false;

  Stream<List<CastDevice>> get devicesStream => _devices.stream;
  List<CastDevice> get devices => List.unmodifiable(_current);

  Stream<List<CastRoute>> get routesStream => _routes.stream;
  List<CastRoute> get routes => List.unmodifiable(_currentRoutes);

  Stream<CastSessionStatus> get sessionStream => _session.stream;
  CastSessionStatus get sessionStatus => _sessionStatus;

  bool get sessionAvailable => _sessionAvailable;

  bool get _isAndroid => PlatformCapabilities.isAndroid;

  // ---- SDK path ----

  Future<bool> isSessionAvailable() async {
    if (!_isAndroid) return false;
    _ensureSessionListening();
    try {
      _sessionAvailable =
          await _sessionChannel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (e) {
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
            final status = CastSessionStatus.fromMap(event);
            _sessionStatus = status;
            if (!_session.isClosed) _session.add(status);
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
    } catch (_) {}
  }

  Future<void> stopSessionDiscovery() async {
    if (!_isAndroid) return;
    try {
      await _sessionChannel.invokeMethod<bool>('stopDiscovery');
    } catch (_) {}
  }

  Future<bool> connect(String routeId) async {
    if (!_isAndroid) return false;
    try {
      return await _sessionChannel
              .invokeMethod<bool>('connect', {'routeId': routeId}) ??
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
    } catch (_) {
      return false;
    }
  }

  Future<CastResult> castLocalFile({
    required String path,
    String title = '',
    String artist = '',
    String album = '',
    String? artwork,
    String mime = 'audio/mpeg',
  }) async {
    if (!_isAndroid) {
      return const CastResult(success: false, error: 'unsupported_platform');
    }
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
        },
      );
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
  }) async {
    if (!_isAndroid) {
      return const CastResult(success: false, error: 'unsupported_platform');
    }
    try {
      final dynamic res = await _sessionChannel.invokeMethod<dynamic>(
        'castUrl',
        {
          'url': url,
          'title': title,
          'artist': artist,
          'album': album,
          'artwork': artwork,
          'mime': mime,
        },
      );
      return _parseResult(res);
    } catch (e, st) {
      ErrorLogger.log('Cast castUrl failed',
          error: e, stackTrace: st, category: 'Cast');
      return const CastResult(success: false, error: 'channel_error');
    }
  }

  Future<bool> setPlaybackState(String action, {int? positionMs}) async {
    if (!_isAndroid) return false;
    try {
      final dynamic res = await _sessionChannel.invokeMethod<dynamic>(
        'setPlaybackState',
        {'action': action, 'positionMs': positionMs},
      );
      return res is Map && res['success'] == true;
    } catch (_) {
      return false;
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
    } catch (_) {
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
    } catch (_) {}
  }

  Future<void> stopDiscovery() async {
    if (!_isAndroid) return;
    try {
      await _methodChannel.invokeMethod<bool>('stopDiscovery');
    } catch (_) {}
  }

  Future<CastResult> castTo(String deviceId) async {
    if (!_isAndroid) {
      return const CastResult(success: false, error: 'unsupported_platform');
    }
    try {
      final dynamic res = await _methodChannel
          .invokeMethod<dynamic>('castTo', {
        'deviceId': deviceId,
        'appId': receiverAppId,
      })
          .timeout(const Duration(seconds: 8));
      return _parseResult(res);
    } catch (e, st) {
      ErrorLogger.log('Cast castTo failed',
          error: e, stackTrace: st, category: 'Cast');
      return const CastResult(success: false, error: 'channel_error');
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
    if (!_devices.isClosed) _devices.close();
    if (!_routes.isClosed) _routes.close();
    if (!_session.isClosed) _session.close();
  }
}
