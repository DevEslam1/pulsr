// lib/core/services/hires_audio_service.dart
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import '../../domain/models/audio_output_info.dart';
import '../utils/error_logger.dart';

@lazySingleton
class HiResAudioService {
  static const MethodChannel _methodChannel = MethodChannel('com.pulsr.music/hires_dac');
  static const EventChannel _eventChannel = EventChannel('com.pulsr.music/hires_dac_events');

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
      _eventSubscription = _eventChannel
          .receiveBroadcastStream()
          .handleError((e, st) {
            // Ignore missing plugin exception in unit tests or platforms without native implementation
            if (e is! MissingPluginException) {
              ErrorLogger.log('HiRes DAC event stream error',
                  error: e, stackTrace: st, category: 'HiResAudio');
            }
          })
          .listen(
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
      final Map<dynamic, dynamic>? res =
          await _methodChannel.invokeMapMethod<dynamic, dynamic>('getAudioOutputInfo');
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

  void dispose() {
    _eventSubscription?.cancel();
    _deviceController.close();
  }
}
