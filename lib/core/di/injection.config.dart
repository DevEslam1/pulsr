// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:io' as _i497;

import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:pulsr/core/di/injection.dart' as _i953;
import 'package:pulsr/core/services/auth_service.dart' as _i535;
import 'package:pulsr/core/services/cloud_sync_service.dart' as _i225;
import 'package:pulsr/core/services/file_intent_handler.dart' as _i134;
import 'package:pulsr/core/services/lrclib_service.dart' as _i621;
import 'package:pulsr/core/services/scrobbler_service.dart' as _i629;
import 'package:pulsr/core/services/yt_download_service.dart' as _i742;
import 'package:pulsr/core/services/ytm_account_service.dart' as _i631;
import 'package:pulsr/core/services/ytm_service.dart' as _i391;
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart' as _i401;
import 'package:pulsr/data/audio/audio_handler.dart' as _i366;
import 'package:pulsr/data/db/app_database.dart' as _i682;
import 'package:pulsr/data/repositories/music_repository.dart' as _i626;
import 'package:pulsr/data/repositories/smart_playlist_engine.dart' as _i399;
import 'package:pulsr/data/scanner/media_scanner_service.dart' as _i483;
import 'package:pulsr/domain/repositories/music_repository_interface.dart'
    as _i320;
import 'package:pulsr/domain/usecases/backup_usecases.dart' as _i545;
import 'package:pulsr/domain/usecases/folder_usecases.dart' as _i1017;
import 'package:pulsr/domain/usecases/get_albums_usecase.dart' as _i496;
import 'package:pulsr/domain/usecases/get_artists_usecase.dart' as _i602;
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart' as _i117;
import 'package:pulsr/domain/usecases/get_genres_usecase.dart' as _i485;
import 'package:pulsr/domain/usecases/get_songs_usecase.dart' as _i168;
import 'package:pulsr/domain/usecases/get_years_usecase.dart' as _i651;
import 'package:pulsr/domain/usecases/playlist_io_usecases.dart' as _i265;
import 'package:pulsr/domain/usecases/playlist_usecases.dart' as _i792;
import 'package:pulsr/domain/usecases/search_music_usecase.dart' as _i644;
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart' as _i800;
import 'package:pulsr/features/auth/cubit/auth_cubit.dart' as _i918;
import 'package:pulsr/features/library/cubit/library_cubit.dart' as _i633;
import 'package:pulsr/features/player/cubit/player_cubit.dart' as _i147;
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart' as _i431;
import 'package:pulsr/features/search/cubit/search_cubit.dart' as _i984;
import 'package:pulsr/features/settings/cubit/settings_cubit.dart' as _i41;
import 'package:pulsr/features/smart_playlist_builder/smart_playlist_builder_cubit.dart'
    as _i790;
import 'package:pulsr/features/widgets/widget_service.dart' as _i42;
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart'
    as _i873;
import 'package:pulsr/features/ytm_search/cubit/ytm_search_cubit.dart' as _i171;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final networkModule = _$NetworkModule();
    gh.singleton<_i497.HttpClient>(() => networkModule.httpClient);
    gh.singleton<_i535.AuthService>(() => _i535.AuthService());
    gh.singleton<_i629.ScrobblerService>(() => _i629.ScrobblerService());
    gh.singleton<_i631.YtmAccountService>(() => _i631.YtmAccountService());
    gh.singleton<_i391.YtmService>(() => _i391.YtmService());
    gh.singleton<_i401.DynamicThemeCubit>(() => _i401.DynamicThemeCubit());
    gh.singleton<_i682.AppDatabase>(() => _i682.AppDatabase());
    gh.singleton<_i265.PlaylistExportUseCase>(
        () => _i265.PlaylistExportUseCase());
    gh.lazySingleton<_i42.WidgetService>(() => _i42.WidgetService());
    gh.singleton<_i399.SmartPlaylistEngine>(
        () => _i399.SmartPlaylistEngine(gh<_i682.AppDatabase>()));
    gh.singleton<_i320.IMusicRepository>(
        () => _i626.MusicRepository(gh<_i682.AppDatabase>()));
    gh.factory<_i171.YtmSearchCubit>(
        () => _i171.YtmSearchCubit(service: gh<_i391.YtmService>()));
    gh.singleton<_i792.PlaylistUseCases>(() => _i792.PlaylistUseCases(
          gh<_i320.IMusicRepository>(),
          gh<_i399.SmartPlaylistEngine>(),
        ));
    gh.singleton<_i621.LrclibService>(
        () => _i621.LrclibService(client: gh<_i497.HttpClient>()));
    gh.singleton<_i483.MediaScannerService>(
        () => _i483.MediaScannerService(gh<_i320.IMusicRepository>()));
    gh.singleton<_i545.ExportBackupUseCase>(
        () => _i545.ExportBackupUseCase(gh<_i320.IMusicRepository>()));
    gh.singleton<_i1017.FolderUseCases>(
        () => _i1017.FolderUseCases(gh<_i320.IMusicRepository>()));
    gh.singleton<_i496.GetAlbumsUseCase>(
        () => _i496.GetAlbumsUseCase(gh<_i320.IMusicRepository>()));
    gh.singleton<_i602.GetArtistsUseCase>(
        () => _i602.GetArtistsUseCase(gh<_i320.IMusicRepository>()));
    gh.singleton<_i117.GetFavoritesUseCase>(
        () => _i117.GetFavoritesUseCase(gh<_i320.IMusicRepository>()));
    gh.singleton<_i485.GetGenresUseCase>(
        () => _i485.GetGenresUseCase(gh<_i320.IMusicRepository>()));
    gh.singleton<_i168.GetSongsUseCase>(
        () => _i168.GetSongsUseCase(gh<_i320.IMusicRepository>()));
    gh.singleton<_i651.GetYearsUseCase>(
        () => _i651.GetYearsUseCase(gh<_i320.IMusicRepository>()));
    gh.singleton<_i265.PlaylistImportUseCase>(
        () => _i265.PlaylistImportUseCase(gh<_i320.IMusicRepository>()));
    gh.singleton<_i644.SearchMusicUseCase>(
        () => _i644.SearchMusicUseCase(gh<_i320.IMusicRepository>()));
    gh.singleton<_i800.ToggleFavoriteUseCase>(
        () => _i800.ToggleFavoriteUseCase(gh<_i320.IMusicRepository>()));
    gh.factory<_i431.PlaylistCubit>(() =>
        _i431.PlaylistCubit(playlistUseCases: gh<_i792.PlaylistUseCases>()));
    gh.singleton<_i225.CloudSyncService>(() => _i225.CloudSyncService(
          gh<_i535.AuthService>(),
          gh<_i320.IMusicRepository>(),
          gh<_i682.AppDatabase>(),
        ));
    gh.factory<_i790.SmartPlaylistBuilderCubit>(
        () => _i790.SmartPlaylistBuilderCubit(
              gh<_i399.SmartPlaylistEngine>(),
              gh<_i792.PlaylistUseCases>(),
            ));
    gh.lazySingleton<_i742.YtDownloadService>(() => _i742.YtDownloadService(
          gh<_i497.HttpClient>(),
          gh<_i391.YtmService>(),
          gh<_i483.MediaScannerService>(),
          gh<_i320.IMusicRepository>(),
        ));
    gh.factory<_i918.AuthCubit>(() => _i918.AuthCubit(
          gh<_i535.AuthService>(),
          gh<_i225.CloudSyncService>(),
        ));
    gh.singleton<_i545.ImportBackupUseCase>(() => _i545.ImportBackupUseCase(
          gh<_i320.IMusicRepository>(),
          gh<_i682.AppDatabase>(),
        ));
    await gh.singletonAsync<_i366.PulsrAudioHandler>(
      () => _i366.PulsrAudioHandler.create(
        gh<_i320.IMusicRepository>(),
        gh<_i391.YtmService>(),
      ),
      preResolve: true,
      dispose: (i) => i.dispose(),
    );
    gh.factory<_i984.SearchCubit>(() => _i984.SearchCubit(
          searchUseCase: gh<_i644.SearchMusicUseCase>(),
          folderUseCases: gh<_i1017.FolderUseCases>(),
        ));
    gh.singleton<_i41.SettingsCubit>(() =>
        _i41.SettingsCubit(scannerService: gh<_i483.MediaScannerService>()));
    gh.factory<_i633.LibraryCubit>(() => _i633.LibraryCubit(
          getSongsUseCase: gh<_i168.GetSongsUseCase>(),
          getAlbumsUseCase: gh<_i496.GetAlbumsUseCase>(),
          getArtistsUseCase: gh<_i602.GetArtistsUseCase>(),
          getGenresUseCase: gh<_i485.GetGenresUseCase>(),
          getYearsUseCase: gh<_i651.GetYearsUseCase>(),
          getFavoritesUseCase: gh<_i117.GetFavoritesUseCase>(),
          toggleFavoriteUseCase: gh<_i800.ToggleFavoriteUseCase>(),
          folderUseCases: gh<_i1017.FolderUseCases>(),
        ));
    gh.lazySingleton<_i147.PlayerCubit>(() => _i147.PlayerCubit(
          audioHandler: gh<_i366.PulsrAudioHandler>(),
          repository: gh<_i320.IMusicRepository>(),
          toggleFavoriteUseCase: gh<_i800.ToggleFavoriteUseCase>(),
          settingsCubit: gh<_i41.SettingsCubit>(),
          widgetService: gh<_i42.WidgetService>(),
          scrobblerService: gh<_i629.ScrobblerService>(),
        ));
    gh.factory<_i873.YtmDownloadCubit>(() => _i873.YtmDownloadCubit(
          gh<_i742.YtDownloadService>(),
          gh<_i147.PlayerCubit>(),
        ));
    gh.singleton<_i134.FileIntentHandler>(() => _i134.FileIntentHandler(
          gh<_i320.IMusicRepository>(),
          gh<_i147.PlayerCubit>(),
        ));
    return this;
  }
}

class _$NetworkModule extends _i953.NetworkModule {}
