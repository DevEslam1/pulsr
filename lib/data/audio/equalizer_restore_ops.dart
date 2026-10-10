// lib/data/audio/equalizer_restore_ops.dart
part of 'equalizer_manager.dart';

/// Preference load/migration for [EqualizerManager]. Extracted from the class
/// (fat-file ratchet 01-4). Same library via `part of`, so private state stays
/// accessible and all `_restorePreferences()` call sites keep working.
extension EqualizerRestoreOps on EqualizerManager {
  Future<void> _restorePreferences() async {
    try {
      final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
      isEnabled = prefs.getBool(PrefsKeys.eqEnabled) ?? false;
      // Band-count migration: prefer the explicit count key; fall back to the
      // legacy boolean (true => 32) so existing installs keep their mode.
      final storedBandCount = prefs.getInt(PrefsKeys.eqBandCount);
      if (storedBandCount != null &&
          (storedBandCount == 10 ||
              storedBandCount == 32 ||
              storedBandCount == 64)) {
        eqBandCount = storedBandCount;
      } else if (prefs.getBool(PrefsKeys.eq32BandMode) ??
          (prefs.getBool('eq_32_band_mode') ?? false)) {
        eqBandCount = 32;
      } else {
        eqBandCount = 10;
      }
      final presetName = prefs.getString(PrefsKeys.eqPresetName) ?? 'Flat';
      final gainsJson = prefs.getString(PrefsKeys.eqGains);
      final bass = prefs.getDouble(PrefsKeys.eqBassBoost) ?? 0.0;
      volumeBoost = prefs.getDouble(PrefsKeys.eqVolumeBoost) ?? 0.0;

      final customFreqsJson = prefs.getString(PrefsKeys.eqCustomFrequencies);
      if (customFreqsJson != null) {
        try {
          final decodedFreqs = (json.decode(customFreqsJson) as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList();
          if (decodedFreqs.length == 10 &&
              decodedFreqs.every((f) => f.isFinite && f > 0)) {
            customFrequencies = decodedFreqs;
          }
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to decode custom EQ frequencies',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }
      final custom32Json = prefs.getString(PrefsKeys.eqCustom32Frequencies);
      if (custom32Json != null) {
        try {
          final decoded32 = (json.decode(custom32Json) as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList();
          if (decoded32.length == 32 &&
              decoded32.every((f) => f.isFinite && f > 0)) {
            custom32Frequencies = decoded32;
          }
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to decode custom 32-band EQ frequencies',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }
      final custom64Json = prefs.getString(PrefsKeys.eqCustom64Frequencies);
      if (custom64Json != null) {
        try {
          final decoded64 = (json.decode(custom64Json) as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList();
          if (decoded64.length == 64 &&
              decoded64.every((f) => f.isFinite && f > 0)) {
            custom64Frequencies = decoded64;
          }
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to decode custom 64-band EQ frequencies',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }

      final targetFreqs = activeFrequencies;
      List<double> gains = List<double>.filled(targetFreqs.length, 0.0);
      bool gainsLoaded = false;
      if (gainsJson != null) {
        try {
          final decoded = json.decode(gainsJson) as List<dynamic>;
          final parsedGains =
              decoded.map((e) => (e as num).toDouble()).toList();
          if (parsedGains.isNotEmpty) {
            gains = EqPreset.interpolateGains(
              parsedGains,
              targetFrequencies: targetFreqs,
            );
            gainsLoaded = gains.length == targetFreqs.length;
          }
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to decode equalizer gains from prefs',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }

      if (!gainsLoaded) {
        final match = EqPreset.defaultPresets.where(
          (p) => p.name == presetName,
        );
        if (match.isNotEmpty) {
          gains = EqPreset.interpolateGains(
            match.first.gains,
            targetFrequencies: targetFreqs,
          );
        } else {
          gains = List<double>.filled(targetFreqs.length, 0.0);
        }
      }

      currentPreset = EqPreset(name: presetName, gains: gains, bassBoost: bass);
      comparisonSlots[ComparisonSlot.slotA] = currentPreset;
      preampDb = DspParamRanges.preampDb
          .clampRaw(prefs.getDouble(PrefsKeys.eqPreamp) ?? 0.0);

      isVirtualizerEnabled =
          prefs.getBool(PrefsKeys.eqVirtualizerEnabled) ?? false;
      virtualizerStrength =
          prefs.getDouble(PrefsKeys.eqVirtualizerStrength) ?? 0.0;

      final dynPresetStr = prefs.getString(PrefsKeys.eqDynamicsPreset) ??
          DynamicsPreset.off.name;
      dynamicsPreset = DynamicsPreset.values.firstWhere(
        (d) => d.name == dynPresetStr,
        orElse: () => DynamicsPreset.off,
      );
      isDynamicsEnabled = prefs.getBool(PrefsKeys.eqDynamicsEnabled) ?? false;
      _isDynamicsBypassed =
          prefs.getBool(PrefsKeys.eqDynamicsBypassed) ?? false;

      isSpatializerEnabled =
          prefs.getBool(PrefsKeys.eqSpatializerEnabled) ?? false;

      isCrossfeedEnabled = prefs.getBool(PrefsKeys.crossfeedEnabled) ?? false;
      crossfeedDelayUs = prefs.getDouble(PrefsKeys.crossfeedDelayUs) ?? 350.0;
      crossfeedFeedDb = prefs.getDouble(PrefsKeys.crossfeedFeedDb) ?? -9.0;
      crossfeedMode = prefs.getInt(PrefsKeys.crossfeedMode) ?? 0;
      crossfeedFcut = prefs.getDouble(PrefsKeys.crossfeedFcut) ?? 650.0;

      isLimiterEnabled =
          prefs.getBool(PrefsKeys.lookaheadLimiterEnabled) ?? false;
      limiterThresholdDb =
          prefs.getDouble(PrefsKeys.lookaheadLimiterThresholdDb) ?? -0.2;
      limiterReleaseMs =
          prefs.getDouble(PrefsKeys.lookaheadLimiterReleaseMs) ?? 50.0;
      limiterLookaheadMs =
          prefs.getDouble(PrefsKeys.lookaheadLimiterLookaheadMs) ?? 3.0;
      compressorRatio = prefs.getDouble(PrefsKeys.compressorRatio) ?? 3.0;
      compressorAttackMs =
          prefs.getDouble(PrefsKeys.compressorAttackMs) ?? 15.0;
      compressorMakeupGainDb =
          prefs.getDouble(PrefsKeys.compressorMakeupGainDb) ?? 0.0;
      // Only forward compressor knobs to the HAL when the user actually saved
      // them: the native brickwall limiter defaults must not silently turn into
      // a 3:1 / 15 ms compressor for users who never opened the sheet.
      _hasStoredCompressorParams =
          prefs.containsKey(PrefsKeys.compressorRatio) ||
              prefs.containsKey(PrefsKeys.compressorAttackMs) ||
              prefs.containsKey(PrefsKeys.compressorMakeupGainDb);

      isReverbEnabled =
          prefs.getBool(PrefsKeys.convolutionReverbEnabled) ?? false;
      // A stored `custom` reverb is only valid if its impulse response can be
      // reloaded from the persisted WAV path. Re-apply it here; if reloading
      // fails (file gone/corrupt), fall back honestly to the default room
      // instead of leaving the UI claiming "Custom (Loaded)" with no IR.
      final storedReverb = ReverbPreset.fromWireValue(
          prefs.getInt(PrefsKeys.convolutionReverbPreset) ??
              ReverbPreset.studio.wireValue);
      if (storedReverb == ReverbPreset.custom) {
        final irPath = prefs.getString(PrefsKeys.customReverbIrPath);
        var customIrRestored = false;
        if (irPath != null && irPath.isNotEmpty) {
          try {
            final samples = await IrFileParser.parseWavFile(File(irPath));
            if (samples.isNotEmpty &&
                await _effectsChannel.loadImpulseResponse(samples)) {
              reverbPreset = ReverbPreset.custom.wireValue;
              // _pushFullEffectState re-loads the IR from this field; it was
              // left empty, so a custom reverb came back with NO impulse
              // response after the first track change / route change.
              customImpulseResponse = samples;
              customIrRestored = true;
            }
          } catch (e, st) {
            ErrorLogger.log(
              'Failed to restore custom reverb IR from $irPath',
              error: e,
              stackTrace: st,
              category: 'EqualizerManager',
            );
          }
        }
        if (!customIrRestored) {
          reverbPreset = ReverbPreset.studio.wireValue;
        }
      } else {
        reverbPreset = storedReverb.wireValue;
      }
      reverbWetDry = prefs.getDouble(PrefsKeys.convolutionReverbWetDry) ?? 0.20;
      reverbPredelayMs =
          prefs.getDouble(PrefsKeys.convolutionReverbPredelayMs) ?? 0.0;
      reverbDamping =
          prefs.getDouble(PrefsKeys.convolutionReverbDamping) ?? 0.5;

      stereoBalance = prefs.getDouble(PrefsKeys.stereoBalance) ?? 0.0;
      monoMix = prefs.getBool(PrefsKeys.monoMix) ?? false;
      isSincResamplerEnabled =
          _effectsChannel.isPlaybackSincResamplerSupported &&
              (prefs.getBool(PrefsKeys.sincResamplerEnabled) ?? false);

      // Phase 1 DSP expansion stages (missing keys = neutral defaults)
      isSaturationEnabled = prefs.getBool(PrefsKeys.saturationEnabled) ?? false;
      saturationDrive = prefs.getDouble(PrefsKeys.saturationDrive) ?? 0.3;
      saturationMix = prefs.getDouble(PrefsKeys.saturationMix) ?? 0.5;
      saturationTilt = prefs.getDouble(PrefsKeys.saturationTilt) ?? 0.3;
      saturationMode = prefs.getInt(PrefsKeys.saturationMode) ?? 0;
      saturationMultiband =
          prefs.getBool(PrefsKeys.saturationMultiband) ?? false;

      isStereoWidthEnabled =
          prefs.getBool(PrefsKeys.stereoWidthEnabled) ?? false;
      stereoWidth = prefs.getDouble(PrefsKeys.stereoWidth) ?? 1.0;
      stereoWidthMultiband =
          prefs.getBool(PrefsKeys.stereoWidthMultiband) ?? false;
      stereoWidthLow = prefs.getDouble(PrefsKeys.stereoWidthLow) ?? 1.0;
      stereoWidthMid = prefs.getDouble(PrefsKeys.stereoWidthMid) ?? 1.0;
      stereoWidthHigh = prefs.getDouble(PrefsKeys.stereoWidthHigh) ?? 1.0;
      stereoWidthLowCrossoverHz =
          prefs.getDouble(PrefsKeys.stereoWidthLowCrossoverHz) ?? 160.0;
      stereoWidthHighCrossoverHz =
          prefs.getDouble(PrefsKeys.stereoWidthHighCrossoverHz) ?? 2500.0;

      isLoudnessContourEnabled =
          prefs.getBool(PrefsKeys.loudnessContourEnabled) ?? false;
      loudnessContourIntensity =
          prefs.getDouble(PrefsKeys.loudnessContourIntensity) ?? 0.0;

      isSubCrossoverEnabled =
          prefs.getBool(PrefsKeys.subCrossoverEnabled) ?? false;
      subCrossoverCornerHz =
          prefs.getDouble(PrefsKeys.subCrossoverCornerHz) ?? 80.0;
      subCrossoverSlopeDbPerOct =
          prefs.getDouble(PrefsKeys.subCrossoverSlopeDbPerOct) ?? 24.0;
      subCrossoverGain = prefs.getDouble(PrefsKeys.subCrossoverGain) ?? 0.8;
      subCrossoverBassMono =
          prefs.getBool(PrefsKeys.subCrossoverBassMono) ?? false;
      subCrossoverAntiPop =
          prefs.getBool(PrefsKeys.subCrossoverAntiPop) ?? true;

      isDynamicEqEnabled = prefs.getBool(PrefsKeys.dynamicEqEnabled) ?? false;
      reverbCrossChannel = prefs.getDouble(PrefsKeys.reverbCrossChannel) ?? 0.0;

      isMultibandCompressorEnabled =
          prefs.getBool(PrefsKeys.multibandCompressorEnabled) ?? false;
      multibandCompressorF0 =
          prefs.getDouble(PrefsKeys.multibandCompressorF0) ?? 160.0;
      multibandCompressorF1 =
          prefs.getDouble(PrefsKeys.multibandCompressorF1) ?? 1000.0;
      multibandCompressorF2 =
          prefs.getDouble(PrefsKeys.multibandCompressorF2) ?? 5000.0;
      final mbcJson = prefs.getString(PrefsKeys.multibandCompressorBands);
      if (mbcJson != null) {
        try {
          final decoded = (json.decode(mbcJson) as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map(MultibandCompressorBandConfig.fromJson)
              .toList();
          if (decoded.isNotEmpty) multibandCompressorBands = decoded;
        } catch (_) {}
      }
      isDynamicBassEnabled =
          prefs.getBool(PrefsKeys.dynamicBassEnabled) ?? false;
      dynamicBassStrength =
          prefs.getDouble(PrefsKeys.dynamicBassStrength) ?? 1.0;
      dynamicBassXLow = prefs.getInt(PrefsKeys.dynamicBassXLow) ?? 100;
      dynamicBassXHigh = prefs.getInt(PrefsKeys.dynamicBassXHigh) ?? 5600;
      dynamicBassYLow = prefs.getInt(PrefsKeys.dynamicBassYLow) ?? 40;
      dynamicBassYHigh = prefs.getInt(PrefsKeys.dynamicBassYHigh) ?? 80;
      dynamicBassSideGainLow =
          prefs.getDouble(PrefsKeys.dynamicBassSideGainLow) ?? 0.10;
      dynamicBassSideGainHigh =
          prefs.getDouble(PrefsKeys.dynamicBassSideGainHigh) ?? 0.50;
      dynamicBassPreset = prefs.getInt(PrefsKeys.dynamicBassPreset) ?? 0;
      isViperDdcEnabled = prefs.getBool(PrefsKeys.viperDdcEnabled) ?? false;
      viperDdcProfileName =
          prefs.getString(PrefsKeys.viperDdcProfileName) ?? '';
      viperDdcContent = prefs.getString(PrefsKeys.viperDdcContent) ?? '';
      isArbitraryEqEnabled =
          prefs.getBool(PrefsKeys.arbitraryEqEnabled) ?? false;
      arbitraryEqString = prefs.getString(PrefsKeys.arbitraryEqString) ?? '';
      arbitraryEqLinearPhase =
          prefs.getBool(PrefsKeys.arbitraryEqLinearPhase) ?? false;
      isLiveProgEnabled = prefs.getBool(PrefsKeys.liveProgEnabled) ?? false;
      liveProgCode = prefs.getString(PrefsKeys.liveProgCode) ?? '';
      liveProgSliders
        ..clear()
        ..addAll(
            decodeLiveProgSliders(prefs.getString(PrefsKeys.liveProgSliders)));
      dspPreference = prefs.getString(PrefsKeys.dspPreference) ?? 'native';
      if (dspPreference != 'native' &&
          dspPreference != 'oem' &&
          dspPreference != 'auto') {
        dspPreference = 'native';
      }
      final bitPerfect = prefs.getBool(PrefsKeys.bitPerfectOutput) ?? false;
      final bypassDsp = prefs.getBool(PrefsKeys.bypassDspOnBitPerfect) ?? true;
      isBitPerfectBypass = bitPerfect && bypassDsp;
      isDitherEnabled = prefs.getBool(PrefsKeys.ditherEnabled) ?? true;
      ditherTargetBitDepth = prefs.getInt(PrefsKeys.ditherTargetBitDepth) ?? 16;
      if (ditherTargetBitDepth != 16 &&
          ditherTargetBitDepth != 24 &&
          ditherTargetBitDepth != 32) {
        ditherTargetBitDepth = 16;
      }
      // Bluetooth Hi-Res opt-in mirrors into the dither-on-BT permission so a
      // restored session keeps dithering on BT only when the user asked for it.
      isBluetoothDitherEnabled =
          prefs.getBool(PrefsKeys.bluetoothHiResEnabled) ?? false;
      _sanitizeRestoredState();
      // Hydrate stored dynamic-EQ bands and the selected headphone profile into
      // memory BEFORE the bit-perfect early-return. These only populate
      // in-memory state (no native push), so the stored config survives the
      // session even while bypass is on and is correctly re-applied once bypass
      // is turned off, instead of being silently lost.
      final dynEqJson = prefs.getString(PrefsKeys.dynamicEqBands);
      if (dynEqJson != null) {
        try {
          final decoded = (json.decode(dynEqJson) as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map(DynamicEqBandConfig.fromJson)
              .toList();
          if (decoded.isNotEmpty) dynamicEqBands = decoded;
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to decode dynamic EQ bands from prefs',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }

      final profileId = prefs.getString(PrefsKeys.eqHeadphoneProfileId);
      if (profileId != null) {
        try {
          await HeadphoneProfilesRepository().loadProfiles();
          selectedHeadphoneProfile =
              HeadphoneProfilesRepository().getProfileById(profileId);
        } catch (e, st) {
          // Previously this aborted the ENTIRE restore, so no effect state
          // was ever pushed to native for the session.
          ErrorLogger.log(
            'Failed to load headphone profile $profileId during restore',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }

      if (PlatformCapabilities.isAndroid) {
        await _effectsChannel.setDspPreference(dspPreference);
        await _effectsChannel.setBypassDspForBitPerfect(isBitPerfectBypass);
        // Restore dither too: it was previously loaded into in-memory state
        // but never pushed, so a saved-ON dither did nothing until toggled.
        if (isDitherEnabled) {
          await _effectsChannel.setDitherParams(
            enabled: true,
            targetBitDepth: ditherTargetBitDepth,
            isBluetooth: isBluetoothRoute,
            allowBluetoothDither: isBluetoothDitherEnabled,
          );
        }
      }
      if (isBitPerfectBypass) {
        _syncPipeline();
        return;
      }

      // Batch native effect enables to avoid sound-drop dropout (requires EQ off/on to fix)
      // Previously each await toggled DynamicsProcessing causing 20+ JNI hops on audio thread during playback.
      // Now batch independent effects together and defer DynamicsProcessing last to prevent double-processing bypass churn.
      final pendingFutures = <Future<void>>[];
      if (isEnabled) {
        // Apply preset first without enabling, then enable atomically
        await applyCurrentPreset();
        pendingFutures.add(_effectsChannel.setEqEnabled(true));
        pendingFutures.add(_effectsChannel.setNativeEqEnabled(true));
      }
      if (currentPreset.bassBoost > 0) {
        pendingFutures.add(setBassBoost(currentPreset.bassBoost));
      }
      if (volumeBoost > 0) {
        pendingFutures.add(setVolumeBoost(volumeBoost));
      }
      if (preampDb != 0.0) {
        pendingFutures.add(_effectsChannel.setEqPreamp(preampDb));
      }
      if (_effectsChannel.isVirtualizerSupported) {
        pendingFutures
            .add(_effectsChannel.setVirtualizerEnabled(isVirtualizerEnabled));
        if (isVirtualizerEnabled) {
          pendingFutures.add(
            _effectsChannel.setVirtualizerStrength(virtualizerStrength),
          );
        }
      }

      pendingFutures.add(_applySpatializerWithFallback(isSpatializerEnabled));

      if (isCrossfeedEnabled) {
        pendingFutures.add(
          _effectsChannel.setCrossfeedParams(
            crossfeedDelayUs,
            crossfeedFeedDb,
            fcut: crossfeedFcut,
          ),
        );
        pendingFutures.add(_effectsChannel.setCrossfeedMode(crossfeedMode));
      }
      pendingFutures
          .add(_effectsChannel.setCrossfeedEnabled(isCrossfeedEnabled));

      if (isLimiterEnabled) {
        pendingFutures.add(
          _effectsChannel.setLimiterParams(
            limiterLookaheadMs,
            limiterThresholdDb,
            limiterReleaseMs,
            ratio: _hasStoredCompressorParams ? compressorRatio : null,
            attackMs: _hasStoredCompressorParams ? compressorAttackMs : null,
            makeupGainDb:
                _hasStoredCompressorParams ? compressorMakeupGainDb : null,
          ),
        );
      }
      pendingFutures.add(_effectsChannel.setLimiterEnabled(isLimiterEnabled));

      if (isReverbEnabled) {
        pendingFutures.add(_effectsChannel.setReverbPreset(reverbPreset));
        pendingFutures.add(_effectsChannel.setReverbWetDry(reverbWetDry));
        pendingFutures.add(
          _effectsChannel.setReverbParams(
            predelayMs: reverbPredelayMs,
            damping: reverbDamping,
            crossChannel: reverbCrossChannel,
          ),
        );
      }
      pendingFutures.add(_effectsChannel.setReverbEnabled(isReverbEnabled));

      if (stereoBalance != 0.0) {
        pendingFutures.add(_effectsChannel.setStereoBalance(stereoBalance));
      }
      pendingFutures.add(_effectsChannel.setMonoMix(monoMix));
      pendingFutures
          .add(_effectsChannel.setSincResamplerEnabled(isSincResamplerEnabled));

      if (isSaturationEnabled) {
        pendingFutures.add(
          _effectsChannel.setSaturationParams(
            saturationDrive,
            saturationMix,
            saturationTilt,
            mode: saturationMode,
          ),
        );
        pendingFutures.add(
          _effectsChannel.setSaturationMultiband(saturationMultiband),
        );
      }
      pendingFutures
          .add(_effectsChannel.setSaturationEnabled(isSaturationEnabled));

      if (isStereoWidthEnabled) {
        pendingFutures.add(
          _effectsChannel.setStereoWidthParams(
            stereoWidth,
            multiband: stereoWidthMultiband,
            lowWidth: stereoWidthLow,
            midWidth: stereoWidthMid,
            highWidth: stereoWidthHigh,
            lowCrossoverHz: stereoWidthLowCrossoverHz,
            highCrossoverHz: stereoWidthHighCrossoverHz,
          ),
        );
      }
      pendingFutures
          .add(_effectsChannel.setStereoWidthEnabled(isStereoWidthEnabled));

      if (isLoudnessContourEnabled) {
        pendingFutures.add(
          _effectsChannel.setLoudnessContourParams(
            loudnessContourIntensity,
            loudnessVolumeLinear,
          ),
        );
      }
      pendingFutures.add(
          _effectsChannel.setLoudnessContourEnabled(isLoudnessContourEnabled));

      if (isSubCrossoverEnabled) {
        pendingFutures.add(
          _effectsChannel.setSubCrossoverParams(
            subCrossoverCornerHz,
            subCrossoverSlopeDbPerOct,
            subCrossoverGain,
            bassMono: subCrossoverBassMono,
            antiPop: subCrossoverAntiPop,
          ),
        );
      }
      pendingFutures
          .add(_effectsChannel.setSubCrossoverEnabled(isSubCrossoverEnabled));

      if (isDynamicEqEnabled) {
        pendingFutures.add(_pushDynamicEqConfig());
      }
      pendingFutures
          .add(_effectsChannel.setDynamicEqEnabled(isDynamicEqEnabled));

      if (isMultibandCompressorEnabled) {
        pendingFutures.add(_pushMultibandCompressorConfig());
      }
      pendingFutures.add(
        _effectsChannel
            .setMultibandCompressorEnabled(isMultibandCompressorEnabled),
      );

      pendingFutures.add(
        _effectsChannel.setDynamicBassParams(
          enabled: isDynamicBassEnabled,
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

      if (isViperDdcEnabled && viperDdcContent.isNotEmpty) {
        pendingFutures.add(_effectsChannel.loadViperDdc(
          ddcContent: viperDdcContent,
          profileName: viperDdcProfileName,
        ));
      }
      pendingFutures.add(_effectsChannel.setViperDdcEnabled(isViperDdcEnabled));

      if (isArbitraryEqEnabled && arbitraryEqString.isNotEmpty) {
        pendingFutures.add(_effectsChannel.loadArbitraryEq(
          eqString: arbitraryEqString,
          linearPhase: arbitraryEqLinearPhase,
        ));
      }
      pendingFutures
          .add(_effectsChannel.setArbitraryEqEnabled(isArbitraryEqEnabled));

      if (isLiveProgEnabled && liveProgCode.isNotEmpty) {
        pendingFutures.add(_effectsChannel.loadLiveProgCode(liveProgCode));
        for (final entry in liveProgSliders.entries) {
          pendingFutures
              .add(_effectsChannel.setLiveProgSlider(entry.key, entry.value));
        }
      }
      pendingFutures.add(_effectsChannel.setLiveProgEnabled(isLiveProgEnabled));
      // Dynamics last — it triggers recalculateActiveStages which disables OEM engine; doing it last prevents intermediate dropout
      // Log individual failures so failed effect stages are diagnosable while allowing remaining stages to complete
      if (pendingFutures.isNotEmpty) {
        final results = await Future.wait(
          pendingFutures.map(
            (f) => f.then((_) => true).catchError((Object e, StackTrace st) {
              ErrorLogger.log(
                'Failed to restore audio effect preference',
                error: e,
                stackTrace: st,
                category: 'EqualizerManager',
              );
              return false;
            }),
          ),
        );
        final failCount = results.where((r) => !r).length;
        if (failCount > 0) {
          ErrorLogger.log(
            '$failCount/${pendingFutures.length} audio effects failed to restore',
            category: 'EqualizerManager',
          );
        }
      }
      if (isDynamicsEnabled && !_isDynamicsBypassed) {
        // Small delay lets AudioTrack stabilize before DynamicsProcessing rebuild (fixes sound drops needing EQ toggle)
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _effectsChannel.setDynamicsPreset(dynamicsPreset, true);
      }
      _syncPipeline();
    } catch (e, st) {
      if (!_isDisposed) {
        ErrorLogger.log(
          'Failed to restore equalizer preferences',
          error: e,
          stackTrace: st,
          category: 'EqualizerManager',
        );
      }
    }
  }
}
