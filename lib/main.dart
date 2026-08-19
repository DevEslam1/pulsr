// lib/main.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/theme/aura_theme.dart';
import 'core/theme/dynamic_theme_cubit.dart';
import 'core/router/app_router.dart';
import 'data/audio/audio_handler.dart';
import 'data/db/app_database.dart';
import 'data/repositories/music_repository.dart';
import 'data/scanner/media_scanner_service.dart';
import 'domain/usecases/get_songs_usecase.dart';
import 'domain/usecases/get_albums_usecase.dart';
import 'domain/usecases/get_artists_usecase.dart';
import 'domain/usecases/get_favorites_usecase.dart';
import 'domain/usecases/toggle_favorite_usecase.dart';
import 'domain/usecases/search_music_usecase.dart';
import 'domain/usecases/playlist_usecases.dart';
import 'domain/usecases/folder_usecases.dart';
import 'features/library/cubit/library_cubit.dart';
import 'features/player/cubit/player_cubit.dart';
import 'features/playlists/cubit/playlist_cubit.dart';
import 'features/search/cubit/search_cubit.dart';
import 'features/settings/cubit/settings_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // System Chrome configuration
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Database & Repository
  final db = AppDatabase();
  final repository = MusicRepository(db);

  // Initialize Audio Handler
  final audioHandler = await AudioService.init(
    builder: () => PulsrAudioHandler(repository),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.pulsr.audio',
      androidNotificationChannelName: 'Pulsr Audio Playback',
      androidNotificationOngoing: true,
      androidNotificationClickStartsActivity: true,
      androidStopForegroundOnPause: false,
      androidResumeOnClick: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  // Initialize Scanner Service
  final scannerService = MediaScannerService(repository);

  // Initialize Domain UseCases
  final getSongsUseCase = GetSongsUseCase(repository);
  final getAlbumsUseCase = GetAlbumsUseCase(repository);
  final getArtistsUseCase = GetArtistsUseCase(repository);
  final getFavoritesUseCase = GetFavoritesUseCase(repository);
  final toggleFavoriteUseCase = ToggleFavoriteUseCase(repository);
  final searchMusicUseCase = SearchMusicUseCase(repository);
  final playlistUseCases = PlaylistUseCases(repository);
  final folderUseCases = FolderUseCases(repository);

  runApp(
    PulsrApp(
      database: db,
      repository: repository,
      audioHandler: audioHandler,
      scannerService: scannerService,
      getSongsUseCase: getSongsUseCase,
      getAlbumsUseCase: getAlbumsUseCase,
      getArtistsUseCase: getArtistsUseCase,
      getFavoritesUseCase: getFavoritesUseCase,
      toggleFavoriteUseCase: toggleFavoriteUseCase,
      searchMusicUseCase: searchMusicUseCase,
      playlistUseCases: playlistUseCases,
      folderUseCases: folderUseCases,
    ),
  );
}

class PulsrApp extends StatefulWidget {
  final AppDatabase database;
  final MusicRepository repository;
  final PulsrAudioHandler audioHandler;
  final MediaScannerService scannerService;
  final GetSongsUseCase getSongsUseCase;
  final GetAlbumsUseCase getAlbumsUseCase;
  final GetArtistsUseCase getArtistsUseCase;
  final GetFavoritesUseCase getFavoritesUseCase;
  final ToggleFavoriteUseCase toggleFavoriteUseCase;
  final SearchMusicUseCase searchMusicUseCase;
  final PlaylistUseCases playlistUseCases;
  final FolderUseCases folderUseCases;

  const PulsrApp({
    super.key,
    required this.database,
    required this.repository,
    required this.audioHandler,
    required this.scannerService,
    required this.getSongsUseCase,
    required this.getAlbumsUseCase,
    required this.getArtistsUseCase,
    required this.getFavoritesUseCase,
    required this.toggleFavoriteUseCase,
    required this.searchMusicUseCase,
    required this.playlistUseCases,
    required this.folderUseCases,
  });

  @override
  State<PulsrApp> createState() => _PulsrAppState();
}

class _PulsrAppState extends State<PulsrApp> {
  late final _router = createRouter(widget.scannerService);

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: widget.database),
        RepositoryProvider<MusicRepository>.value(value: widget.repository),
        RepositoryProvider<PulsrAudioHandler>.value(value: widget.audioHandler),
        RepositoryProvider<MediaScannerService>.value(value: widget.scannerService),
        RepositoryProvider<GetSongsUseCase>.value(value: widget.getSongsUseCase),
        RepositoryProvider<GetAlbumsUseCase>.value(value: widget.getAlbumsUseCase),
        RepositoryProvider<GetArtistsUseCase>.value(value: widget.getArtistsUseCase),
        RepositoryProvider<GetFavoritesUseCase>.value(value: widget.getFavoritesUseCase),
        RepositoryProvider<ToggleFavoriteUseCase>.value(value: widget.toggleFavoriteUseCase),
        RepositoryProvider<SearchMusicUseCase>.value(value: widget.searchMusicUseCase),
        RepositoryProvider<PlaylistUseCases>.value(value: widget.playlistUseCases),
        RepositoryProvider<FolderUseCases>.value(value: widget.folderUseCases),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<DynamicThemeCubit>(
            create: (_) => DynamicThemeCubit(),
          ),
          BlocProvider<PlayerCubit>(
            create: (_) => PlayerCubit(
              audioHandler: widget.audioHandler,
              repository: widget.repository,
              toggleFavoriteUseCase: widget.toggleFavoriteUseCase,
            ),
          ),
          BlocProvider<LibraryCubit>(
            create: (_) => LibraryCubit(
              getSongsUseCase: widget.getSongsUseCase,
              getAlbumsUseCase: widget.getAlbumsUseCase,
              getArtistsUseCase: widget.getArtistsUseCase,
              getFavoritesUseCase: widget.getFavoritesUseCase,
              toggleFavoriteUseCase: widget.toggleFavoriteUseCase,
              folderUseCases: widget.folderUseCases,
            ),
          ),
          BlocProvider<SearchCubit>(
            create: (_) => SearchCubit(
              searchUseCase: widget.searchMusicUseCase,
            ),
          ),
          BlocProvider<PlaylistCubit>(
            create: (_) => PlaylistCubit(
              playlistUseCases: widget.playlistUseCases,
            ),
          ),
          BlocProvider<SettingsCubit>(
            create: (_) => SettingsCubit(
              scannerService: widget.scannerService,
            ),
          ),
        ],
        child: MaterialApp.router(
          title: 'Pulsr Music',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          darkTheme: AuraTheme.darkTheme,
          theme: AuraTheme.darkTheme,
          routerConfig: _router,
        ),
      ),
    );
  }
}
