// lib/features/player/cubit/player_dependencies.dart
import '../../../core/services/device_profile_service.dart';
import '../../../core/services/earbud_optimization_service.dart';
import '../../../core/services/hires_audio_service.dart';
import '../../../core/services/lrclib_service.dart';
import '../../../core/services/quran_mode_service.dart';
import '../../../core/services/scrobbler_service.dart';
import '../../../core/services/settings_profiles_service.dart';
import '../../../core/services/smart_audio_service.dart';
import '../../../core/services/sponsorblock_service.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/telemetry/playback_latency_tracker.dart';
import '../../../data/audio/per_song_eq_store.dart';
import '../../../data/audio/per_song_volume_store.dart';
import '../../../data/audio/song_rating_store.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../widgets/widget_service.dart';

/// FIX-A03: Parameter object bundling auxiliary services for [PlayerCubit].
/// Keeps the constructor clean while maintaining backwards compatibility.
class PlayerDependencies {
  final SettingsCubit? settingsCubit;
  final WidgetService? widgetService;
  final ScrobblerService? scrobblerService;
  final SettingsProfilesService? settingsProfilesService;
  final DeviceProfileService? deviceProfileService;
  final HiResAudioService? hiResAudioService;
  final SmartAudioService? smartAudioService;
  final PlaybackLatencyTracker? latencyTracker;
  final PerSongEqStore? perSongEqStore;
  final PerSongVolumeStore? perSongVolumeStore;
  final SongRatingStore? songRatingStore;
  final SponsorBlockService? sponsorBlockService;
  final QuranModeService? quranModeService;
  final EarbudOptimizationService? earbudOptimizationService;
  final LrclibService? lrclibService;
  final YtmAccountService? ytmAccountService;
  final MediaScannerService? mediaScannerService;

  const PlayerDependencies({
    this.settingsCubit,
    this.widgetService,
    this.scrobblerService,
    this.settingsProfilesService,
    this.deviceProfileService,
    this.hiResAudioService,
    this.smartAudioService,
    this.latencyTracker,
    this.perSongEqStore,
    this.perSongVolumeStore,
    this.songRatingStore,
    this.sponsorBlockService,
    this.quranModeService,
    this.earbudOptimizationService,
    this.lrclibService,
    this.ytmAccountService,
    this.mediaScannerService,
  });
}
