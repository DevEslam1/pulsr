part of 'audio_effects_channel.dart';

// Remaster/decoder-probe bridge methods extracted from AudioEffectsChannel.
// Private fields stay on the channel; a part shares this library's scope.

extension AudioEffectsRemasterProbeOps on AudioEffectsChannel {
  // --- REMASTER: OUTPUT OVERSAMPLING & RECONSTRUCTION FILTERS ---

  /// Probes the platform MediaCodec list for a decoder that advertises [mime].
  /// Returns false off Android and on any bridge failure: unknown support must
  /// never be reported as playable.
  Future<bool> probeAudioDecoder(String mime, {int sampleRate = 0}) async {
    // iOS AVFoundation decodes ALAC natively; the MediaCodec path is Android.
    if (!_isAndroid) return PlatformCapabilities.isIOS;
    try {
      final result = await AudioEffectsChannel._channel
          .invokeMethod<bool>('probeAudioDecoder', {
            'mime': mime,
            if (sampleRate > 0) 'sampleRate': sampleRate,
          })
          .timeout(const Duration(seconds: 2));
      return result ?? false;
    } catch (e, st) {
      ErrorLogger.log('probeAudioDecoder($mime) failed',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
      return false;
    }
  }
}

extension AudioEffectsPcmToDsdOps on AudioEffectsChannel {
  // --- REMASTER: REAL-TIME PCM -> DSD MODULATOR ---

  Future<bool> setPcmToDsdEnabled(bool enabled) async {
    if (!_isAndroid) return false;
    try {
      await _invokeNativeSetter('setPcmToDsdEnabled', {
        'enabled': enabled,
      });
      _cachedPcmToDsdEnabled = enabled;
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isPcmToDsdEnabled() async {
    if (!_isAndroid) return _cachedPcmToDsdEnabled;
    try {
      final enabled = await AudioEffectsChannel._channel
          .invokeMethod<bool>('isPcmToDsdEnabled')
          .timeout(const Duration(seconds: 2));
      final res = enabled ?? false;
      _cachedPcmToDsdEnabled = res;
      return res;
    } catch (e, st) {
      ErrorLogger.log('isPcmToDsdEnabled failed',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
      return _cachedPcmToDsdEnabled;
    }
  }

  /// DSD multiple: 64 (DSD64), 128 (DSD128), 256 (DSD256).
  Future<bool> setPcmToDsdRate(int rate) async {
    final valid = (rate == 128 || rate == 256) ? rate : 64;
    if (!_isAndroid) return false;
    try {
      await _invokeNativeSetter('setPcmToDsdRate', {
        'rate': valid,
      });
      _cachedPcmToDsdRate = valid;
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<int> getPcmToDsdRate() async {
    if (!_isAndroid) return _cachedPcmToDsdRate;
    try {
      final rate = await AudioEffectsChannel._channel
          .invokeMethod<int>('getPcmToDsdRate')
          .timeout(const Duration(seconds: 2));
      final res = (rate == 128 || rate == 256) ? rate! : 64;
      _cachedPcmToDsdRate = res;
      return res;
    } catch (e, st) {
      ErrorLogger.log('getPcmToDsdRate failed',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
      return _cachedPcmToDsdRate;
    }
  }

  /// SDM loop order: 1..5.
  Future<bool> setPcmToDsdOrder(int order) async {
    final valid = order.clamp(1, 5);
    if (!_isAndroid) return false;
    try {
      await _invokeNativeSetter('setPcmToDsdOrder', {
        'order': valid,
      });
      _cachedPcmToDsdOrder = valid;
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<int> getPcmToDsdOrder() async {
    if (!_isAndroid) return _cachedPcmToDsdOrder;
    try {
      final order = await AudioEffectsChannel._channel
          .invokeMethod<int>('getPcmToDsdOrder')
          .timeout(const Duration(seconds: 2));
      final res = order?.clamp(1, 5) ?? 5;
      _cachedPcmToDsdOrder = res;
      return res;
    } catch (e, st) {
      ErrorLogger.log('getPcmToDsdOrder failed',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
      return _cachedPcmToDsdOrder;
    }
  }
}
