// lib/data/audio/audio_effects_channel.dart
import 'dart:io';
import 'package:flutter/services.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/audio_effects_config.dart';

class AudioEffectsChannel {
  static const MethodChannel _channel = MethodChannel(PulsrChannels.audioEffects);

  static final AudioEffectsChannel _instance = AudioEffectsChannel._internal();
  factory AudioEffectsChannel() => _instance;
  AudioEffectsChannel._internal();

  bool _isVirtualizerSupported = false;
  bool _isDynamicsSupported = false;
  bool _isSpatializerSupported = false;
  bool _isHeadTrackerAvailable = false;
  bool _isVolumeBoostSupported = false;
  bool _isBassBoostSupported = false;
  bool _isFloatOutputSupported = true;
  bool _isHardwareOffloadSupported = true;
  bool _hasOemAudio = false;
  List<String> _detectedOemEngines = [];

  bool get isVirtualizerSupported => _isVirtualizerSupported;
  bool get isDynamicsSupported => _isDynamicsSupported;
  bool get isSpatializerSupported => _isSpatializerSupported;
  bool get isHeadTrackerAvailable => _isHeadTrackerAvailable;
  bool get isVolumeBoostSupported => _isVolumeBoostSupported;
  bool get isBassBoostSupported => _isBassBoostSupported;
  bool get isFloatOutputSupported => _isFloatOutputSupported;
  bool get isHardwareOffloadSupported => _isHardwareOffloadSupported;
  bool get hasOemAudio => _hasOemAudio;
  List<String> get detectedOemEngines => List.unmodifiable(_detectedOemEngines);

  Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      final caps = await _channel.invokeMapMethod<String, dynamic>('getCapabilities');
      if (caps != null) {
        _isVirtualizerSupported = (caps['isVirtualizerSupported'] as bool?) ?? false;
        _isDynamicsSupported = (caps['isDynamicsSupported'] as bool?) ?? false;
        _isVolumeBoostSupported = (caps['isVolumeBoostSupported'] as bool?) ?? false;
        _isBassBoostSupported = (caps['isBassBoostSupported'] as bool?) ?? false;
        _isFloatOutputSupported = (caps['isFloatOutputSupported'] as bool?) ?? true;
        _isHardwareOffloadSupported = (caps['isHardwareOffloadSupported'] as bool?) ?? true;
      }

      final spatialMap = await _channel.invokeMapMethod<String, dynamic>('getSpatializerState');
      if (spatialMap != null) {
        _isSpatializerSupported = (spatialMap['isSupported'] as bool?) ?? false;
        _isHeadTrackerAvailable = (spatialMap['isHeadTrackerAvailable'] as bool?) ?? false;
      }

      final oemMap = await detectOemAudio();
      _hasOemAudio = (oemMap['hasOemAudio'] as bool?) ?? false;
      _detectedOemEngines = (oemMap['detectedEngines'] as List<dynamic>?)?.cast<String>() ?? [];
    } catch (e, st) {
      ErrorLogger.log('Failed to initialize platform audio effects channel', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<Map<String, dynamic>> detectOemAudio() async {
    if (!Platform.isAndroid) return {'hasOemAudio': false, 'detectedEngines': <String>[]};
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('detectOemAudio');
      return result ?? {'hasOemAudio': false, 'detectedEngines': <String>[]};
    } catch (e, st) {
      ErrorLogger.log('Failed to detect OEM audio engines', error: e, stackTrace: st, category: 'AudioEffectsChannel');
      return {'hasOemAudio': false, 'detectedEngines': <String>[]};
    }
  }

  Future<bool> hasActiveEffects() async {
    if (!Platform.isAndroid) return false;
    try {
      final active = await _channel.invokeMethod<bool>('hasActiveEffects');
      return active ?? false;
    } catch (_) {
      return false;
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

  // --- NATIVE PARAMETRIC EQ ---

  Future<void> setNativeEqBand(int index, double freq, double gainDb, double q, {int type = 0, bool enabled = true}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setNativeEqBand', {
        'index': index,
        'frequency': freq,
        'gainDb': gainDb,
        'q': q,
        'type': type,
        'enabled': enabled,
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to set native EQ band ($index)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setNativeEqBandCount(int count) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setNativeEqBandCount', {'count': count});
    } catch (e, st) {
      ErrorLogger.log('Failed to set native EQ band count ($count)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setNativeEqEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setNativeEqEnabled', {'enabled': enabled});
    } catch (e, st) {
      ErrorLogger.log('Failed to set native EQ enabled ($enabled)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- HEADPHONE CROSSFEED ---

  Future<void> setCrossfeedEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setCrossfeedEnabled', {'enabled': enabled});
    } catch (e, st) {
      ErrorLogger.log('Failed to set crossfeed enabled ($enabled)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setCrossfeedParams(double delayUs, double feedDb) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setCrossfeedParams', {'delayUs': delayUs, 'feedDb': feedDb});
    } catch (e, st) {
      ErrorLogger.log('Failed to set crossfeed params', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- LOOKAHEAD BRICKWALL LIMITER ---

  Future<void> setLimiterEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setLimiterEnabled', {'enabled': enabled});
    } catch (e, st) {
      ErrorLogger.log('Failed to set limiter enabled ($enabled)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setLimiterParams(double lookaheadMs, double thresholdDb, double releaseMs) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setLimiterParams', {
        'lookaheadMs': lookaheadMs,
        'thresholdDb': thresholdDb,
        'releaseMs': releaseMs,
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to set limiter params', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- CONVOLUTION REVERB ---

  Future<void> setReverbEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setReverbEnabled', {'enabled': enabled});
    } catch (e, st) {
      ErrorLogger.log('Failed to set reverb enabled ($enabled)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setReverbPreset(int preset) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setReverbPreset', {'preset': preset});
    } catch (e, st) {
      ErrorLogger.log('Failed to set reverb preset ($preset)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setReverbWetDry(double wetRatio) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setReverbWetDry', {'wetRatio': wetRatio});
    } catch (e, st) {
      ErrorLogger.log('Failed to set reverb wet/dry ($wetRatio)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> loadImpulseResponse(List<double> irSamples) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('loadImpulseResponse', {'irSamples': irSamples});
    } catch (e, st) {
      ErrorLogger.log('Failed to load impulse response', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- STEREO BALANCE & MONO MIX ---

  Future<void> setStereoBalance(double balance) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setStereoBalance', {'balance': balance.clamp(-1.0, 1.0)});
    } catch (e, st) {
      ErrorLogger.log('Failed to set stereo balance ($balance)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setMonoMix(bool mono) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setMonoMix', {'mono': mono});
    } catch (e, st) {
      ErrorLogger.log('Failed to set mono mix ($mono)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- SINC RESAMPLER ---

  Future<void> setSincResamplerEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setSincResamplerEnabled', {'enabled': enabled});
    } catch (e, st) {
      ErrorLogger.log('Failed to set sinc resampler enabled ($enabled)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setSincResamplerRates(double inRate, double outRate) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setSincResamplerRates', {'inRate': inRate, 'outRate': outRate});
    } catch (e, st) {
      ErrorLogger.log('Failed to set sinc resampler rates ($inRate -> $outRate)', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- DSD DECODING ---

  Future<List<double>?> decodeDsd(List<int> dsdL, List<int> dsdR, {int dsdRate = 64, int targetSampleRate = 176400, int bitOrder = 0}) async {
    if (!Platform.isAndroid) return null;
    try {
      final List<dynamic>? res = await _channel.invokeListMethod<dynamic>('decodeDsd', {
        'dsdL': Uint8List.fromList(dsdL),
        'dsdR': Uint8List.fromList(dsdR),
        'byteCount': dsdL.length,
        'dsdRate': dsdRate,
        'targetSampleRate': targetSampleRate,
        'bitOrder': bitOrder,
      });
      if (res != null) {
        return res.map((e) => (e as num).toDouble()).toList();
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to decode DSD stream', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
    return null;
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
