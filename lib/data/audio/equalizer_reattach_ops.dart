// lib/data/audio/equalizer_reattach_ops.dart
part of 'equalizer_manager.dart';

/// Session reattach and full native DSP state push for [EqualizerManager].
/// Extracted from the core file to stay below the fat-file ratchet cap; shares
/// the library via part of so private state remains directly accessible.
extension EqualizerReattachOps on EqualizerManager {
  Future<void> _runReattach() async {
    final sessionId = _pendingReattachSessionId;
    _pendingReattachSessionId = null;
    // null = a newer queued call already applied the collapsed newest id.
    if (sessionId == null) return;
    if (sessionId <= 0) {
      ErrorLogger.log(
        'Skipping reattach: invalid session ID $sessionId',
        category: 'EqualizerManager',
      );
      return;
    }
    // FIX M-11: ExoPlayer can reuse same session ID after underrun/gapless;
    // always reapply to ensure effects survive AudioTrack recreation.
    // We still gate on an identical full-state fingerprint below if needed.
    try {
      ErrorLogger.log(
        'Reattaching effects to session $sessionId',
        category: 'EqualizerManager',
      );
      await _effectsChannel.releaseEffects();
      ErrorLogger.log('Released old effects', category: 'EqualizerManager');
      await _effectsChannel.setAudioSessionId(sessionId);
      ErrorLogger.log(
        'Set audio session ID: $sessionId',
        category: 'EqualizerManager',
      );
      await _pushFullEffectState();
      ErrorLogger.log(
        'Pushed full effect state to session $sessionId',
        category: 'EqualizerManager',
      );
      // Mark applied only on success so a later same-id event can retry a
      // failed attach (e.g. channel timeout while the HAL was still settling).
      _lastAppliedSessionId = sessionId;
      ErrorLogger.log(
        'Successfully reattached to session $sessionId',
        category: 'EqualizerManager',
      );
    } catch (e, st) {
      DspReliabilityTracker.instance.recordSessionReattachFailure(e);
      ErrorLogger.log(
        'reapplyToSession($sessionId) failed',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
      _lastAppliedSessionId = null; // Reset so next attempt will retry
    }
  }

  /// Pushes every active effect (enabled flags, band count, bands, presets)
  /// to the native stack. Assumes the session is already established — either
  /// after [_runReattach] recreated it or after a route change.
  Future<void> _pushFullEffectState() async {
    // Always initialize the baseline EQ effect chain so AudioEffect instances
    // are created and attached to the session. This ensures isSessionAttached=true.
    // The EQ will be enabled/disabled based on actual state.
    final futures = <Future<void>>[];

    // Routing truth first: preference + bypass + dither must precede stage
    // pushes, otherwise a reattach re-enables stages that bypass should mute.
    try {
      await _effectsChannel.setDspPreference(dspPreference);
      await _effectsChannel.setBypassDspForBitPerfect(isBitPerfectBypass);
      await _effectsChannel.setLowPowerRoute(isLowPowerRouteEnabled);
      await _effectsChannel.setDitherParams(
        enabled: isDitherEnabled,
        targetBitDepth: ditherTargetBitDepth,
        isBluetooth: isBluetoothRoute,
        allowBluetoothDither: isBluetoothDitherEnabled,
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to push routing truth (preference/bypass/dither)',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }

    if (isBitPerfectBypass) {
      // In Bit-Perfect bypass mode, all DSP stages must remain completely disabled.
      // Skipping the remaining stage pushes avoids wasting JNI roundtrips and prevents
      // transient leakage before the native bypass gate takes full effect.
      return;
    }

    // Initialize EQ chain with current band configuration and enable state
    try {
      final freqs = activeFrequencies;
      await _effectsChannel.setNativeEqBandCount(freqs.length);

      final effectiveEqEnabled = isEnabled && !isFirCorrectionActive;
      if (effectiveEqEnabled) {
        await _applyCurrentPresetCore();
      }

      await _effectsChannel.setEqEnabled(effectiveEqEnabled);
      await _effectsChannel.setNativeEqEnabled(effectiveEqEnabled);
      for (final idx in soloedBands) {
        if (idx >= 0 && idx < freqs.length) {
          futures.add(_effectsChannel.setBandSolo(idx, true));
        }
      }
      for (final idx in mutedBands) {
        if (idx >= 0 && idx < freqs.length) {
          futures.add(_effectsChannel.setBandMute(idx, true));
        }
      }
      // Native eqPreampDb resets to 0 whenever the plugin is re-created.
      // Restore the persisted manual preamp, falling back to the headphone
      // profile preamp only when no manual value was stored.
      final storedPreamp = preampDb;
      final effectivePreamp = storedPreamp != 0.0
          ? storedPreamp
          : (selectedHeadphoneProfile?.preampGain ??
              (autoPreampEnabled && !isFirCorrectionActive
                  ? currentPreset.recommendedPreampDb
                  : 0.0));
      await _effectsChannel.setEqPreamp(effectivePreamp);
      if (storedPreamp == 0.0) preampDb = effectivePreamp;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to initialize EQ chain',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
      // Continue even if EQ init fails - other effects may still work
    }

    if (currentPreset.bassBoost > 0) {
      // Direct channel call to avoid _debouncedSavePreferences thrash on hot path (track change)
      final milliBels =
          (currentPreset.bassBoost.clamp(0.0, 1.0) * 1000).round();
      futures.add(_effectsChannel.setBassBoost(milliBels));
    }
    if (volumeBoost > 0) {
      final milliBels = (volumeBoost.clamp(0.0, 1.0) * 1000).round();
      futures.add(_effectsChannel.setVolumeBoost(milliBels));
    }
    if (isVirtualizerEnabled && _effectsChannel.isVirtualizerSupported) {
      // FIX M-9: skip no-op IPC when virtualizer is not supported
      futures.add(_effectsChannel.setVirtualizerEnabled(true));
      futures.add(_effectsChannel.setVirtualizerStrength(virtualizerStrength));
    }
    if (isSpatializerEnabled) {
      // Guarded fallback: on devices without a Spatializer API this also
      // re-asserts the virtualizer, so reattach matches the public setter.
      futures.add(_applySpatializerWithFallback(true));
    }
    if (isCrossfeedEnabled && !isHrtfEnabled) {
      futures.add(() async {
        await _effectsChannel.setCrossfeedParams(
          crossfeedDelayUs,
          crossfeedFeedDb,
          fcut: crossfeedFcut,
        );
        await _effectsChannel.setCrossfeedMode(crossfeedMode);
        await _effectsChannel.setCrossfeedEnabled(true);
      }());
    } else {
      futures.add(_effectsChannel.setCrossfeedEnabled(false));
    }
    if (isHrtfEnabled) {
      futures.add(() async {
        if (hrtfSofaPath != null && hrtfSofaPath!.isNotEmpty) {
          await _effectsChannel.loadHrtfSofa(hrtfSofaPath!);
        }
        await _effectsChannel.setHrtfAzimuth(hrtfAzimuth);
        await _effectsChannel.setHrtfElevation(hrtfElevation);
        await _effectsChannel.setHrtfBinauralEnabled(true);
      }());
    } else {
      futures.add(_effectsChannel.setHrtfBinauralEnabled(false));
    }
    if (isLimiterEnabled) {
      futures.add(() async {
        await _effectsChannel.setLimiterParams(
          limiterLookaheadMs,
          limiterThresholdDb,
          limiterReleaseMs,
          ratio: _hasStoredCompressorParams ? compressorRatio : null,
          attackMs: _hasStoredCompressorParams ? compressorAttackMs : null,
          makeupGainDb:
              _hasStoredCompressorParams ? compressorMakeupGainDb : null,
        );
        await _effectsChannel.setLimiterEnabled(true);
      }());
    }
    if (isReverbEnabled) {
      futures.add(() async {
        if (reverbPreset == ReverbPreset.custom.wireValue &&
            customImpulseResponse.isNotEmpty) {
          await _effectsChannel.loadImpulseResponse(customImpulseResponse);
        } else {
          await _effectsChannel.setReverbPreset(reverbPreset);
        }
        await _effectsChannel.setReverbWetDry(reverbWetDry);
        await _effectsChannel.setReverbParams(
          predelayMs: reverbPredelayMs,
          damping: reverbDamping,
          crossChannel: reverbCrossChannel,
        );
        await _effectsChannel.setReverbEnabled(true);
      }());
    }
    if (stereoBalance != 0.0) {
      futures.add(_effectsChannel.setStereoBalance(stereoBalance));
    }
    if (monoMix) futures.add(_effectsChannel.setMonoMix(true));
    // Re-assert the resampler so a user-disabled resampler stays disabled
    // after a reattach/route change instead of silently reverting to ON.
    futures.add(
      _effectsChannel.setSincResamplerEnabled(isSincResamplerEnabled),
    );
    if (isSaturationEnabled) {
      futures.add(() async {
        await _effectsChannel.setSaturationParams(
          saturationDrive,
          saturationMix,
          saturationTilt,
          mode: saturationMode,
          multiband: saturationMultiband,
        );
        await _effectsChannel.setSaturationMultiband(saturationMultiband);
        await _effectsChannel.setSaturationEnabled(true);
      }());
    }
    if (isStereoWidthEnabled) {
      futures.add(() async {
        await _effectsChannel.setStereoWidthParams(
          stereoWidth,
          multiband: stereoWidthMultiband,
          lowWidth: stereoWidthLow,
          midWidth: stereoWidthMid,
          highWidth: stereoWidthHigh,
          lowCrossoverHz: stereoWidthLowCrossoverHz,
          highCrossoverHz: stereoWidthHighCrossoverHz,
        );
        await _effectsChannel.setStereoWidthEnabled(true);
      }());
    }
    if (isLoudnessContourEnabled) {
      futures.add(() async {
        await _effectsChannel.setLoudnessContourParams(
          loudnessContourIntensity,
          loudnessVolumeLinear,
        );
        await _effectsChannel.setLoudnessContourEnabled(true);
      }());
    }
    if (isSubCrossoverEnabled) {
      futures.add(() async {
        await _effectsChannel.setSubCrossoverParams(
          subCrossoverCornerHz,
          subCrossoverSlopeDbPerOct,
          subCrossoverGain,
          bassMono: subCrossoverBassMono,
          antiPop: subCrossoverAntiPop,
        );
        await _effectsChannel.setSubCrossoverEnabled(true);
      }());
    }
    if (isLfeCrossoverEnabled) {
      futures.add(() async {
        await _effectsChannel.setLfeCrossoverParams(
          crossoverHz: lfeCrossoverHz,
          lfeLowPassHz: lfeLowPassHz,
          slopeDbPerOct: lfeSlopeDbPerOct,
          lfeGainDb: lfeGainDb,
          lfeChannelIndex: lfeChannelIndex,
          redirectBass: lfeRedirectBass,
        );
        await _effectsChannel.setLfeCrossoverEnabled(true);
      }());
    }
    // Push the stored per-channel values even while the stage is disabled:
    // otherwise a cold start with the manager off leaves the engine at zero,
    // and re-enabling later would silently lose every trim/delay.
    futures.add(() async {
      for (int ch = 0; ch < 8; ++ch) {
        await _effectsChannel.setChannelManagerChannel(
          ch,
          trimDb: channelManagerTrimDb[ch],
          delayMs: channelManagerDelayMs[ch],
        );
      }
      await _effectsChannel.setChannelManagerEnabled(
        isChannelManagerEnabled,
        channelCount: channelManagerChannelCount,
      );
    }());
    if (isDynamicEqEnabled) {
      futures.add(() async {
        await _pushDynamicEqConfig();
        await _effectsChannel.setDynamicEqEnabled(true);
      }());
    }
    if (isMultibandCompressorEnabled) {
      futures.add(() async {
        await _pushMultibandCompressorConfig();
        await _effectsChannel.setMultibandCompressorEnabled(true);
      }());
    }
    if (isDynamicBassEnabled) {
      futures.add(
        _effectsChannel.setDynamicBassParams(
          enabled: true,
          strength: dynamicBassStrength,
          xLow: dynamicBassXLow,
          xHigh: dynamicBassXHigh,
          yLow: dynamicBassYLow,
          yHigh: dynamicBassYHigh,
          sideGainLow: dynamicBassSideGainLow,
          sideGainHigh: dynamicBassSideGainHigh,
          devicePreset: dynamicBassPreset,
        ),
      );
    }
    if (isViperDdcEnabled) {
      futures.add(() async {
        if (viperDdcContent.isNotEmpty) {
          await _effectsChannel.loadViperDdc(
            ddcContent: viperDdcContent,
            profileName: viperDdcProfileName,
          );
        }
        await _effectsChannel.setViperDdcEnabled(true);
      }());
    }
    if (isArbitraryEqEnabled && arbitraryEqString.isNotEmpty) {
      futures.add(() async {
        await _effectsChannel.loadArbitraryEq(
          eqString: arbitraryEqString,
          linearPhase: arbitraryEqLinearPhase,
        );
        await _effectsChannel.setArbitraryEqEnabled(true);
      }());
    }
    if (isLiveProgEnabled && liveProgCode.isNotEmpty) {
      futures.add(() async {
        await _effectsChannel.loadLiveProgCode(liveProgCode);
        for (final entry in liveProgSliders.entries) {
          await _effectsChannel.setLiveProgSlider(entry.key, entry.value);
        }
        await _effectsChannel.setLiveProgEnabled(true);
      }());
    }

    // Partial-failure tolerance: one failing effect must not abort the rest.
    // FIX-H02: Wrap Future.wait in try/catch without rethrowing so one failure does not abort other effects
    if (futures.isNotEmpty) {
      try {
        await Future.wait(
          futures.map(
            (f) => f.then<void>((_) {}).catchError((Object e) {
              ErrorLogger.log(
                'Effect push failed (continuing with remaining effects)',
                error: e,
                category: 'EqualizerManager',
              );
            }),
          ),
          eagerError: false,
        );
      } catch (e, st) {
        ErrorLogger.log(
          'Future.wait failed while reapplying effects',
          error: e,
          stackTrace: st,
          category: 'EqualizerManager',
        );
      }
    }

    // Dynamics last: recalculateActiveStages may disable the OEM engine.
    if (isDynamicsEnabled && !_isDynamicsBypassed) {
      await _effectsChannel.setDynamicsPreset(dynamicsPreset, true);
    }

    if (isReverbEnabled || isViperDdcEnabled || isArbitraryEqEnabled) {
      await _warmupScheduler.warmup();
    }

    // Readback verification to catch parameter drift
    try {
      final verified = await _effectsChannel.verifyState();
      if (verified != null) {
        final expectedEqEnabled = isEnabled && !isFirCorrectionActive;
        bool matches = true;
        if (verified.containsKey('eqEnabled') &&
            verified['eqEnabled'] != expectedEqEnabled) {
          matches = false;
        }
        if (verified.containsKey('preampDb') && verified['preampDb'] is num) {
          final diff =
              ((verified['preampDb'] as num).toDouble() - preampDb).abs();
          if (diff > 1e-4) matches = false;
        }
        if (!matches) {
          // Re-push once
          await _effectsChannel.setEqEnabled(expectedEqEnabled);
          await _effectsChannel.setEqPreamp(preampDb);
          final recheck = await _effectsChannel.verifyState();
          if (recheck != null) {
            final recheckPreamp =
                (recheck['preampDb'] as num?)?.toDouble() ?? preampDb;
            if ((recheckPreamp - preampDb).abs() > 1e-4 ||
                recheck['eqEnabled'] != expectedEqEnabled) {
              ErrorLogger.log(
                'DSP parameter readback verification mismatch after retry',
                category: 'EqualizerManager',
              );
            }
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log(
        'DSP readback verification error',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }

    unawaited(_effectsChannel.getAutoDegradedStages());
  }
}
