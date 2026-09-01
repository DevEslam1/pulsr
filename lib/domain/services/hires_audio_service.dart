// lib/core/services/hires_audio_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import '../../domain/models/audio_output_info.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/platform_capabilities.dart';

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

  HiResAudioService() {
    _init();
  }

  void _init() {
    if (!PlatformCapabilities.isAndroid) return;
    try {
      _eventSubscription =
          _eventChannel.receiveBroadcastStream().handleError((Object e, StackTrace st) {
        if (e is! MissingPluginException) {
          ErrorLogger.log('HiRes DAC event stream error',
              error: e, stackTrace: st, category: 'HiResAudio');
        }
      }).listen(
        (data) {
          if (data is Map) {
            final info = AudioOutputInfo.fromMap(data);
            // Deduplicate consecutive identical emissions
            if (_cachedOutputInfo != null &&
                _cachedOutputInfo!.deviceName == info.deviceName &&
                _cachedOutputInfo!.sampleRate == info.sampleRate &&
                _cachedOutputInfo!.isBitPerfectActive == info.isBitPerfectActive) {
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
      const fb = AudioOutputInfo(deviceName: 'Default Audio Output', isUsbDac: false, sampleRate: 44100, bitDepth: 16, isBitPerfectActive: false);
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
      final bool? success = await _methodChannel
          .invokeMethod<bool>('setBitPerfectMode', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
      await getAudioOutputInfo();
      return success ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setBitPerfectMode($enabled)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> selectOutputDevice(int deviceId) async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final dynamic res = await _methodChannel
          .invokeMethod<dynamic>('setOutputDevice', {'deviceId': deviceId})
          .timeout(const Duration(seconds: 3));
      await getAudioOutputInfo();
      if (res is Map) return (res['success'] as bool?) ?? false;
      if (res is bool) return res;
      return false;
    } catch (e, st) {
      ErrorLogger.log('Failed to selectOutputDevice($deviceId)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> clearOutputDevice() async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? success = await _methodChannel
          .invokeMethod<bool>('clearOutputDevice')
          .timeout(const Duration(seconds: 2));
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
    try {
      final bool? success = await _methodChannel
          .invokeMethod<bool>('setTargetOutputFormat', {'sampleRate': sampleRate, 'bitDepth': bitDepth})
          .timeout(const Duration(seconds: 2));
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
      final bool? ok = await _methodChannel
          .invokeMethod<bool>('setBluetoothCodec', {'codec': codec})
          .timeout(const Duration(seconds: 3));
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
    try {
      final bool? ok = await _methodChannel
          .invokeMethod<bool>('setBluetoothSampleRate', {'sampleRate': hz})
          .timeout(const Duration(seconds: 3));
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
      final bool? ok = await _methodChannel
          .invokeMethod<bool>('setBluetoothBitDepth', {'bitDepth': bits})
          .timeout(const Duration(seconds: 3));
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
      final bool? ok = await _methodChannel
          .invokeMethod<bool>('setBluetoothLdacQuality', {'mode': mode})
          .timeout(const Duration(seconds: 3));
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

