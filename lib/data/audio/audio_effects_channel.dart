// lib/data/audio/audio_effects_channel.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/platform_capabilities.dart';
import '../../domain/models/audio_effects_config.dart';
import '../../domain/models/dsp_debug_report.dart';

class AudioEffectsChannel {
  /// Test-only observation of the last value pushed to the native
  /// bit-perfect DSP-bypass switch (null = nothing pushed yet).
  @visibleForTesting
  static bool? lastPushedBypassDspForBitPerfect;

  static const MethodChannel _channel = MethodChannel(
    PulsrChannels.audioEffects,
  );

  static final AudioEffectsChannel _instance = AudioEffectsChannel._internal();
  factory AudioEffectsChannel() => _instance;
  AudioEffectsChannel._internal() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final StreamController<void> _routeChangedController =
      StreamController<void>.broadcast();

  /// Stream emitting whenever the native audio route changes (earpods/headphones connected/disconnected).
  Stream<void> get onRouteChanged => _routeChangedController.stream;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onRouteChanged') {
      if (!_routeChangedController.isClosed) {
        _routeChangedController.add(null);
      }
    }
  }

  /// Whether the platform can apply native audio effects at all. Every
  /// bool-returning setter must report `false` here instead of pretending the
  /// effect was applied, so callers can gate the UI truthfully.
  bool get _isAndroid => PlatformCapabilities.isAndroid;

  /// Dispose stream controller (call on hot restart / test teardown).
  void dispose() {
    if (!_autoDegradeStreamController.isClosed) {
      _autoDegradeStreamController.close();
    }
    if (!_routeChangedController.isClosed) {
      _routeChangedController.close();
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
  // Health of the session-bound AudioEffect (HAL) chain: EQ, dynamics,
  // virtualizer, bass boost, loudness enhancer.
  bool _isPcmDspAttached = false;

  /// Whether the native C++ chain is in the audible path. The vendored
  /// just_audio fork splices NativeDspAudioProcessor into ExoPlayer's audio
  /// sink, so this is true whenever libpulsr_dsp loaded.
  bool _hasPcmDspPath = false;
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
  bool get isPcmDspAttached => _isPcmDspAttached;

  /// Whether the native C++ DSP chain is in ExoPlayer's audible path.
  bool get hasPcmDspPath => _hasPcmDspPath;
  bool get hasOemAudio => _hasOemAudio;
  List<String> get detectedOemEngines => List.unmodifiable(_detectedOemEngines);

  Future<void> init() async {
    if (!_isAndroid) return;
    // Isolate each probe so partial success is retained
    try {
      final caps = await _channel
          .invokeMapMethod<String, dynamic>('getCapabilities')
          .timeout(const Duration(seconds: 8));
      if (caps != null) {
        _isVirtualizerSupported =
            (caps['isVirtualizerSupported'] == true ||
                caps['isVirtualizerSupported'] == 1);
        _isDynamicsSupported =
            (caps['isDynamicsSupported'] == true ||
                caps['isDynamicsSupported'] == 1);
        _isVolumeBoostSupported =
            (caps['isVolumeBoostSupported'] == true ||
                caps['isVolumeBoostSupported'] == 1);
        _isBassBoostSupported =
            (caps['isBassBoostSupported'] == true ||
                caps['isBassBoostSupported'] == 1);
        _isFloatOutputSupported =
            (caps['isFloatOutputSupported'] == true ||
                caps['isFloatOutputSupported'] == 1);
        _isHardwareOffloadSupported =
            (caps['isHardwareOffloadSupported'] == true ||
                caps['isHardwareOffloadSupported'] == 1);
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to getCapabilities',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
    try {
      final pipeline = await _channel
          .invokeMapMethod<String, dynamic>('getProcessingCapabilities')
          .timeout(const Duration(seconds: 8));
      _isPcmDspAttached = pipeline?['isPcmDspAttached'] == true;
      _hasPcmDspPath = pipeline?['hasPcmDspPath'] == true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to get DSP processing capabilities',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
    try {
      final spatialMap = await _channel
          .invokeMapMethod<String, dynamic>('getSpatializerState')
          .timeout(const Duration(seconds: 8));
      if (spatialMap != null) {
        _isSpatializerSupported = (spatialMap['isSupported'] == true);
        _isHeadTrackerAvailable =
            (spatialMap['isHeadTrackerAvailable'] == true);
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to getSpatializerState',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
    try {
      final oemMap = await detectOemAudio();
      _hasOemAudio = (oemMap['hasOemAudio'] == true);
      _detectedOemEngines =
          (oemMap['detectedEngines'] as List<dynamic>?)?.cast<String>() ?? [];
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to detectOemAudio',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<Map<String, dynamic>> detectOemAudio() async {
    if (!_isAndroid) {
      return {'hasOemAudio': false, 'detectedEngines': <String>[]};
    }
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('detectOemAudio')
          .timeout(const Duration(seconds: 8));
      return result ?? {'hasOemAudio': false, 'detectedEngines': <String>[]};

    } catch (e, st) {
      ErrorLogger.log(
        'Failed to detect OEM audio engines',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return {'hasOemAudio': false, 'detectedEngines': <String>[]};
    }
  }

  /// Query installed vendor / Dolby Atmos effects.
  Future<Map<String, dynamic>> detectSystemEffects() async {
    if (!_isAndroid) {
      return {
        'status': 'unsupportedDevice',
        'detectedBundles': <String>[],
        'hasDolbyOrVendor': false,
      };
    }
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('detectSystemEffects')
          .timeout(const Duration(seconds: 2));
      return result ?? {
        'status': 'unsupportedDevice',
        'detectedBundles': <String>[],
        'hasDolbyOrVendor': false,
      };
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to detect system audio effects',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return {
        'status': 'unknown',
        'detectedBundles': <String>[],
        'hasDolbyOrVendor': false,
      };
    }
  }

  /// Configure policy for vendor Dolby/system effects ('auto', 'tryDisable', 'leaveOn').
  Future<String> setSystemEffectsPolicy(String policy, {bool isHiResOrBitPerfect = false}) async {
    if (!_isAndroid) return 'unsupportedDevice';
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setSystemEffectsPolicy',
        {
          'policy': policy,
          'isHiResOrBitPerfect': isHiResOrBitPerfect,
        },
      ).timeout(const Duration(seconds: 2));
      return result?['status'] as String? ?? 'unknown';
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set system effects policy',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return 'unknown';
    }
  }

  /// Get current live status of system effects ('bypassed', 'active', 'unknown', 'unsupportedDevice').
  Future<Map<String, dynamic>> getSystemEffectsStatus() async {
    if (!_isAndroid) {
      return {'status': 'unsupportedDevice', 'detectedBundles': <String>[]};
    }
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('getSystemEffectsStatus')
          .timeout(const Duration(seconds: 2));
      return result ?? {'status': 'unknown', 'detectedBundles': <String>[]};
    } catch (_) {
      return {'status': 'unknown', 'detectedBundles': <String>[]};
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

  /// Pushes the active player's audio session id to the native effect stack.
  ///
  /// Guards against invalid ids: 0 (or negative) means "no session" and would
  /// bind AudioEffect instances to the global output mix, so it is ignored.
  /// The native side additionally releases + recreates the effects on the new
  /// session and reports truthful attachment state back.
  Future<void> setAudioSessionId(int sessionId) async {
    if (!_isAndroid) return;
    if (sessionId <= 0) {
      ErrorLogger.log(
        'Ignoring invalid audio session id ($sessionId)',
        category: 'AudioEffectsChannel',
      );
      return;
    }
    try {
      ErrorLogger.log(
        'Calling native setAudioSessionId($sessionId)',
        category: 'AudioEffectsChannel',
      );
      final result = await _channel
          .invokeMethod('setAudioSessionId', {'audioSessionId': sessionId})
          .timeout(const Duration(seconds: 2));
      ErrorLogger.log(
        'Native setAudioSessionId($sessionId) returned: $result',
        category: 'AudioEffectsChannel',
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set audioSessionId ($sessionId)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      rethrow; // Re-throw so reapplyToSession knows this failed
    }
  }

  /// Returns true when the native layer confirmed the boost was applied.
  /// An explicit `false` means the device has no LoudnessEnhancer, the effect
  /// failed to build, no audio session is attached, or the platform is not
  /// Android (unsupported). A missing return (older bridges) is treated as
  /// success so nothing regresses.
  Future<bool> setVolumeBoost(int milliBels) async {
    if (!_isAndroid) return false;
    try {
      final bool? applied = await _channel
          .invokeMethod<bool>('setVolumeBoost', {'milliBels': milliBels})
          .timeout(const Duration(seconds: 3));
      return applied ?? true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set volume boost ($milliBels mB)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  /// Returns true when the native BassBoost was actually applied.
  Future<bool> setBassBoost(int strength) async {
    if (!_isAndroid) return false;
    try {
      final bool? applied = await _channel
          .invokeMethod<bool>('setBassBoost', {'strength': strength})
          .timeout(const Duration(seconds: 3));
      return applied ?? true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set bass boost strength ($strength)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  /// Returns true when the native Virtualizer was actually enabled/disabled.
  Future<bool> setVirtualizerEnabled(bool enabled) async {
    if (!_isAndroid) return false;
    try {
      final bool? applied = await _channel
          .invokeMethod<bool>('setVirtualizerEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
      return applied ?? true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set virtualizer enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  /// Returns true when the native Virtualizer strength was actually applied.
  Future<bool> setVirtualizerStrength(double strength0to1) async {
    if (!_isAndroid) return false;
    try {
      final intStrength = (strength0to1.clamp(0.0, 1.0) * 1000).round();
      final bool? applied = await _channel
          .invokeMethod<bool>('setVirtualizerStrength', {
        'strength': intStrength,
      }).timeout(const Duration(seconds: 3));
      return applied ?? true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set virtualizer strength ($strength0to1)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  /// Returns true when DynamicsProcessing accepted the preset.
  Future<bool> setDynamicsPreset(DynamicsPreset preset, bool enabled) async {
    if (!_isAndroid) return false;
    try {
      final bool? applied = await _channel
          .invokeMethod<bool>('setDynamicsPreset', {
            'preset': preset.name,
            'enabled': enabled && preset != DynamicsPreset.off,
          })
          .timeout(const Duration(seconds: 3));
      return applied ?? true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set dynamics preset (${preset.name})',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  /// Returns true when the Spatializer (or its Virtualizer fallback) applied.
  Future<bool> setSpatializerEnabled(bool enabled) async {
    if (!_isAndroid) return false;
    try {
      final bool? applied = await _channel
          .invokeMethod<bool>('setSpatializerEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
      return applied ?? true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set spatializer enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  /// Enables/disables the native 10-band graphic EQ (DynamicsProcessing postEq).
  Future<void> setEqEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setEqEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set EQ enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  /// Sets the band center frequencies (Hz). Length defines the band count.
  Future<void> setEqBands(List<double> frequencies) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setEqBands', {'frequencies': frequencies})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set EQ bands ($frequencies)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  /// Live-updates a single band's gain (dB) without rebuilding the effect.
  Future<void> setEqBandGain(int index, double gainDb) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setEqBandGain', {
        'index': index,
        'gainDb': gainDb,
      });
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set EQ band gain (index $index, $gainDb dB)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  /// Sets all band gains (dB) at once. Length should match the band count.
  Future<void> setEqBandGains(List<double> gains) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setEqBandGains', {'gains': gains})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set EQ band gains ($gains)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  /// Sets the EQ preamp (dB). Negative values attenuate as real headroom.
  Future<void> setEqPreamp(double preampDb) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setEqPreamp', {'preampDb': preampDb})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set EQ preamp ($preampDb dB)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- NATIVE PARAMETRIC EQ ---

  Future<void> setNativeEqBand(
    int index,
    double freq,
    double gainDb,
    double q, {
    int type = 0,
    bool enabled = true,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setNativeEqBand', {
            'index': index,
            'frequency': freq,
            'gainDb': gainDb,
            'q': q,
            'type': type,
            'enabled': enabled,
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set native EQ band ($index)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
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
      await _channel
          .invokeMethod('setNativeEqBandsBulk', {
            'frequencies': frequencies,
            'gains': gains,
            'qs': qs ?? List<double>.filled(frequencies.length, 1.414),
            'types': types ?? List<int>.filled(frequencies.length, 0),
          })
          .timeout(const Duration(seconds: 5));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set native EQ bands bulk',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setNativeEqBandCount(int count) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setNativeEqBandCount', {'count': count})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set native EQ band count ($count)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setNativeEqEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setNativeEqEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set native EQ enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  /// Unified bypass for all DSP stages when bit-perfect is active.
  /// [isDop] mirrors the DoP lock into the native snapshot when known.
  Future<void> setBypassDspForBitPerfect(bool bypass, {bool? isDop}) async {
    if (!_isAndroid) return;
    lastPushedBypassDspForBitPerfect = bypass;
    try {
      await _channel
          .invokeMethod('setBypassDspForBitPerfect', {
            'bypass': bypass,
            if (isDop != null) 'isDop': isDop,
          })
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set bypass DSP for bit-perfect ($bypass)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- NATIVE REPLAYGAIN (tag-supplied pre-gain in DSP) ---

  /// Pushes ReplayGain tags into the native DSP pre-gain stage. The gain comes
  /// from the track's existing ReplayGain tags; there is no EBU R128 / RG 2.0
  /// measurement in the native path (the Dart side computes the multiplier).
  /// [mode]: 0=off, 1=track, 2=album. Keeps the Android mixer at unity so
  /// DoP markers and bit-perfect PCM survive; volume slider stays separate.
  ///
  /// Returns true when the native engine applied the params. An explicit
  /// `false` means the native DSP engine is not loaded. A missing return
  /// (older bridges) is treated as success.
  Future<bool> setReplayGainParams({
    required int mode,
    required double trackGainDb,
    required double albumGainDb,
    required double trackPeak,
    required double albumPeak,
    required double preAmpDb,
    bool preventClipping = true,
    required bool enabled,
  }) async {
    if (!_isAndroid) return false;
    try {
      final bool? applied = await _channel
          .invokeMethod<bool>('setReplayGainParams', {
            'mode': mode,
            'trackGainDb': trackGainDb,
            'albumGainDb': albumGainDb,
            'trackPeak': trackPeak,
            'albumPeak': albumPeak,
            'preAmpDb': preAmpDb,
            'preventClipping': preventClipping,
            'enabled': enabled,
          })
          .timeout(const Duration(seconds: 2));
      return applied ?? true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set native ReplayGain params (mode=$mode)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  /// Returns true when the native ReplayGain enable flag was applied.
  Future<bool> setReplayGainEnabled(bool enabled) async {
    if (!_isAndroid) return false;
    try {
      final bool? applied = await _channel
          .invokeMethod<bool>('setReplayGainEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 2));
      return applied ?? true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set native ReplayGain enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  // --- HEADPHONE CROSSFEED ---

  Future<void> setCrossfeedEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setCrossfeedEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set crossfeed enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setCrossfeedParams(double delayUs, double feedDb) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setCrossfeedParams', {
            'delayUs': delayUs,
            'feedDb': feedDb,
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set crossfeed params',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- LOOKAHEAD BRICKWALL LIMITER ---

  Future<void> setLimiterEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setLimiterEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set limiter enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setLimiterParams(
    double lookaheadMs,
    double thresholdDb,
    double releaseMs, {
    double? ratio,
    double? attackMs,
    double? makeupGainDb,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setLimiterParams', {
            'lookaheadMs': lookaheadMs,
            'thresholdDb': thresholdDb,
            'releaseMs': releaseMs,
            // Compressor knobs (HAL DynamicsProcessing limiter). Omitted unless
            // the user owns them so the native brickwall defaults are preserved.
            if (ratio != null) 'ratio': ratio,
            if (attackMs != null) 'attackMs': attackMs,
            if (makeupGainDb != null) 'makeupGainDb': makeupGainDb,
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set limiter params',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- CONVOLUTION REVERB ---

  Future<void> setReverbEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setReverbEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set reverb enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setReverbPreset(int preset) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setReverbPreset', {'preset': preset})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set reverb preset ($preset)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setReverbWetDry(double wetRatio) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setReverbWetDry', {'wetRatio': wetRatio})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set reverb wet/dry ($wetRatio)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  /// Loads a custom impulse response into the native convolution reverb.
  /// Returns false when the request was rejected (invalid/empty samples,
  /// native DSP unavailable, channel error, or an explicit native failure)
  /// so callers do not report a successful custom-IR load untruthfully.
  Future<bool> loadImpulseResponse(List<double> irSamples) async {
    if (!_isAndroid) return false;
    if (irSamples.isEmpty) {
      ErrorLogger.log(
        'Cannot load an empty impulse response',
        category: 'AudioEffectsChannel',
      );
      return false;
    }
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'loadImpulseResponse',
        {'irSamples': irSamples},
      );
      // Older bridges return nothing on success; only an explicit false is a
      // failure signal.
      return result ?? true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to load impulse response',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  // --- STEREO BALANCE & MONO MIX ---

  Future<void> setStereoBalance(double balance) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setStereoBalance', {
            'balance': balance.clamp(-1.0, 1.0),
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set stereo balance ($balance)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setMonoMix(bool mono) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setMonoMix', {'mono': mono})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set mono mix ($mono)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- SINC RESAMPLER ---

  Future<void> setSincResamplerEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setSincResamplerEnabled', {
        'enabled': enabled,
      });
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set sinc resampler enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setSincResamplerRates(double inRate, double outRate) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setSincResamplerRates', {
            'inRate': inRate,
            'outRate': outRate,
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set sinc resampler rates ($inRate -> $outRate)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  /// Resampler quality: 0 = Fast (linear), 1 = Standard (16-tap),
  /// 2 = High (32-tap), 3 = Ultra (64-tap). Best-effort on Android only.
  Future<void> setSincResamplerQuality(int quality) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setSincResamplerQuality', {
        'quality': quality.clamp(0, 3),
      });
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set sinc resampler quality ($quality)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- PHASE 1 DSP EXPANSION: HARMONIC SATURATION / EXCITER ---

  Future<void> setSaturationEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setSaturationEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set saturation enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setSaturationParams(
    double drive,
    double mix,
    double tilt, {
    int mode = 0,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setSaturationParams', {
            'drive': drive,
            'mix': mix,
            'tilt': tilt,
            'mode': mode,
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set saturation params',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- PHASE 1 DSP EXPANSION: STEREO WIDTH (MID/SIDE) ---

  Future<void> setStereoWidthEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setStereoWidthEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set stereo width enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setStereoWidthParams(
    double width, {
    bool multiband = false,
    double lowWidth = 1.0,
    double midWidth = 1.0,
    double highWidth = 1.0,
    double lowCrossoverHz = 160.0,
    double highCrossoverHz = 2500.0,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setStereoWidthParams', {
            'width': width,
            'multiband': multiband,
            'lowWidth': lowWidth,
            'midWidth': midWidth,
            'highWidth': highWidth,
            'lowCrossoverHz': lowCrossoverHz,
            'highCrossoverHz': highCrossoverHz,
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set stereo width ($width)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- PHASE 1 DSP EXPANSION: LOUDNESS CONTOUR (FLETCHER-MUNSON) ---

  Future<void> setLoudnessContourEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setLoudnessContourEnabled', {
        'enabled': enabled,
      });
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set loudness contour enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setLoudnessContourParams(
    double intensity,
    double volumeLinear,
  ) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setLoudnessContourParams', {
            'intensity': intensity,
            'volumeLinear': volumeLinear,
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set loudness contour params',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- PHASE 1 DSP EXPANSION: SUBWOOFER / LFE CROSSOVER ---

  Future<void> setSubCrossoverEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setSubCrossoverEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set sub crossover enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setSubCrossoverParams(
    double cornerHz,
    double slopeDbPerOct,
    double subGain, {
    bool bassMono = false,
    bool antiPop = true,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setSubCrossoverParams', {
            'cornerHz': cornerHz,
            'slopeDbPerOct': slopeDbPerOct,
            'subGain': subGain,
            'bassMono': bassMono,
            'antiPop': antiPop,
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set sub crossover params',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- PHASE 1 DSP EXPANSION: DYNAMIC EQ ---

  Future<void> setDynamicEqEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setDynamicEqEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set dynamic EQ enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setDynamicEqBandCount(int count) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setDynamicEqBandCount', {'count': count})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set dynamic EQ band count ($count)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
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
    double maxBoostDb = 12.0,
    int mode = 0,
    int filterType = 0,
    bool enabled = true,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setDynamicEqBand', {
            'index': index,
            'frequency': frequency,
            'q': q,
            'thresholdDb': thresholdDb,
            'ratio': ratio,
            'attackMs': attackMs,
            'releaseMs': releaseMs,
            'maxCutDb': maxCutDb,
            'maxBoostDb': maxBoostDb,
            'mode': mode,
            'filterType': filterType,
            'enabled': enabled,
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set dynamic EQ band $index',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- NATIVE C++ 4-BAND MULTIBAND COMPRESSOR ---

  Future<void> setMultibandCompressorEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setMultibandCompressorEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set multiband compressor enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setMultibandCompressorBand(
    int bandIndex, {
    required double thresholdDb,
    required double ratio,
    required double attackMs,
    required double releaseMs,
    required double kneeDb,
    required double makeupGainDb,
    bool enabled = true,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setMultibandCompressorBand', {
            'bandIndex': bandIndex,
            'thresholdDb': thresholdDb,
            'ratio': ratio,
            'attackMs': attackMs,
            'releaseMs': releaseMs,
            'kneeDb': kneeDb,
            'makeupGainDb': makeupGainDb,
            'enabled': enabled,
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set multiband compressor band $bandIndex',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setMultibandCompressorCrossovers({
    required double f0,
    required double f1,
    required double f2,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setMultibandCompressorCrossovers', {
            'f0': f0,
            'f1': f1,
            'f2': f2,
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set multiband compressor crossovers',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setDynamicBassParams({
    required bool enabled,
    required double strength,
    required int xLow,
    required int xHigh,
    required int yLow,
    required int yHigh,
    required double sideGainLow,
    required double sideGainHigh,
    required int devicePreset,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setDynamicBassParams', {
            'enabled': enabled,
            'strength': strength,
            'xLow': xLow,
            'xHigh': xHigh,
            'yLow': yLow,
            'yHigh': yHigh,
            'sideGainLow': sideGainLow,
            'sideGainHigh': sideGainHigh,
            'devicePreset': devicePreset,
          })
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set dynamic bass params',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- DSD DECODING ---

  Future<List<double>?> decodeDsd(
    List<int> dsdL,
    List<int> dsdR, {
    int dsdRate = 64,
    int targetSampleRate = 176400,
    // 0 = MSB first (DSF), 1 = LSB first (DFF) - must match eq_jni_bridge.cpp
    int bitOrder = 0,
  }) async {
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
      ErrorLogger.log(
        'Failed to decode DSD stream',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
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
      ErrorLogger.log(
        'setBandSolo failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setBandMute(int index, bool mute) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setBandMute', {'index': index, 'mute': mute})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log(
        'setBandMute failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setReverbParams({
    double predelayMs = 0.0,
    double damping = 0.5,
    double crossChannel = 0.0,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setReverbParams', {
            'predelayMs': predelayMs,
            'damping': damping,
            'crossChannel': crossChannel,
          })
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log(
        'setReverbParams failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setReverbCrossChannel(double crossChannel) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setReverbCrossChannel', {'crossChannel': crossChannel})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log(
        'setReverbCrossChannel failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> setDspPreference(String preference) async {
    if (!_isAndroid) return;
    // Called during settings load, which can run before the native effects
    // plugin has attached to the engine. Retry once after a short delay instead
    // of surfacing a startup TimeoutException crash report.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _channel
            .invokeMethod('setDspPreference', {'preference': preference})
            .timeout(Duration(seconds: attempt == 0 ? 2 : 4));
        return;
      } catch (e, st) {
        if (attempt == 1) {
          ErrorLogger.log(
            'setDspPreference failed',
            error: e,
            stackTrace: st,
            category: 'AudioEffectsChannel',
          );
        } else {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    }
  }

  // --- DITHER (TPDF) + BIT-PERFECT SNAPSHOT ---

  /// Returns true when the native dither stage accepted the params. Dither is
  /// intentionally skipped on BT routes by the native side (still "applied").
  /// Returns false off Android, where there is no native DSP stage.
  ///
  /// This is the single reachable dither entry point: it carries the enable
  /// flag, target depth and route together. The old enable-only
  /// `setDitherEnabled` wrapper was unreachable and has been removed.
  Future<bool> setDitherParams({
    required bool enabled,
    required int targetBitDepth,
    required bool isBluetooth,
  }) async {
    if (!_isAndroid) return false;
    try {
      final bool? applied = await _channel
          .invokeMethod<bool>('setDitherParams', {
            'enabled': enabled,
            'targetBitDepth': targetBitDepth,
            'isBluetooth': isBluetooth,
          })
          .timeout(const Duration(seconds: 2));
      return applied ?? true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set dither params',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  /// Mirrors bypass into the native snapshot (plus optional DoP flag).
  Future<void> setBitPerfectParams({
    required bool enabled,
    required bool isDop,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setBitPerfectParams', {
            'enabled': enabled,
            'isDop': isDop,
          })
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set bit-perfect params',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<void> releaseEffects() async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('releaseEffects')
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to release audio effects',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  /// Call whenever audio format changes or on session resume/track switch.
  /// Forces native DSP generation bump, re-calculates all filter coefficients for [sampleRate],
  /// and flushes stale audio filter state.
  Future<void> resyncForTrack(double sampleRate, {int channels = 2}) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('resyncForTrack', {
            'sampleRate': sampleRate,
            'channels': channels,
          })
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to resync DSP for track ($sampleRate Hz)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  /// Configures native synthetic IR LRU cache budget (16MB on low RAM devices, 64MB default).
  Future<void> setCacheBudgetBytes(int budgetBytes) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setCacheBudgetBytes', {'budgetBytes': budgetBytes})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log(
        'setCacheBudgetBytes failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  /// Gets the current bitmask of auto-degraded stages from the native DSP engine.
  Future<int> getAutoDegradedStages() async {
    if (!_isAndroid) return 0;
    try {
      final dynamic res = await _channel
          .invokeMethod<dynamic>('getAutoDegradedStages')
          .timeout(const Duration(seconds: 2));
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
  Stream<int> get onAutoDegradedSessionStarted =>
      _autoDegradeStreamController.stream;

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
      return await _channel
          .invokeMapMethod<String, dynamic>('getDspDebugStatus')
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  /// Retrieves a structured DSP Debug Report of all active stages and engines.
  Future<DspDebugReport?> getDspDebugReport() async {
    final status = await getDspDebugStatus();
    if (status == null) return null;
    try {
      return DspDebugReport.fromMap(status);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to parse DspDebugReport',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return null;
    }
  }

  // --- BS2B CROSSFEED MODE ---
  Future<void> setCrossfeedMode(int mode) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setCrossfeedMode', {'mode': mode})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set crossfeed mode ($mode)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- MULTIBAND SATURATION ---
  Future<void> setSaturationMultiband(bool multiband) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setSaturationMultiband', {'multiband': multiband})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set saturation multiband ($multiband)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  // --- VIPER-DDC ---
  Future<void> setViperDdcEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setViperDdcEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set ViPER-DDC enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<bool> loadViperDdc({
    required String ddcContent,
    required String profileName,
  }) async {
    if (!_isAndroid) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>('loadViperDdc', {
        'ddcContent': ddcContent,
        'profileName': profileName,
      });
      return ok ?? false;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to load ViPER-DDC ($profileName)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  // --- ARBITRARY RESPONSE EQUALIZER ---
  Future<void> setArbitraryEqEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setArbitraryEqEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set Arbitrary EQ enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<bool> loadArbitraryEq({
    required String eqString,
    bool linearPhase = false,
  }) async {
    if (!_isAndroid) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>('loadArbitraryEq', {
        'eqString': eqString,
        'linearPhase': linearPhase,
      });
      return ok ?? false;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to load Arbitrary EQ',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  // --- LIVE PROGRAMMABLE DSP ---
  Future<void> setLiveProgEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setLiveProgEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set LiveProg enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  Future<String> loadLiveProgCode(String code) async {
    if (!_isAndroid) return 'Unsupported platform';
    try {
      final String? status = await _channel.invokeMethod<String>(
        'loadLiveProgCode',
        {'code': code},
      );
      return status ?? 'OK';
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to load LiveProg code',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return e.toString();
    }
  }

  Future<void> setLiveProgSlider(int index, double value) async {
    if (!_isAndroid) return;
    try {
      await _channel
          .invokeMethod('setLiveProgSlider', {'index': index, 'value': value})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set LiveProg slider $index',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }
}
