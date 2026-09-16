// lib/domain/services/usb_exclusive_service.dart
import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/platform_capabilities.dart';

/// Snapshot of the attached USB audio device and exclusive-path state.
class UsbExclusiveStatus {
  final bool attached;
  final bool permitted;
  final String? deviceName;
  final int? vendorId;
  final int? productId;
  final int uacVersion;
  final String uacLabel;
  final bool hasVolumeControl;
  final bool exclusiveActive;
  final bool exclusiveSupported;
  final double? hardwareVolumeDb;
  final double? minVolumeDb;
  final double? maxVolumeDb;
  final int? interfaceNumber;
  final bool streamingActive;
  final bool streamingSupported;

  const UsbExclusiveStatus({
    required this.attached,
    required this.permitted,
    this.deviceName,
    this.vendorId,
    this.productId,
    this.uacVersion = 0,
    this.uacLabel = 'none',
    this.hasVolumeControl = false,
    this.exclusiveActive = false,
    this.exclusiveSupported = false,
    this.hardwareVolumeDb,
    this.minVolumeDb,
    this.maxVolumeDb,
    this.interfaceNumber,
    this.streamingActive = false,
    this.streamingSupported = false,
  });

  static const UsbExclusiveStatus none = UsbExclusiveStatus(
    attached: false,
    permitted: false,
  );

  factory UsbExclusiveStatus.fromMap(Map<dynamic, dynamic> map) {
    double? d(Object? v) => v is num ? v.toDouble() : null;
    int? i(Object? v) => v is num ? v.toInt() : null;
    return UsbExclusiveStatus(
      attached: map['attached'] == true,
      permitted: map['permitted'] == true,
      deviceName: map['deviceName'] as String?,
      vendorId: i(map['vendorId']),
      productId: i(map['productId']),
      uacVersion: i(map['uacVersion']) ?? 0,
      uacLabel: (map['uacLabel'] as String?) ?? 'none',
      hasVolumeControl: map['hasVolumeControl'] == true,
      exclusiveActive: map['exclusiveActive'] == true,
      exclusiveSupported: map['exclusiveSupported'] == true,
      hardwareVolumeDb: d(map['hardwareVolumeDb']),
      minVolumeDb: d(map['minVolumeDb']),
      maxVolumeDb: d(map['maxVolumeDb']),
      interfaceNumber: i(map['interfaceNumber']),
      streamingActive: map['streamingActive'] == true,
      streamingSupported: map['streamingSupported'] == true,
    );
  }
}

/// Controls an attached USB DAC's hardware volume through UAC class requests
/// and exposes the optional exclusive-interface state.
class UsbExclusiveService {
  static const MethodChannel _methodChannel =
      MethodChannel(PulsrChannels.usbExclusive);
  static const EventChannel _eventChannel =
      EventChannel(PulsrChannels.usbExclusiveEvents);

  static final UsbExclusiveService _instance = UsbExclusiveService._internal();
  factory UsbExclusiveService() => _instance;
  UsbExclusiveService._internal();

  final StreamController<UsbExclusiveStatus> _controller =
      StreamController<UsbExclusiveStatus>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  UsbExclusiveStatus _last = UsbExclusiveStatus.none;

  Stream<UsbExclusiveStatus> get statusStream => _controller.stream;
  UsbExclusiveStatus get lastStatus => _last;

  bool get _isAndroid => PlatformCapabilities.isAndroid;

  void _ensureListening() {
    if (!_isAndroid || _subscription != null) return;
    try {
      _subscription = _eventChannel.receiveBroadcastStream().listen(
        (data) {
          if (data is Map) {
            final status = UsbExclusiveStatus.fromMap(data);
            _last = status;
            if (!_controller.isClosed) _controller.add(status);
          }
        },
        onError: (Object e, StackTrace st) {
          if (e is! MissingPluginException) {
            ErrorLogger.log('USB exclusive stream error',
                error: e, stackTrace: st, category: 'UsbExclusive');
          }
        },
        cancelOnError: false,
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to attach USB exclusive stream',
          error: e, stackTrace: st, category: 'UsbExclusive');
    }
  }

  Future<UsbExclusiveStatus> getStatus() async {
    if (!_isAndroid) return UsbExclusiveStatus.none;
    _ensureListening();
    try {
      final Map<dynamic, dynamic>? res = await _methodChannel
          .invokeMapMethod<dynamic, dynamic>('getStatus');
      if (res != null) {
        _last = UsbExclusiveStatus.fromMap(res);
        return _last;
      }
    } catch (e, st) {
      if (e is! MissingPluginException) {
        ErrorLogger.log('Failed to get USB status',
            error: e, stackTrace: st, category: 'UsbExclusive');
      }
    }
    return _last;
  }

  Future<bool> requestPermission() async {
    if (!_isAndroid) return false;
    try {
      final bool? granted = await _methodChannel
          .invokeMethod<bool>('requestPermission')
          .timeout(const Duration(seconds: 15));
      await getStatus();
      return granted ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to request USB permission',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  Future<bool> setExclusive(bool enabled) async {
    if (!_isAndroid) return false;
    if (enabled && (!_last.attached || !_last.permitted)) {
      await getStatus();
      if (!_last.attached || !_last.permitted) return false;
    }
    if (enabled && !_last.exclusiveSupported && _last.attached) {
      // Still attempt: some DACs report support only after first claim.
      ErrorLogger.addBreadcrumb('USB exclusive claim without advertised support',
          category: 'UsbExclusive');
    }
    try {
      final dynamic res = await _methodChannel
          .invokeMethod<dynamic>('setExclusive', {'enabled': enabled})
          .timeout(const Duration(seconds: 8));
      await getStatus();
      if (res is Map) return res['error'] == null;
      return res == true;
    } catch (e, st) {
      ErrorLogger.log('Failed to set USB exclusive($enabled)',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  Future<bool> setHardwareVolume(double db) async {
    if (!_isAndroid) return false;
    var clamped = db;
    final min = _last.minVolumeDb;
    final max = _last.maxVolumeDb;
    if (min != null && max != null && min <= max) {
      clamped = db.clamp(min, max);
    }
    try {
      final dynamic res = await _methodChannel
          .invokeMethod<dynamic>('setHardwareVolume', {'db': clamped})
          .timeout(const Duration(seconds: 5));
      if (res is Map && res['error'] != null) return false;
      await getStatus();
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to set USB hardware volume($db dB)',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  /// Raw UAC2 isochronous streaming (experimental; unvalidated on hardware).
  Future<bool> startStreaming({int sampleRate = 48000, int channels = 2}) async {
    if (!_isAndroid) return false;
    const validRates = [44100, 48000, 88200, 96000, 176400, 192000];
    if (!validRates.contains(sampleRate)) return false;
    if (channels < 1 || channels > 8) return false;
    if (!_last.permitted || !_last.streamingSupported) {
      await getStatus();
      if (!_last.permitted || !_last.streamingSupported) return false;
    }
    try {
      final dynamic res = await _methodChannel.invokeMethod<dynamic>(
          'startStreaming', {
        'sampleRate': sampleRate,
        'channels': channels,
      }).timeout(const Duration(seconds: 10));
      await getStatus();
      if (res is Map) return res['success'] == true;
      return false;
    } catch (e, st) {
      ErrorLogger.log('Failed to start USB streaming',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  Future<bool> stopStreaming() async {
    if (!_isAndroid) return false;
    try {
      final dynamic res = await _methodChannel
          .invokeMethod<dynamic>('stopStreaming')
          .timeout(const Duration(seconds: 5));
      await getStatus();
      if (res is Map) return res['success'] == true;
      return false;
    } catch (e, st) {
      ErrorLogger.log('Failed to stop USB streaming',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    if (!_controller.isClosed) _controller.close();
  }
}
