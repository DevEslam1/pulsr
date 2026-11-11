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
  formatUnsupported,
  submitFailed,
  invalidArgs,
  uac3Unsupported,
  clockNotVerified,
  uac1RateReadbackUnsupported,
  source32BitFloatNotBitPerfect,
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
      case UsbStreamResult.formatUnsupported:
        return 'DAC does not support requested format (rate, depth, or channels)';
      case UsbStreamResult.submitFailed:
        return 'Failed to submit isochronous USB transfer URBs';
      case UsbStreamResult.invalidArgs:
        return 'Invalid audio streaming configuration parameters';
      case UsbStreamResult.uac3Unsupported:
        return 'USB Audio Class 3 devices are not supported for bit-perfect streaming';
      case UsbStreamResult.clockNotVerified:
        return 'Could not verify the DAC clock source; streaming refused';
      case UsbStreamResult.uac1RateReadbackUnsupported:
        return 'UAC1 sample-rate readback is not supported by this DAC; Strict Bit-Perfect requires verified rates';
      case UsbStreamResult.source32BitFloatNotBitPerfect:
        return 'Source format is 32-bit float; lossy conversion to integer is not bit-perfect';
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
  /// Last successfully forwarded raw integer source depth; zero is nonraw.
  final int rawPcmBitDepth;
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
  /// Frames written to the wire while the render tap's channel count differed
  /// from the sink's. Non-zero means output is not sample-identical (channels
  /// were duplicated, silenced or dropped) and must be surfaced.
  final int channelMismatchFrames;
  final bool rateVerified;
  final List<Map<String, dynamic>> advertisedFormats;

  const UsbExclusiveStatus({
    required this.attached,
    required this.permitted,
    this.deviceId,
    this.hardwareVolumeApplied = false,
    this.streamingSampleRate = 0,
    this.streamingBitDepth = 0,
    this.streamingChannels = 0,
    this.rawPcmBitDepth = 0,
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
    this.channelMismatchFrames = 0,
    this.rateVerified = false,
    this.advertisedFormats = const [],
  });

  UsbExclusiveStatus copyWith({
    bool? attached,
    bool? permitted,
    int? deviceId,
    bool? hardwareVolumeApplied,
    int? streamingSampleRate,
    int? streamingBitDepth,
    int? streamingChannels,
    int? rawPcmBitDepth,
    String? deviceName,
    int? vendorId,
    int? productId,
    int? uacVersion,
    String? uacLabel,
    bool? hasVolumeControl,
    bool? exclusiveActive,
    bool? exclusiveSupported,
    double? hardwareVolumeDb,
    double? minVolumeDb,
    double? maxVolumeDb,
    int? interfaceNumber,
    bool? streamingActive,
    bool? streamingSupported,
    List<int>? supportedRates,
    int? lastError,
    int? lastStreamErrorCode,
    int? channelMismatchFrames,
    bool? rateVerified,
    List<Map<String, dynamic>>? advertisedFormats,
  }) {
    return UsbExclusiveStatus(
      attached: attached ?? this.attached,
      permitted: permitted ?? this.permitted,
      deviceId: deviceId ?? this.deviceId,
      hardwareVolumeApplied:
          hardwareVolumeApplied ?? this.hardwareVolumeApplied,
      streamingSampleRate: streamingSampleRate ?? this.streamingSampleRate,
      streamingBitDepth: streamingBitDepth ?? this.streamingBitDepth,
      streamingChannels: streamingChannels ?? this.streamingChannels,
      rawPcmBitDepth: rawPcmBitDepth ?? this.rawPcmBitDepth,
      deviceName: deviceName ?? this.deviceName,
      vendorId: vendorId ?? this.vendorId,
      productId: productId ?? this.productId,
      uacVersion: uacVersion ?? this.uacVersion,
      uacLabel: uacLabel ?? this.uacLabel,
      hasVolumeControl: hasVolumeControl ?? this.hasVolumeControl,
      exclusiveActive: exclusiveActive ?? this.exclusiveActive,
      exclusiveSupported: exclusiveSupported ?? this.exclusiveSupported,
      hardwareVolumeDb: hardwareVolumeDb ?? this.hardwareVolumeDb,
      minVolumeDb: minVolumeDb ?? this.minVolumeDb,
      maxVolumeDb: maxVolumeDb ?? this.maxVolumeDb,
      interfaceNumber: interfaceNumber ?? this.interfaceNumber,
      streamingActive: streamingActive ?? this.streamingActive,
      streamingSupported: streamingSupported ?? this.streamingSupported,
      supportedRates: supportedRates ?? this.supportedRates,
      lastError: lastError ?? this.lastError,
      lastStreamErrorCode: lastStreamErrorCode ?? this.lastStreamErrorCode,
      channelMismatchFrames:
          channelMismatchFrames ?? this.channelMismatchFrames,
      rateVerified: rateVerified ?? this.rateVerified,
      advertisedFormats: advertisedFormats ?? this.advertisedFormats,
    );
  }

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
      rawPcmBitDepth: map['streamingActive'] == true
          ? (i(map['rawPcmBitDepth']) ?? 0) : 0,
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
      channelMismatchFrames: i(map['channelMismatchFrames']) ?? 0,
      rateVerified: map['streamingActive'] == true && map['rateVerified'] == true,
      advertisedFormats: (map['advertisedFormats'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
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
    bool strict = false,
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
        'strict': strict,
      }).timeout(const Duration(seconds: 10));
      final status = await _readStatus();
      if (res is Map) {
        if (res['success'] == true) {
          final openedDepth = status?.streamingBitDepth ?? 0;
          final depthSatisfied = strict
              ? openedDepth == bitDepth
              : (openedDepth >= bitDepth &&
                  (openedDepth == 16 || openedDepth == 24 || openedDepth == 32));
          return status != null && status.attached && status.permitted &&
                  status.streamingActive && status.deviceId == before.deviceId &&
                  status.deviceId != null &&
                  status.streamingSampleRate == sampleRate &&
                  depthSatisfied &&
                  status.streamingChannels == channels
              ? UsbStreamResult.ok : UsbStreamResult.unknown;
        }
        final err = res['error'] as String?;
        switch (err) {
          case 'claim_failed':
            return UsbStreamResult.claimFailed;
          case 'alt_setting_failed':
            return UsbStreamResult.altSettingFailed;
          case 'format_unsupported':
            return UsbStreamResult.formatUnsupported;
          case 'rate_unsupported':
            return UsbStreamResult.rateUnsupported;
          case 'submit_failed':
            return UsbStreamResult.submitFailed;
          case 'invalid_args':
            return UsbStreamResult.invalidArgs;
          case 'uac3_unsupported':
            return UsbStreamResult.uac3Unsupported;
          case 'clock_not_verified':
            return UsbStreamResult.clockNotVerified;
          case 'uac1_rate_readback_unsupported':
            return UsbStreamResult.uac1RateReadbackUnsupported;
          case 'source_32bit_float_conversion_not_lossless':
            return UsbStreamResult.source32BitFloatNotBitPerfect;
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

  /// Channel count of the track the render tap last processed. 0 = unknown
  /// (nothing decoded yet), in which case the caller keeps its own default.
  Future<void> resetChannelMismatchFrames() async {
    if (!_isAndroid) return;
    try {
      await _methodChannel.invokeMethod<void>('resetChannelMismatchFrames');
    } catch (e, st) {
      ErrorLogger.log('Failed to reset channel mismatch frames',
          error: e, stackTrace: st, category: 'UsbExclusive');
    }
  }

  Future<int> getProducerChannels() async {
    if (!_isAndroid) return 0;
    try {
      final dynamic res = await _methodChannel
          .invokeMethod<dynamic>('getProducerChannels')
          .timeout(const Duration(milliseconds: 250));
      final value = (res as num?)?.toInt() ?? 0;
      return (value >= 1 && value <= 8) ? value : 0;
    } catch (e, st) {
      ErrorLogger.log('Failed to get producer channels', error: e, stackTrace: st, category: 'UsbExclusive');
      return 0;
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
    } catch (e, st) {
      ErrorLogger.log('Failed to get diagnostics', error: e, stackTrace: st, category: 'UsbExclusive');
      return const {};
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    if (!_controller.isClosed) _controller.close();
  }
}
