// lib/data/audio/audio_effects_channel.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/platform_capabilities.dart';
import '../../domain/models/audio_effects_config.dart';

class AudioEffectsChannel {
  /// Test-only observation of the last value pushed to the native
  /// bit-perfect DSP-bypass switch (null = nothing pushed yet).
  @visibleForTesting
  static bool? lastPushedBypassDspForBitPerfect;

  static const MethodChannel _channel =
      MethodChannel(PulsrChannels.audioEffects);

  static final AudioEffectsChannel _instance = AudioEffectsChannel._internal();
  factory AudioEffectsChannel() => _instance;
  AudioEffectsChannel._internal();

  bool get _isAndroid => PlatformCapabilities.isAndroid;

  /// Dispose stream controller (call on hot restart / test teardown).
  void dispose() {
    if (!_autoDegradeStreamController.isClosed) {
      _autoDegradeStreamController.close();
    }
  }

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
    if (!_isAndroid) return;
    // Isolate each probe so partial success is retained
    try {
      final caps = await _channel
          .invokeMapMethod<String, dynamic>('getCapabilities')
          .timeout(const Duration(seconds: 2));
      if (caps != null) {
        _isVirtualizerSupported =
            (caps['isVirtualizerSupported'] == true || caps['isVirtualizerSupported'] == 1);
        _isDynamicsSupported =
            (caps['isDynamicsSupported'] == true || caps['isDynamicsSupported'] == 1);
        _isVolumeBoostSupported =
            (caps['isVolumeBoostSupported'] == true || caps['isVolumeBoostSupported'] == 1);
        _isBassBoostSupported =
            (caps['isBassBoostSupported'] == true || caps['isBassBoostSupported'] == 1);
        _isFloatOutputSupported =
            (caps['isFloatOutputSupported'] == true || caps['isFloatOutputSupported'] == 1);
        _isHardwareOffloadSupported =
            (caps['isHardwareOffloadSupported'] == true || caps['isHardwareOffloadSupported'] == 1);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to getCapabilities',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
    try {
      final spatialMap = await _channel
          .invokeMapMethod<String, dynamic>('getSpatializerState')
          .timeout(const Duration(seconds: 2));
      if (spatialMap != null) {
        _isSpatializerSupported = (spatialMap['isSupported'] == true);
        _isHeadTrackerAvailable =
            (spatialMap['isHeadTrackerAvailable'] == true);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to getSpatializerState',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
    try {
      final oemMap = await detectOemAudio();
      _hasOemAudio = (oemMap['hasOemAudio'] == true);
      _detectedOemEngines =
          (oemMap['detectedEngines'] as List<dynamic>?)?.cast<String>() ?? [];
    } catch (e, st) {
      ErrorLogger.log('Failed to detectOemAudio',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<Map<String, dynamic>> detectOemAudio() async {
    if (!_isAndroid) {
      return {'hasOemAudio': false, 'detectedEngines': <String>[]};
    }
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('detectOemAudio')
          .timeout(const Duration(seconds: 2));
      return result ?? {'hasOemAudio': false, 'detectedEngines': <String>[]};
    } catch (e, st) {
      ErrorLogger.log('Failed to detect OEM audio engines',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
      return {'hasOemAudio': false, 'detectedEngines': <String>[]};
    }
  }

  Future<bool> hasActiveEffects() async {
    if (!_isAndroid) return false;
    try {
      final active = await _channel
          .invokeMethod<bool>('hasActiveEffects')
          .timeout(const Duration(seconds: 2));
      return active ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setAudioSessionId(int sessionId) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setAudioSessionId', {'audioSessionId': sessionId})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log('Failed to set audioSessionId ($sessionId)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setVolumeBoost(int milliBels) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setVolumeBoost', {'milliBels': milliBels}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set volume boost ($milliBels mB)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setBassBoost(int strength) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setBassBoost', {'strength': strength}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set bass boost strength ($strength)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setVirtualizerEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setVirtualizerEnabled', {'enabled': enabled});
    } catch (e, st) {
      ErrorLogger.log('Failed to set virtualizer enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setVirtualizerStrength(double strength0to1) async {
    if (!_isAndroid) return;
    try {
      final intStrength = (strength0to1.clamp(0.0, 1.0) * 1000).round();
      await _channel
          .invokeMethod('setVirtualizerStrength', {'strength': intStrength});
    } catch (e, st) {
      ErrorLogger.log('Failed to set virtualizer strength ($strength0to1)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setDynamicsPreset(DynamicsPreset preset, bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setDynamicsPreset', {
        'preset': preset.name,
        'enabled': enabled && preset != DynamicsPreset.off,
      }).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set dynamics preset (${preset.name})',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setSpatializerEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setSpatializerEnabled', {'enabled': enabled});
    } catch (e, st) {
      ErrorLogger.log('Failed to set spatializer enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Enables/disables the native 10-band graphic EQ (DynamicsProcessing postEq).
  Future<void> setEqEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setEqEnabled', {'enabled': enabled}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set EQ enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Sets the band center frequencies (Hz). Length defines the band count.
  Future<void> setEqBands(List<double> frequencies) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setEqBands', {'frequencies': frequencies}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set EQ bands ($frequencies)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Live-updates a single band's gain (dB) without rebuilding the effect.
  Future<void> setEqBandGain(int index, double gainDb) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setEqBandGain', {'index': index, 'gainDb': gainDb});
    } catch (e, st) {
      ErrorLogger.log('Failed to set EQ band gain (index $index, $gainDb dB)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Sets all band gains (dB) at once. Length should match the band count.
  Future<void> setEqBandGains(List<double> gains) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setEqBandGains', {'gains': gains}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set EQ band gains ($gains)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Sets the EQ preamp (dB). Negative values attenuate as real headroom.
  Future<void> setEqPreamp(double preampDb) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setEqPreamp', {'preampDb': preampDb}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set EQ preamp ($preampDb dB)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- NATIVE PARAMETRIC EQ ---

  Future<void> setNativeEqBand(int index, double freq, double gainDb, double q,
      {int type = 0, bool enabled = true}) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setNativeEqBand', {
        'index': index,
        'frequency': freq,
        'gainDb': gainDb,
        'q': q,
        'type': type,
        'enabled': enabled,
      }).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set native EQ band ($index)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Bulk update for all bands in a single JNI hop (reduces 32 hops -> 1).
  Future<void> setNativeEqBandsBulk({
    required List<double> frequencies,
    required List<double> gains,
    List<double>? qs,
    List<int>? types,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setNativeEqBandsBulk', {
        'frequencies': frequencies,
        'gains': gains,
        'qs': qs ?? List<double>.filled(frequencies.length, 1.414),
        'types': types ?? List<int>.filled(frequencies.length, 0),
      }).timeout(const Duration(seconds: 5));
    } catch (e, st) {
      ErrorLogger.log('Failed to set native EQ bands bulk',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setNativeEqBandCount(int count) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setNativeEqBandCount', {'count': count}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set native EQ band count ($count)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setNativeEqEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setNativeEqEnabled', {'enabled': enabled}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set native EQ enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Unified bypass for all DSP stages when bit-perfect is active.
  Future<void> setBypassDspForBitPerfect(bool bypass) async {
    if (!_isAndroid) return;
    lastPushedBypassDspForBitPerfect = bypass;
    try {
      await _channel
          .invokeMethod('setBypassDspForBitPerfect', {'bypass': bypass})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log('Failed to set bypass DSP for bit-perfect ($bypass)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- HEADPHONE CROSSFEED ---

  Future<void> setCrossfeedEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setCrossfeedEnabled', {'enabled': enabled}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set crossfeed enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setCrossfeedParams(double delayUs, double feedDb) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod(
          'setCrossfeedParams', {'delayUs': delayUs, 'feedDb': feedDb}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set crossfeed params',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- LOOKAHEAD BRICKWALL LIMITER ---

  Future<void> setLimiterEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setLimiterEnabled', {'enabled': enabled}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set limiter enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setLimiterParams(
      double lookaheadMs, double thresholdDb, double releaseMs) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setLimiterParams', {
        'lookaheadMs': lookaheadMs,
        'thresholdDb': thresholdDb,
        'releaseMs': releaseMs,
      }).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set limiter params',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- CONVOLUTION REVERB ---

  Future<void> setReverbEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setReverbEnabled', {'enabled': enabled}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set reverb enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setReverbPreset(int preset) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setReverbPreset', {'preset': preset}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set reverb preset ($preset)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setReverbWetDry(double wetRatio) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setReverbWetDry', {'wetRatio': wetRatio}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set reverb wet/dry ($wetRatio)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> loadImpulseResponse(List<double> irSamples) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('loadImpulseResponse', {'irSamples': irSamples});
    } catch (e, st) {
      ErrorLogger.log('Failed to load impulse response',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- STEREO BALANCE & MONO MIX ---

  Future<void> setStereoBalance(double balance) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod(
          'setStereoBalance', {'balance': balance.clamp(-1.0, 1.0)}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set stereo balance ($balance)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setMonoMix(bool mono) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setMonoMix', {'mono': mono}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set mono mix ($mono)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- SINC RESAMPLER ---

  Future<void> setSincResamplerEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setSincResamplerEnabled', {'enabled': enabled});
    } catch (e, st) {
      ErrorLogger.log('Failed to set sinc resampler enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setSincResamplerRates(double inRate, double outRate) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod(
          'setSincResamplerRates', {'inRate': inRate, 'outRate': outRate}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
          'Failed to set sinc resampler rates ($inRate -> $outRate)',
          error: e,
          stackTrace: st,
          category: 'AudioEffectsChannel');
    }
  }

  // --- PHASE 1 DSP EXPANSION: HARMONIC SATURATION / EXCITER ---

  Future<void> setSaturationEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setSaturationEnabled', {'enabled': enabled}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set saturation enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setSaturationParams(double drive, double mix, double tilt) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setSaturationParams', {
        'drive': drive,
        'mix': mix,
        'tilt': tilt,
      }).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set saturation params',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- PHASE 1 DSP EXPANSION: STEREO WIDTH (MID/SIDE) ---

  Future<void> setStereoWidthEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setStereoWidthEnabled', {'enabled': enabled}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set stereo width enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setStereoWidthParams(double width) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setStereoWidthParams', {'width': width}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set stereo width ($width)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- PHASE 1 DSP EXPANSION: LOUDNESS CONTOUR (FLETCHER-MUNSON) ---

  Future<void> setLoudnessContourEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setLoudnessContourEnabled', {'enabled': enabled});
    } catch (e, st) {
      ErrorLogger.log('Failed to set loudness contour enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setLoudnessContourParams(
      double intensity, double volumeLinear) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setLoudnessContourParams', {
        'intensity': intensity,
        'volumeLinear': volumeLinear,
      }).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set loudness contour params',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- PHASE 1 DSP EXPANSION: SUBWOOFER / LFE CROSSOVER ---

  Future<void> setSubCrossoverEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setSubCrossoverEnabled', {'enabled': enabled}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set sub crossover enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setSubCrossoverParams(
      double cornerHz, double slopeDbPerOct, double subGain) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setSubCrossoverParams', {
        'cornerHz': cornerHz,
        'slopeDbPerOct': slopeDbPerOct,
        'subGain': subGain,
      }).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set sub crossover params',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- PHASE 1 DSP EXPANSION: DYNAMIC EQ ---

  Future<void> setDynamicEqEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setDynamicEqEnabled', {'enabled': enabled}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set dynamic EQ enabled ($enabled)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setDynamicEqBandCount(int count) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setDynamicEqBandCount', {'count': count}).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set dynamic EQ band count ($count)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setDynamicEqBand(
    int index, {
    required double frequency,
    required double q,
    required double thresholdDb,
    required double ratio,
    required double attackMs,
    required double releaseMs,
    required double maxCutDb,
    bool enabled = true,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setDynamicEqBand', {
        'index': index,
        'frequency': frequency,
        'q': q,
        'thresholdDb': thresholdDb,
        'ratio': ratio,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        'maxCutDb': maxCutDb,
        'enabled': enabled,
      }).timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Failed to set dynamic EQ band $index',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  // --- DSD DECODING ---

  Future<List<double>?> decodeDsd(List<int> dsdL, List<int> dsdR,
      {int dsdRate = 64,
      int targetSampleRate = 176400,
      int bitOrder = 0}) async {
    if (!_isAndroid) return null;
    try {
      final List<dynamic>? res = await _channel
          .invokeListMethod<dynamic>('decodeDsd', {
            'dsdL': Uint8List.fromList(dsdL),
            'dsdR': Uint8List.fromList(dsdR),
            'byteCount': dsdL.length,
            'dsdRate': dsdRate,
            'targetSampleRate': targetSampleRate,
            'bitOrder': bitOrder,
          })
          .timeout(const Duration(seconds: 10));
      if (res != null) {
        return res.map((e) => (e as num).toDouble()).toList();
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to decode DSD stream',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
    return null;
  }

  Future<int> getPipelineLatencyFrames() async {
    if (!_isAndroid) return 0;
    try {
      final dynamic latency = await _channel
          .invokeMethod<dynamic>('getPipelineLatencyFrames')
          .timeout(const Duration(seconds: 2));
      if (latency is num) return latency.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> setBandSolo(int index, bool solo) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setBandSolo', {'index': index, 'solo': solo})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log('setBandSolo failed', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setBandMute(int index, bool mute) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setBandMute', {'index': index, 'mute': mute})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log('setBandMute failed', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setReverbParams(
      {double predelayMs = 0.0, double damping = 0.5}) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setReverbParams', {'predelayMs': predelayMs, 'damping': damping})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log('setReverbParams failed', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> setDspPreference(String preference) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setDspPreference', {'preference': preference})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log('setDspPreference failed', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  Future<void> releaseEffects() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('releaseEffects').timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log('Failed to release audio effects',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Call whenever audio format changes or on session resume/track switch.
  /// Forces native DSP generation bump, re-calculates all filter coefficients for [sampleRate],
  /// and flushes stale audio filter state.
  Future<void> resyncForTrack(double sampleRate, {int channels = 2}) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('resyncForTrack', {'sampleRate': sampleRate, 'channels': channels})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log('Failed to resync DSP for track ($sampleRate Hz)',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Configures native synthetic IR LRU cache budget (16MB on low RAM devices, 64MB default).
  Future<void> setCacheBudgetBytes(int budgetBytes) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setCacheBudgetBytes', {'budgetBytes': budgetBytes}).timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log('setCacheBudgetBytes failed', error: e, stackTrace: st, category: 'AudioEffectsChannel');
    }
  }

  /// Gets the current bitmask of auto-degraded stages from the native DSP engine.
  Future<int> getAutoDegradedStages() async {
    if (!_isAndroid) return 0;
    try {
      final dynamic res = await _channel.invokeMethod<dynamic>('getAutoDegradedStages').timeout(const Duration(seconds: 2));
      final stages = (res as num?)?.toInt() ?? 0;
      _handleAutoDegradeTransition(stages);
      return stages;
    } catch (_) {
      return 0;
    }
  }

  final _autoDegradeStreamController = StreamController<int>.broadcast();
  int _lastKnownDegradedStages = 0;

  /// Stream that emits the auto-degraded stage mask EXACTLY ONCE per 0 -> nonzero transition.
  /// No spam within the same degraded session; re-notifies only after full recovery to 0.
  Stream<int> get onAutoDegradedSessionStarted => _autoDegradeStreamController.stream;

  void _handleAutoDegradeTransition(int currentStages) {
    if (_lastKnownDegradedStages == 0 && currentStages != 0) {
      _autoDegradeStreamController.add(currentStages);
    }
    _lastKnownDegradedStages = currentStages;
  }

  /// Retrieves internal DSP status for assertions/testing.
  Future<Map<String, dynamic>?> getDspDebugStatus() async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMapMethod<String, dynamic>('getDspDebugStatus').timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }
}
