// lib/core/services/hires_audio_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import '../../domain/models/audio_output_info.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/platform_capabilities.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of a media-route change request.
class OutputRouteResult {
  final bool success;
  final String? error;
  final bool requiresSystemPicker;

  const OutputRouteResult({
    required this.success,
    this.error,
    this.requiresSystemPicker = false,
  });
}

@lazySingleton
class HiResAudioService {
  static const MethodChannel _methodChannel =
      MethodChannel(PulsrChannels.hiresDac);
  static const EventChannel _eventChannel =
      EventChannel(PulsrChannels.hiresDacEvents);

  final StreamController<AudioOutputInfo> _deviceController =
      StreamController<AudioOutputInfo>.broadcast();

  Stream<AudioOutputInfo> get outputDeviceStream => _deviceController.stream;
  StreamSubscription<dynamic>? _eventSubscription;
  AudioOutputInfo? _cachedOutputInfo;

  AudioOutputInfo? get currentOutputInfo => _cachedOutputInfo;

  /// Sample rates accepted by the native `setTargetOutputFormat` (0 = auto).
  /// The native side performs no validation of its own, so this set is the
  /// single gate that keeps an unsupported rate from being requested silently.
  static const Set<int> validTargetSampleRates = <int>{
    0,
    44100,
    48000,
    88200,
    96000,
    176400,
    192000,
    352800,
    384000,
    705600,
    768000,
  };

  /// Bit depths accepted by the native `setTargetOutputFormat` (0 = auto).
  /// 8.24 packed is deliberately absent: the native layer does not report it,
  /// so it is not offered rather than faked.
  static const Set<int> validTargetBitDepths = <int>{0, 16, 24, 32};

  /// The widest first-class sample-rate envelope Pulsr can request (T5).
  static const List<int> envelopeSampleRateLadder = <int>[
    44100,
    48000,
    88200,
    96000,
    176400,
    192000,
    352800,
    384000,
    705600,
    768000,
  ];

  /// T5 pure filter: only rates the current output actually reports as
  /// supported survive. [deviceSampleRates] comes from [AudioOutputInfo] while
  /// [directFormats] comes from Android's `isDirectPlaybackSupported` probe;
  /// either can carry a rate the other misses. No rate is ever invented.
  static List<int> supportedSampleRateOptions({
    required List<int> deviceSampleRates,
    required List<AudioDirectFormat> directFormats,
    List<int> ladder = envelopeSampleRateLadder,
  }) {
    final reported = <int>{
      ...deviceSampleRates.where((r) => r > 0),
      ...directFormats.where((f) => f.supported).map((f) => f.sampleRate),
    };
    final supported =
        ladder.where((rate) => reported.contains(rate)).toList()..sort();
    if (supported.isNotEmpty) return supported;
    // No capability report at all: fall back to the only universally safe rates
    // rather than presenting unsupported hi-res tiers.
    return ladder.where((r) => r == 44100 || r == 48000).toList();
  }

  /// T2 pure decision: the track rate that should be pushed to the native
  /// output, or null when nothing should be sent. De-dupes against the last
  /// requested rate and never fights AVRCP on a Bluetooth route.
  static int? followTrackRateToApply({
    required int? trackSampleRate,
    required int? lastRequestedSampleRate,
    required bool isBluetooth,
    required bool followTrackEnabled,
  }) {
    if (!followTrackEnabled) return null;
    if (isBluetooth) return null;
    final rate = trackSampleRate;
    if (rate == null || rate <= 0) return null;
    if (rate == lastRequestedSampleRate) return null;
    if (!validTargetSampleRates.contains(rate)) return null;
    return rate;
  }

  HiResAudioService() {
    _init();
  }

  static bool _isSameOutputInfo(AudioOutputInfo a, AudioOutputInfo b) =>
      a.deviceName == b.deviceName &&
      a.sampleRate == b.sampleRate &&
      a.bitDepth == b.bitDepth &&
      a.isBitPerfectActive == b.isBitPerfectActive &&
      a.isBitPerfectSupported == b.isBitPerfectSupported &&
      a.targetSampleRate == b.targetSampleRate &&
      a.targetBitDepth == b.targetBitDepth &&
      a.activeDeviceType == b.activeDeviceType &&
      a.isBluetooth == b.isBluetooth &&
      a.isLeAudio == b.isLeAudio &&
      a.bleAudioPresent == b.bleAudioPresent &&
      a.btCodecName == b.btCodecName &&
      a.btSampleRateHz == b.btSampleRateHz &&
      a.btBitDepth == b.btBitDepth &&
      a.btLdacQualityMode == b.btLdacQualityMode &&
      a.usbAudioClass == b.usbAudioClass &&
      a.btCodecConnected == b.btCodecConnected;

  void _init() {
    if (!PlatformCapabilities.isAndroid) return;
    try {
      _eventSubscription = _eventChannel
          .receiveBroadcastStream()
          .handleError((Object e, StackTrace st) {
        if (e is! MissingPluginException) {
          ErrorLogger.log('HiRes DAC event stream error',
              error: e, stackTrace: st, category: 'HiResAudio');
        }
      }).listen(
        (data) {
          if (data is Map) {
            final info = AudioOutputInfo.fromMap(data);
            // Deduplicate consecutive identical emissions. Compare every field a
            // consumer can observe: deduping on only name/rate/bit-perfect hid
            // route changes (Bluetooth codec, LE Audio, USB class) from device
            // profiles and the earbud/automation UI.
            if (_cachedOutputInfo != null &&
                _isSameOutputInfo(_cachedOutputInfo!, info)) {
              return;
            }
            _cachedOutputInfo = info;
            if (!_deviceController.isClosed) _deviceController.add(info);
          }
        },
        cancelOnError: false,
      );
      // Eagerly query current status
      unawaited(getAudioOutputInfo());
    } catch (e, st) {
      ErrorLogger.log('Failed to initialize HiRes DAC listener',
          error: e, stackTrace: st, category: 'HiResAudio');
    }
  }

  Future<AudioOutputInfo> getAudioOutputInfo() async {
    if (!PlatformCapabilities.isAndroid) {
      const fb = AudioOutputInfo(
          deviceName: 'Default Audio Output',
          isUsbDac: false,
          sampleRate: 44100,
          bitDepth: 16,
          isBitPerfectActive: false);
      _cachedOutputInfo = fb;
      return fb;
    }
    try {
      final Map<dynamic, dynamic>? res = await _methodChannel
          .invokeMapMethod<dynamic, dynamic>('getAudioOutputInfo')
          .timeout(const Duration(seconds: 3));
      if (res != null) {
        final info = AudioOutputInfo.fromMap(res);
        // Avoid duplicate stream emission if same as cached
        final cached = _cachedOutputInfo;
        if (cached == null ||
            cached.deviceName != info.deviceName ||
            cached.sampleRate != info.sampleRate ||
            cached.isBitPerfectActive != info.isBitPerfectActive) {
          _cachedOutputInfo = info;
          if (!_deviceController.isClosed) _deviceController.add(info);
        } else {
          _cachedOutputInfo = info;
        }
        return info;
      }
    } catch (e, st) {
      if (e is! MissingPluginException || kDebugMode) {
        ErrorLogger.log('Failed to getAudioOutputInfo',
            error: e, stackTrace: st, category: 'HiResAudio');
      }
    }

    const fallback = AudioOutputInfo(
      deviceName: 'Default Audio Output',
      isUsbDac: false,
      sampleRate: 44100,
      bitDepth: 16,
      isBitPerfectActive: false,
    );
    _cachedOutputInfo = fallback;
    return fallback;
  }

  /// Phase 4: per-format direct-playback capability probe (API 29+; older
  /// Android levels report every entry as unsupported - no fabricated claims).
  Future<List<AudioDirectFormat>> getDirectCapabilities() async {
    if (!PlatformCapabilities.isAndroid) return const [];
    try {
      final Map<dynamic, dynamic>? res = await _methodChannel
          .invokeMapMethod<dynamic, dynamic>('getDirectCapabilities')
          .timeout(const Duration(seconds: 3));
      final raw = res?['directFormats'];
      final out = <AudioDirectFormat>[];
      if (raw is List) {
        for (final d in raw) {
          if (d is Map) out.add(AudioDirectFormat.fromMap(d));
        }
      }
      return out;
    } catch (e, st) {
      ErrorLogger.log('Failed to getDirectCapabilities',
          error: e, stackTrace: st, category: 'HiResAudio');
      return const [];
    }
  }

  /// Phase 4: USB DAC diagnostics (advertised UAC version + label).
  /// Returns null when no audio USB device is present or off Android.
  Future<Map<String, Object?>?> getUsbDacCapabilities() async {
    if (!PlatformCapabilities.isAndroid) return null;
    try {
      return await _methodChannel
          .invokeMapMethod<String, Object?>('getUsbDacCapabilities')
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log('Failed to getUsbDacCapabilities',
          error: e, stackTrace: st, category: 'HiResAudio');
      return null;
    }
  }

  Future<bool> isBitPerfectSupported() async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? supported = await _methodChannel
          .invokeMethod<bool>('isBitPerfectSupported')
          .timeout(const Duration(seconds: 2));
      return supported ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setBitPerfectMode(bool enabled) async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? success = await _methodChannel.invokeMethod<bool>(
          'setBitPerfectMode',
          {'enabled': enabled}).timeout(const Duration(seconds: 8));
      await getAudioOutputInfo();
      if (success != true && enabled) {
        // Unsupported hardware: fall back to DSP path and refresh state so
        // the UI never shows bit-perfect as active when it isn't.
        ErrorLogger.log(
            'Bit-perfect rejected by device — falling back to DSP path',
            category: 'HiResAudio');
        try {
          await _methodChannel.invokeMethod<bool>(
              'setBitPerfectMode', {'enabled': false});
        } catch (_) {}
        await getAudioOutputInfo();
        return false;
      }
      return success ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setBitPerfectMode($enabled)',
          error: e, stackTrace: st, category: 'HiResAudio');
      // Device may have disconnected mid-call — refresh so stale
      // bit-perfect state is never displayed.
      try {
        await getAudioOutputInfo();
      } catch (_) {}
      return false;
    }
  }

  /// Asks the platform to route media to [deviceId].
  ///
  /// Forcing the media route needs MODIFY_AUDIO_ROUTING, which only privileged
  /// builds hold, so `requiresSystemPicker` is the normal outcome on retail
  /// devices — hand the user [openOutputSwitcher] instead of reporting success.
  Future<OutputRouteResult> selectOutputDevice(int deviceId) async {
    if (!PlatformCapabilities.isAndroid) {
      return const OutputRouteResult(
          success: false, error: 'unsupported_platform');
    }
    try {
      final dynamic res = await _methodChannel.invokeMethod<dynamic>(
          'setOutputDevice',
          {'deviceId': deviceId}).timeout(const Duration(seconds: 8));
      await getAudioOutputInfo();
      if (res is Map) {
        return OutputRouteResult(
          success: (res['success'] as bool?) ?? false,
          error: res['error'] as String?,
          requiresSystemPicker: (res['requiresSystemPicker'] as bool?) ?? false,
        );
      }
      if (res is bool) return OutputRouteResult(success: res);
      return const OutputRouteResult(success: false, error: 'unknown_response');
    } catch (e, st) {
      ErrorLogger.log('Failed to selectOutputDevice($deviceId)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return const OutputRouteResult(success: false, error: 'channel_error');
    }
  }

  /// Opens Android's media output switcher — the sanctioned way for an
  /// unprivileged app to move the route.
  Future<bool> openOutputSwitcher() async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? ok = await _methodChannel
          .invokeMethod<bool>('openOutputSwitcher')
          .timeout(const Duration(seconds: 5));
      return ok ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to openOutputSwitcher',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> clearOutputDevice() async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? success = await _methodChannel
          .invokeMethod<bool>('clearOutputDevice')
          .timeout(const Duration(seconds: 8));
      await getAudioOutputInfo();
      return success ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to clearOutputDevice',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> setTargetOutputFormat(
      {int sampleRate = 0, int bitDepth = 0}) async {
    if (!PlatformCapabilities.isAndroid) return false;
    // Validate before hitting native: 0 = auto, otherwise must be a sane
    // rate; bit depth must be 0 (auto), 16, 24 or 32.
    if (!validTargetSampleRates.contains(sampleRate)) {
      ErrorLogger.log(
          'Rejected invalid sample rate $sampleRate', category: 'HiResAudio');
      return false;
    }
    if (!validTargetBitDepths.contains(bitDepth)) {
      ErrorLogger.log('Rejected invalid bit depth $bitDepth',
          category: 'HiResAudio');
      return false;
    }
    try {
      final bool? success = await _methodChannel.invokeMethod<bool>(
          'setTargetOutputFormat', {
        'sampleRate': sampleRate,
        'bitDepth': bitDepth
      }).timeout(const Duration(seconds: 8));
      await getAudioOutputInfo();
      return success ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setTargetOutputFormat($sampleRate, $bitDepth)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<void> requestBluetoothPermission() async {
    if (!PlatformCapabilities.isAndroid) return;
    try {
      // Android 12+: BLUETOOTH_CONNECT is a runtime permission. Try the
      // standard system dialog first; fall back to the native handler
      // (opens App Settings) when denied or permanently denied.
      var status = await Permission.bluetoothConnect.status;
      if (!status.isGranted) {
        status = await Permission.bluetoothConnect.request();
      }
      if (status.isGranted) return;
      await _methodChannel
          .invokeMethod<void>('requestBluetoothPermission')
          .timeout(const Duration(seconds: 5));
    } catch (e, st) {
      ErrorLogger.log('requestBluetoothPermission failed',
          error: e, stackTrace: st, category: 'HiResAudio');
    }
  }

  Future<void> openBluetoothDevOptions() async {
    if (!PlatformCapabilities.isAndroid) return;
    try {
      await _methodChannel
          .invokeMethod<void>('openBluetoothDevOptions')
          .timeout(const Duration(seconds: 5));
    } catch (e, st) {
      ErrorLogger.log('openBluetoothDevOptions failed',
          error: e, stackTrace: st, category: 'HiResAudio');
    }
  }

  // -- Bluetooth codec control --

  Future<bool> setBluetoothCodec(String codec) async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? ok = await _methodChannel.invokeMethod<bool>(
          'setBluetoothCodec',
          {'codec': codec}).timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await getAudioOutputInfo();
      return ok ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setBluetoothCodec($codec)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> setBluetoothSampleRate(int hz) async {
    if (!PlatformCapabilities.isAndroid) return false;
    const validBtRates = <int>{44100, 48000, 88200, 96000, 176400, 192000};
    if (!validBtRates.contains(hz)) {
      ErrorLogger.log('Rejected invalid BT sample rate $hz',
          category: 'HiResAudio');
      return false;
    }
    try {
      final bool? ok = await _methodChannel.invokeMethod<bool>(
          'setBluetoothSampleRate',
          {'sampleRate': hz}).timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await getAudioOutputInfo();
      return ok ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setBluetoothSampleRate($hz)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> setBluetoothBitDepth(int bits) async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? ok = await _methodChannel.invokeMethod<bool>(
          'setBluetoothBitDepth',
          {'bitDepth': bits}).timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await getAudioOutputInfo();
      return ok ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setBluetoothBitDepth($bits)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> setBluetoothLdacQuality(int mode) async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? ok = await _methodChannel.invokeMethod<bool>(
          'setBluetoothLdacQuality',
          {'mode': mode}).timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await getAudioOutputInfo();
      return ok ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setBluetoothLdacQuality($mode)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    if (!_deviceController.isClosed) _deviceController.close();
  }
}
