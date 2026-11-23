// lib/data/services/usb_exclusive_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
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
  clockSelectorRestoreFailed,
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
      case UsbStreamResult.clockSelectorRestoreFailed:
        return 'The DAC clock selector could not be restored; streaming refused';
      case UsbStreamResult.unknown:
        return 'Failed to initialize USB bit-perfect streaming';
    }
  }
}

/// Probed UAC2 DSD alternate setting tuple.
class DsdAltSettingTuple {
  final int interfaceNumber;
  final int altSetting;
  final int endpointAddress;
  final int channels;
  final int bytesPerSample;
  final int framesPerSecond;
  final int dsdRate;

  const DsdAltSettingTuple({
    required this.interfaceNumber,
    required this.altSetting,
    required this.endpointAddress,
    this.channels = 2,
    this.bytesPerSample = 4,
    required this.framesPerSecond,
    required this.dsdRate,
  });

  factory DsdAltSettingTuple.fromList(List<dynamic> list) {
    int toInt(dynamic v, int fallback) => v is num ? v.toInt() : fallback;
    return DsdAltSettingTuple(
      interfaceNumber: list.isNotEmpty ? toInt(list[0], 0) : 0,
      altSetting: list.length > 1 ? toInt(list[1], 0) : 0,
      endpointAddress: list.length > 2 ? toInt(list[2], 0) : 0,
      channels: list.length > 3 ? toInt(list[3], 2) : 2,
      bytesPerSample: list.length > 4 ? toInt(list[4], 4) : 4,
      framesPerSecond: list.length > 5 ? toInt(list[5], 0) : 0,
      dsdRate: list.length > 6 ? toInt(list[6], 0) : 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'interfaceNumber': interfaceNumber,
        'altSetting': altSetting,
        'endpoint': endpointAddress,
        'channels': channels,
        'bytesPerSample': bytesPerSample,
        'framesPerSecond': framesPerSecond,
        'dsdRate': dsdRate,
      };

  @override
  String toString() =>
      'DsdAltSettingTuple(iface: $interfaceNumber, alt: $altSetting, ep: 0x${endpointAddress.toRadixString(16)}, '
      'channels: $channels, bytes: $bytesPerSample, fps: $framesPerSecond, rate: DSD$dsdRate)';
}

/// Clock architecture actually in use for an active direct-USB stream.
///
/// The native sink derives this from the data path, not from what the UI asked
/// for. `bitPerfectLocked` is only reported when raw integer PCM of the same
/// rate, depth and channel count reached the wire with no SRC, dither, remap or
/// underrun for the session.
enum UsbClockDomain {
  unknown,
  bitPerfectLocked,
  asrc,
  bestEffort;

  /// Parses the stable wire name from Kotlin/native. Unknown values fail closed
  /// to [unknown] so a new native label can never be rendered as a claim.
  static UsbClockDomain fromWire(Object? value) {
    switch (value) {
      case 'bitPerfectLocked':
        return UsbClockDomain.bitPerfectLocked;
      case 'asrc':
        return UsbClockDomain.asrc;
      case 'bestEffort':
        return UsbClockDomain.bestEffort;
      default:
        return UsbClockDomain.unknown;
    }
  }

  String get wireName => switch (this) {
        UsbClockDomain.bitPerfectLocked => 'bitPerfectLocked',
        UsbClockDomain.asrc => 'asrc',
        UsbClockDomain.bestEffort => 'bestEffort',
        UsbClockDomain.unknown => 'unknown',
      };

  /// True only for a verified bit-exact path. Never infer this from
  /// `streamingActive` or from the mode the user picked.
  bool get isBitPerfect => this == UsbClockDomain.bitPerfectLocked;

  /// True when the path resamples by design; must be labeled `resampled`.
  bool get isResampled => this == UsbClockDomain.asrc;

  String toShortLabel() => switch (this) {
        UsbClockDomain.bitPerfectLocked => 'Bit-perfect',
        UsbClockDomain.asrc => 'Resampled (clock sync)',
        UsbClockDomain.bestEffort => 'Best effort',
        UsbClockDomain.unknown => 'Unknown',
      };
}

/// Clock architecture requested when opening a direct-USB stream.
///
/// Codes are part of the Dart -> Kotlin -> C++ contract and must stay in sync
/// with `UsbRenderMode` in `UsbAudioSink.h`.
enum UsbRenderMode {
  bestEffort(0),
  bitPerfectPull(1),
  clockSyncAsrc(2);

  const UsbRenderMode(this.nativeCode);

  final int nativeCode;

  static UsbRenderMode fromNativeCode(int? value) => switch (value) {
        1 => UsbRenderMode.bitPerfectPull,
        2 => UsbRenderMode.clockSyncAsrc,
        _ => UsbRenderMode.bestEffort,
      };
}

/// Snapshot of the attached USB audio device and exclusive-path state.
///
/// `clockDomain` is the only field an audiophile claim may be based on: it is
/// derived by the native sink from the actual data path, never inferred by the
/// UI. `asrc` and `bestEffort` are explicitly non-bit-perfect.
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
  final bool hasMuteControl;
  final bool? hardwareMute;
  final bool exclusiveActive;
  final bool exclusiveSupported;
  final double? hardwareVolumeDb;
  final double? minVolumeDb;
  final double? maxVolumeDb;
  final int? interfaceNumber;
  final bool streamingActive;
  final bool dsdActive;
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

  /// Clock architecture the native sink reports for the current session.
  final UsbClockDomain clockDomain;

  /// Estimated clock drift between this device and the DAC, in parts per
  /// million, rounded by native. 0 when no estimate is available.
  final int clockDriftPpm;

  /// Milliseconds of PCM buffered ahead of the USB worker.
  final int ringFillMs;

  /// Whether the DAC exposes an asynchronous feedback IN endpoint.
  final bool feedbackPresent;

  /// Worker-observed ring underruns for the current session.
  final int underrunCount;

  /// Frames dropped because the producer outran the ring.
  final int overrunCount;

  /// True when a failed URB drain is holding the interface claim; the next open
  /// must not rebind the kernel driver.
  final bool drainPending;

  /// Lifecycle state reported by the Kotlin session state machine.
  final String sessionState;

  /// Quirk keys actually applied to the last start, in canonical order.
  final List<String> quirkApplied;

  /// Quirk keys rejected by validation, mapped to a stable reason.
  final Map<String, String> quirkRejected;

  /// True when an applied quirk changed bit-perfect semantics (for example
  /// forced 16-bit). The UI must surface this instead of a bare claim.
  final bool quirkBitPerfectAffected;

  /// Stable reason when [quirkBitPerfectAffected] is true.
  final String? quirkBitPerfectReason;

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
    this.hasMuteControl = false,
    this.hardwareMute,
    this.exclusiveActive = false,
    this.exclusiveSupported = false,
    this.hardwareVolumeDb,
    this.minVolumeDb,
    this.maxVolumeDb,
    this.interfaceNumber,
    this.streamingActive = false,
    this.dsdActive = false,
    this.streamingSupported = false,
    this.supportedRates = const [],
    this.lastError,
    this.lastStreamErrorCode,
    this.channelMismatchFrames = 0,
    this.rateVerified = false,
    this.advertisedFormats = const [],
    this.clockDomain = UsbClockDomain.unknown,
    this.clockDriftPpm = 0,
    this.ringFillMs = 0,
    this.feedbackPresent = false,
    this.underrunCount = 0,
    this.overrunCount = 0,
    this.drainPending = false,
    this.sessionState = 'unknown',
    this.quirkApplied = const [],
    this.quirkRejected = const {},
    this.quirkBitPerfectAffected = false,
    this.quirkBitPerfectReason,
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
    bool? hasMuteControl,
    bool? hardwareMute,
    bool? exclusiveActive,
    bool? exclusiveSupported,
    double? hardwareVolumeDb,
    double? minVolumeDb,
    double? maxVolumeDb,
    int? interfaceNumber,
    bool? streamingActive,
    bool? dsdActive,
    bool? streamingSupported,
    List<int>? supportedRates,
    int? lastError,
    int? lastStreamErrorCode,
    int? channelMismatchFrames,
    bool? rateVerified,
    List<Map<String, dynamic>>? advertisedFormats,
    UsbClockDomain? clockDomain,
    int? clockDriftPpm,
    int? ringFillMs,
    bool? feedbackPresent,
    int? underrunCount,
    int? overrunCount,
    bool? drainPending,
    String? sessionState,
    List<String>? quirkApplied,
    Map<String, String>? quirkRejected,
    bool? quirkBitPerfectAffected,
    String? quirkBitPerfectReason,
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
      hasMuteControl: hasMuteControl ?? this.hasMuteControl,
      hardwareMute: hardwareMute ?? this.hardwareMute,
      exclusiveActive: exclusiveActive ?? this.exclusiveActive,
      exclusiveSupported: exclusiveSupported ?? this.exclusiveSupported,
      hardwareVolumeDb: hardwareVolumeDb ?? this.hardwareVolumeDb,
      minVolumeDb: minVolumeDb ?? this.minVolumeDb,
      maxVolumeDb: maxVolumeDb ?? this.maxVolumeDb,
      interfaceNumber: interfaceNumber ?? this.interfaceNumber,
      streamingActive: streamingActive ?? this.streamingActive,
      dsdActive: dsdActive ?? this.dsdActive,
      streamingSupported: streamingSupported ?? this.streamingSupported,
      supportedRates: supportedRates ?? this.supportedRates,
      lastError: lastError ?? this.lastError,
      lastStreamErrorCode: lastStreamErrorCode ?? this.lastStreamErrorCode,
      channelMismatchFrames:
          channelMismatchFrames ?? this.channelMismatchFrames,
      rateVerified: rateVerified ?? this.rateVerified,
      advertisedFormats: advertisedFormats ?? this.advertisedFormats,
      clockDomain: clockDomain ?? this.clockDomain,
      clockDriftPpm: clockDriftPpm ?? this.clockDriftPpm,
      ringFillMs: ringFillMs ?? this.ringFillMs,
      feedbackPresent: feedbackPresent ?? this.feedbackPresent,
      underrunCount: underrunCount ?? this.underrunCount,
      overrunCount: overrunCount ?? this.overrunCount,
      drainPending: drainPending ?? this.drainPending,
      sessionState: sessionState ?? this.sessionState,
      quirkApplied: quirkApplied ?? this.quirkApplied,
      quirkRejected: quirkRejected ?? this.quirkRejected,
      quirkBitPerfectAffected:
          quirkBitPerfectAffected ?? this.quirkBitPerfectAffected,
      quirkBitPerfectReason:
          quirkBitPerfectReason ?? this.quirkBitPerfectReason,
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
      hasMuteControl: map['hasMuteControl'] == true,
      hardwareMute: map['hardwareMute'] is bool
          ? map['hardwareMute'] as bool
          : null,
      exclusiveActive: map['exclusiveActive'] == true,
      exclusiveSupported: map['exclusiveSupported'] == true,
      hardwareVolumeDb: d(map['hardwareVolumeDb']),
      minVolumeDb: d(map['minVolumeDb']),
      maxVolumeDb: d(map['maxVolumeDb']),
      interfaceNumber: i(map['interfaceNumber']),
      streamingActive: map['streamingActive'] == true,
      dsdActive: map['dsdActive'] == true,
      streamingSupported: map['streamingSupported'] == true,
      supportedRates: (map['supportedRates'] is List)
          ? (map['supportedRates'] as List)
              .whereType<num>()
              .map((e) => e.toInt())
              .toList()
          : const [],
      lastError: i(map['lastError']),
      lastStreamErrorCode: i(map['resultCode']),
      channelMismatchFrames: i(map['channelMismatchFrames']) ?? 0,
      rateVerified: map['streamingActive'] == true && map['rateVerified'] == true,
      advertisedFormats: (map['advertisedFormats'] is List)
          ? (map['advertisedFormats'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [],
      clockDomain: UsbClockDomain.fromWire(map['clockDomain']),
      clockDriftPpm: i(map['clockDriftPpm']) ?? 0,
      ringFillMs: i(map['ringFillMs']) ?? 0,
      feedbackPresent: map['feedbackPresent'] == true,
      underrunCount: i(map['underrunCount']) ?? 0,
      overrunCount: i(map['overrunCount']) ?? 0,
      drainPending: map['drainPending'] == true,
      sessionState: (map['sessionState'] as String?) ?? 'unknown',
      quirkApplied: (map['quirkApplied'] is List)
          ? (map['quirkApplied'] as List)
              .map((e) => '$e')
              .toList()
          : const [],
      quirkRejected: (map['quirkRejected'] is Map)
          ? (map['quirkRejected'] as Map).map(
              (key, value) => MapEntry('$key', '$value'),
            )
          : const {},
      quirkBitPerfectAffected: map['quirkBitPerfectAffected'] == true,
      quirkBitPerfectReason: map['quirkBitPerfectReason'] as String?,
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

  static UsbExclusiveService? _instance;
  factory UsbExclusiveService() =>
      _instance ??= UsbExclusiveService._internal();
  UsbExclusiveService._internal();

  /// Visible for testing to allow creating mocks/fakes.
  @visibleForTesting
  UsbExclusiveService.forTest();

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

  /// Test seam: drive the same broadcast path the platform event channel uses.
  @visibleForTesting
  void debugPublishStatus(UsbExclusiveStatus status) => _publish(status);

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
      if (res is Map) {
        return res['error'] == null && res['success'] != false;
      }
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
      final bool ok = res == true ||
          (res is Map && res['error'] == null && res['success'] != false);
      if (!ok) return false;
      await getStatus();
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to set USB hardware volume($db dB)',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  /// Reset USB Feature Unit hardware volume back to 0 dB (unity gain) when
  /// handing volume control back to software/DVC or disabling hardware volume.
  Future<bool> resetHardwareVolume() async {
    if (!_isAndroid) return false;
    try {
      final dynamic res = await _methodChannel
          .invokeMethod<dynamic>('resetHardwareVolume')
          .timeout(const Duration(seconds: 5));
      final bool ok = res == true ||
          (res is Map && res['error'] == null && res['success'] != false);
      if (!ok) return false;
      await getStatus();
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to reset USB hardware volume',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  /// Sets whether USB DAC hardware volume control is enabled by user preference.
  Future<bool> setUsbHardwareVolumeEnabled(bool enabled) async {
    if (!_isAndroid) return false;
    try {
      final dynamic res = await _methodChannel
          .invokeMethod<dynamic>('setUsbHardwareVolumeEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 2));
      return res == true;
    } catch (e, st) {
      ErrorLogger.log('Failed to setUsbHardwareVolumeEnabled($enabled)',
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
    UsbRenderMode renderMode = UsbRenderMode.bestEffort,
  }) async {
    if (!_isAndroid) return UsbStreamResult.invalidArgs;
    // Includes the 44.1-family high-rate endpoints (705.6/768 kHz) that UAC1
    // continuous ranges and UAC2 clock ranges advertise. Omitting them here
    // refused a rate the DAC had actually reported.
    const validRates = [
      44100,
      48000,
      88200,
      96000,
      176400,
      192000,
      352800,
      384000,
      705600,
      768000
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
        'renderMode': renderMode.nativeCode,
      }).timeout(const Duration(seconds: 10));
      final status = await _readStatus();
      if (res is Map) {
        if (res['success'] == true) {
          final openedDepth = status?.streamingBitDepth ?? 0;
          final depthSatisfied = strict
              ? openedDepth == bitDepth
              : (openedDepth >= bitDepth &&
                  (openedDepth == 16 || openedDepth == 24 || openedDepth == 32));
          final satisfied = status != null &&
              status.attached &&
              status.permitted &&
              status.streamingActive &&
              status.deviceId == before.deviceId &&
              status.deviceId != null &&
              status.streamingSampleRate == sampleRate &&
              depthSatisfied &&
              status.streamingChannels == channels;
          if (satisfied) {
            return UsbStreamResult.ok;
          } else {
            await stopStreaming();
            return UsbStreamResult.unknown;
          }
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
          case 'clock_selector_restore_failed':
            return UsbStreamResult.clockSelectorRestoreFailed;
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
    } catch (e, st) {
      ErrorLogger.log('Failed to getBufferedMs',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return 0.0;
    }
  }

  /// Channel count of the track the render tap last processed. 0 = unknown
  /// (nothing decoded yet), in which case the caller keeps its own default.
  Future<void> resetChannelMismatchFrames() async {
    if (!_isAndroid) return;
    try {
      await _methodChannel
          .invokeMethod<void>('resetChannelMismatchFrames')
          .timeout(const Duration(seconds: 3));
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

  /// Structured USB event ring the native/Kotlin layer keeps for this session.
  ///
  /// Returns an empty list when the platform has no handler, so a diagnostics
  /// export still succeeds on older builds.
  Future<List<Map<String, dynamic>>> getUsbEvents() async {
    if (!_isAndroid) return const [];
    try {
      final List<dynamic>? res = await _methodChannel
          .invokeListMethod<dynamic>('getUsbEvents')
          .timeout(const Duration(milliseconds: 500));
      return res
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const [];
    } catch (e, st) {
      ErrorLogger.log('Failed to read USB events',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return const [];
    }
  }

  /// Starts the optional reader-thread PCM source for a pull stream.
  ///
  /// The file must be an integer PCM WAV whose rate, channels, container and
  /// valid bits exactly match the open stream; a mismatch is refused rather
  /// than converted. Only meaningful in [UsbRenderMode.bitPerfectPull].
  Future<bool> startPcmFile(String path) async {
    if (!_isAndroid || path.isEmpty) return false;
    try {
      final bool? res = await _methodChannel
          .invokeMethod<bool>('startPcmFile', <String, Object?>{'path': path})
          .timeout(const Duration(seconds: 5));
      return res ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to start the USB PCM source',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  /// Stops the reader-thread PCM source (the stream stays open).
  Future<bool> stopPcmFile() async {
    if (!_isAndroid) return false;
    try {
      final bool? res = await _methodChannel
          .invokeMethod<bool>('stopPcmFile')
          .timeout(const Duration(seconds: 5));
      return res ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to stop the USB PCM source',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  /// Whether a reader-thread PCM source is currently feeding the pull stream.
  Future<bool> hasPcmFileSource() async {
    if (!_isAndroid) return false;
    try {
      final bool? res = await _methodChannel
          .invokeMethod<bool>('hasPcmFileSource')
          .timeout(const Duration(milliseconds: 500));
      return res ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to check hasPcmFileSource',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  /// Starts native DSD streaming with the probed alternate setting tuple.
  Future<bool> startDsdStreaming(DsdAltSettingTuple tuple, {bool strict = true}) async {
    if (!_isAndroid) return false;
    if (tuple.interfaceNumber < 0 ||
        tuple.altSetting < 0 ||
        tuple.endpointAddress <= 0 ||
        tuple.channels < 1 ||
        tuple.channels > 8 ||
        tuple.bytesPerSample <= 0 ||
        tuple.framesPerSecond < 0 ||
        tuple.dsdRate < 0) {
      ErrorLogger.log('startDsdStreaming: invalid tuple $tuple',
          category: 'UsbExclusive');
      return false;
    }
    final before = await _readStatus();
    if (before == null || !before.attached || !before.permitted) {
      ErrorLogger.log('startDsdStreaming: DAC not attached/permitted',
          category: 'UsbExclusive');
      return false;
    }
    try {
      final res = await _methodChannel.invokeMapMethod<String, dynamic>(
        'startDsdStreaming',
        {
          ...tuple.toMap(),
          'strict': strict,
        },
      ).timeout(const Duration(seconds: 10));
      await _readStatus();
      return res?['success'] == true;
    } catch (e, st) {
      ErrorLogger.log('startDsdStreaming failed',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  /// Writes one stereo 1-bit DSD block to the native DSD sink.
  /// Returns false on backpressure (ring full) or if streaming is inactive.
  Future<bool> writeDsd(Uint8List left, Uint8List right, {int producerId = 0}) async {
    if (!_isAndroid) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('writeDsd', {
        'left': left,
        'right': right,
        'producerId': producerId,
      }).timeout(const Duration(seconds: 2));
      return res == true;
    } catch (e, st) {
      ErrorLogger.log('writeDsd failed',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  /// Checks whether native DSD streaming is active on the DAC.
  Future<bool> isDsdActive() async {
    if (!_isAndroid) return false;
    try {
      final res = await _methodChannel
          .invokeMethod<bool>('isDsdActive')
          .timeout(const Duration(seconds: 2));
      return res == true;
    } catch (e, st) {
      ErrorLogger.log('isDsdActive failed',
          error: e, stackTrace: st, category: 'UsbExclusive');
      return false;
    }
  }

  /// Pushes the per-device quirk profile to the exclusive plugin.
  ///
  /// The plugin validates it again and only applies safe quirks; a rejected
  /// value is reported as false and never blocks streaming.
  Future<bool> applyQuirkProfile(Map<String, Object?> profile) async {
    if (!_isAndroid) return false;
    try {
      final dynamic res = await _methodChannel
          .invokeMethod<dynamic>('setQuirkProfile', profile)
          .timeout(const Duration(seconds: 3));
      if (res is Map) return res['ok'] == true;
      return res == true;
    } catch (e, st) {
      ErrorLogger.log('Failed to push the USB quirk profile',
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
