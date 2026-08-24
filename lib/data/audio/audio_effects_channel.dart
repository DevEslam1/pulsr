// lib/data/audio/audio_effects_channel.dart
import 'dart:io';
import 'package:flutter/services.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/audio_effects_config.dart';

class AudioEffectsChannel {
  static const MethodChannel _channel = MethodChannel('com.pulsr.music/audio_effects');

  static final AudioEffectsChannel _instance = AudioEffectsChannel._internal();
  factory AudioEffectsChannel() => _instance;
  AudioEffectsChannel._internal();

  bool _isVirtualizerSupported = false;
  bool _isDynamicsSupported = false;
  bool _isSpatializerSupported = false;
  bool _isVolumeBoostSupported = false;
  bool _isBassBoostSupported = false;

  bool get isVirtualizerSupported => _isVirtualizerSupported;
  bool get isDynamicsSupported => _isDynamicsSupported;
  bool get isSpatializerSupported => _isSpatializerSupported;
  bool get isVolumeBoostSupported => _isVolumeBoostSupported;
  bool get isBassBoostSupported => _isBassBoostSupported;

  Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      final virtSup = await _channel.invokeMethod<bool>('isVirtualizerSupported');
      _isVirtualizerSupported = virtSup ?? false;

      final dynSup = await _channel.invokeMethod<bool>('isDynamicsSupported');
      _isDynamicsSupported = dynSup ?? false;

      final vbSup = await _channel.invokeMethod<bool>('isVolumeBoostSupported');
      _isVolumeBoostSupported = vbSup ?? false;

      final bbSup = await _channel.invokeMethod<bool>('isBassBoostSupported');
      _isBassBoostSupported = bbSup ?? false;

      final spatialMap = await _channel.invokeMapMethod<String, dynamic>('getSpatializerState');
      if (spatialMap != null) {
        _isSpatializerSupported = (spatialMap['isSupported'] as bool?) ?? false;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to initialize platform audio effects channel', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setAudioSessionId(int sessionId) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setAudioSessionId', {'audioSessionId': sessionId});
    } catch (e, st) {
      ErrorLogger.log('Failed to set audioSessionId ($sessionId)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setVolumeBoost(int milliBels) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setVolumeBoost', {'milliBels': milliBels});
    } catch (e, st) {
      ErrorLogger.log('Failed to set volume boost ($milliBels mB)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setBassBoost(int strength) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setBassBoost', {'strength': strength});
    } catch (e, st) {
      ErrorLogger.log('Failed to set bass boost strength ($strength)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setVirtualizerEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setVirtualizerEnabled', {'enabled': enabled});
    } catch (e, st) {
      ErrorLogger.log('Failed to set virtualizer enabled ($enabled)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setVirtualizerStrength(double strength0to1) async {
    if (!Platform.isAndroid) return;
    try {
      final intStrength = (strength0to1.clamp(0.0, 1.0) * 1000).round();
      await _channel.invokeMethod('setVirtualizerStrength', {'strength': intStrength});
    } catch (e, st) {
      ErrorLogger.log('Failed to set virtualizer strength ($strength0to1)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setDynamicsPreset(DynamicsPreset preset, bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setDynamicsPreset', {
        'preset': preset.name,
        'enabled': enabled && preset != DynamicsPreset.off,
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to set dynamics preset (${preset.name})', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setSpatializerEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setSpatializerEnabled', {'enabled': enabled});
    } catch (e, st) {
      ErrorLogger.log('Failed to set spatializer enabled ($enabled)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Enables/disables the native 10-band graphic EQ (DynamicsProcessing postEq).
  Future<void> setEqEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setEqEnabled', {'enabled': enabled});
    } catch (e, st) {
      ErrorLogger.log('Failed to set EQ enabled ($enabled)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Sets the band center frequencies (Hz). Length defines the band count.
  Future<void> setEqBands(List<double> frequencies) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setEqBands', {'frequencies': frequencies});
    } catch (e, st) {
      ErrorLogger.log('Failed to set EQ bands ($frequencies)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Live-updates a single band's gain (dB) without rebuilding the effect.
  Future<void> setEqBandGain(int index, double gainDb) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setEqBandGain', {'index': index, 'gainDb': gainDb});
    } catch (e, st) {
      ErrorLogger.log('Failed to set EQ band gain (index $index, $gainDb dB)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Sets all band gains (dB) at once. Length should match the band count.
  Future<void> setEqBandGains(List<double> gains) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setEqBandGains', {'gains': gains});
    } catch (e, st) {
      ErrorLogger.log('Failed to set EQ band gains ($gains)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Sets the EQ preamp (dB). Negative values attenuate as real headroom.
  Future<void> setEqPreamp(double preampDb) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setEqPreamp', {'preampDb': preampDb});
    } catch (e, st) {
      ErrorLogger.log('Failed to set EQ preamp ($preampDb dB)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> releaseEffects() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('releaseEffects');
    } catch (e, st) {
      ErrorLogger.log('Failed to release audio effects', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }
}
