// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'dart:io' as _i497;

import 'package:flutter_secure_storage/flutter_secure_storage.dart' as _i558;
import 'package:get_it/get_it.dart' as _i174;
import 'package:http/http.dart' as _i519;
import 'package:injectable/injectable.dart' as _i526;
import 'package:pulsr/core/di/injection.dart' as _i953;
import 'package:pulsr/core/services/file_intent_handler.dart' as _i134;
import 'package:pulsr/core/telemetry/clock.dart' as _i621;
import 'package:pulsr/core/telemetry/playback_latency_tracker.dart' as _i626;
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart' as _i401;
import 'package:pulsr/data/audio/audio_handler.dart' as _i366;
import 'package:pulsr/data/db/app_database.dart' as _i682;
import 'package:pulsr/data/downloads/yt_download_service.dart' as _i680;
import 'package:pulsr/data/repositories/download_repository_impl.dart' as _i877;
import 'package:pulsr/data/repositories/music_repository.dart' as _i627;
import 'package:pulsr/data/repositories/smart_playlist_engine.dart' as _i399;
import 'package:pulsr/data/scanner/media_scanner_service.dart' as _i483;
import 'package:pulsr/data/services/artist_bio_service.dart' as _i891;
import 'package:pulsr/data/services/artwork_cache_manager.dart' as _i408;
import 'package:pulsr/data/services/cloud_sync_service.dart' as _i838;
import 'package:pulsr/data/services/lrclib_service.dart' as _i201;
import 'package:pulsr/data/services/metadata_search_service.dart' as _i344;
import 'package:pulsr/data/services/missing_artwork_service.dart' as _i871;
import 'package:pulsr/data/services/scrobbler_service.dart' as _i748;
import 'package:pulsr/data/services/xdm_backend_service.dart' as _i403;
import 'package:pulsr/data/services/ytm_account_service.dart' as _i74;
import 'package:pulsr/data/services/ytm_browse_service.dart' as _i415;
import 'package:pulsr/data/services/ytm_cache_manager.dart' as _i557;
import 'package:pulsr/data/services/ytm_client_version_resolver.dart' as _i520;
import 'package:pulsr/data/services/ytm_service.dart' as _i1053;
import 'package:pulsr/data/services/ytm_url_cache.dart' as _i150;
import 'package:pulsr/domain/repositories/download_repository_interface.dart'
    as _i783;
import 'package:pulsr/domain/repositories/music_repository_interface.dart'
    as _i320;
import 'package:pulsr/domain/repositories/smart_playlist_engine_interface.dart'
    as _i632;
import 'package:pulsr/domain/services/auth_service.dart' as _i244;
import 'package:pulsr/domain/services/autoeq_service.dart' as _i169;
import 'package:pulsr/domain/services/automation_rules_service.dart' as _i607;
import 'package:pulsr/domain/services/device_profile_service.dart' as _i655;
import 'package:pulsr/domain/services/duplicate_finder_service.dart' as _i200;
import 'package:pulsr/domain/services/hires_audio_service.dart' as _i1054;
import 'package:pulsr/domain/services/playlist_share_service.dart' as _i618;
import 'package:pulsr/domain/services/playlist_suggestions_service.dart'
    as _i131;
import 'package:pulsr/domain/services/room_correction_service.dart' as _i589;
import 'package:pulsr/domain/services/settings_profiles_service.dart' as _i341;
import 'package:pulsr/domain/services/theme_scheduler_service.dart' as _i173;
import 'package:pulsr/domain/usecases/backup_usecases.dart' as _i545;
import 'package:pulsr/domain/usecases/download_lifecycle_usecases.dart'
    as _i1001;
import 'package:pulsr/domain/usecases/download_query_usecases.dart' as _i233;
import 'package:pulsr/domain/usecases/download_queue_usecases.dart' as _i6;
import 'package:pulsr/domain/usecases/folder_usecases.dart' as _i1017;
import 'package:pulsr/domain/usecases/get_albums_usecase.dart' as _i496;
import 'package:pulsr/domain/usecases/get_artists_usecase.dart' as _i602;
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart' as _i117;
import 'package:pulsr/domain/usecases/get_genres_usecase.dart' as _i485;
import 'package:pulsr/domain/usecases/get_songs_usecase.dart' as _i168;
import 'package:pulsr/domain/usecases/get_years_usecase.dart' as _i652;
import 'package:pulsr/domain/usecases/playlist_io_usecases.dart' as _i265;
import 'package:pulsr/domain/usecases/playlist_usecases.dart' as _i792;
import 'package:pulsr/domain/usecases/search_music_usecase.dart' as _i644;
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart' as _i800;
import 'package:pulsr/features/auth/cubit/auth_cubit.dart' as _i918;
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart' as _i752;
import 'package:pulsr/features/downloads/cubit/ytm_download_cubit.dart'
    as _i309;
import 'package:pulsr/features/home_widget/widget_service.dart' as _i651;
import 'package:pulsr/features/library/cubit/library_cubit.dart' as _i633;
import 'package:pulsr/features/player/cubit/player_cubit.dart' as _i147;
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart' as _i431;
import 'package:pulsr/features/search/cubit/search_cubit.dart' as _i984;
import 'package:pulsr/features/settings/cubit/settings_cubit.dart' as _i41;
import 'package:pulsr/features/smart_playlist_builder/cubit/smart_playlist_builder_cubit.dart'
    as _i1022;
import 'package:pulsr/features/ytm_search/cubit/ytm_search_cubit.dart' as _i171;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final networkModule = _$NetworkModule();
    final storageModule = _$StorageModule();
    gh.singleton<_i497.HttpClient>(
      () => networkModule.httpClient,
      dispose: _i953.disposeHttpClient,
    );
    gh.singleton<_i519.Client>(() => networkModule.pkgHttpClient);
    gh.singleton<_i401.DynamicThemeCubit>(() => _i401.DynamicThemeCubit());
    gh.singleton<_i682.AppDatabase>(() => _i682.AppDatabase());
    gh.singleton<_i408.ArtworkCacheManager>(() => _i408.ArtworkCacheManager());
    gh.singleton<_i557.YtmCacheManager>(() => _i557.YtmCacheManager());
    gh.singleton<_i520.YtmClientVersionResolver>(
      () => _i520.YtmClientVersionResolver(),
    );
    gh.singleton<_i1053.YtmService>(
      () => _i1053.YtmService(),
      dispose: (i) => i.dispose(),
    );
    gh.singleton<_i150.YtmUrlCache>(() => _i150.YtmUrlCache());
    gh.singleton<_i244.AuthService>(() => _i244.AuthService());
    gh.singleton<_i169.AutoEqService>(() => _i169.AutoEqService());
    gh.singleton<_i607.AutomationRulesService>(
      () => _i607.AutomationRulesService(),
    );
    gh.singleton<_i200.DuplicateFinderService>(
      () => _i200.DuplicateFinderService(),
    );
    gh.singleton<_i618.PlaylistShareService>(
      () => _i618.PlaylistShareService(),
    );
    gh.singleton<_i131.PlaylistSuggestionsService>(
      () => _i131.PlaylistSuggestionsService(),
    );
    gh.singleton<_i341.SettingsProfilesService>(
      () => _i341.SettingsProfilesService(),
    );
    gh.singleton<_i173.ThemeSchedulerService>(
      () => _i173.ThemeSchedulerService(),
    );
    gh.singleton<_i265.PlaylistExportUseCase>(
      () => _i265.PlaylistExportUseCase(),
    );
    gh.lazySingleton<_i558.FlutterSecureStorage>(
      () => storageModule.secureStorage,
    );
    gh.lazySingleton<_i626.PlaybackLatencyTracker>(
      () => _i626.PlaybackLatencyTracker(),
    );
    gh.lazySingleton<_i655.DeviceProfileService>(
      () => _i655.DeviceProfileService(),
    );
    gh.lazySingleton<_i1054.HiResAudioService>(
      () => _i1054.HiResAudioService(),
    );
    gh.lazySingleton<_i589.RoomCorrectionService>(
      () => _i589.RoomCorrectionService(),
    );
    gh.lazySingleton<_i651.WidgetService>(() => _i651.WidgetService());
    gh.singleton<_i74.YtmAccountService>(
      () => _i74.YtmAccountService(gh<_i520.YtmClientVersionResolver>()),
    );
    gh.singleton<_i632.ISmartPlaylistEngine>(
      () => _i399.SmartPlaylistEngine(gh<_i682.AppDatabase>()),
    );
    gh.lazySingleton<_i344.MetadataSearchService>(
      () => _i344.MetadataSearchService(gh<_i519.Client>()),
    );
    gh.singleton<_i748.ScrobblerService>(
      () => _i748.ScrobblerService(
        gh<_i519.Client>(),
        gh<_i558.FlutterSecureStorage>(),
      ),
    );
    gh.lazySingleton<_i621.Clock>(() => const _i621.SystemClock());
    gh.singleton<_i320.IMusicRepository>(
      () => _i627.MusicRepository(gh<_i682.AppDatabase>()),
    );
    gh.singleton<_i201.LrclibService>(
      () => _i201.LrclibService(client: gh<_i497.HttpClient>()),
    );
    gh.factory<_i171.YtmSearchCubit>(
      () => _i171.YtmSearchCubit(service: gh<_i1053.YtmService>()),
    );
    gh.singleton<_i483.MediaScannerService>(
      () => _i483.MediaScannerService(gh<_i320.IMusicRepository>()),
    );
    gh.singleton<_i545.ExportBackupUseCase>(
      () => _i545.ExportBackupUseCase(gh<_i320.IMusicRepository>()),
    );
    gh.singleton<_i1017.FolderUseCases>(
      () => _i1017.FolderUseCases(gh<_i320.IMusicRepository>()),
    );
    gh.singleton<_i496.GetAlbumsUseCase>(
      () => _i496.GetAlbumsUseCase(gh<_i320.IMusicRepository>()),
    );
    gh.singleton<_i602.GetArtistsUseCase>(
      () => _i602.GetArtistsUseCase(gh<_i320.IMusicRepository>()),
    );
    gh.singleton<_i117.GetFavoritesUseCase>(
      () => _i117.GetFavoritesUseCase(gh<_i320.IMusicRepository>()),
    );
    gh.singleton<_i485.GetGenresUseCase>(
      () => _i485.GetGenresUseCase(gh<_i320.IMusicRepository>()),
    );
    gh.singleton<_i168.GetSongsUseCase>(
      () => _i168.GetSongsUseCase(gh<_i320.IMusicRepository>()),
    );
    gh.singleton<_i652.GetYearsUseCase>(
      () => _i652.GetYearsUseCase(gh<_i320.IMusicRepository>()),
    );
    gh.singleton<_i265.PlaylistImportUseCase>(
      () => _i265.PlaylistImportUseCase(gh<_i320.IMusicRepository>()),
    );
    gh.singleton<_i644.SearchMusicUseCase>(
      () => _i644.SearchMusicUseCase(gh<_i320.IMusicRepository>()),
    );
    gh.singleton<_i800.ToggleFavoriteUseCase>(
      () => _i800.ToggleFavoriteUseCase(gh<_i320.IMusicRepository>()),
    );
    gh.singleton<_i792.PlaylistUseCases>(
      () => _i792.PlaylistUseCases(
        gh<_i320.IMusicRepository>(),
        gh<_i632.ISmartPlaylistEngine>(),
      ),
    );
    gh.factory<_i431.PlaylistCubit>(
      () => _i431.PlaylistCubit(playlistUseCases: gh<_i792.PlaylistUseCases>()),
    );
    gh.lazySingleton<_i403.XdmBackendService>(
      () => _i403.XdmBackendService(
        secureStorage: gh<_i558.FlutterSecureStorage>(),
      ),
    );
    gh.singleton<_i415.YtmBrowseService>(
      () => _i415.YtmBrowseService(gh<_i1053.YtmService>()),
    );
    gh.singleton<_i891.ArtistBioService>(
      () => _i891.ArtistBioService(gh<_i519.Client>()),
    );
    gh.singleton<_i871.MissingArtworkService>(
      () => _i871.MissingArtworkService(gh<_i519.Client>()),
    );
    gh.singleton<_i545.ImportBackupUseCase>(
      () => _i545.ImportBackupUseCase(
        gh<_i320.IMusicRepository>(),
        gh<_i682.AppDatabase>(),
      ),
    );
    gh.singleton<_i41.SettingsCubit>(
      () => _i41.SettingsCubit(
        scannerService: gh<_i483.MediaScannerService>(),
        hiResAudioService: gh<_i1054.HiResAudioService>(),
        secureStorage: gh<_i558.FlutterSecureStorage>(),
      ),
    );
    gh.singletonAsync<_i366.PulsrAudioHandler>(
      () => _i366.PulsrAudioHandler.create(
        gh<_i320.IMusicRepository>(),
        gh<_i1053.YtmService>(),
      ),
      dispose: (i) => i.dispose(),
    );
    gh.factory<_i984.SearchCubit>(
      () => _i984.SearchCubit(
        searchUseCase: gh<_i644.SearchMusicUseCase>(),
        folderUseCases: gh<_i1017.FolderUseCases>(),
      ),
    );
    gh.lazySingleton<_i680.YtDownloadService>(
      () => _i680.YtDownloadService(
        gh<_i497.HttpClient>(),
        gh<_i1053.YtmService>(),
        gh<_i483.MediaScannerService>(),
        gh<_i320.IMusicRepository>(),
      ),
    );
    gh.singleton<_i838.CloudSyncService>(
      () => _i838.CloudSyncService(
        gh<_i244.AuthService>(),
        gh<_i320.IMusicRepository>(),
        gh<_i682.AppDatabase>(),
      ),
    );
    gh.factory<_i633.LibraryCubit>(
      () => _i633.LibraryCubit(
        getSongsUseCase: gh<_i168.GetSongsUseCase>(),
        getAlbumsUseCase: gh<_i496.GetAlbumsUseCase>(),
        getArtistsUseCase: gh<_i602.GetArtistsUseCase>(),
        getGenresUseCase: gh<_i485.GetGenresUseCase>(),
        getYearsUseCase: gh<_i652.GetYearsUseCase>(),
        getFavoritesUseCase: gh<_i117.GetFavoritesUseCase>(),
        toggleFavoriteUseCase: gh<_i800.ToggleFavoriteUseCase>(),
        folderUseCases: gh<_i1017.FolderUseCases>(),
        musicRepository: gh<_i320.IMusicRepository>(),
      ),
    );
    gh.singleton<_i783.IDownloadRepository>(
      () => _i877.DownloadRepositoryImpl(gh<_i680.YtDownloadService>()),
    );
    gh.singletonAsync<_i147.PlayerCubit>(
      () async => _i147.PlayerCubit(
        audioHandler: await getAsync<_i366.PulsrAudioHandler>(),
        repository: gh<_i320.IMusicRepository>(),
        toggleFavoriteUseCase: gh<_i800.ToggleFavoriteUseCase>(),
        settingsCubit: gh<_i41.SettingsCubit>(),
        widgetService: gh<_i651.WidgetService>(),
        scrobblerService: gh<_i748.ScrobblerService>(),
        settingsProfilesService: gh<_i341.SettingsProfilesService>(),
        deviceProfileService: gh<_i655.DeviceProfileService>(),
        hiResAudioService: gh<_i1054.HiResAudioService>(),
        latencyTracker: gh<_i626.PlaybackLatencyTracker>(),
      ),
    );
    gh.factory<_i1022.SmartPlaylistBuilderCubit>(
      () => _i1022.SmartPlaylistBuilderCubit(
        gh<_i632.ISmartPlaylistEngine>(),
        gh<_i792.PlaylistUseCases>(),
      ),
    );
    gh.singleton<_i1001.PauseDownloadUseCase>(
      () => _i1001.PauseDownloadUseCase(gh<_i783.IDownloadRepository>()),
    );
    gh.singleton<_i1001.ResumeDownloadUseCase>(
      () => _i1001.ResumeDownloadUseCase(gh<_i783.IDownloadRepository>()),
    );
    gh.singleton<_i1001.RetryDownloadUseCase>(
      () => _i1001.RetryDownloadUseCase(gh<_i783.IDownloadRepository>()),
    );
    gh.singleton<_i1001.DeleteDownloadUseCase>(
      () => _i1001.DeleteDownloadUseCase(gh<_i783.IDownloadRepository>()),
    );
    gh.singleton<_i233.ObserveDownloadsUseCase>(
      () => _i233.ObserveDownloadsUseCase(gh<_i783.IDownloadRepository>()),
    );
    gh.singleton<_i233.GetDownloadStorageStatsUseCase>(
      () =>
          _i233.GetDownloadStorageStatsUseCase(gh<_i783.IDownloadRepository>()),
    );
    gh.singleton<_i6.QueueDownloadUseCase>(
      () => _i6.QueueDownloadUseCase(gh<_i783.IDownloadRepository>()),
    );
    gh.singleton<_i6.QueueDownloadsBatchUseCase>(
      () => _i6.QueueDownloadsBatchUseCase(gh<_i783.IDownloadRepository>()),
    );
    gh.singleton<_i6.PrioritizeDownloadUseCase>(
      () => _i6.PrioritizeDownloadUseCase(gh<_i783.IDownloadRepository>()),
    );
    gh.singleton<_i6.ReorderDownloadsUseCase>(
      () => _i6.ReorderDownloadsUseCase(gh<_i783.IDownloadRepository>()),
    );
    gh.singletonAsync<_i134.FileIntentHandler>(
      () async => _i134.FileIntentHandler(
        gh<_i320.IMusicRepository>(),
        await getAsync<_i147.PlayerCubit>(),
      ),
    );
    gh.factory<_i918.AuthCubit>(
      () => _i918.AuthCubit(
        gh<_i244.AuthService>(),
        gh<_i838.CloudSyncService>(),
      ),
    );
    gh.singleton<_i752.DownloadsCubit>(
      () => _i752.DownloadsCubit(
        gh<_i6.QueueDownloadUseCase>(),
        gh<_i1001.PauseDownloadUseCase>(),
        gh<_i1001.ResumeDownloadUseCase>(),
        gh<_i1001.RetryDownloadUseCase>(),
        gh<_i1001.DeleteDownloadUseCase>(),
        gh<_i233.ObserveDownloadsUseCase>(),
        gh<_i233.GetDownloadStorageStatsUseCase>(),
        gh<_i6.ReorderDownloadsUseCase>(),
        gh<_i6.PrioritizeDownloadUseCase>(),
        gh<_i6.QueueDownloadsBatchUseCase>(),
      ),
    );
    gh.singletonAsync<_i309.YtmDownloadCubit>(
      () async => _i309.YtmDownloadCubit(
        gh<_i680.YtDownloadService>(),
        await getAsync<_i147.PlayerCubit>(),
        gh<_i783.IDownloadRepository>(),
      ),
    );
    return this;
  }
}

class _$NetworkModule extends _i953.NetworkModule {}

class _$StorageModule extends _i953.StorageModule {}
