// lib/data/services/usb_exclusive_service.dart
import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/platform_capabilities.dart';

/// Structured result enum matching native UsbStreamResult codes.
enum UsbStreamResult {
  ok,
  claimFailed,
  altSettingFailed,
  rateUnsupported,
  submitFailed,
  invalidArgs,
  unknown;

  bool get isOk => this == UsbStreamResult.ok;

  String toUserMessage() {
    switch (this) {
      case UsbStreamResult.ok:
        return 'Streaming active';
      case UsbStreamResult.claimFailed:
        return 'USB interface is busy or claimed by another process';
      case UsbStreamResult.altSettingFailed:
        return 'Failed to select USB audio streaming alternate setting';
      case UsbStreamResult.rateUnsupported:
        return 'DAC does not support requested sample rate';
      case UsbStreamResult.submitFailed:
        return 'Failed to submit isochronous USB transfer URBs';
      case UsbStreamResult.invalidArgs:
        return 'Invalid audio streaming configuration parameters';
      case UsbStreamResult.unknown:
        return 'Failed to initialize USB bit-perfect streaming';
    }
  }
}

/// Snapshot of the attached USB audio device and exclusive-path state.
class UsbExclusiveStatus {
  final bool attached;
  final bool permitted;
  /// Android UsbDevice.deviceId, NOT AudioDeviceInfo.id.
  final int? deviceId;
  final bool hardwareVolumeApplied;
  final int streamingSampleRate;
  final int streamingBitDepth;
  final int streamingChannels;
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
  final List<int> supportedRates;
  final int? lastError;
  final int? lastStreamErrorCode;

  const UsbExclusiveStatus({
    required this.attached,
    required this.permitted,
    this.deviceId,
    this.hardwareVolumeApplied = false,
    this.streamingSampleRate = 0,
    this.streamingBitDepth = 0,
    this.streamingChannels = 0,
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
    this.supportedRates = const [],
    this.lastError,
    this.lastStreamErrorCode,
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
      deviceId: i(map['deviceId']),
      hardwareVolumeApplied: map['hardwareVolumeApplied'] == true,
      streamingSampleRate: i(map['streamingSampleRate']) ?? 0,
      streamingBitDepth: i(map['streamingBitDepth']) ?? 0,
      streamingChannels: i(map['streamingChannels']) ?? 0,
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
      supportedRates: (map['supportedRates'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      lastError: i(map['lastError']),
      lastStreamErrorCode: i(map['resultCode']),
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

  Future<UsbExclusiveStatus> getStatus() async =>
      await _readStatus() ?? UsbExclusiveStatus.none;

  void _publish(UsbExclusiveStatus status) {
    _last = status;
    if (!_controller.isClosed) _controller.add(status);
  }

  // Null means unknown, not a confirmed inactive stream. Never use the cache
  // to acknowledge a start/stop or a hardware volume write.
  Future<UsbExclusiveStatus?> _readStatus() async {
    if (!_isAndroid) return null;
    _ensureListening();
    try {
      final Map<dynamic, dynamic>? res =
          await _methodChannel.invokeMapMethod<dynamic, dynamic>('getStatus');
      if (res != null) {
        _publish(UsbExclusiveStatus.fromMap(res));
        return _last;
      }
    } catch (e, st) {
      if (e is! MissingPluginException) {
        ErrorLogger.log('Failed to get USB status',
            error: e, stackTrace: st, category: 'UsbExclusive');
      }
    }
    _publish(UsbExclusiveStatus.none);
    return null;
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
    if (enabled) {
      await getStatus();
      if (!_last.attached || !_last.permitted) return false;
    }
    if (enabled && !_last.exclusiveSupported && _last.attached) {
      // Still attempt: some DACs report support only after first claim.
      ErrorLogger.addBreadcrumb(
          'USB exclusive claim without advertised support',
          category: 'UsbExclusive');
    }
    try {
      final dynamic res = await _methodChannel.invokeMethod<dynamic>(
          'setExclusive',
          {'enabled': enabled}).timeout(const Duration(seconds: 8));
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
      final dynamic res = await _methodChannel.invokeMethod<dynamic>(
          'setHardwareVolume',
          {'db': clamped}).timeout(const Duration(seconds: 5));
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
  Future<UsbStreamResult> startStreaming({
    int sampleRate = 48000,
    int channels = 2,
    int bitDepth = 16,
  }) async {
    if (!_isAndroid) return UsbStreamResult.invalidArgs;
    const validRates = [
      44100,
      48000,
      88200,
      96000,
      176400,
      192000,
      352800,
      384000
    ];
    if (!validRates.contains(sampleRate)) {
      return UsbStreamResult.rateUnsupported;
    }
    if (channels < 1 || channels > 8) return UsbStreamResult.invalidArgs;
    if (![16, 24, 32].contains(bitDepth)) return UsbStreamResult.invalidArgs;
    final before = await _readStatus();
    if (before == null || !before.attached || !before.permitted) {
      return UsbStreamResult.claimFailed;
    }
    if (!before.streamingSupported) return UsbStreamResult.invalidArgs;
    try {
      final dynamic res =
          await _methodChannel.invokeMethod<dynamic>('startStreaming', {
        'sampleRate': sampleRate,
        'channels': channels,
        'bitDepth': bitDepth,
      }).timeout(const Duration(seconds: 10));
      final status = await _readStatus();
      if (res is Map) {
        if (res['success'] == true) {
          return status != null && status.attached && status.permitted &&
                  status.streamingActive && status.deviceId == before.deviceId &&
                  status.deviceId != null &&
                  status.streamingSampleRate == sampleRate &&
                  status.streamingBitDepth == bitDepth &&
                  status.streamingChannels == channels
              ? UsbStreamResult.ok : UsbStreamResult.unknown;
        }
        final err = res['error'] as String?;
        switch (err) {
          case 'claim_failed':
            return UsbStreamResult.claimFailed;
          case 'alt_setting_failed':
            return UsbStreamResult.altSettingFailed;
          case 'rate_unsupported':
            return UsbStreamResult.rateUnsupported;
          case 'submit_failed':
            return UsbStreamResult.submitFailed;
          case 'invalid_args':
            return UsbStreamResult.invalidArgs;
          default:
            return UsbStreamResult.unknown;
        }
      }
      return UsbStreamResult.unknown;
    } catch (e, st) {
      ErrorLogger.log('Failed to start USB streaming',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return UsbStreamResult.unknown;
    }
  }

  Future<List<int>> querySupportedRates() async {
    if (!_isAndroid) return const [];
    try {
      final List<dynamic>? res = await _methodChannel
          .invokeListMethod<dynamic>('querySupportedRates')
          .timeout(const Duration(seconds: 3));
      if (res != null) {
        final rates = res.map((e) => (e as num).toInt()).toList()..sort();
        return rates;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to query USB supported rates',
          error: e, stackTrace: st, category: 'UsbExclusive');
    }
    return _last.supportedRates;
  }

  Future<bool> stopStreaming() async {
    if (!_isAndroid) return false;
    try {
      final dynamic res = await _methodChannel
          .invokeMethod<dynamic>('stopStreaming')
          .timeout(const Duration(seconds: 5));
      final status = await _readStatus();
      return res is Map && res['success'] == true &&
          status != null && !status.streamingActive;
    } catch (e, st) {
      ErrorLogger.log('Failed to stop USB streaming',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  Future<double> getBufferedMs() async {
    if (!_isAndroid) return 0.0;
    try {
      final dynamic res = await _methodChannel
          .invokeMethod<dynamic>('getBufferedMs')
          .timeout(const Duration(milliseconds: 250));
      return (res as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  Future<Map<String, dynamic>> getDiagnostics() async {
    if (!_isAndroid) return const {};
    try {
      final dynamic res = await _methodChannel
          .invokeMethod<dynamic>('getDiagnostics')
          .timeout(const Duration(milliseconds: 500));
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return const {};
    } catch (_) {
      return const {};
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    if (!_controller.isClosed) _controller.close();
  }
}
