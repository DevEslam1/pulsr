// lib/core/constants/prefs_keys.dart

class PrefsKeys {
  static const String eqEnabled = 'eq_enabled';
  static const String eqPresetName = 'eq_preset_name';
  static const String eqGains = 'eq_gains';
  static const String eqBassBoost = 'eq_bass_boost';
  static const String eqVolumeBoost = 'eq_volume_boost';
  static const String eqVirtualizerEnabled = 'eq_virtualizer_enabled';
  static const String eqVirtualizerStrength = 'eq_virtualizer_strength';
  static const String eqDynamicsPreset = 'eq_dynamics_preset';
  static const String eqDynamicsEnabled = 'eq_dynamics_enabled';
  static const String eqDynamicsBypassed = 'eq_dynamics_bypassed';
  static const String eqSpatializerEnabled = 'eq_spatializer_enabled';
  static const String eqHeadphoneProfileId = 'eq_headphone_profile_id';
  static const String eqCustomFrequencies = 'eq_custom_frequencies';
  static const String customEqProfiles = 'custom_eq_profiles';
  static const String resumeAfterInterruption =
      'setting_resume_after_interruption';
  static const String themeMode = 'setting_theme_mode';
  static const String customAccentColor = 'setting_custom_accent_color';
  static const String dynamicThemingEnabled = 'setting_dynamic_theming_enabled';
  static const String playerThemeMode = 'setting_player_theme_mode';
  static const String crossfadeEnabled = 'setting_crossfade_enabled';
  static const String crossfadeDurationSec = 'setting_crossfade_duration_sec';
  static const String playbackSpeed = 'setting_playback_speed';
  static const String playbackShuffle = 'setting_playback_shuffle';
  static const String playbackRepeatMode = 'setting_playback_repeat_mode';
  static const String replayGainMode = 'setting_replay_gain_mode';
  static const String replayGainPreampWithRg =
      'setting_replay_gain_preamp_with_rg';
  static const String replayGainPreampWithoutRg =
      'setting_replay_gain_preamp_without_rg';
  static const String sleepTimerTarget = 'sleep_timer_target';
  static const String queueSlots = 'queue_slots_v1';
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
  static const String stereoWidthEnabled = 'setting_stereo_width_enabled';
  static const String stereoWidth = 'setting_stereo_width';
  static const String loudnessContourEnabled =
      'setting_loudness_contour_enabled';
  static const String loudnessContourIntensity =
      'setting_loudness_contour_intensity';
  static const String subCrossoverEnabled = 'setting_sub_crossover_enabled';
  static const String subCrossoverCornerHz = 'setting_sub_crossover_corner_hz';
  static const String subCrossoverSlopeDbPerOct =
      'setting_sub_crossover_slope_db_per_oct';
  static const String subCrossoverGain = 'setting_sub_crossover_gain';
  static const String dynamicEqEnabled = 'setting_dynamic_eq_enabled';
  static const String dynamicEqBands = 'setting_dynamic_eq_bands';

  // FIX(N1): Artwork cache disk limit key
  static const String settingMaxCacheSizeMb = 'setting_max_cache_size_mb';

  // FIX(B3): Cloud sync preferences keys
  static const String cloudSyncLastTimestamp = 'cloud_sync_last_timestamp';
  static const String cloudSyncFavoritesEnabled = 'cloud_sync_favorites_enabled';
  static const String cloudSyncPlaylistsEnabled = 'cloud_sync_playlists_enabled';
  static const String cloudSyncDocHashes = 'cloud_sync_doc_hashes_v1';

  // FIX(S1-FU): History deduplication keys
  static const String historyLastSongId = 'history_last_song_id';
  static const String historyLastTimeMs = 'history_last_time_ms';

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
  static const String scrobblerLastScrobbledTimestamp = scrobbleLastTimestamp;
  static const String scrobblerOfflineQueue = scrobbleOfflineQueue;
}
