// lib/core/constants/prefs_keys.dart

class PrefsKeys {
  static const String eqEnabled = 'eq_enabled';
  static const String eqPresetName = 'eq_preset_name';
  static const String eqGains = 'eq_gains';
  static const String eqBassBoost = 'eq_bass_boost';
  static const String eqPreamp = 'eq_preamp_db';
  static const String eqVolumeBoost = 'eq_volume_boost';
  static const String eqVirtualizerEnabled = 'eq_virtualizer_enabled';
  static const String eqVirtualizerStrength = 'eq_virtualizer_strength';
  static const String eqDynamicsPreset = 'eq_dynamics_preset';
  static const String eqDynamicsEnabled = 'eq_dynamics_enabled';
  static const String eqDynamicsBypassed = 'eq_dynamics_bypassed';
  static const String eqSpatializerEnabled = 'eq_spatializer_enabled';
  static const String eqHeadphoneProfileId = 'eq_headphone_profile_id';
  static const String eqCustomFrequencies = 'eq_custom_frequencies';
  static const String eq32BandMode = 'eq_32_band_mode';
  static const String eqBandCount = 'eq_band_count';
  static const String eqCustom32Frequencies = 'eq_custom_32_frequencies';
  static const String eqCustom64Frequencies = 'eq_custom_64_frequencies';
  static const String customEqProfiles = 'custom_eq_profiles';
  static const String resumeAfterInterruption =
      'setting_resume_after_interruption';
  static const String themeMode = 'setting_theme_mode';
  // Live store is 'setting_custom_accent' (SettingsCubit._keyCustomAccent);
  // the '_color' suffixed value was a dead duplicate (orphan 20-01).
  static const String customAccentColor = 'setting_custom_accent';
  // Live legacy bool is 'setting_dynamic_theme' (SettingsCubit._keyDynamicTheme);
  // the '_enabled' suffixed value was a dead duplicate (orphan 20-01).
  static const String dynamicThemingEnabled = 'setting_dynamic_theme';
  static const String playerThemeMode = 'setting_player_theme_mode';
  static const String playbackSpeed = 'setting_playback_speed';
  static const String playbackPitch = 'setting_playback_pitch';
  static const String advancedPlaybackSpeed = 'setting_advanced_playback_speed';
  static const String playbackShuffle = 'setting_playback_shuffle';
  static const String playbackRepeatMode = 'setting_playback_repeat_mode';
  static const String replayGainMode = 'setting_replay_gain_mode';
  static const String replayGainPreampWithRg =
      'setting_replay_gain_preamp_with_rg';
  static const String replayGainPreampWithoutRg =
      'setting_replay_gain_preamp_without_rg';
  static const String sleepTimerTarget = 'sleep_timer_target';
  static const String queueSlots = 'queue_slots_v1';
  // Removed: queueActiveSlot ('queue_active_slot_v1') was dead — the active
  // slot is embedded in queue_slots_v1 (orphan 20-01, tranche 5).
  static const String ytdlpBackendEnabled = 'setting_ytdlp_backend_enabled';
  static const String ytdlpBackendUrl = 'setting_ytdlp_backend_url';
  static const String ytdlpBackendToken = 'setting_ytdlp_backend_token';
  static const String syncCookiesToBackend = 'setting_sync_cookies_to_backend';
  static const String extractorEngine = 'setting_extractor_engine';
  static const String languageCode = 'setting_language_code';
  static const String bitPerfectOutput = 'setting_bit_perfect_output';
  static const String bypassDspOnBitPerfect =
      'setting_bypass_dsp_on_bit_perfect';
  static const String crossfeedEnabled = 'setting_crossfeed_enabled';
  static const String crossfeedDelayUs = 'setting_crossfeed_delay_us';
  static const String crossfeedFeedDb = 'setting_crossfeed_feed_db';
  static const String lookaheadLimiterEnabled =
      'setting_lookahead_limiter_enabled';
  static const String lookaheadLimiterThresholdDb =
      'setting_lookahead_limiter_threshold_db';
  static const String lookaheadLimiterReleaseMs =
      'setting_lookahead_limiter_release_ms';
  static const String lookaheadLimiterLookaheadMs =
      'setting_lookahead_limiter_lookahead_ms';
  // Studio compressor knobs on the limiter/HAL DynamicsProcessing stage.
  static const String compressorRatio = 'setting_compressor_ratio';
  static const String compressorAttackMs = 'setting_compressor_attack_ms';
  static const String compressorMakeupGainDb =
      'setting_compressor_makeup_gain_db';
  static const String convolutionReverbEnabled =
      'setting_convolution_reverb_enabled';
  static const String convolutionReverbPreset =
      'setting_convolution_reverb_preset';
  static const String convolutionReverbWetDry =
      'setting_convolution_reverb_wet_dry';
  static const String stereoBalance = 'setting_stereo_balance';
  static const String monoMix = 'setting_mono_mix';
  static const String sincResamplerEnabled = 'setting_sinc_resampler_enabled';
  // Phase 1 DSP expansion stages
  static const String saturationEnabled = 'setting_saturation_enabled';
  static const String saturationDrive = 'setting_saturation_drive';
  static const String saturationMix = 'setting_saturation_mix';
  static const String saturationTilt = 'setting_saturation_tilt';
  static const String saturationMode = 'setting_saturation_mode';
  static const String stereoWidthEnabled = 'setting_stereo_width_enabled';
  static const String stereoWidth = 'setting_stereo_width';
  static const String stereoWidthMultiband = 'setting_stereo_width_multiband';
  static const String stereoWidthLow = 'setting_stereo_width_low';
  static const String stereoWidthMid = 'setting_stereo_width_mid';
  static const String stereoWidthHigh = 'setting_stereo_width_high';
  static const String stereoWidthLowCrossoverHz =
      'setting_stereo_width_low_crossover_hz';
  static const String stereoWidthHighCrossoverHz =
      'setting_stereo_width_high_crossover_hz';
  static const String loudnessContourEnabled =
      'setting_loudness_contour_enabled';
  static const String loudnessContourIntensity =
      'setting_loudness_contour_intensity';
  static const String subCrossoverEnabled = 'setting_sub_crossover_enabled';
  static const String subCrossoverCornerHz = 'setting_sub_crossover_corner_hz';
  static const String subCrossoverSlopeDbPerOct =
      'setting_sub_crossover_slope_db_per_oct';
  static const String subCrossoverGain = 'setting_sub_crossover_gain';
  static const String subCrossoverBassMono = 'setting_sub_crossover_bass_mono';
  static const String subCrossoverAntiPop = 'setting_sub_crossover_anti_pop';
  static const String dynamicEqEnabled = 'setting_dynamic_eq_enabled';
  static const String dynamicEqBands = 'setting_dynamic_eq_bands';
  static const String reverbCrossChannel = 'setting_reverb_cross_channel';
  static const String multibandCompressorEnabled =
      'setting_multiband_compressor_enabled';
  static const String multibandCompressorBands =
      'setting_multiband_compressor_bands';
  static const String multibandCompressorF0 = 'setting_multiband_compressor_f0';
  static const String multibandCompressorF1 = 'setting_multiband_compressor_f1';
  static const String multibandCompressorF2 = 'setting_multiband_compressor_f2';

  static const String dynamicBassEnabled = 'setting_dynamic_bass_enabled';
  static const String dynamicBassStrength = 'setting_dynamic_bass_strength';
  static const String dynamicBassXLow = 'setting_dynamic_bass_x_low';
  static const String dynamicBassXHigh = 'setting_dynamic_bass_x_high';
  static const String dynamicBassYLow = 'setting_dynamic_bass_y_low';
  static const String dynamicBassYHigh = 'setting_dynamic_bass_y_high';
  static const String dynamicBassSideGainLow = 'setting_dynamic_bass_side_gain_low';
  static const String dynamicBassSideGainHigh = 'setting_dynamic_bass_side_gain_high';
  static const String dynamicBassPreset = 'setting_dynamic_bass_preset';

  // JamesDSP feature parity stages
  static const String crossfeedMode = 'setting_crossfeed_mode';
  static const String saturationMultiband = 'setting_saturation_multiband';
  static const String viperDdcEnabled = 'setting_viper_ddc_enabled';
  static const String viperDdcProfileName = 'setting_viper_ddc_profile_name';
  static const String viperDdcContent = 'setting_viper_ddc_content';
  static const String arbitraryEqEnabled = 'setting_arbitrary_eq_enabled';
  static const String arbitraryEqString = 'setting_arbitrary_eq_string';
  static const String liveProgEnabled = 'setting_live_prog_enabled';
  static const String liveProgCode = 'setting_live_prog_code';

  // FIX(N1): Artwork cache disk limit key
  static const String settingMaxCacheSizeMb = 'setting_max_cache_size_mb';

  // FIX(B3): Cloud sync preferences keys
  static const String cloudSyncLastTimestamp = 'cloud_sync_last_timestamp';
  static const String cloudSyncFavoritesEnabled = 'cloud_sync_favorites_enabled';
  static const String cloudSyncPlaylistsEnabled = 'cloud_sync_playlists_enabled';
  // Live store is 'cloud_sync_hashes_cache' (CloudSyncService._keySyncedHashes);
  // the '_doc_hashes_v1' value was a dead duplicate (orphan 20-01).
  static const String cloudSyncDocHashes = 'cloud_sync_hashes_cache';

  // Removed: historyLastSongId/historyLastTimeMs were dead — history dedup is
  // in-memory + Drift play_history (orphan 20-01, tranche 5).

  // FIX(B2): Canonical SharedPreferences keys for Scrobbler service
  static const String scrobbleLastKey = 'last_scrobble_key';
  static const String scrobbleLastTime = 'last_scrobble_time';
  static const String scrobbleLastId = 'last_scrobbled_id';
  static const String scrobbleLastTimestamp = 'last_scrobbled_timestamp';
  static const String scrobblePendingSong = 'scrobbler_last_song';
  static const String scrobblePendingTime = 'scrobbler_last_time';
  static const String scrobblePendingPos = 'scrobbler_last_position';
  static const String scrobblePendingDuration = 'scrobbler_last_duration';
  static const String scrobblePendingArtist = 'scrobbler_last_artist';
  static const String scrobblePendingTrack = 'scrobbler_last_track';
  static const String scrobblePendingAlbum = 'scrobbler_last_album';
  static const String scrobbleOfflineQueue = 'scrobbler_offline_queue';

  static const String systemEffectsPolicy = 'setting_system_effects_policy';
  static const String bluetoothLatencyOffsetMs = 'setting_bluetooth_latency_offset_ms';

  // Aliases for backwards compatibility with tests and services
  static const String scrobblerLastSong = scrobblePendingSong;
  static const String scrobblerLastTime = scrobblePendingTime;
  static const String scrobblerLastPos = scrobblePendingPos;
  static const String scrobblerLastArtist = scrobblePendingArtist;
  static const String scrobblerLastTrack = scrobblePendingTrack;
  static const String scrobblerLastAlbum = scrobblePendingAlbum;
  static const String scrobblerLastDuration = scrobblePendingDuration;
  static const String scrobblerLastScrobbledKey = scrobbleLastKey;
  static const String scrobblerLastScrobbledTime = scrobbleLastTime;
  static const String scrobblerLastScrobbledId = scrobbleLastId;
  static const String scrobblerOfflineQueue = scrobbleOfflineQueue;

  // Advanced playback engine features
  // F1–F11 maximize-feature-set keys
  // Removed: abLoopEnabled ('ab_loop_enabled') was dead — A-B state lives in
  // AbLoopManager 'ab_loops_v1' per-track store (orphan 20-01, tranche 5).
  static const String hedgedResolutionEnabled = 'hedged_resolution_enabled';
  static const String adaptiveQualityEnabled = 'adaptive_quality_enabled';
  static const String duckingMode = 'audio_ducking_mode_v1';
  static const String duckingLevel = 'audio_ducking_level_v1';
  static const String multiOutputMode = 'multi_output_mode_v1';
  static const String dspSnapshotEnabled = 'dsp_snapshot_enabled_v1';
  static const String silenceSkipSensitivity = 'skip_silence_sensitivity_v1';
  static const String trackDelayMap = 'per_track_audio_delay_v1';
  static const String bookmarksMap = 'playback_bookmarks_v1';

  // F-67: SponsorBlock auto-skip controls.
  static const String sponsorBlockEnabled = 'sponsorblock_enabled';
  static const String sponsorBlockCategories = 'sponsorblock_categories';

  // F-27: manual loudness normalization toggle (read by PulsrAudioHandler).
  static const String audioNormalizationEnabled = 'audio_normalization_enabled';

  static const String dspPreference = 'setting_dsp_preference'; // 'native' | 'oem' | 'auto'
  static const String ditherEnabled = 'setting_dither_enabled';
  static const String ditherTargetBitDepth = 'setting_dither_target_bit_depth';
  static const String mqaDecodingEnabled = 'setting_mqa_decoding_enabled';
  static const String customReverbIrPath = 'setting_custom_reverb_ir_path';
  // Snapshot of the user's DSP state captured when Quran Mode is enabled, so
  // disabling it restores the pre-Quran EQ/reverb/dynamics even across a
  // process restart (when the in-memory snapshot no longer exists).
  static const String quranRestoreSnapshot = 'quran_restore_snapshot_v1';
  static const String spatializerEngine = 'setting_spatializer_engine'; // 'off' | 'systemHardware' | 'binauralAmbisonic'
  // Removed: exclusiveOffloadEnabled was dead — no native exclusive-offload
  // path exists (orphan 20-01, tranche 5). Reintroduce with native support.

  // T6: Direct Volume Control. Pins Android's media stream to maximum and
  // applies the composed gain in the native float DSP path instead of relying
  // on Android's digital volume attenuation (higher dynamic range at low volume).
  static const String dvcEnabled = 'setting_dvc_enabled';

  // USB DAC hardware volume: when on, Pulsr drives the DAC's UAC Feature Unit
  // hardware volume directly instead of only the Android media stream.
  static const String usbHardwareVolumeEnabled =
      'setting_usb_hardware_volume_enabled';

  // Per-session audio telemetry (route/codec/negotiated format/interruptions).
  static const String audioSessionLogEnabled =
      'setting_audio_session_log_enabled';

  // Opt-in per-track output-format negotiation (default OFF: keeps the manual,
  // device-global output format unless the user enables it).
  static const String outputFormatNegotiationEnabled =
      'setting_output_format_negotiation_enabled';

  // Opt-in 24/32-bit float DSP path (default OFF: the native DSP chain stays
  // on the historical 16-bit sink path, byte-identical to today).
  static const String floatOutputEnabled = 'setting_float_output_enabled';

  // Opt-in AAudio "Direct" output path (default OFF: the sink stays the
  // historical DefaultAudioSink + native DSP chain). When on, playback goes
  // through a native AAudio stream (EXCLUSIVE attempt, SHARED fallback) and
  // the DSP processor chain is bypassed for bit-perfect output.
  static const String aaudioOutputEnabled = 'setting_aaudio_output_enabled';
  static const String aaudioPreferExclusive =
      'setting_aaudio_prefer_exclusive';
  static const String aaudioTargetBufferMs =
      'setting_aaudio_target_buffer_ms';

  // Resampler quality: 0 = Fast (linear), 1 = Standard (16-tap),
  // 2 = High (32-tap), 3 = Ultra (64-tap, default).
  static const String sincResamplerQuality = 'setting_sinc_resampler_quality';

  // BPM-synced crossfade: align crossfade duration to the nearest
  // 2/4/8/16/32 beats of the incoming track when a BPM value is known.
  static const String bpmSyncCrossfadeEnabled =
      'setting_bpm_sync_crossfade_enabled';

  // T2: reconfigure the output device to each track's native sample rate
  // (skipped on Bluetooth, where the AVRCP/codec link owns the rate).
  static const String followTrackSampleRate =
      'setting_follow_track_sample_rate';

  // T3: strict bit-perfect / no-resample. Forces the Bit-Perfect output and
  // the DSP bypass, then follows each track's exact rate. Enabled only on a
  // path that reports exclusive bit-perfect support.
  static const String strictBitPerfect = 'setting_strict_bit_perfect';

  // T4: DSD (DSF/DFF) output transport. 'pcm' (default, safe: decode to PCM)
  // or 'dop' (frame as DSD over PCM for a compatible USB DAC). Never
  // auto-enabled — DoP requires an explicit user choice plus a detected DAC.
  static const String dsdOutputMode = 'setting_dsd_output_mode';

  // Smart Audio: 'auto' adapts AutoEQ + output quality to the connected device
  // and track; 'manual' leaves the user's explicit choices untouched.
  static const String smartAudioMode = 'setting_smart_audio_mode';
  // Per-device AutoEQ matches remembered by device key (see DeviceProfileService).
  static const String smartAudioAutoEqLinks = 'setting_smart_audio_autoeq_links';

  // UI complexity: 'normal' (default, curated) | 'professional' (full controls).
  static const String experienceMode = 'setting_experience_mode';
}
