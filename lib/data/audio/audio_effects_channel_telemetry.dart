// lib/data/audio/audio_effects_channel_telemetry.dart
part of 'audio_effects_channel.dart';

/// Telemetry, advanced DSP stages (ViPER-DDC / Arbitrary EQ / LiveProg),
/// custody verification, thermal/battery and routing bridge methods mixed
/// into [AudioEffectsChannel] so they remain mockable instance methods while
/// keeping the core channel file under the fat-file ratchet cap.
mixin _AudioEffectsChannelTelemetryMixin {
  bool get _isAndroid;
  Future<dynamic> _invokeNativeSetter(
    String method, [
    Map<String, dynamic>? arguments,
  ]);

  /// Gets the current bitmask of auto-degraded stages from the native DSP engine.
  Future<int> getAutoDegradedStages() async {
    if (!_isAndroid) return 0;
    try {
      final dynamic res = await AudioEffectsChannel._channel
          .invokeMethod<dynamic>('getAutoDegradedStages')
          .timeout(const Duration(seconds: 2));
      final stages = (res as num?)?.toInt() ?? 0;
      _handleAutoDegradeTransition(stages);
      return stages;
    } catch (_) {
      return 0;
    }
  }

  /// Queries real-time engine telemetry (Limiter GR, DynEQ GR, Multiband GR, RTF, and auto-degrade).
  Future<DspTelemetry> getTelemetry() async {
    if (!_isAndroid) return const DspTelemetry.zero();
    // Throws on failure so callers (DspTelemetryCubit) can implement backoff.
    // Previously every error was swallowed and returned as zero, which made the
    // cubit's "park after N failures" backoff unreachable in production.
    final dynamic res = await AudioEffectsChannel._channel
        .invokeMethod<dynamic>('getTelemetry')
        .timeout(const Duration(milliseconds: 250));
    if (res is List) {
      final telemetry = DspTelemetry.fromNativeList(res);
      _handleAutoDegradeTransition(telemetry.autoDegradedStages);
      return telemetry;
    }
    throw StateError('Unexpected getTelemetry payload: $res');
  }

  final _autoDegradeStreamController = StreamController<int>.broadcast();
  int _lastKnownDegradedStages = 0;

  /// Stream that emits the auto-degraded stage mask EXACTLY ONCE per 0 -> nonzero transition.
  /// No spam within the same degraded session; re-notifies only after full recovery to 0.
  Stream<int> get onAutoDegradedSessionStarted =>
      _autoDegradeStreamController.stream;

  void _handleAutoDegradeTransition(int currentStages) {
    if (_lastKnownDegradedStages == 0 && currentStages != 0) {
      DspReliabilityTracker.instance.recordAutoDegradeActivation(currentStages);
      if (!_autoDegradeStreamController.isClosed) {
        _autoDegradeStreamController.add(currentStages);
      }
    } else if (_lastKnownDegradedStages != 0 && currentStages == 0) {
      DspReliabilityTracker.instance.recordAutoDegradeRecovery();
    }
    _lastKnownDegradedStages = currentStages;
  }

  /// Retrieves the current weekly sound dose (0.0 to >1.0, where 1.0 = 100% weekly sound dose).
  Future<double> getWeeklyDose() async {
    if (!_isAndroid) return 0.0;
    try {
      // The standard codec delivers a whole-number reply (0, 1) as an int, and
      // invokeMethod<double> then throws a cast error that the catch below
      // swallowed, so the dose silently read 0.0. Accept any num.
      final dynamic res = await AudioEffectsChannel._channel
          .invokeMethod<dynamic>('getWeeklyDose')
          .timeout(const Duration(milliseconds: 250));
      return res is num && res.isFinite ? res.toDouble() : 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  // --- LIVE GAIN REDUCTION (telemetry; the sheet that shows these is the only
  // way a user can tell that a limiter is working rather than coloring the sound)

  /// Gain reduction of the lookahead limiter in dB (0 when it is idle). The
  /// limiter only enters the chain when the graph can exceed unity gain, so a
  /// non-zero reading is evidence that peaks are being caught.
  Future<double> getLimiterGrDb() => _readGrDb('getLimiterGrDb');

  /// Worst-case (most negative) gain reduction across the dynamic EQ's
  /// [bandCount] bands, in dB.
  Future<double> getDynEqGrDb({int bandCount = 4}) =>
      _readWorstGrDb('getDynEqGrDb', bandCount);

  /// Worst-case gain reduction across the multiband compressor's [bandCount]
  /// bands, in dB.
  Future<double> getMultibandGrDb({int bandCount = 4}) =>
      _readWorstGrDb('getMultibandGrDb', bandCount);

  Future<double> _readGrDb(String method, {int? band}) async {
    if (!_isAndroid) return 0.0;
    try {
      // Same reason getWeeklyDose accepts any num: a whole-number reply arrives
      // as an int and a typed invokeMethod<double> throws on it.
      final dynamic res = await AudioEffectsChannel._channel
          .invokeMethod<dynamic>(
              method, band == null ? null : <String, dynamic>{'band': band})
          .timeout(const Duration(milliseconds: 250));
      return res is num && res.isFinite ? res.toDouble() : 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Native gain reduction is reported as a magnitude in dB; the loudest band
  /// is the one a listener perceives, so the maximum is the useful reading.
  Future<double> _readWorstGrDb(String method, int bandCount) async {
    double worst = 0.0;
    for (int band = 0; band < bandCount; ++band) {
      final gr = await _readGrDb(method, band: band);
      if (gr.abs() > worst.abs()) worst = gr;
    }
    return worst;
  }

  /// Resets the weekly sound dose accumulator to 0.0.
  Future<bool> resetWeeklyDose() async {
    if (!_isAndroid) return false;
    try {
      final res = await AudioEffectsChannel._channel
          .invokeMethod<bool>('resetWeeklyDose')
          .timeout(const Duration(seconds: 1));
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if safety limiter attenuation (-6 dBFS ceiling) is actively engaged.
  Future<bool> isSafetyAttenuationActive() async {
    if (!_isAndroid) return false;
    try {
      final res = await AudioEffectsChannel._channel
          .invokeMethod<bool>('isSafetyAttenuationActive')
          .timeout(const Duration(milliseconds: 250));
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Configures Headphone Safety parameters in the native DSP engine.
  Future<void> setHeadphoneSafetyParams({
    required bool enabled,
    double doseThreshold = 1.0,
    double safetyCeilingDb = -6.0,
  }) async {
    if (!_isAndroid || !doseThreshold.isFinite || !safetyCeilingDb.isFinite) {
      return;
    }
    try {
      await _invokeNativeSetter('setHeadphoneSafetyParams', {
        'enabled': enabled,
        'doseThreshold': doseThreshold,
        'safetyCeilingDb': safetyCeilingDb,
      }).timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set headphone safety params',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      rethrow;
    }
  }

  /// Retrieves internal DSP status for assertions/testing.
  Future<Map<String, dynamic>?> getDspDebugStatus() async {
    if (!_isAndroid) return null;
    try {
      return await AudioEffectsChannel._channel
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
      await _invokeNativeSetter('setCrossfeedMode', {'mode': mode})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set crossfeed mode ($mode)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      rethrow;
    }
  }

  // --- MULTIBAND SATURATION ---
  Future<void> setSaturationMultiband(bool multiband) async {
    if (!_isAndroid) return;
    try {
      await _invokeNativeSetter(
              'setSaturationMultiband', {'multiband': multiband})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set saturation multiband ($multiband)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      rethrow;
    }
  }

  // --- VIPER-DDC ---
  Future<void> setViperDdcEnabled(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _invokeNativeSetter('setViperDdcEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set ViPER-DDC enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      rethrow;
    }
  }

  Future<bool> loadViperDdc({
    required String ddcContent,
    required String profileName,
  }) async {
    if (!_isAndroid) return false;
    try {
      final bool? ok = await AudioEffectsChannel._channel
          .invokeMethod<bool>('loadViperDdc', {
        'ddcContent': ddcContent,
        'profileName': profileName,
      }).timeout(const Duration(seconds: 10)); // large payload
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
      await _invokeNativeSetter('setArbitraryEqEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set Arbitrary EQ enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      rethrow;
    }
  }

  Future<bool> loadArbitraryEq({
    required String eqString,
    bool linearPhase = false,
  }) async {
    if (!_isAndroid) return false;
    try {
      final bool? ok = await AudioEffectsChannel._channel
          .invokeMethod<bool>('loadArbitraryEq', {
        'eqString': eqString,
        'linearPhase': linearPhase,
      }).timeout(const Duration(seconds: 10)); // large payload
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
      await _invokeNativeSetter('setLiveProgEnabled', {'enabled': enabled})
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set LiveProg enabled ($enabled)',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      rethrow;
    }
  }

  Future<String> loadLiveProgCode(String code) async {
    if (!_isAndroid) return 'Unsupported platform';
    try {
      final String? status =
          await AudioEffectsChannel._channel.invokeMethod<String>(
        'loadLiveProgCode',
        {'code': code},
      ).timeout(const Duration(seconds: 10)); // large payload / EEL compile
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
    if (!_isAndroid || !value.isFinite) return;
    try {
      await _invokeNativeSetter(
              'setLiveProgSlider', {'index': index, 'value': value})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to set LiveProg slider $index',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      rethrow;
    }
  }

  /// Queries current device thermal throttling status (0=None, 1=Light, 2=Moderate, 3=Severe, etc.).
  Future<int> getThermalStatus() async {
    if (!_isAndroid) return 0;
    try {
      final int? status = await AudioEffectsChannel._channel
          .invokeMethod<int>('getThermalStatus')
          .timeout(const Duration(seconds: 2));
      return status ?? 0;
    } catch (e, st) {
      ErrorLogger.log(
        'getThermalStatus failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return 0;
    }
  }

  /// Heuristic DSP battery drain estimates (mAh/hr) for the active stages.
  /// Modelled from RTF and stage count — not coulomb-counter measurements, as
  /// the `isHeuristic` flag says.
  Future<Map<String, dynamic>> getDspBatteryDrainEstimate() async {
    if (!_isAndroid) return const {};
    try {
      final res = await AudioEffectsChannel._channel
          .invokeMapMethod<String, dynamic>('getDspBatteryDrainEstimate')
          .timeout(const Duration(seconds: 2));
      return res ?? const {};
    } catch (e, st) {
      ErrorLogger.log(
        'getDspBatteryDrainEstimate failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return const {};
    }
  }

  /// Typed wrapper around [getDspBatteryDrainEstimate].
  Future<DspBatteryEstimate> getDspBatteryEstimate() async {
    try {
      final map = await getDspBatteryDrainEstimate();
      return DspBatteryEstimate.fromMap(map);
    } catch (e, st) {
      ErrorLogger.log(
        'getDspBatteryEstimate failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return const DspBatteryEstimate();
    }
  }

  /// Sets the native low-power bypass state.
  Future<bool> setLowPowerRoute(bool enabled) async {
    if (!_isAndroid) return false;
    try {
      final res = await AudioEffectsChannel._channel.invokeMethod<bool>(
        'setLowPowerRoute',
        {'enabled': enabled},
      ).timeout(const Duration(seconds: 3));
      return res ?? false;
    } catch (e, st) {
      ErrorLogger.log('setLowPowerRoute failed',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
      return false;
    }
  }

  /// Checks whether the native low-power bypass is currently active.
  Future<bool> isLowPowerBypassed() async {
    if (!_isAndroid) return false;
    try {
      final res = await AudioEffectsChannel._channel
          .invokeMethod<bool>('isLowPowerBypassed')
          .timeout(const Duration(seconds: 3));
      return res ?? false;
    } catch (e, st) {
      ErrorLogger.log('isLowPowerBypassed failed',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
      return false;
    }
  }

  /// Retrieves the native engine custody report (sample rate, buffer size, active stages, latency, bit-exactness).
  Future<Map<String, dynamic>> getChainOfCustodyReport() async {
    if (!_isAndroid) return const {};
    try {
      final res = await AudioEffectsChannel._channel
          .invokeMapMethod<String, dynamic>('getChainOfCustodyReport')
          .timeout(const Duration(seconds: 2));
      return res ?? const {};
    } catch (e, st) {
      ErrorLogger.log(
        'getChainOfCustodyReport failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return const {};
    }
  }

  /// Asks the native engine to capture the next [frames] of PCM on both sides of
  /// the DSP chain. Fails when a window is already pending; nothing is measured
  /// unless playback is actually feeding blocks.
  Future<Map<String, dynamic>> armCustodyWindow({
    required int frames,
    required double sampleRate,
    required bool bitPerfect,
    required bool bypassCompare,
  }) async {
    if (!_isAndroid) {
      return const {'armed': false, 'reason': 'unsupportedPlatform'};
    }
    try {
      final res = await AudioEffectsChannel._channel
          .invokeMapMethod<String, dynamic>('armCustodyWindow', {
        'frames': frames,
        'sampleRate': sampleRate,
        'bitPerfect': bitPerfect,
        'bypassCompare': bypassCompare,
      }).timeout(const Duration(seconds: 2));
      return res ?? const {'armed': false, 'reason': 'noResponse'};
    } catch (e, st) {
      ErrorLogger.log(
        'armCustodyWindow failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return const {'armed': false, 'reason': 'channelError'};
    }
  }

  /// Collects the captured window with SHA-256 digests of both halves. Returns
  /// `{'available': false, ...}` when nothing was captured — the caller must
  /// treat that as "unverified", never as a pass.
  Future<Map<String, dynamic>> collectCustodyWindow() async {
    if (!_isAndroid) {
      return const {'available': false, 'reason': 'unsupportedPlatform'};
    }
    try {
      final res = await AudioEffectsChannel._channel
          .invokeMapMethod<String, dynamic>('collectCustodyWindow')
          .timeout(const Duration(seconds: 3));
      return res ?? const {'available': false, 'reason': 'noResponse'};
    } catch (e, st) {
      ErrorLogger.log(
        'collectCustodyWindow failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return const {'available': false, 'reason': 'channelError'};
    }
  }

  /// Abandons a pending window (e.g. the user left the sheet before playback
  /// filled it) so a later arm() is not blocked by it.
  Future<void> cancelCustodyWindow() async {
    if (!_isAndroid) return;
    try {
      await AudioEffectsChannel._channel
          .invokeMethod<void>('cancelCustodyWindow')
          .timeout(
            const Duration(seconds: 2),
          );
    } catch (e, st) {
      ErrorLogger.log(
        'cancelCustodyWindow failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
    }
  }

  /// Verifies active DSP effect parameters against native hardware state.
  Future<Map<String, dynamic>?> verifyState() async {
    if (!_isAndroid) return null;
    try {
      return await AudioEffectsChannel._channel
          .invokeMapMethod<String, dynamic>('verifyState')
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log(
        'verifyState failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return null;
    }
  }

  /// Sends a silent buffer through the DSP pipeline to warm up complex filters (e.g. convolver)
  /// before unmuting, preventing audible pops/clicks.
  Future<bool> sendWarmupBuffer({int durationMs = 100}) async {
    if (!_isAndroid) return false;
    try {
      final res = await AudioEffectsChannel._channel.invokeMethod<bool>(
          'sendWarmupBuffer',
          {'durationMs': durationMs}).timeout(const Duration(seconds: 2));
      return res ?? true;
    } catch (e, st) {
      ErrorLogger.log('sendWarmupBuffer failed',
          error: e, stackTrace: st, category: 'AudioEffectsChannel');
      return false;
    }
  }

  /// Whether hardware audio offload is allowed given active DSP and DVC state.
  Future<bool> isOffloadAllowed() async {
    if (!_isAndroid) return false;
    try {
      return await AudioEffectsChannel._channel
              .invokeMethod<bool>('isOffloadAllowed')
              .timeout(const Duration(seconds: 3)) ??
          false;
    } catch (e, st) {
      ErrorLogger.log(
        'isOffloadAllowed failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return false;
    }
  }

  /// Configures multi-output routing mode.
  Future<String> setMultiOutputRoute(String mode) async {
    if (!_isAndroid) return 'unsupported';
    try {
      final res = await AudioEffectsChannel._channel.invokeMethod<String>(
          'setMultiOutputRoute',
          {'mode': mode}).timeout(const Duration(seconds: 3));
      return res ?? 'unsupported';
    } catch (e, st) {
      ErrorLogger.log(
        'setMultiOutputRoute failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return 'unsupported';
    }
  }

  /// Queries whether Android audio output is free of voice-call/ringtone focus
  /// preemption. Returns `true` off Android or on channel failure so playback
  /// controls fail open gracefully.
  Future<bool> getFocusState() async {
    if (!_isAndroid) return true;
    try {
      final res = await AudioEffectsChannel._channel
          .invokeMethod<bool>('getFocusState')
          .timeout(const Duration(seconds: 2));
      return res ?? true;
    } catch (e, st) {
      ErrorLogger.log(
        'getFocusState failed',
        error: e,
        stackTrace: st,
        category: 'AudioEffectsChannel',
      );
      return true;
    }
  }
}
