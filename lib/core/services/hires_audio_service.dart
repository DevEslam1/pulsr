// lib/core/services/hires_audio_service.dart
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import '../../domain/models/audio_output_info.dart';
import '../constants/channels.dart';
import '../utils/error_logger.dart';

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
    try {
      _eventSubscription =
          _eventChannel.receiveBroadcastStream().handleError((Object e, StackTrace st) {
        // Ignore missing plugin exception in unit tests or platforms without native implementation
        if (e is! MissingPluginException) {
          ErrorLogger.log('HiRes DAC event stream error',
              error: e, stackTrace: st, category: 'HiResAudio');
        }
      }).listen(
        (data) {
          if (data is Map) {
            final info = AudioOutputInfo.fromMap(data);
            _cachedOutputInfo = info;
            _deviceController.add(info);
          }
        },
        cancelOnError: false,
      );
      // Eagerly query current status
      getAudioOutputInfo();
    } catch (e, st) {
      ErrorLogger.log('Failed to initialize HiRes DAC listener',
          error: e, stackTrace: st, category: 'HiResAudio');
    }
  }

  Future<AudioOutputInfo> getAudioOutputInfo() async {
    try {
      final Map<dynamic, dynamic>? res = await _methodChannel
          .invokeMapMethod<dynamic, dynamic>('getAudioOutputInfo');
      if (res != null) {
        final info = AudioOutputInfo.fromMap(res);
        _cachedOutputInfo = info;
        _deviceController.add(info);
        return info;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to getAudioOutputInfo',
          error: e, stackTrace: st, category: 'HiResAudio');
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

  Future<bool> isBitPerfectSupported() async {
    try {
      final bool? supported =
          await _methodChannel.invokeMethod<bool>('isBitPerfectSupported');
      return supported ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setBitPerfectMode(bool enabled) async {
    try {
      final bool? success = await _methodChannel.invokeMethod<bool>(
        'setBitPerfectMode',
        {'enabled': enabled},
      );
      await getAudioOutputInfo();
      return success ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setBitPerfectMode($enabled)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> selectOutputDevice(int deviceId) async {
    try {
      final bool? success = await _methodChannel.invokeMethod<bool>(
        'setOutputDevice',
        {'deviceId': deviceId},
      );
      await getAudioOutputInfo();
      return success ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to selectOutputDevice($deviceId)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> clearOutputDevice() async {
    try {
      final bool? success =
          await _methodChannel.invokeMethod<bool>('clearOutputDevice');
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
    try {
      final bool? success = await _methodChannel.invokeMethod<bool>(
        'setTargetOutputFormat',
        {
          'sampleRate': sampleRate,
          'bitDepth': bitDepth,
        },
      );
      await getAudioOutputInfo();
      return success ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setTargetOutputFormat($sampleRate, $bitDepth)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _deviceController.close();
  }
}
