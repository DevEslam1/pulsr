// lib/data/audio/equalizer_multichannel_ops.dart
part of 'equalizer_manager.dart';

/// Channel layout / ChannelManager / LFE operations, extracted from the
/// ratcheted manager core. Same library via `part of`.
extension EqualizerMultichannelOps on EqualizerManager {
  AudioChannelLayout? get channelLayout =>
      AudioChannelLayout.fromChannelCount(channelManagerChannelCount);

  Future<void> setChannelManagerEnabled(bool enabled, {int? channelCount}) async {
    final prevEnabled = isChannelManagerEnabled;
    final prevCount = channelManagerChannelCount;
    final targetCount = (channelCount ?? prevCount).clamp(2, 8);
    try {
      if (PlatformCapabilities.isAndroid) {
        await _effectsChannel.setChannelManagerEnabled(enabled, channelCount: targetCount);
        if (enabled) {
          // Re-enabling must not lose the trims/delays the UI (and prefs)
          // still hold: the native stage was disabled during restore, so push
          // all eight values again.
          for (int ch = 0; ch < 8; ++ch) {
            await _effectsChannel.setChannelManagerChannel(
              ch,
              trimDb: channelManagerTrimDb[ch],
              delayMs: channelManagerDelayMs[ch],
            );
          }
        }
      }
      isChannelManagerEnabled = enabled;
      channelManagerChannelCount = targetCount;
      _debouncedSavePreferences();
      _syncPipeline();
    } catch (e, st) {
      isChannelManagerEnabled = prevEnabled;
      channelManagerChannelCount = prevCount;
      ErrorLogger.log('Failed to set channel manager enabled',
          error: e, stackTrace: st, category: 'EqualizerManager');
      rethrow;
    }
  }

  /// Applies a speaker layout atomically: channel count, LFE index and the LFE
  /// stage enable are one decision. On 3.0/4.0 layouts the LFE stage is always
  /// disabled (there is no LFE channel); on 5.1/7.1 it is index 3.
  Future<void> setChannelLayout(
    AudioChannelLayout layout, {
    bool? enabled,
  }) async {
    if (!AudioChannelLayout.offered.contains(layout)) {
      throw ArgumentError.value(layout, 'layout', 'Unsupported layout');
    }
    final prevEnabled = isChannelManagerEnabled;
    final prevCount = channelManagerChannelCount;
    final prevLfeEnabled = isLfeCrossoverEnabled;
    final prevLfeIndex = lfeChannelIndex;
    final targetEnabled = enabled ?? isChannelManagerEnabled;
    final targetLfeEnabled = layout.hasLfe ? isLfeCrossoverEnabled : false;
    final targetLfeIndex = layout.lfeIndex < 0 ? 0 : layout.lfeIndex;
    try {
      if (PlatformCapabilities.isAndroid) {
        await _effectsChannel.setChannelManagerEnabled(
          targetEnabled,
          channelCount: layout.channelCount,
        );
        for (int ch = 0; ch < 8; ++ch) {
          await _effectsChannel.setChannelManagerChannel(
            ch,
            trimDb: channelManagerTrimDb[ch],
            delayMs: channelManagerDelayMs[ch],
          );
        }
        await _effectsChannel.setLfeCrossoverParams(
          crossoverHz: lfeCrossoverHz,
          lfeLowPassHz: lfeLowPassHz,
          slopeDbPerOct: lfeSlopeDbPerOct,
          lfeGainDb: lfeGainDb,
          lfeChannelIndex: targetLfeIndex,
          redirectBass: lfeRedirectBass,
        );
        await _effectsChannel.setLfeCrossoverEnabled(targetLfeEnabled);
      }
      isChannelManagerEnabled = targetEnabled;
      channelManagerChannelCount = layout.channelCount;
      lfeChannelIndex = targetLfeIndex;
      isLfeCrossoverEnabled = targetLfeEnabled;
      _debouncedSavePreferences();
      _syncPipeline();
    } catch (e, st) {
      isChannelManagerEnabled = prevEnabled;
      channelManagerChannelCount = prevCount;
      lfeChannelIndex = prevLfeIndex;
      isLfeCrossoverEnabled = prevLfeEnabled;
      ErrorLogger.log('Failed to set channel layout',
          error: e, stackTrace: st, category: 'EqualizerManager');
      rethrow;
    }
  }

  Future<void> setChannelManagerChannel(
    int channel, {
    double? trimDb,
    double? delayMs,
  }) async {
    if (channel < 0 || channel >= 8) return;
    final prevTrim = channelManagerTrimDb[channel];
    final prevDelay = channelManagerDelayMs[channel];
    final targetTrim = trimDb != null ? DspParamRanges.channelManagerTrimDb.clamp(trimDb) : prevTrim;
    final targetDelay = delayMs != null ? DspParamRanges.channelManagerDelayMs.clamp(delayMs) : prevDelay;
    try {
      if (PlatformCapabilities.isAndroid) {
        await _effectsChannel.setChannelManagerChannel(channel, trimDb: targetTrim, delayMs: targetDelay);
      }
      channelManagerTrimDb[channel] = targetTrim;
      channelManagerDelayMs[channel] = targetDelay;
      _debouncedSavePreferences();
    } catch (e, st) {
      channelManagerTrimDb[channel] = prevTrim;
      channelManagerDelayMs[channel] = prevDelay;
      ErrorLogger.log('Failed to set channel manager channel',
          error: e, stackTrace: st, category: 'EqualizerManager');
      rethrow;
    }
  }

  // --- MULTICHANNEL LFE CROSSOVER ---

  Future<void> setLfeCrossover(
    bool enabled, {
    double? crossoverHz,
    double? lfeLowPassHz,
    double? slopeDbPerOct,
    double? lfeGainDb,
    int? lfeChannelIndex,
    bool? redirectBass,
  }) async {
    final prevEnabled = isLfeCrossoverEnabled;
    final prevCrossover = lfeCrossoverHz;
    final prevLp = this.lfeLowPassHz;
    final prevSlope = lfeSlopeDbPerOct;
    final prevGain = this.lfeGainDb;
    final prevLfeCh = this.lfeChannelIndex;
    final prevRedirect = lfeRedirectBass;

    final targetCrossover = crossoverHz != null
        ? DspParamRanges.lfeCrossoverHz.clamp(crossoverHz)
        : prevCrossover;
    final targetLp = lfeLowPassHz != null
        ? DspParamRanges.lfeLowPassHz.clamp(lfeLowPassHz)
        : prevLp;
    final targetSlope = slopeDbPerOct != null
        ? (slopeDbPerOct < 18.0 ? 12.0 : 24.0)
        : prevSlope;
    final targetGain = lfeGainDb != null
        ? DspParamRanges.lfeGainDb.clamp(lfeGainDb)
        : prevGain;
    final layout = channelLayout;
    final noLfeLayout = layout != null && !layout.hasLfe;
    final targetLfeCh = (lfeChannelIndex ?? prevLfeCh).clamp(0, 7).toInt();
    final targetRedirect = redirectBass ?? prevRedirect;
    final effectiveEnabled = enabled && !noLfeLayout;

    try {
      if (PlatformCapabilities.isAndroid) {
        await _effectsChannel.setLfeCrossoverParams(
          crossoverHz: targetCrossover,
          lfeLowPassHz: targetLp,
          slopeDbPerOct: targetSlope,
          lfeGainDb: targetGain,
          lfeChannelIndex: targetLfeCh,
          redirectBass: targetRedirect,
        );
        await _effectsChannel.setLfeCrossoverEnabled(effectiveEnabled);
      }
      lfeCrossoverHz = targetCrossover;
      lfeLowPassHz = targetLp;
      lfeSlopeDbPerOct = targetSlope;
      lfeGainDb = targetGain;
      lfeChannelIndex = targetLfeCh;
      lfeRedirectBass = targetRedirect;
      isLfeCrossoverEnabled = effectiveEnabled;
      _debouncedSavePreferences();
      _syncPipeline();
    } catch (e, st) {
      lfeCrossoverHz = prevCrossover;
      lfeLowPassHz = prevLp;
      lfeSlopeDbPerOct = prevSlope;
      lfeGainDb = prevGain;
      lfeChannelIndex = prevLfeCh;
      lfeRedirectBass = prevRedirect;
      isLfeCrossoverEnabled = prevEnabled;
      ErrorLogger.log('Failed to set LFE crossover',
          error: e, stackTrace: st, category: 'EqualizerManager');
      rethrow;
    }
  }

}
