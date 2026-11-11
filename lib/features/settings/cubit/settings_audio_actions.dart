part of 'settings_cubit.dart';

mixin SettingsAudioActions on PulsrCubit<SettingsState> {
  final Mutex _audioModeMutex = Mutex();

  /// True while Bit-Perfect is running through Pulsr's own UAC2 isochronous
  /// sink instead of Android's exclusive mixer attributes. Not persisted: the
  /// boot restore re-establishes it from the saved preference.
  bool _bitPerfectViaDirectStream = false;

  /// Last direct-sink start failure, surfaced next to the mixer reason so the
  /// user learns why the fallback did not engage.
  String? _lastDirectUsbFailure;

  /// Last rate pushed to the tap-side SRC, so a route refresh that changes
  /// nothing does not re-fan-out to every player. Null = never pushed.
  int? _lastTapSrcTargetRate;

  /// Restores user DSP/follow preferences when Strict Bit-Perfect is turned OFF.
  bool? _preStrictBypass;
  bool? _preStrictFollowRate;

  /// Last source blocked reason emitted on the mixer path, so repeated tracks
  /// with the same blocker do not flood the UI with duplicate error emissions.
  String? _lastSourceBlockReason;

  bool get _currentSourceNeedsRawInteger {
    final song = getIt.isRegistered<PulsrAudioHandler>()
        ? getIt<PulsrAudioHandler>().currentSong : null;
    return effectiveSourceBitDepth(tagged: song?.bitDepth ?? 0,
        decoded: state.currentOutputDevice?.decodedBitDepth ?? 0) > 24;
  }

  bool get _integer32DirectUsbEligible {
    final usb = UsbExclusiveService().lastStatus;
    return state.currentOutputDevice?.isUsbDac == true &&
        !state.aaudioOutputEnabled && usb.streamingSupported &&
        usb.advertisedFormats.any((f) =>
            ((f['bitResolution'] as num?)?.toInt() ?? 0) >= 32);
  }

  Future<bool> validateBitPerfectTrackSource(SongsTableData song) =>
      _audioModeMutex.protect(() async {
        if (!state.bitPerfectOutput) return false;
        final depth = effectiveSourceBitDepth(tagged: song.bitDepth ?? 0,
            decoded: state.currentOutputDevice?.decodedBitDepth ?? 0);
        final rate = effectiveSourceSampleRate(
          tagged: song.sampleRate ?? 0,
          decoded: state.currentOutputDevice?.decodedSampleRate ?? 0,
        );
        final reason = AudioConflicts.bitPerfectSourceBlockedReason(
          path: song.path, codec: song.codec, bitDepth: depth,
          isRadio: song.source == SongSource.radio,
          integer32DirectUsbEligible: _integer32DirectUsbEligible,
          requireConfirmedCodec: state.strictBitPerfect || _bitPerfectViaDirectStream,
        );
        final unknownRate = rate <= 0 ||
            !HiResAudioService.validTargetSampleRates.contains(rate);
        if (reason == null && !unknownRate) return true;
        final message = reason ?? 'Source sample rate is unconfirmed.';
        if (state.strictBitPerfect) {
          await _rollbackBitPerfectEnable(message);
        } else if (_bitPerfectViaDirectStream) {
          await _suspendDirectBitPerfectForTrack(message);
        } else {
          safeEmit(state.copyWith(errorMessage: message));
        }
        return false;
      });

  /// Shared wording for a refused DSP-bypass push. The platform reason is
  /// appended when the channel captured one: without it the toast said only
  /// "failed", which is not actionable for an owned stage that refused.
  String _bypassUpdateFailedMessage() {
    final base = L10nHolder.current?.dspBypassUpdateFailed ??
        'Failed to update the native DSP bypass.';
    final reason = AudioEffectsChannel.lastBypassRejectionReason;
    return reason == null || reason.isEmpty ? base : '$base $reason';
  }

  Future<void> _pushBitPerfectBypass(bool enabled) async {
    if (getIt.isRegistered<PulsrAudioHandler>()) {
      await getIt<PulsrAudioHandler>().setBitPerfectTransportPolicy(enabled);
    }
    if (getIt.isRegistered<EqualizerManager>()) {
      await getIt<EqualizerManager>().setBypassDspForBitPerfect(enabled);
    } else {
      await AudioEffectsChannel().setBypassDspForBitPerfect(enabled);
    }
  }

  /// Last-resort Bit-Perfect path for DACs/OS builds without exclusive mixer
  /// attributes: the direct UAC2 sink writes the PCM straight to the DAC while
  /// the native DSP tee mutes the HAL path. Returns true when the stream runs.
  Future<bool> _tryStartDirectUsbStreaming({
    bool strict = false,
    int? sampleRate,
    int? bitDepth,
    int? channels,
  }) async {
    _lastDirectUsbFailure = null;
    if (!PlatformCapabilities.isAndroid) return false;
    // AAudio Direct bypasses the ExoPlayer DSP chain the USB tee lives in.
    if (state.aaudioOutputEnabled) {
      _lastDirectUsbFailure = 'AAudio Direct output is on — turn it off to use the direct USB path';
      return false;
    }
    // The direct sink writes to the USB device it opens; never start it while
    // the media route is on Bluetooth, the speaker, or an unknown route.
    if (state.currentOutputDevice?.isUsbDac != true) {
      _lastDirectUsbFailure = 'The current output is not a USB DAC.';
      return false;
    }
    try {
      final usb = UsbExclusiveService();
      var status = await usb.getStatus();
      if (!status.attached) {
        _lastDirectUsbFailure = 'the USB DAC is not visible to the app';
        return false;
      }
      if (!status.permitted) {
        final granted = await usb.requestPermission();
        if (!granted) {
          _lastDirectUsbFailure = 'USB access permission was not granted';
          return false;
        }
        status = await usb.getStatus();
        if (!status.attached || !status.permitted) {
          _lastDirectUsbFailure = 'USB access is no longer available';
          return false;
        }
      }
      if (!status.streamingSupported) {
        _lastDirectUsbFailure = 'this DAC does not expose a streamable USB Audio interface';
        return false;
      }
      final song = getIt.isRegistered<PulsrAudioHandler>()
          ? getIt<PulsrAudioHandler>().currentSong : null;
      // A track whose format is unknown (0, "not read") is not a format: asking
      // for 0 Hz would be refused with "format_unsupported" and look like a
      // broken DAC rather than unreadable metadata.
      final trackRate = _usableRate(
        sampleRate ??
            effectiveSourceSampleRate(
              tagged: song?.sampleRate ?? 0,
              decoded: state.currentOutputDevice?.decodedSampleRate ?? 0,
            ),
      );
      final sourceDepth = effectiveSourceBitDepth(
        tagged: math.max(song?.bitDepth ?? 0, bitDepth ?? 0),
        decoded: state.currentOutputDevice?.decodedBitDepth ?? 0,
      );
      // Recheck at the transport boundary: the source may have changed while
      // the caller awaited the mixer or USB probe. PCM32 is only eligible on
      // the raw integer path, never merely because the DAC accepts 32 bits.
      final sourceBlock = AudioConflicts.bitPerfectSourceBlockedReason(
        path: song?.path,
        codec: song?.codec,
        bitDepth: sourceDepth,
        isRadio: song?.source == SongSource.radio,
        integer32DirectUsbEligible: _integer32DirectUsbEligible,
        requireConfirmedCodec: song != null && (strict || state.strictBitPerfect),
      );
      if (sourceBlock != null) {
        _lastDirectUsbFailure = sourceBlock;
        return false;
      }
      final trackDepth = resolveFollowBitDepth(
        trackBitDepth: sourceDepth,
        streamingBitDepth: status.streamingBitDepth,
        deviceBitDepth: state.currentOutputDevice?.availableDevices
                .where((d) => d.isCurrent).firstOrNull?.maxBitDepth ??
            state.currentOutputDevice?.bitDepth ?? 0,
      );
      if (song != null && (trackRate == null ||
          !HiResAudioService.validTargetSampleRates.contains(trackRate) ||
          AudioConflicts.classifySourceCodec(path: song.path, codec: song.codec) ==
              AudioSourceCodecState.unknown)) {
        _lastDirectUsbFailure = 'Source format is unconfirmed; direct playback suspended.';
        return false;
      }
      // Channels: prefer what the native producer is currently supplying, then
      // the track metadata, then the safe stereo default. Without this the sink
      // always opens in 2-channel mode even for multichannel tracks.
      final producerChannels = await UsbExclusiveService().getProducerChannels();
      final effectiveChannels = channels ?? (producerChannels > 0 ? producerChannels : 2);
      // Retain ownership even after a failed start until teardown is confirmed.
      _bitPerfectViaDirectStream = true;
      final res = await usb.startStreaming(
        sampleRate: trackRate ?? _directStreamSampleRate(),
        bitDepth: trackDepth,
        channels: effectiveChannels,
        strict: strict,
      );
      if (!res.isOk) {
        _lastDirectUsbFailure = res.toUserMessage();
        ErrorLogger.log(
          'Direct USB bit-perfect streaming refused (${res.name})',
          category: 'SettingsAudioActions',
        );
      } else {
        _lastDirectUsbFailure = null;
      }
      return res.isOk;
    } catch (e, st) {
      _lastDirectUsbFailure = e.toString();
      ErrorLogger.log('Direct USB bit-perfect streaming failed',
          error: e, stackTrace: st, category: 'SettingsAudioActions');
      return false;
    }
  }

  /// A format field is only a fact when it is positive: `0` means "not read",
  /// and forwarding it makes the transport refuse the stream as if the DAC
  /// could not carry the track.
  static int? _usableRate(int? value) => (value == null || value <= 0) ? null : value;

  int _directStreamSampleRate() {
    final deviceRate = state.currentOutputDevice?.sampleRate ?? 0;
    if (deviceRate > 0) return deviceRate;
    final rates = [...UsbExclusiveService().lastStatus.supportedRates]..sort();
    if (rates.isNotEmpty) {
      return rates.firstWhere((r) => r >= 48000, orElse: () => rates.last);
    }
    return 48000;
  }

  bool get bitPerfectViaDirectStream => _bitPerfectViaDirectStream;

  /// Non-persistent suspend for a track the direct sink cannot carry: the
  /// endpoint is released (the native tee unmutes the HAL, so audio continues
  /// on the normal output path instead of going silent), the saved Bit-Perfect
  /// preference stays, and sink ownership stays claimed so the next supported
  /// track restarts the stream. Contrast with [_rollbackBitPerfectEnable],
  /// which drops the preference when Strict made a promise the track broke.
  Future<bool> suspendDirectBitPerfectForTrack(String reason) =>
      _audioModeMutex.protect(() => _suspendDirectBitPerfectForTrack(reason));

  Future<bool> _suspendDirectBitPerfectForTrack(String reason) async {
    if (!_bitPerfectViaDirectStream) return false;
    _lastDirectUsbFailure = reason;
    final stopped = await UsbExclusiveService().stopStreaming();
    if (!isClosed) {
      safeEmit(state.copyWith(
        errorMessage: stopped
            ? (L10nHolder.current?.directUsbSuspendedArmed(reason) ??
                '$reason Bit-Perfect stays armed and resumes on a supported track.')
            : (L10nHolder.current?.directUsbStopFailedStillOwns(reason) ??
                '$reason The direct USB stream could not be stopped; it still '
                'owns the output. Retry or disable Bit-Perfect.'),
      ));
    }
    await refreshOutputDevice();
    return stopped;
  }

  Future<bool> _stopDirectUsbStreaming() async {
    final stopped = await UsbExclusiveService().stopStreaming();
    if (stopped) _bitPerfectViaDirectStream = false;
    return stopped;
  }

  Future<bool> _teardownBitPerfect() async {
    if (_bitPerfectViaDirectStream) return _stopDirectUsbStreaming();
    return _hiResAudioService.setBitPerfectMode(false);
  }

  Future<void> _rollbackBitPerfectEnable(
    String message, {
    bool? restoreBypass,
    bool? restoreFollowRate,
  }) async {
    final stopped = await _teardownBitPerfect();
    final prefs = await SharedPreferences.getInstance();
    final savedPreBypass = _preStrictBypass ??
        (prefs.containsKey(PrefsKeys.preStrictBypass)
            ? prefs.getBool(PrefsKeys.preStrictBypass)
            : null);
    final savedPreFollow = _preStrictFollowRate ??
        (prefs.containsKey(PrefsKeys.preStrictFollowRate)
            ? prefs.getBool(PrefsKeys.preStrictFollowRate)
            : null);
    final targetBypass = restoreBypass ?? savedPreBypass ?? state.bypassDspOnBitPerfect;
    final targetFollowRate = restoreFollowRate ?? savedPreFollow ?? state.followTrackSampleRate;
    if (stopped) {
      _preStrictBypass = null;
      _preStrictFollowRate = null;
      await prefs.remove(PrefsKeys.preStrictBypass);
      await prefs.remove(PrefsKeys.preStrictFollowRate);
      await prefs.setBool(PrefsKeys.bitPerfectOutput, false);
      await prefs.setBool(PrefsKeys.strictBitPerfect, false);
      await prefs.setBool(PrefsKeys.bypassDspOnBitPerfect, targetBypass);
      await prefs.setBool(PrefsKeys.followTrackSampleRate, targetFollowRate);
      try {
        await _pushBitPerfectBypass(false);
      } catch (e, st) {
        ErrorLogger.log('Bit-perfect rollback could not restore the DSP',
            error: e, stackTrace: st, category: 'SettingsAudioActions');
      }
    }
    // The direct sink is the only component that knows why it refused; without
    // its reason the user sees "not supported" for a DAC that reported a
    // concrete failure (permission, claim, unsupported format).
    final direct = _lastDirectUsbFailure;
    final explained =
        direct == null ? message : '$message Direct USB streaming: $direct.';
    safeEmit(state.copyWith(
      bitPerfectOutput: !stopped,
      strictBitPerfect: !stopped && state.strictBitPerfect,
      bypassDspOnBitPerfect: stopped ? targetBypass : state.bypassDspOnBitPerfect,
      followTrackSampleRate: stopped ? targetFollowRate : state.followTrackSampleRate,
      errorMessage: stopped
          ? explained
          : '$explained Output teardown failed; retry disabling Bit-Perfect.',
    ));
  }

  /// The same owner handles track-format switches and their teardown. A failed
  /// direct switch must never strand a live USB endpoint outside Settings.
  ///
  /// Refusing one track's format is not a reason to leave Bit-Perfect: the
  /// preference is only discarded when Strict Bit-Perfect made a promise this
  /// track cannot keep. Otherwise the mode stays armed and the reason is
  /// surfaced, so the next track can still use it.
  Future<bool> setBitPerfectTrackFormat({
    required int sampleRate,
    required int bitDepth,
    int? channels,
  }) =>
      _audioModeMutex.protect(() async {
        if (!state.bitPerfectOutput) return false;
        final song = getIt.isRegistered<PulsrAudioHandler>()
            ? getIt<PulsrAudioHandler>().currentSong
            : null;
        final sourceDepth = effectiveSourceBitDepth(
          tagged: math.max(song?.bitDepth ?? 0, bitDepth),
          decoded: state.currentOutputDevice?.decodedBitDepth ?? 0,
        );
        if (sourceDepth > 24 && state.currentOutputDevice?.isUsbDac == true &&
            !state.aaudioOutputEnabled) {
          await UsbExclusiveService().getStatus();
        }
        final sourceBlock = AudioConflicts.bitPerfectSourceBlockedReason(
          path: song?.path,
          bitDepth: sourceDepth,
          isRadio: song?.source == SongSource.radio,
          codec: song?.codec,
          integer32DirectUsbEligible: _integer32DirectUsbEligible,
          requireConfirmedCodec: song != null &&
              (state.strictBitPerfect || _bitPerfectViaDirectStream),
        );
        if (sourceBlock != null) {
          if (state.strictBitPerfect) {
            await _rollbackBitPerfectEnable(
              '$sourceBlock, which Strict Bit-Perfect promises to carry unchanged.',
            );
            return false;
          }
          if (_bitPerfectViaDirectStream) {
            await _suspendDirectBitPerfectForTrack(sourceBlock);
            return false;
          }
          if (!isClosed) {
            if (_lastSourceBlockReason != sourceBlock) {
              _lastSourceBlockReason = sourceBlock;
              safeEmit(state.copyWith(errorMessage: sourceBlock));
            }
          }
          await refreshOutputDevice();
          return false;
        }

        var direct = _bitPerfectViaDirectStream;
        bool applied;
        if (!direct && sourceDepth > 24) {
          // The mixer/float pipeline cannot carry integer PCM32 unchanged.
          // Do not claim the raw sink until the previous owner confirms release.
          if (!await _hiResAudioService.setBitPerfectMode(false)) {
            safeEmit(state.copyWith(errorMessage:
                'Mixer output teardown failed; Bit-Perfect still owns the '
                'previous output. Retry or disable Bit-Perfect.'));
            await refreshOutputDevice();
            return false;
          }
          applied = await _tryStartDirectUsbStreaming(
            strict: state.strictBitPerfect,
            sampleRate: sampleRate,
            bitDepth: sourceDepth,
            channels: channels,
          );
          direct = _bitPerfectViaDirectStream;
        } else if (direct) {
          await UsbExclusiveService().resetChannelMismatchFrames();
          final producerChannels = await UsbExclusiveService().getProducerChannels();
          final int effectiveChannels = channels ?? (producerChannels > 0 ? producerChannels : 2);
          final res = await UsbExclusiveService().startStreaming(
            sampleRate: sampleRate,
            channels: effectiveChannels,
            bitDepth: sourceDepth,
            strict: state.strictBitPerfect,
          );
          applied = res.isOk;
          _lastDirectUsbFailure = applied ? null : res.toUserMessage();
        } else {
          applied =
              await _hiResAudioService.setTargetOutputFormat(
                  sampleRate: sampleRate, bitDepth: bitDepth);
        }
        if (applied) {
          _lastDirectUsbFailure = null;
          final wasSourceBlock = _lastSourceBlockReason != null &&
              state.errorMessage == _lastSourceBlockReason;
          _lastSourceBlockReason = null;
          if (wasSourceBlock) {
            safeEmit(state.copyWith(errorMessage: null));
          }
          await refreshOutputDevice();
          return true;
        }
        final detail = _lastDirectUsbFailure;
        final message = 'This output refused $sampleRate Hz / $bitDepth-bit'
            '${detail == null ? '' : ': $detail'}';
        if (state.strictBitPerfect) {
          // Strict promised this track unchanged; the same rule for direct and
          // mixer output. The rollback tears the direct sink down as needed.
          await _rollbackBitPerfectEnable(
              '$message, which Strict Bit-Perfect promises to carry unchanged.');
          return false;
        }
        if (direct) {
          await _suspendDirectBitPerfectForTrack(message);
          return false;
        }
        if (!isClosed) safeEmit(state.copyWith(errorMessage: message));
        await refreshOutputDevice();
        return false;
      });

  Future<void> setReplayGainMode(ReplayGainMode mode) async {
    markDirty('replayGainMode');
    if (mode != ReplayGainMode.off) {
      final blocked = AudioConflicts.replayGainBlockedByBitPerfect(
        bitPerfectOutput: state.bitPerfectOutput,
        bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
        device: state.currentOutputDevice,
        aaudioEnabled: state.aaudioOutputEnabled,
      );
      if (blocked != null) {
        safeEmit(state.copyWith(errorMessage: blocked));
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsCubit._keyReplayGainMode, mode.name);
    // PlayerCubit reacts to this state emission by re-applying the gain. Save
    // first so AudioHandler's cached preferences cannot calculate using the
    // previous mode (which made ReplayGain look enabled but sound unchanged).
    safeEmit(state.copyWith(replayGainMode: mode, errorMessage: null));
  }

  Future<void> setReplayGainPreampWithRg(double db) async {
    markDirty('replayGainPreampWithRg');
    final clamped = db.clamp(-15.0, 15.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(SettingsCubit._keyReplayGainPreampWithRg, clamped);
    safeEmit(state.copyWith(replayGainPreampWithRg: clamped));
  }

  Future<void> setReplayGainPreampWithoutRg(double db) async {
    markDirty('replayGainPreampWithoutRg');
    final clamped = db.clamp(-15.0, 15.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(SettingsCubit._keyReplayGainPreampWithoutRg, clamped);
    safeEmit(state.copyWith(replayGainPreampWithoutRg: clamped));
  }

  Future<void> setStreamingQuality(YtmAudioQuality quality) async {
    markDirty('streamingQuality');
    safeEmit(state.copyWith(streamingQuality: quality));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsCubit._keyStreamingQuality, quality.name);
    await prefs.remove('adaptive_runtime_quality');
  }

  Future<void> setDownloadQuality(YtmAudioQuality quality) async {
    markDirty('downloadQuality');
    safeEmit(state.copyWith(downloadQuality: quality));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsCubit._keyDownloadQuality, quality.name);
  }

  Future<void> setWifiOnlyMode(bool enabled) async {
    markDirty('wifiOnlyMode');
    safeEmit(state.copyWith(wifiOnlyMode: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsCubit._keyWifiOnlyMode, enabled);
  }

  Future<void> setOfflineOnlyMode(bool enabled) async {
    markDirty('offlineOnlyMode');
    safeEmit(state.copyWith(offlineOnlyMode: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsCubit._keyOfflineOnlyMode, enabled);
  }

  /// Crossfade overlaps two tracks and would alter the bitstream, so turning on
  /// a bit-perfect path must clear any active crossfade rather than leaving both
  /// persisted and letting the engine overlap tracks anyway.
  Future<void> _forceCrossfadeOff({required String reason}) async {
    if (getIt.isRegistered<PulsrAudioHandler>()) {
      await getIt<PulsrAudioHandler>().cancelActiveCrossfade();
    }
    if (state.crossfadeSeconds <= 0.01) return;
    markDirty('crossfadeSeconds');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(SettingsCubit._keyCrossfade, 0.0);
    if (isClosed) return;
    safeEmit(state.copyWith(crossfadeSeconds: 0.0, errorMessage: reason));
  }

  Future<void> _forceCrossfadeOffForBitPerfect() => _forceCrossfadeOff(
        reason:
            'Crossfade disabled: it is not compatible with Bit-Perfect output.',
      );

  Future<void> setBitPerfectOutput(bool enabled) =>
      _audioModeMutex.protect(() => _setBitPerfectOutput(enabled));

  Future<void> _setBitPerfectOutput(bool enabled) async {
    markDirty('bitPerfectOutput');
    final prevBypass = state.bypassDspOnBitPerfect;
    final prevFollowRate = state.followTrackSampleRate;
    if (enabled) {
      if (state.currentOutputDevice?.isUsbDac == true && !state.aaudioOutputEnabled) {
        await UsbExclusiveService().getStatus();
      }
      final song = getIt.isRegistered<PulsrAudioHandler>()
          ? getIt<PulsrAudioHandler>().currentSong : null;
      final sourceBlock = AudioConflicts.bitPerfectSourceBlockedReason(
        path: song?.path,
        bitDepth: effectiveSourceBitDepth(tagged: song?.bitDepth ?? 0,
            decoded: state.currentOutputDevice?.decodedBitDepth ?? 0),
        isRadio: song?.source == SongSource.radio,
        codec: song?.codec,
        integer32DirectUsbEligible: _integer32DirectUsbEligible,
        requireConfirmedCodec: state.strictBitPerfect && song != null,
      );
      if (sourceBlock != null) {
        safeEmit(state.copyWith(errorMessage: sourceBlock));
        return;
      }
      final block = AudioConflicts.bitPerfectBlockedReason(
        state.currentOutputDevice,
      );
      if (block != null) {
        safeEmit(state.copyWith(errorMessage: block));
        return;
      }
    }
    // Talk to the platform BEFORE emitting: an optimistic emit made the switch
    // animate ON and immediately snap back OFF whenever the route rejected
    // exclusive mode (e.g. USB DAC on Android < 14).
    final prefs = await SharedPreferences.getInstance();
    if (enabled && _bitPerfectViaDirectStream && !await _stopDirectUsbStreaming()) {
      safeEmit(state.copyWith(errorMessage: L10nHolder.current?.directUsbStreamStopFailedRetry ?? 'Could not stop the previous USB stream. Retry disabling Bit-Perfect.'));
      return;
    }
    var applied = enabled
        ? (!_currentSourceNeedsRawInteger &&
            await _hiResAudioService.setBitPerfectMode(true))
        : await _teardownBitPerfect();
    if (enabled && !applied) applied = await _tryStartDirectUsbStreaming();
    if (enabled && !applied && _bitPerfectViaDirectStream) {
      await _rollbackBitPerfectEnable('Direct USB startup could not be confirmed.', restoreBypass: prevBypass, restoreFollowRate: prevFollowRate);
      return;
    }
    if (!enabled && !applied) {
      safeEmit(state.copyWith(
        errorMessage:
            'The output device could not disable Bit-Perfect. Try again.',
      ));
      await refreshOutputDevice();
      return;
    }
    if (enabled && !applied) {
      // Device rejected bit-perfect (unsupported/route change). Keep the pref
      // and UI off so neither claims bit-perfect output that is not active.
      try {
        await prefs.setBool(PrefsKeys.bitPerfectOutput, false);
        await prefs.setBool(PrefsKeys.strictBitPerfect, false);
        await prefs.setBool(PrefsKeys.bypassDspOnBitPerfect, prevBypass);
        await prefs.setBool(PrefsKeys.followTrackSampleRate, prevFollowRate);
        await _pushBitPerfectBypass(false);
      } catch (_) {}
      if (!isClosed) {
        final reason = _hiResAudioService.lastBitPerfectFailureReason;
        final base = AudioConflicts.bitPerfectReasonMessage(reason) ??
            'Bit-Perfect output is not supported by the current output device.';
        final directHint = _lastDirectUsbFailure == null
            ? ''
            : ' Direct USB streaming also failed: $_lastDirectUsbFailure.';
        safeEmit(state.copyWith(
          bitPerfectOutput: false,
          strictBitPerfect: false,
          bypassDspOnBitPerfect: prevBypass,
          followTrackSampleRate: prevFollowRate,
          errorMessage: '$base$directHint',
        ));
      }
      await refreshOutputDevice();
      return;
    }
    try {
      await _pushBitPerfectBypass(enabled &&
          (state.bypassDspOnBitPerfect || state.strictBitPerfect));
      if (enabled) await _forceCrossfadeOffForBitPerfect();
    } catch (e, st) {
      ErrorLogger.log('Bit-perfect DSP transition failed',
          error: e, stackTrace: st, category: 'SettingsAudioActions');
      final refusal = _bypassUpdateFailedMessage();
      if (enabled) {
        // The rollback emits its own message (including a failed teardown);
        // passing the refusal wording in keeps that detail and the platform
        // reason, instead of overwriting both with a generic line afterwards.
        await _rollbackBitPerfectEnable(refusal, restoreBypass: prevBypass, restoreFollowRate: prevFollowRate);
      } else {
        // The transport is already down; do not resurrect it after a failed
        // DSP restore. Keep the UI truthful and allow a subsequent retry.
        await prefs.setBool(PrefsKeys.bitPerfectOutput, false);
        await prefs.setBool(PrefsKeys.strictBitPerfect, false);
        safeEmit(state.copyWith(
          bitPerfectOutput: false,
          strictBitPerfect: false,
          errorMessage: refusal,
        ));
      }
      await refreshOutputDevice();
      return;
    }
    // Transport reconciliation is performed by _pushBitPerfectBypass on every
    // transition, including strict and bypass changes; saved choices survive.
    await prefs.setBool(PrefsKeys.bitPerfectOutput, enabled);
    if (!enabled) {
      markDirty('strictBitPerfect');
      await prefs.setBool(PrefsKeys.strictBitPerfect, false);
    }
    if (!isClosed) {
      safeEmit(
        state.copyWith(
          bitPerfectOutput: enabled,
          strictBitPerfect: enabled && state.strictBitPerfect,
          errorMessage: null,
        ),
      );
    }
    if (enabled && _bitPerfectViaDirectStream) {
      await setFollowTrackSampleRate(true);
    }
    // Wire bypass: when bit-perfect enabled and user wants bypass, force DSP off via native
    if (enabled && state.bypassDspOnBitPerfect) {
      // Also force ReplayGain off — software gain breaks bit-perfect
      if (state.replayGainMode != ReplayGainMode.off) {
        await prefs.setString(
            SettingsCubit._keyReplayGainMode, ReplayGainMode.off.name);
        safeEmit(
          state.copyWith(
            replayGainMode: ReplayGainMode.off,
            errorMessage:
                'ReplayGain disabled: not compatible with Bit-Perfect bypass.',
          ),
        );
      }
    }
    await refreshOutputDevice();
  }

  Future<void> setBypassDspOnBitPerfect(bool enabled) =>
      _audioModeMutex.protect(() => _setBypassDspOnBitPerfect(enabled));

  Future<void> _setBypassDspOnBitPerfect(bool enabled) async {
    if (!enabled && state.strictBitPerfect) {
      safeEmit(state.copyWith(
        errorMessage:
            'Disable Strict Bit-Perfect before enabling DSP processing.',
      ));
      return;
    }
    if (state.bitPerfectOutput) {
      try {
        await _pushBitPerfectBypass(enabled);
      } catch (_) {
        safeEmit(state.copyWith(errorMessage: _bypassUpdateFailedMessage()));
        return;
      }
    }
    markDirty('bypassDspOnBitPerfect');
    safeEmit(state.copyWith(bypassDspOnBitPerfect: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.bypassDspOnBitPerfect, enabled);
    await refreshOutputDevice();
  }

  Future<void> loadMqaDecodingPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      SettingsCubit.mqaEnabledCache =
          prefs.getBool(PrefsKeys.mqaDecodingEnabled) ?? true;
    } catch (e, st) {
      ErrorLogger.log('MQA preference load failed',
          error: e, stackTrace: st, category: 'Settings');
    }
    MqaDecoderHelper.isMqaEnabled = () => SettingsCubit.mqaEnabledCache;
  }

  Future<void> setMqaDecodingEnabled(bool enabled) async {
    SettingsCubit.mqaEnabledCache = enabled;
    MqaDecoderHelper.isMqaEnabled = () => SettingsCubit.mqaEnabledCache;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.mqaDecodingEnabled, enabled);
    } catch (e, st) {
      ErrorLogger.log('MQA preference save failed',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  /// T2: follow the current track's native sample rate on every track change.
  /// The actual native call happens in PlayerCubit (it owns the track-change
  /// stream and the de-dupe state); this only persists the preference.
  Future<void> setFollowTrackSampleRate(bool value) async {
    if (!value && state.strictBitPerfect) {
      safeEmit(state.copyWith(
        errorMessage:
            'Strict Bit-Perfect requires following the track sample rate.',
      ));
      return;
    }
    markDirty('followTrackSampleRate');
    safeEmit(state.copyWith(followTrackSampleRate: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.followTrackSampleRate, value);
  }

  /// T4: select the DSD (DSF/DFF) output transport.
  ///
  /// Refuses DoP unless the native probe has confirmed a compatible USB DAC, so
  /// the persisted preference can never claim native DSD on a path that cannot
  /// carry it. PCM is always allowed and is the default.
  Future<void> setDsdOutputMode(DsdOutputMode mode) async {
    markDirty('dsdOutputMode');
    if (mode == DsdOutputMode.dop && !state.dsdDopSupported) {
      safeEmit(state.copyWith(
        errorMessage:
            'DoP output requires a connected USB DAC that supports DSD over PCM.',
      ));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.dsdOutputMode, mode.name);
    safeEmit(state.copyWith(dsdOutputMode: mode, errorMessage: null));
  }

  /// T3: strict bit-perfect (no resample). Enabling forces Bit-Perfect output,
  /// the DSP bypass and follow-track, then surfaces the conflict reason rather
  /// than silently muting stages. Disabled when the path cannot do bit-perfect.
  Future<void> setStrictBitPerfect(bool enabled) =>
      _audioModeMutex.protect(() => _setStrictBitPerfect(enabled));

  Future<void> _setStrictBitPerfect(bool enabled) async {
    markDirty('strictBitPerfect');
    markDirty('bitPerfectOutput');
    markDirty('bypassDspOnBitPerfect');
    markDirty('followTrackSampleRate');
    // FIX-C01: Capture the pre-call configuration so a refusal can put it back
    // instead of switching features the user never asked to disable.
    final prevBitPerfect = state.bitPerfectOutput;
    final prevBypass = state.bypassDspOnBitPerfect;
    final prevFollowRate = state.followTrackSampleRate;
    if (enabled) {
      if (state.currentOutputDevice?.isUsbDac == true && !state.aaudioOutputEnabled) {
        await UsbExclusiveService().getStatus();
      }
      final song = getIt.isRegistered<PulsrAudioHandler>()
          ? getIt<PulsrAudioHandler>().currentSong : null;
      final sourceBlock = AudioConflicts.bitPerfectSourceBlockedReason(
        path: song?.path,
        bitDepth: effectiveSourceBitDepth(tagged: song?.bitDepth ?? 0,
            decoded: state.currentOutputDevice?.decodedBitDepth ?? 0),
        isRadio: song?.source == SongSource.radio,
        codec: song?.codec,
        integer32DirectUsbEligible: _integer32DirectUsbEligible,
        requireConfirmedCodec: song != null,
      );
      final effectiveRate = effectiveSourceSampleRate(
        tagged: song?.sampleRate ?? 0,
        decoded: state.currentOutputDevice?.decodedSampleRate ?? 0,
      );
      final unknownRate = song != null && (effectiveRate <= 0 ||
          !HiResAudioService.validTargetSampleRates.contains(effectiveRate));
      if (sourceBlock != null || unknownRate) {
        safeEmit(state.copyWith(errorMessage:
            sourceBlock ?? 'Source sample rate is unconfirmed.'));
        return;
      }
      final block = AudioConflicts.strictBitPerfectBlockedReason(
        state.currentOutputDevice,
      );
      if (block != null) {
        safeEmit(state.copyWith(errorMessage: block));
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    if (!enabled) {
      await prefs.setBool(PrefsKeys.strictBitPerfect, false);
      final restoreBypass = _preStrictBypass ??
          (prefs.containsKey(PrefsKeys.preStrictBypass)
              ? prefs.getBool(PrefsKeys.preStrictBypass)
              : null);
      final restoreFollowRate = _preStrictFollowRate ??
          (prefs.containsKey(PrefsKeys.preStrictFollowRate)
              ? prefs.getBool(PrefsKeys.preStrictFollowRate)
              : null);
      _preStrictBypass = null;
      _preStrictFollowRate = null;
      await prefs.remove(PrefsKeys.preStrictBypass);
      await prefs.remove(PrefsKeys.preStrictFollowRate);
      if (restoreBypass != null && restoreFollowRate != null) {
        // Restore bypass and follow-rate to what they were before Strict was
        // enabled. Without this, the user's EQ/ReplayGain/Crossfade remain muted
        // even after they turn Strict off, because bypassDspOnBitPerfect is left
        // as `true` from the Strict enable path.
        await prefs.setBool(PrefsKeys.bypassDspOnBitPerfect, restoreBypass);
        await prefs.setBool(PrefsKeys.followTrackSampleRate, restoreFollowRate);
        final targetBypass = state.bitPerfectOutput && restoreBypass;
        // Only push a real change. Re-sending the value the native chain
        // already holds rebuilds the processing chain for nothing, and Strict
        // OFF commonly restores `true` while the chain is already bypassed.
        if (targetBypass != state.bypassDspOnBitPerfect) {
          await _pushBitPerfectBypass(targetBypass);
        }
        safeEmit(state.copyWith(
          strictBitPerfect: false,
          bypassDspOnBitPerfect: restoreBypass,
          followTrackSampleRate: restoreFollowRate,
          errorMessage: null,
        ));
      } else {
        safeEmit(state.copyWith(
          strictBitPerfect: false,
          errorMessage: null,
        ));
      }
      await refreshOutputDevice();
      return;
    }
    // Confirm with the platform BEFORE emitting: the old optimistic emit made
    // the strict switch animate ON and snap back OFF whenever exclusive mode
    // was refused.
    if (_bitPerfectViaDirectStream && !await _stopDirectUsbStreaming()) {
      safeEmit(state.copyWith(errorMessage: L10nHolder.current?.directUsbStreamStopFailed ?? 'Could not stop the previous USB stream.'));
      return;
    }
    // Preserve decoder precision before opening either Media3/USB tee or AAudio.
    if (!state.floatOutputEnabled) await setFloatOutputEnabled(true);
    var applied = !_currentSourceNeedsRawInteger &&
        await _hiResAudioService.setBitPerfectMode(true);
    if (!applied) applied = await _tryStartDirectUsbStreaming(strict: true);
    if (!applied && _bitPerfectViaDirectStream) {
      await _rollbackBitPerfectEnable('Direct USB startup could not be confirmed.', restoreBypass: prevBypass, restoreFollowRate: prevFollowRate);
      return;
    }
    if (!applied) {
      // Strict bit-perfect is impossible on this device; revert rather than
      // persist a configuration the hardware cannot honour. The revert restores
      // what the user had: forcing Bit-Perfect and the DSP bypass off as well
      // discarded a working exclusive setup just because Strict was refused.
      try {
        await prefs.setBool(PrefsKeys.strictBitPerfect, false);
        await prefs.setBool(PrefsKeys.bitPerfectOutput, prevBitPerfect);
        await prefs.setBool(PrefsKeys.bypassDspOnBitPerfect, prevBypass);
        await prefs.setBool(PrefsKeys.followTrackSampleRate, prevFollowRate);
        await _pushBitPerfectBypass(prevBitPerfect && prevBypass);
      } catch (e, st) {
        ErrorLogger.log('Failed to persist strict bit-perfect revert',
            error: e, stackTrace: st, category: 'Settings');
      }
      if (!isClosed) {
        final reason = _hiResAudioService.lastBitPerfectFailureReason;
        final base = AudioConflicts.bitPerfectReasonMessage(reason) ??
            (L10nHolder.current?.strictBitPerfectUnsupportedDevice ?? 'Strict Bit-Perfect is not supported by the current output device.');
        final directHint = _lastDirectUsbFailure == null
            ? ''
            : ' Direct USB streaming also failed: $_lastDirectUsbFailure.';
        safeEmit(state.copyWith(
          strictBitPerfect: false,
          bitPerfectOutput: prevBitPerfect,
          bypassDspOnBitPerfect: prevBypass,
          followTrackSampleRate: prevFollowRate,
          errorMessage: '$base$directHint',
        ));
      }
      await refreshOutputDevice();
      return;
    }
    try {
      await _pushBitPerfectBypass(true);
      await _forceCrossfadeOffForBitPerfect();
    } catch (_) {
      await _rollbackBitPerfectEnable(
        L10nHolder.current?.dspBypassOrCrossfadeDisableFailed ?? 'Failed to enable the native DSP bypass or disable crossfade.',
        restoreBypass: prevBypass,
        restoreFollowRate: prevFollowRate,
      );
      await refreshOutputDevice();
      return;
    }
    // Only capture pre-Strict values if they are not already set (prevents double-enable overwrite and survives restarts)
    final bool hasPersistedBypass = prefs.containsKey(PrefsKeys.preStrictBypass);
    final bool hasPersistedFollow = prefs.containsKey(PrefsKeys.preStrictFollowRate);
    if (_preStrictBypass == null && !hasPersistedBypass) {
      _preStrictBypass = prevBypass;
      await prefs.setBool(PrefsKeys.preStrictBypass, prevBypass);
    } else if (_preStrictBypass == null && hasPersistedBypass) {
      _preStrictBypass = prefs.getBool(PrefsKeys.preStrictBypass);
    }
    if (_preStrictFollowRate == null && !hasPersistedFollow) {
      _preStrictFollowRate = prevFollowRate;
      await prefs.setBool(PrefsKeys.preStrictFollowRate, prevFollowRate);
    } else if (_preStrictFollowRate == null && hasPersistedFollow) {
      _preStrictFollowRate = prefs.getBool(PrefsKeys.preStrictFollowRate);
    }
    await prefs.setBool(PrefsKeys.strictBitPerfect, true);
    await prefs.setBool(PrefsKeys.bitPerfectOutput, true);
    await prefs.setBool(PrefsKeys.bypassDspOnBitPerfect, true);
    await prefs.setBool(PrefsKeys.followTrackSampleRate, true);
    if (!isClosed) {
      safeEmit(state.copyWith(
        strictBitPerfect: true,
        bitPerfectOutput: true,
        bypassDspOnBitPerfect: true,
        followTrackSampleRate: true,
        errorMessage: null,
      ));
    }
    // Software gain would alter the bitstream; turn it off like the normal
    // Bit-Perfect path does.
    if (state.replayGainMode != ReplayGainMode.off) {
      await prefs.setString(
          SettingsCubit._keyReplayGainMode, ReplayGainMode.off.name);
      if (!isClosed) {
        safeEmit(state.copyWith(replayGainMode: ReplayGainMode.off));
      }
    }
    await refreshOutputDevice();
  }

  /// Requests an app media route and reads back the outcome while playing.
  ///
  /// On retail builds the platform lacks [MODIFY_AUDIO_ROUTING] and signals
  /// this via [OutputRouteResult.requiresSystemPicker]. In that case we
  /// automatically open the system media-output switcher so the user can
  /// complete the route change, and return `true` so the caller does not also
  /// show a "switch unavailable" snackbar.
  Future<bool> selectOutputDevice(int deviceId) =>
      _audioModeMutex.protect(() async {
        final wasDirect = _bitPerfectViaDirectStream;
        final wasBitPerfect = state.bitPerfectOutput || wasDirect;

        // The direct sink owns the USB endpoint and mutes the HAL. Stop it
        // before changing routes, otherwise the HAL stays silent or the sink
        // keeps writing to the old DAC. Only a confirmed stop releases
        // ownership: clearing the flag after a failed one would strand a live
        // endpoint nobody can tear down.
        if (wasDirect && !await _stopDirectUsbStreaming()) {
          safeEmit(state.copyWith(
            errorMessage: L10nHolder.current?.directUsbSinkSwitchOwnershipFailed ??
                'The direct USB stream could not be stopped; the output was not switched and Bit-Perfect still owns the previous DAC output.',
          ));
          return false;
        }

        final res = await _hiResAudioService.selectOutputDevice(deviceId);
        if (res.requiresSystemPicker) {
          // Retail ROM: direct routing is restricted. Hand off to the system
          // media-output panel which the user can operate without special
          // permissions. Return true so the sheet does not show an error snackbar.
          if (wasBitPerfect) await _setBitPerfectOutput(false);
          await _hiResAudioService.openOutputSwitcher();
          await refreshOutputDevice();
          return true;
        }
        if (!res.success) {
          if (wasBitPerfect) {
            await refreshOutputDevice();
            if (state.currentOutputDevice?.isUsbDac == true) {
              await _setBitPerfectOutput(true);
            } else {
              await _setBitPerfectOutput(false);
            }
          }
          safeEmit(state.copyWith(
              errorMessage:
                  'Could not switch the playback output (${res.error ?? "unavailable"}).'));
          await refreshOutputDevice();
          return false;
        }

        await refreshOutputDevice();
        if (wasBitPerfect) {
          final routeIsUsb = state.currentOutputDevice?.isUsbDac == true;
          // Re-establish exclusive/direct output on the new USB route; turn the
          // saved preference off when the route is no longer a DAC.
          await _setBitPerfectOutput(routeIsUsb);
        }
        return res.success;
      });

  Future<bool> openOutputSwitcher() => _hiResAudioService.openOutputSwitcher();

  Future<void> clearOutputDevice() => _audioModeMutex.protect(() async {
        if (state.bitPerfectOutput || _bitPerfectViaDirectStream) {
          await _setBitPerfectOutput(false);
        }
        await _hiResAudioService.clearOutputDevice();
        await refreshOutputDevice();
      });

  Future<void> setTargetOutputSampleRate(int sampleRate) =>
      _audioModeMutex.protect(() async {
        final applied = await _hiResAudioService.setTargetOutputFormat(
          sampleRate: sampleRate,
          bitDepth: state.currentOutputDevice?.targetBitDepth ?? 0,
        );
        if (applied) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('target_output_sample_rate', sampleRate);
        } else {
          safeEmit(state.copyWith(
              errorMessage: L10nHolder.current?.outputCannotApplySampleRate ?? 'This output cannot apply the requested sample rate.'));
        }
        await refreshOutputDevice();
      });

  Future<void> setTargetOutputBitDepth(int bitDepth) =>
      _audioModeMutex.protect(() async {
        final applied = await _hiResAudioService.setTargetOutputFormat(
          sampleRate: state.currentOutputDevice?.targetSampleRate ?? 0,
          bitDepth: bitDepth,
        );
        if (applied) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('target_output_bit_depth', bitDepth);
        } else {
          safeEmit(state.copyWith(
              errorMessage: L10nHolder.current?.outputCannotApplyBitDepth ?? 'This output cannot apply the requested bit depth.'));
        }
        await refreshOutputDevice();
      });

  /// Returns true when the platform accepted the request; false means the
  /// stock ROM refused it (SystemApi) — caller must offer Developer Options.
  Future<bool> setBluetoothCodec(String codec) async {
    // Optimistic UI: update btCodecName immediately
    final ok = await _hiResAudioService.setBluetoothCodec(codec);
    await refreshOutputDevice();
    return ok;
  }

  Future<bool> setBluetoothSampleRate(int hz) async {
    final ok = await _hiResAudioService.setBluetoothSampleRate(hz);
    await refreshOutputDevice();
    return ok;
  }

  Future<bool> setBluetoothBitDepth(int bits) async {
    final ok = await _hiResAudioService.setBluetoothBitDepth(bits);
    await refreshOutputDevice();
    return ok;
  }

  Future<bool> setBluetoothLdacQuality(int mode) async {
    final ok = await _hiResAudioService.setBluetoothLdacQuality(mode);
    await refreshOutputDevice();
    return ok;
  }

  /// Triggers a runtime BLUETOOTH_CONNECT permission request (Android 12+).
  /// Falls back to opening app settings if already permanently denied.
  Future<void> requestBluetoothPermission() async {
    await _hiResAudioService.requestBluetoothPermission();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await refreshOutputDevice();
  }

  /// Opens Android Developer Options directly to the Bluetooth Audio Codec page.
  Future<void> openBluetoothDevOptions() async {
    await _hiResAudioService.openBluetoothDevOptions();
  }

  /// Opens the platform screen where the Bluetooth audio codec can be changed
  /// (Bluetooth settings first, then Developer Options). Retail builds cannot
  /// write the codec directly, so this is the sanctioned deep-link.
  Future<bool> openBluetoothCodecSettings() async {
    final opened = await _hiResAudioService.openBluetoothCodecSettings();
    if (!opened) {
      safeEmit(state.copyWith(
          errorMessage: L10nHolder.current?.cannotOpenBluetoothCodecSettings ?? 'Could not open Bluetooth codec settings.'));
    }
    return opened;
  }

  /// Opt-in Bluetooth Hi-Res (best-effort). Bluetooth is a lossy codec link, so
  /// this can never be bit-perfect; it stops the app from making the link worse:
  ///   * item 1 - keeps the float DSP path on so 24/32-bit samples are not
  ///     truncated to 16-bit in-app before the codec encoder;
  ///   * item 5 - permits the native TPDF dither stage on BT at the codec depth;
  ///   * item 3 - the per-track codec-rate alignment is driven by the player
  ///     (see PlayerDspController.maybeFollowTrackSampleRate).
  Future<void> setBluetoothHiResEnabled(bool enabled) async {
    markDirty('bluetoothHiResEnabled');
    safeEmit(state.copyWith(bluetoothHiResEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.bluetoothHiResEnabled, enabled);
    // Item 1: never truncate to 16-bit before the codec encoder.
    if (enabled && !state.floatOutputEnabled) {
      await setFloatOutputEnabled(true);
    }
    // Item 5: mirror the dither-on-BT permission into the effects layer so every
    // later dither push (and route resync) carries it.
    if (getIt.isRegistered<EqualizerManager>()) {
      final eq = getIt<EqualizerManager>();
      eq.isBluetoothDitherEnabled = enabled;
      if (eq.isDitherEnabled) {
        await eq.setDither(true, allowBluetoothDither: enabled);
      }
    }
  }

  /// Probes the native DoP capability and stores the single [dop] gate in state.
  /// Used by the device-change listener; [refreshOutputDevice] folds the same
  /// probe into its emit.
  Future<void> _refreshDopSupport() async {
    final caps = await DsdDecoderHelper.probeDopCapabilities();
    if (isClosed) return;
    if (state.dsdDopSupported != caps.canUseDop) {
      safeEmit(state.copyWith(dsdDopSupported: caps.canUseDop));
    }
  }

  /// Monotonic refresh ticket. The platform answers asynchronously, so two
  /// overlapping refreshes (route change + player observer) can complete out of
  /// order; only the newest one may write state.
  int _refreshOutputSeq = 0;

  Future<void> refreshOutputDevice() async {
    final seq = ++_refreshOutputSeq;
    // FIX-C02: Guard against native crash or unhandled exception during device/DOP refresh
    try {
      var info = await _hiResAudioService.getAudioOutputInfo();
      final caps = await DsdDecoderHelper.probeDopCapabilities();
      if (isClosed || seq != _refreshOutputSeq) return;
      if (_bitPerfectViaDirectStream &&
          _lastDirectUsbFailure != null &&
          !info.isBitPerfectActive) {
        info = info.copyWith(bitPerfectFailureReason: _lastDirectUsbFailure);
      }
      safeEmit(
        state.copyWith(
          currentOutputDevice: info,
          dsdDopSupported: caps.canUseDop,
        ),
      );
      await _syncTapSrcRate(info);
    } catch (e, st) {
      ErrorLogger.log('Failed to refresh output device or probe DoP',
          error: e, stackTrace: st, category: 'Settings');
      return;
    }
  }

  /// Keeps the tap-side SRC target on the route's mixer rate.
  ///
  /// This is what stops AudioFlinger from resampling the *finished* DSP: with a
  /// target set, the PCM tap converts to the mixer rate at Ultra quality ahead
  /// of the chain, so the mixer becomes a 1:1 copy. A route whose rate cannot be
  /// verified keeps the historical platform path; this never throws.
  Future<void> _syncTapSrcRate(AudioOutputInfo? info) async {
    if (!getIt.isRegistered<PulsrAudioHandler>()) return;
    final rate = decideTapSrcTargetRate(
      enabled: state.outputFormatNegotiationEnabled,
      // PROPERTY_OUTPUT_SAMPLE_RATE describes the primary output, not the
      // current USB/BT route. Only a live route-specific sink is usable here.
      nativeSampleRate: info?.availableDevices.any((d) => d.isCurrent) == true
          ? (info?.sampleRate ?? 0) : 0,
      bitPerfectActive: info?.isBitPerfectActive ?? false,
      isBluetooth: info?.isBluetooth ?? false,
      deviceSampleRates: info?.supportedSampleRates ?? const <int>[],
    );
    if (rate == _lastTapSrcTargetRate) return;
    _lastTapSrcTargetRate = rate;
    try {
      await getIt<PulsrAudioHandler>().setTapSrcRate(rate);
    } catch (e, st) {
      _lastTapSrcTargetRate = null;
      ErrorLogger.log('Failed to sync tap-side SRC rate ($rate)',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  Future<void> setDspPreference(String preference) async {
    markDirty('dspPreference');
    safeEmit(state.copyWith(dspPreference: preference));
    // EqualizerManager is the single writer for effect keys (including
    // dspPreference). Only persist directly when it is unavailable.
    if (getIt.isRegistered<EqualizerManager>()) {
      await getIt<EqualizerManager>().setDspPreference(preference);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsCubit._keyDspPreference, preference);
    await AudioEffectsChannel().setDspPreference(preference);
  }

  Future<void> setLookaheadLimiter(
    bool enabled, {
    double? thresholdDb,
    double? releaseMs,
    double? lookaheadMs,
  }) async {
    markDirty('limiterEnabled');
    markDirty('limiterThresholdDb');
    markDirty('limiterReleaseMs');
    markDirty('limiterLookaheadMs');
    final newEnabled = enabled;
    final newThreshold = thresholdDb ?? state.limiterThresholdDb;
    final newRelease = releaseMs ?? state.limiterReleaseMs;
    final newLookahead = lookaheadMs ?? state.limiterLookaheadMs;
    safeEmit(
      state.copyWith(
        limiterEnabled: newEnabled,
        limiterThresholdDb: newThreshold,
        limiterReleaseMs: newRelease,
        limiterLookaheadMs: newLookahead,
      ),
    );
    // EqualizerManager owns the limiter keys + persistence; delegating keeps
    // a single writer so this screen cannot diverge from the effect engine.
    if (getIt.isRegistered<EqualizerManager>()) {
      await getIt<EqualizerManager>().setLookaheadLimiter(
        newEnabled,
        thresholdDb: newThreshold,
        releaseMs: newRelease,
        lookaheadMs: newLookahead,
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.lookaheadLimiterEnabled, newEnabled);
    await prefs.setDouble(PrefsKeys.lookaheadLimiterThresholdDb, newThreshold);
    await prefs.setDouble(PrefsKeys.lookaheadLimiterReleaseMs, newRelease);
    await prefs.setDouble(
      'setting_lookahead_limiter_lookahead_ms',
      newLookahead,
    );
    await AudioEffectsChannel().setLimiterParams(
      newLookahead,
      newThreshold,
      newRelease,
    );
    await AudioEffectsChannel().setLimiterEnabled(newEnabled);
  }

  Future<void> setSystemEffectsPolicy(String policy) async {
    markDirty('systemEffectsPolicy');
    safeEmit(state.copyWith(systemEffectsPolicy: policy));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.systemEffectsPolicy, policy);
    try {
      final status = await AudioEffectsChannel().setSystemEffectsPolicy(
        policy,
        isHiResOrBitPerfect: state.bitPerfectOutput,
      );
      if (!isClosed) {
        safeEmit(state.copyWith(systemEffectsStatus: status));
      }
    } catch (_) {}
  }

  Future<void> refreshSystemEffectsStatus() async {
    try {
      final result = await AudioEffectsChannel().detectSystemEffects();
      final status = result['status'] as String? ?? 'unknown';
      final bundles =
          (result['detectedBundles'] as List<dynamic>?)?.cast<String>() ?? [];
      if (!isClosed) {
        safeEmit(state.copyWith(
          systemEffectsStatus: status,
          systemEffectsBundles: bundles,
        ));
      }
    } catch (_) {}
  }

  Future<void> setBluetoothLatencyOffsetMs(int offsetMs) async {
    markDirty('bluetoothLatencyOffsetMs');
    final clamped = offsetMs.clamp(0, 500);
    safeEmit(state.copyWith(bluetoothLatencyOffsetMs: clamped));
    final device = state.currentOutputDevice;
    if (device != null && device.isBluetooth) {
      _lastBtLatencyDeviceKey = DeviceProfileService.deviceKeyFromInfo(device);
      await _deviceProfileService.rememberBtLatency(
          _lastBtLatencyDeviceKey!, clamped);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(PrefsKeys.bluetoothLatencyOffsetMs, clamped);
    }
  }

  String? _lastBtLatencyDeviceKey;

  DeviceProfileService get _deviceProfileService =>
      getIt.isRegistered<DeviceProfileService>()
          ? getIt<DeviceProfileService>()
          : DeviceProfileService();

  /// Restores the latency calibrated for this specific Bluetooth device when
  /// it becomes the active output. Devices never calibrated fall back to the
  /// globally stored offset — the value the slider writes — instead of keeping
  /// whatever was auto-applied for the device that was active before, which
  /// leaked one headset's compensation into another's timing.
  Future<void> _applyPerDeviceBtLatency(AudioOutputInfo device) async {
    if (!device.isBluetooth) return;
    final key = DeviceProfileService.deviceKeyFromInfo(device);
    if (key == _lastBtLatencyDeviceKey) return;
    _lastBtLatencyDeviceKey = key;
    final saved = await _deviceProfileService.btLatencyFor(key);
    if (isClosed) return;
    final target = saved ??
        (await SharedPreferences.getInstance())
            .getInt(PrefsKeys.bluetoothLatencyOffsetMs);
    if (target == null) return;
    final clamped = target.clamp(0, 500);
    if (clamped == state.bluetoothLatencyOffsetMs) return;
    safeEmit(state.copyWith(bluetoothLatencyOffsetMs: clamped));
  }

  /// Toggles per-session audio telemetry. The logger reads this flag on every
  /// call, so disabling takes effect immediately with no re-wiring.
  Future<void> setSessionLogEnabled(bool enabled) async {
    markDirty('sessionLogEnabled');
    safeEmit(state.copyWith(sessionLogEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.audioSessionLogEnabled, enabled);
  }

  /// Per-track output-format negotiation, on by default. Also the gate for
  /// tap-side SRC: with it on, a track whose rate the mixer will not run at is
  /// converted in-app ahead of the DSP chain instead of by AudioFlinger after
  /// it, so turning this off restores the platform-resample path entirely.
  Future<void> setOutputFormatNegotiationEnabled(bool enabled) async {
    markDirty('outputFormatNegotiationEnabled');
    safeEmit(state.copyWith(outputFormatNegotiationEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.outputFormatNegotiationEnabled, enabled);
    await _syncTapSrcRate(state.currentOutputDevice);
  }

  /// Opt-in AAudio Direct output (bit-perfect; the DSP processor chain is
  /// bypassed). Persisted here and pushed to every player by the player
  /// layer; takes effect for newly built sinks.
  Future<void> setAaudioOutputEnabled(bool enabled) =>
      _audioModeMutex.protect(() => _setAaudioOutputEnabled(enabled));

  Future<void> _setAaudioOutputEnabled(bool enabled) async {
    markDirty('aaudioOutputEnabled');
    if (enabled) {
      // AAudio Direct bypasses the ExoPlayer DSP chain the direct-USB
      // Bit-Perfect tee lives in; enabling it would silence the DAC.
      if (_bitPerfectViaDirectStream) {
        safeEmit(state.copyWith(
            errorMessage:
                'Turn off Bit-Perfect before enabling AAudio Direct.'));
        return;
      }
    }
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        final applied = await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
          enabled,
          preferExclusive: state.aaudioPreferExclusive,
          targetBufferMs: state.aaudioTargetBufferMs,
        );
        if (!applied) {
          await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
            state.aaudioOutputEnabled,
            preferExclusive: state.aaudioPreferExclusive,
            targetBufferMs: state.aaudioTargetBufferMs,
          );
          safeEmit(state.copyWith(
              errorMessage:
                  'AAudio output was rejected by a playback player.'));
          return;
        }
      }
    } catch (e) {
      safeEmit(
          state.copyWith(errorMessage: 'Failed to change AAudio output: $e'));
      return;
    }
    // Only after every player accepted the change: turning crossfade and DVC
    // off beforehand discarded settings for a mode that never came on.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.aaudioOutputEnabled, enabled);
    safeEmit(state.copyWith(aaudioOutputEnabled: enabled, errorMessage: null));
    if (enabled) {
      await _forceCrossfadeOff(
          reason: 'Crossfade disabled: AAudio Direct bypasses the DSP chain it '
              'is applied in.');
      if (state.dvcEnabled) await setDvcEnabled(false);
    }
  }

  /// Opt-in Direct Volume Control (DVC). Pins the Android media stream to
  /// maximum and applies the composed output gain in the native float DSP path.
  /// Unavailable on non-Android and while Bit-Perfect bypass is active.
  Future<void> setDvcEnabled(bool enabled) async {
    if (enabled &&
        (state.aaudioOutputEnabled ||
            (state.bitPerfectOutput && state.bypassDspOnBitPerfect))) {
      safeEmit(state.copyWith(
          errorMessage:
              'Direct Volume Control requires the active DSP output path.'));
      return;
    }
    markDirty('dvcEnabled');
    safeEmit(state.copyWith(dvcEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.dvcEnabled, enabled);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setDvcEnabled(enabled);
      }
    } catch (_) {
      // Player not available yet; boot/observer push covers it.
    }
  }

  Future<bool> setUsbHardwareVolumeEnabled(bool enabled) async {
    markDirty('usbHardwareVolumeEnabled');
    try {
      safeEmit(state.copyWith(usbHardwareVolumeEnabled: enabled));
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(PrefsKeys.usbHardwareVolumeEnabled, enabled);
    } catch (_) {
      return false;
    }
  }

  /// Resampler quality (0=Fast/linear, 1=Standard, 2=High, 3=Ultra).
  Future<void> setSincResamplerQuality(int quality) async {
    if (!AudioEffectsChannel().isPlaybackSincResamplerSupported) return;
    markDirty('sincResamplerQuality');
    final clamped = quality.clamp(0, 3);
    safeEmit(state.copyWith(sincResamplerQuality: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.sincResamplerQuality, clamped);
    await AudioEffectsChannel().setSincResamplerQuality(clamped);
  }

  /// BPM-synced crossfade toggle. Pushed straight to the crossfade manager.
  Future<void> setBpmSyncCrossfadeEnabled(bool enabled) async {
    markDirty('bpmSyncCrossfadeEnabled');
    safeEmit(state.copyWith(bpmSyncCrossfadeEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.bpmSyncCrossfadeEnabled, enabled);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setBpmSyncCrossfadeEnabled(enabled);
      }
    } catch (_) {
      // Player not available yet; boot restore covers it.
    }
  }

  /// Automix / Smart Transitions toggle. Pushed straight to the crossfade manager.
  Future<void> setAutomixEnabled(bool enabled) async {
    markDirty('automixEnabled');
    safeEmit(state.copyWith(automixEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.automixEnabled, enabled);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setAutomixEnabled(enabled);
      }
    } catch (_) {
      // Player not available yet; boot restore covers it.
    }
  }

  /// Whether the AAudio stream should attempt EXCLUSIVE sharing first.
  ///
  /// Serialized with [setAaudioOutputEnabled] and reading the enabled flag
  /// inside that lock: pushing the value the state held *before* an in-flight
  /// toggle would undo it.
  Future<void> setAaudioPreferExclusive(bool value) =>
      _audioModeMutex.protect(() async {
        markDirty('aaudioPreferExclusive');
        safeEmit(state.copyWith(aaudioPreferExclusive: value));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(PrefsKeys.aaudioPreferExclusive, value);
        try {
          if (getIt.isRegistered<PulsrAudioHandler>()) {
            await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
              state.aaudioOutputEnabled,
              preferExclusive: value,
              targetBufferMs: state.aaudioTargetBufferMs,
            );
          }
        } catch (_) {
          // Player not available yet; boot/observer push covers it.
        }
      });

  /// Target stream buffer capacity for the AAudio path (8-1000 ms).
  /// Re-pushed to running players so it applies without toggling output.
  ///
  /// Practical guidance:
  ///  - USB-C / wired DAC: 8–20 ms for lowest seek latency.
  ///  - Bluetooth A2DP:    150–300 ms to absorb codec/stack jitter.
  Future<void> setAaudioTargetBufferMs(int ms) =>
      _audioModeMutex.protect(() async {
        markDirty('aaudioTargetBufferMs');
        // Minimum 8 ms: achievable on USB-C DACs at 48 kHz (≈384 frames).
        // Maximum 1000 ms: generous headroom for worst-case BT stacks.
        final clamped = ms.clamp(8, 1000);
        safeEmit(state.copyWith(aaudioTargetBufferMs: clamped));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(PrefsKeys.aaudioTargetBufferMs, clamped);
        try {
          if (getIt.isRegistered<PulsrAudioHandler>()) {
            await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
              state.aaudioOutputEnabled,
              preferExclusive: state.aaudioPreferExclusive,
              targetBufferMs: clamped,
            );
          }
        } catch (_) {
          // Player not available yet; boot/observer push covers it.
        }
      });

  /// Opt-in 24/32-bit float DSP path. Off by default: with the flag off the
  /// vendored Android fork builds the same 16-bit sink as before. When on, the
  /// preference is persisted here and pushed to every player by the player
  /// layer's settings observer (and restored on boot by the audio handler).
  Future<void> setFloatOutputEnabled(bool enabled) async {
    if (!enabled && state.strictBitPerfect) {
      safeEmit(state.copyWith(errorMessage:
          'Strict Bit-Perfect requires full decoder precision.'));
      return;
    }
    markDirty('floatOutputEnabled');
    safeEmit(state.copyWith(floatOutputEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.floatOutputEnabled, enabled);
    // Best-effort immediate push; the player layer also observes the state.
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setFloatOutputEnabled(enabled);
      }
    } catch (_) {
      // Player not available yet; boot/observer push covers it.
    }
  }

  // ── F3/F4/F7/F8/F9/F10 ──────────────────────────────────────────────
  Future<void> setHedgedResolutionEnabled(bool v) async {
    markDirty('hedgedResolutionEnabled');
    safeEmit(state.copyWith(hedgedResolutionEnabled: v));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.hedgedResolutionEnabled, v);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setHedgedResolutionEnabled(v);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply hedged resolution live',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  Future<void> setAdaptiveQualityEnabled(bool v) async {
    markDirty('adaptiveQualityEnabled');
    safeEmit(state.copyWith(adaptiveQualityEnabled: v));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.adaptiveQualityEnabled, v);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setAdaptiveQualityEnabled(v);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply adaptive quality live',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  Future<void> setDuckingMode(String mode) async {
    markDirty('duckingMode');
    safeEmit(state.copyWith(duckingMode: mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.duckingMode, mode);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setDuckingMode(mode);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply ducking mode live',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  Future<void> setDuckingLevel(double level) async {
    markDirty('duckingLevel');
    final clamped = level.clamp(0.05, 1.0);
    safeEmit(state.copyWith(duckingLevel: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(PrefsKeys.duckingLevel, clamped);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setDuckingLevel(clamped);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply ducking level live',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  Future<void> setMultiOutputMode(String mode) async {
    markDirty('multiOutputMode');
    final parsed = MultiOutputMode.values.firstWhere(
      (m) => m.name == mode,
      orElse: () => MultiOutputMode.systemDefault,
    );
    final prefs = await SharedPreferences.getInstance();
    var applied = parsed == MultiOutputMode.systemDefault;
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        applied = await getIt<PulsrAudioHandler>().setMultiOutputMode(parsed);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply multi-output routing live',
          error: e, stackTrace: st, category: 'Settings');
      applied = false;
    }
    if (parsed != MultiOutputMode.systemDefault && !applied) {
      // Android cannot route media to two outputs simultaneously. Revert the
      // selection instead of persisting an option that never takes effect.
      // FIX-M06: Emit systemDefault before prefs write to ensure UI updates immediately even if disk write hangs
      if (!isClosed) {
        safeEmit(state.copyWith(
          multiOutputMode: MultiOutputMode.systemDefault.name,
          errorMessage:
              'This device cannot play to two outputs at once. Output stays on System default.',
        ));
      }
      await prefs.setString(
          PrefsKeys.multiOutputMode, MultiOutputMode.systemDefault.name);
      return;
    }
    await prefs.setString(PrefsKeys.multiOutputMode, parsed.name);
    safeEmit(state.copyWith(multiOutputMode: parsed.name, errorMessage: null));
  }

  Future<void> setDspSnapshotEnabled(bool v) async {
    markDirty('dspSnapshotEnabled');
    safeEmit(state.copyWith(dspSnapshotEnabled: v));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.dspSnapshotEnabled, v);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setDspSnapshotEnabled(v);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply DSP snapshot setting live',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  Future<void> setSilenceSkipSensitivity(int v) async {
    markDirty('silenceSkipSensitivity');
    final clamped = v.clamp(0, 100);
    if (clamped > 0) {
      final blocked = AudioConflicts.silenceSkipBlockedByBitPerfect(
        bitPerfectOutput: state.bitPerfectOutput,
        bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
        device: state.currentOutputDevice,
      );
      if (blocked != null) {
        safeEmit(state.copyWith(errorMessage: blocked));
        return;
      }
    }
    safeEmit(state.copyWith(silenceSkipSensitivity: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.silenceSkipSensitivity, clamped);
    // B17: apply live so the slider actually drives the native silence skipper
    // instead of only persisting a value.
    try {
      await getIt<PulsrAudioHandler>().setSilenceSkipSensitivity(clamped);
    } catch (e, st) {
      ErrorLogger.log('Failed to apply silence-skip sensitivity live',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  /// F5: Bluetooth latency auto-calibration. Uses the codec latency table
  /// plus optional probe samples, then persists the winning offset.
  Future<int> autoCalibrateBluetoothLatency(
      {Future<int> Function()? probe}) async {
    final codec = state.currentOutputDevice?.btCodecName;
    int codecEst = 180;
    try {
      const table = {
        'sbc': 220,
        'aac': 200,
        'aptx': 150,
        'ldac': 250,
        'lc3': 60,
        'opus': 100,
        'lhdc': 180,
      };
      if (codec != null && codec.isNotEmpty) {
        final key = codec.toLowerCase();
        for (final e in table.entries) {
          if (key.contains(e.key)) {
            codecEst = e.value;
            break;
          }
        }
      }
    } catch (_) {}
    var combined = codecEst;
    if (probe != null) {
      final vals = <int>[];
      for (var i = 0; i < 5; i++) {
        try {
          final v = await probe();
          if (v >= 0 && v <= 1000) vals.add(v);
        } catch (_) {}
      }
      if (vals.isNotEmpty) {
        vals.sort();
        final trimmed =
            vals.length >= 4 ? vals.sublist(1, vals.length - 1) : vals;
        final avg = (trimmed.reduce((a, b) => a + b) / trimmed.length).round();
        combined = (codecEst * 0.6 + avg * 0.4).round();
      }
    }
    final clamped = combined.clamp(0, 500);
    await setBluetoothLatencyOffsetMs(clamped);
    return clamped;
  }

  /// Applies the "Maximum Quality" audiophile preset: Bit-perfect output, then
  /// the DSP bypass, ReplayGain off and gapless. Every step is conditional on
  /// the one before it actually applying: when the platform refuses exclusive
  /// output, silently bypassing the user's EQ and gain would leave a chain with
  /// no processing and no bit-perfect either.
  Future<void> applyMaximumQualityPreset() async {
    // Depth first: with the float DSP path off Media3 inserts a 16-bit
    // converter ahead of the native chain, so a 24/32-bit source would reach
    // the DAC as 16-bit no matter what Bit-Perfect later reports.
    if (!state.floatOutputEnabled) {
      await setFloatOutputEnabled(true);
    }
    // AAudio replaces the ExoPlayer sink the direct UAC2 tee lives in. On a
    // USB DAC the tee is the path that can prove its format, so prefer it.
    if (state.aaudioOutputEnabled &&
        state.currentOutputDevice?.isUsbDac == true) {
      await setAaudioOutputEnabled(false);
      if (state.aaudioOutputEnabled) return;
    }
    await setBitPerfectOutput(true);
    if (!state.bitPerfectOutput) return;
    await setBypassDspOnBitPerfect(true);
    if (!state.bypassDspOnBitPerfect) return;
    // These stages edit or overlap the stream; a bit-exact claim cannot
    // coexist with them. Order: crossfade before gapless (gapless refuses a
    // non-zero crossfade), silence skip before it is re-armed anywhere.
    await setCrossfade(0.0);
    if (state.silenceSkipSensitivity > 0) {
      await setSilenceSkipSensitivity(0);
    }
    await setGapless(true);
    await setReplayGainMode(ReplayGainMode.off);
  }

  /// Applies the "Smooth Playback" preset: no bit-perfect, automatic
  /// ReplayGain and a 4 s crossfade. Gapless is turned off first because
  /// crossfade is refused while gapless is on, and nothing here adapts the
  /// buffer (that is the separate "adaptive quality" toggle).
  Future<void> applySmoothPlaybackPreset() async {
    await setBitPerfectOutput(false);
    await setGapless(false);
    await setCrossfade(4.0);
    await setReplayGainMode(ReplayGainMode.auto);
  }

  /// Applies the "Poor Network" preset:
  /// Conservative data usage, zero crossfade, lower bitrate.
  Future<void> applyPoorNetworkPreset() async {
    await setCrossfade(0.0);
    await setGapless(false);
    await setStreamingQuality(YtmAudioQuality.low);
  }

  // Requires: provided by the composing class (same library).
  HiResAudioService get _hiResAudioService;

  // Requires: provided by the composing class (same library).
  Future<void> setCrossfade(double seconds);

  // Requires: provided by the composing class (same library).
  Future<void> setGapless(bool value);

  // Requires: provided by the composing class (same library).
  void markDirty(String field);
}
