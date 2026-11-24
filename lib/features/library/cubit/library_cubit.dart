// lib/features/library/cubit/library_cubit.dart
import 'dart:async';
import 'dart:isolate';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/bloc/base_cubit.dart';
import '../../../core/errors/failures.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/library_cache_manager.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_holder.dart';
import '../../../core/utils/song_classification.dart';
import '../../../data/audio/song_rating_store.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/ytm_track.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../domain/usecases/get_albums_usecase.dart';
import '../../../domain/usecases/get_artists_usecase.dart';
import '../../../domain/usecases/get_genres_usecase.dart';
import '../../../domain/usecases/get_years_usecase.dart';
import '../../../domain/usecases/get_favorites_usecase.dart';
import '../../../domain/usecases/toggle_favorite_usecase.dart';
import '../../../domain/usecases/folder_usecases.dart';
import 'library_state.dart';

import '../../../core/errors/app_error.dart';

@injectable
class LibraryCubit extends PulsrCubit<LibraryState> {
  final GetSongsUseCase _getSongsUseCase;
  final GetAlbumsUseCase _getAlbumsUseCase;
  final GetArtistsUseCase _getArtistsUseCase;
  final GetGenresUseCase _getGenresUseCase;
  final GetYearsUseCase _getYearsUseCase;
  final GetFavoritesUseCase _getFavoritesUseCase;
  final ToggleFavoriteUseCase _toggleFavoriteUseCase;
  final FolderUseCases _folderUseCases;
  final IMusicRepository? _musicRepository;
  final YtmService? _ytmService;
  final YtmAccountService? _ytmAccountService;

  StreamSubscription? _songsSub;
  StreamSubscription? _albumsSub;
  StreamSubscription? _artistsSub;
  StreamSubscription? _genresSub;
  StreamSubscription? _yearsSub;
  StreamSubscription? _favoritesSub;
  StreamSubscription? _downloadedSub;
  int _songsToken = 0;
  int _songsEmissionSeq = 0;
  int _genresToken = 0;
  int _yearsToken = 0;
  int _downloadedToken = 0;
  bool _snapshotConsumed = false;

  /// DB-level pagination window for the songs watch. The full 10k-row list
  /// is never held in state; [loadMoreSongs] grows the window by one page.
  static const int songsPageSize = 500;
  int _songsLimit = songsPageSize;
  bool _hasMoreSongs = false;
  bool _isLoadingMoreSongs = false;
  List<SongsTableData>? _ratingSortedSongs;

  /// True database song count from SQL `COUNT(*)` (distinct from the
  /// paginated `state.songs.length` window).
  final ValueNotifier<int?> totalSongCount = ValueNotifier<int?>(null);

  /// True when the last songs emission hit the current limit window, i.e.
  /// more rows may exist in the database.
  bool get hasMoreSongs => _hasMoreSongs;

  LibraryCubit({
    required GetSongsUseCase getSongsUseCase,
    required GetAlbumsUseCase getAlbumsUseCase,
    required GetArtistsUseCase getArtistsUseCase,
    required GetGenresUseCase getGenresUseCase,
    required GetYearsUseCase getYearsUseCase,
    required GetFavoritesUseCase getFavoritesUseCase,
    required ToggleFavoriteUseCase toggleFavoriteUseCase,
    required FolderUseCases folderUseCases,
    IMusicRepository? musicRepository,
    YtmService? ytmService,
    YtmAccountService? ytmAccountService,
  })  : _getSongsUseCase = getSongsUseCase,
        _getAlbumsUseCase = getAlbumsUseCase,
        _getArtistsUseCase = getArtistsUseCase,
        _getGenresUseCase = getGenresUseCase,
        _getYearsUseCase = getYearsUseCase,
        _getFavoritesUseCase = getFavoritesUseCase,
        _toggleFavoriteUseCase = toggleFavoriteUseCase,
        _folderUseCases = folderUseCases,
        _musicRepository = musicRepository ??
            (getIt.isRegistered<IMusicRepository>()
                ? getIt<IMusicRepository>()
                : null),
        _ytmService = ytmService,
        _ytmAccountService = ytmAccountService,
        super(const LibraryState(isLoading: true)) {
    init();
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSortBy = prefs.getString('library_sort_by') ?? 'title';
      final savedAscending = prefs.getBool('library_sort_ascending') ?? true;
      final savedViewMode = prefs.getString('library_view_mode') == 'grid'
          ? LibraryViewMode.grid
          : LibraryViewMode.list;

      if (!isClosed) {
        safeEmit(state.copyWith(
          sortBy: savedSortBy,
          ascending: savedAscending,
          viewMode: savedViewMode,
        ));
      }
    } catch (e, st) {
      ErrorLogger.log(
          'Failed to load library preferences from SharedPreferences',
          error: e,
          stackTrace: st,
          category: 'LibraryCubit');
    }

    // The disk snapshot exists only to paint a cold start before the live
    // watch emits. Re-applying it on a later init() (e.g. after a rescan)
    // would briefly resurrect deleted songs, so it is consumed exactly once.
    if (!_snapshotConsumed) {
      _snapshotConsumed = true;
      try {
        final snapshot = await LibraryCacheManager().loadSnapshot();
        if (snapshot != null &&
            snapshot.songs.isNotEmpty &&
            !isClosed &&
            state.songs.isEmpty) {
          // Pre-populate cached songs for instant paint, but leave isLoading
          // true until live database watchers emit their data to prevent
          // other tabs (albums, artists, favorites) from prematurely showing
          // an empty state.
          if (totalSongCount.value == null && snapshot.totalSongCount > 0) {
            totalSongCount.value = snapshot.totalSongCount;
          }
          safeEmit(state.copyWith(
            songs: snapshot.songs,
          ));
        }
      } catch (e, st) {
        ErrorLogger.log(
          'Failed to load library cache snapshot',
          error: e,
          stackTrace: st,
          category: 'LibraryCubit',
        );
      }
    }

    await _subscribeSongs();
    if (isClosed) return;
    _subscribeAlbums();
    _subscribeArtists();
    _subscribeGenres();
    _subscribeYears();
    _subscribeFavorites();
    _subscribeDownloaded();
    loadFolders();
  }

  void clearError() {
    safeEmit(state.copyWith(error: null));
  }

  /// Current hidden-folder paths, shared by every library/discovery
  /// subscription so exclusion changes propagate consistently.
  Future<List<String>> _currentExcludedFolders() async {
    try {
      final excludedRes = await _folderUseCases.getExcludedFolders();
      if (isClosed) return const [];
      final List<String> paths = excludedRes.fold((_) => <String>[], (r) => r);
      return paths;
    } catch (e, st) {
      ErrorLogger.log('Failed to fetch excluded folders',
          error: e, stackTrace: st, category: 'LibraryCubit');
      return const [];
    }
  }

  Future<void> _subscribeSongs({bool resetLimit = false}) async {
    final t = ++_songsToken;
    _songsSub?.cancel();
    removeFromComposite(_songsSub);
    _songsSub = null;
    if (resetLimit) {
      _songsLimit = songsPageSize;
      _hasMoreSongs = false;
      _ratingSortedSongs = null;
    }
    final excluded = await _currentExcludedFolders();
    if (isClosed || t != _songsToken) return;
    // Top-rated sort is prefs-backed: SQL has no rating column, so load the
    // sorted rating index and paginate the emitted slice incrementally without
    // truncating large libraries at 5,000 rows.
    final isRatingSort = state.sortBy == 'rating';
    final window = isRatingSort ? null : _songsLimit;
    _refreshTotalSongCount(excluded, token: t);
    _songsSub = autoSub(
      _getSongsUseCase.watchSongs(
        sortBy: isRatingSort ? 'title' : state.sortBy,
        ascending: state.ascending,
        limit: window,
        excludedFolders: excluded,
      ),
      (result) {
        if (isClosed || t != _songsToken) return;
        result.fold(
          (failure) {
            if (isClosed || t != _songsToken) return;
            _isLoadingMoreSongs = false;
            safeEmit(state.copyWith(
                error: failure, isLoading: false, isLoadingMore: false));
          },
          (songs) async {
            final emissionSeq = ++_songsEmissionSeq;
            if (isClosed || t != _songsToken) return;
            // Same optimistic-favorite overlay as the favorites watch: a live
            // DB emission can still carry the pre-toggle truth while a
            // toggleFavorite write is in flight, which would flip the row back
            // in the songs list even though the user just favorited it.
            if (_pendingFavoriteTargets.isNotEmpty) {
              songs = <SongsTableData>[
                for (final s in songs)
                  _pendingFavoriteTargets.containsKey(s.id)
                      ? s.copyWith(isFavorite: _pendingFavoriteTargets[s.id])
                      : s,
              ];
            }
            if (isRatingSort) {
              final sortedSongs =
                  await _sortByRating(songs, ascending: state.ascending);
              if (isClosed ||
                  t != _songsToken ||
                  emissionSeq != _songsEmissionSeq) {
                return;
              }
              _ratingSortedSongs = sortedSongs;
              final page = sortedSongs.length > _songsLimit
                  ? sortedSongs.sublist(0, _songsLimit)
                  : sortedSongs;
              _hasMoreSongs = sortedSongs.length > page.length;
              _isLoadingMoreSongs = false;
              totalSongCount.value = sortedSongs.length;
              safeEmit(state.copyWith(
                  songs: List<SongsTableData>.unmodifiable(page),
                  infoMessage: null,
                  error: null,
                  isLoading: false,
                  isLoadingMore: false));
              LibraryCacheManager().saveSnapshot(
                songs: page,
                totalSongCount: sortedSongs.length,
                albumCount: state.albums.length,
                artistCount: state.artists.length,
              );
              return;
            }
            _ratingSortedSongs = null;
            // Hitting the cap means the DB may hold more rows.
            _hasMoreSongs = songs.length >= _songsLimit;
            _isLoadingMoreSongs = false;
            if (isClosed ||
                t != _songsToken ||
                emissionSeq != _songsEmissionSeq) {
              return;
            }
            safeEmit(state.copyWith(
                songs: List<SongsTableData>.unmodifiable(songs),
                infoMessage: null,
                error: null,
                isLoading: false,
                isLoadingMore: false));
            if (!_hasMoreSongs) {
              totalSongCount.value = songs.length;
              LibraryCacheManager().saveSnapshot(
                songs: songs,
                totalSongCount: songs.length,
                albumCount: state.albums.length,
                artistCount: state.artists.length,
              );
            } else {
              _refreshTotalSongCount(
                excluded,
                token: t,
                snapshotPage: songs,
              );
            }
          },
        );
      },
    );
  }

  void _refreshTotalSongCount(
    List<String> excluded, {
    required int token,
    List<SongsTableData>? snapshotPage,
  }) {
    final repo = _musicRepository;
    if (repo == null) {
      if (snapshotPage != null) {
        LibraryCacheManager().saveSnapshot(
          songs: snapshotPage,
          totalSongCount: snapshotPage.length,
          albumCount: state.albums.length,
          artistCount: state.artists.length,
        );
      }
      return;
    }
    try {
      repo.getTotalSongCount(excludedFolders: excluded).then((res) {
        if (isClosed || token != _songsToken) return;
        final total = res.fold(
          (_) => snapshotPage?.length ?? totalSongCount.value ?? state.songs.length,
          (r) => r,
        );
        totalSongCount.value = total;
        if (snapshotPage != null) {
          LibraryCacheManager().saveSnapshot(
            songs: snapshotPage,
            totalSongCount: total,
            albumCount: state.albums.length,
            artistCount: state.artists.length,
          );
        }
      }).catchError((_) {
        if (snapshotPage != null) {
          LibraryCacheManager().saveSnapshot(
            songs: snapshotPage,
            totalSongCount: snapshotPage.length,
            albumCount: state.albums.length,
            artistCount: state.artists.length,
          );
        }
      });
    } catch (_) {
      if (snapshotPage != null) {
        LibraryCacheManager().saveSnapshot(
          songs: snapshotPage,
          totalSongCount: snapshotPage.length,
          albumCount: state.albums.length,
          artistCount: state.artists.length,
        );
      }
    }
  }

  /// Dart-side top-rated sort (ratings live in SharedPreferences).
  Future<List<SongsTableData>> _sortByRating(List<SongsTableData> songs,
      {bool ascending = false}) async {
    if (!getIt.isRegistered<SongRatingStore>()) {
      return songs;
    }
    final store = getIt<SongRatingStore>();
    try {
      await store.ready;
    } catch (_) {}

    final ratings = <int, int>{};
    for (final s in songs) {
      try {
        ratings[s.id] = store.getRating(s.id.toString());
      } catch (_) {
        ratings[s.id] = 0;
      }
    }

    // The rating reads above are prefs-cached (sync). Only the O(n log n)
    // sort is heavy, so it runs off the UI isolate for large libraries.
    final keys = List.generate(
      songs.length,
      (i) => (
        index: i,
        rating: ratings[songs[i].id] ?? 0,
        title: songs[i].title.toLowerCase(),
      ),
      growable: false,
    );
    final order = keys.length < 300
        ? sortSongIndicesByRating(keys, ascending)
        : await Isolate.run(() => sortSongIndicesByRating(keys, ascending));
    return List<SongsTableData>.generate(
      order.length,
      (i) => songs[order[i]],
      growable: false,
    );
  }

  /// Grows the songs window by one page. Called from the songs list scroll
  /// listener; no-ops while a page load is in flight or the cap wasn't hit.
  void loadMoreSongs() {
    if (_isLoadingMoreSongs || !_hasMoreSongs || isClosed) return;
    _songsLimit += songsPageSize;
    final cachedSorted = _ratingSortedSongs;
    if (state.sortBy == 'rating' && cachedSorted != null) {
      final page = cachedSorted.length > _songsLimit
          ? cachedSorted.sublist(0, _songsLimit)
          : cachedSorted;
      _hasMoreSongs = cachedSorted.length > page.length;
      _isLoadingMoreSongs = false;
      safeEmit(state.copyWith(
        songs: List<SongsTableData>.unmodifiable(page),
        isLoadingMore: false,
      ));
      return;
    }
    _isLoadingMoreSongs = true;
    safeEmit(state.copyWith(isLoadingMore: true));
    _subscribeSongs();
  }

  void _subscribeAlbums() {
    _albumsSub?.cancel();
    removeFromComposite(_albumsSub);
    _albumsSub = autoSub(_getAlbumsUseCase.watchAlbums(), (result) {
      result.fold(
        (failure) => safeEmit(state.copyWith(error: failure)),
        (albums) => safeEmit(state.copyWith(albums: List.unmodifiable(albums))),
      );
    });
  }

  void _subscribeArtists() {
    _artistsSub?.cancel();
    removeFromComposite(_artistsSub);
    _artistsSub = autoSub(_getArtistsUseCase.watchArtists(), (result) {
      result.fold(
        (failure) => safeEmit(state.copyWith(error: failure)),
        (artists) =>
            safeEmit(state.copyWith(artists: List.unmodifiable(artists))),
      );
    });
  }

  Future<void> _subscribeGenres() async {
    final t = ++_genresToken;
    _genresSub?.cancel();
    removeFromComposite(_genresSub);
    final excluded = await _currentExcludedFolders();
    if (isClosed || t != _genresToken) return;
    _genresSub = autoSub(
        _getGenresUseCase.watchGenres(excludedFolders: excluded), (result) {
      if (isClosed || t != _genresToken) return;
      result.fold(
        (failure) => safeEmit(state.copyWith(error: failure)),
        (genres) => safeEmit(state.copyWith(genres: List.unmodifiable(genres))),
      );
    });
  }

  Future<void> _subscribeYears() async {
    final t = ++_yearsToken;
    _yearsSub?.cancel();
    removeFromComposite(_yearsSub);
    final excluded = await _currentExcludedFolders();
    if (isClosed || t != _yearsToken) return;
    _yearsSub = autoSub(_getYearsUseCase.watchYears(excludedFolders: excluded),
        (result) {
      if (isClosed || t != _yearsToken) return;
      result.fold(
        (failure) => safeEmit(state.copyWith(error: failure)),
        (years) => safeEmit(state.copyWith(years: List.unmodifiable(years))),
      );
    });
  }

  /// Streams songs directly inside [folderPath] from the repository, so the
  /// folder tree does not depend on the paginated songs window.
  Stream<Result<List<SongsTableData>>> watchFolderSongs(String folderPath) {
    return _folderUseCases.watchFolderSongs(folderPath);
  }

  void _subscribeDownloaded() {
    final t = ++_downloadedToken;
    _downloadedSub?.cancel();
    removeFromComposite(_downloadedSub);
    final repo = _musicRepository;
    if (repo == null) return;
    () async {
      final excluded = await _currentExcludedFolders();
      if (isClosed || t != _downloadedToken) return;
      _downloadedSub = autoSub(
          repo.watchDownloadedSongs(excludedFolders: excluded), (result) {
        if (isClosed || t != _downloadedToken) return;
        result.fold(
          (failure) => safeEmit(state.copyWith(error: failure)),
          (songs) => safeEmit(state.copyWith(
            downloadedSongs: List<SongsTableData>.unmodifiable(
              songs.where(isDownloadedOnlineTrack),
            ),
          )),
        );
      });
    }();
  }

  void _subscribeFavorites() {
    _favoritesSub?.cancel();
    removeFromComposite(_favoritesSub);
    _favoritesSub = autoSub(_getFavoritesUseCase.watchFavorites(), (result) {
      result.fold(
        (failure) => safeEmit(state.copyWith(error: failure)),
        (favs) {
          if (_pendingFavoriteTargets.isEmpty) {
            safeEmit(state.copyWith(
                favorites: List<SongsTableData>.unmodifiable(favs)));
            return;
          }
          // A favorite toggle is in flight: the DB still holds the pre-toggle
          // truth and this emission would flip the row back until the write
          // settles. Hold the optimistic direction for the affected songs.
          var merged = favs;
          _pendingFavoriteTargets.forEach((songId, targetFav) {
            final has = merged.any((s) => s.id == songId);
            if (targetFav && !has) {
              SongsTableData? optimistic;
              for (final s in state.favorites) {
                if (s.id == songId) {
                  optimistic = s;
                  break;
                }
              }
              if (optimistic == null) {
                for (final s in state.songs) {
                  if (s.id == songId) {
                    optimistic = s;
                    break;
                  }
                }
              }
              if (optimistic != null) {
                merged = [...merged, optimistic.copyWith(isFavorite: true)];
              }
            } else if (!targetFav && has) {
              merged = merged.where((s) => s.id != songId).toList();
            }
          });
          final seen = <int>{};
          merged = merged.where((s) => seen.add(s.id)).toList();
          safeEmit(state.copyWith(
              favorites: List<SongsTableData>.unmodifiable(merged)));
        },
      );
    });
  }

  Future<void> loadFolders() async {
    final result = await _folderUseCases.getFolderHierarchy();
    if (isClosed) return;
    result.fold(
      (failure) => safeEmit(state.copyWith(error: failure)),
      (folders) =>
          safeEmit(state.copyWith(folders: List.unmodifiable(folders))),
    );
  }

  void updateSort(String sortBy, bool ascending) {
    safeEmit(state.copyWith(sortBy: sortBy, ascending: ascending));
    _subscribeSongs(resetLimit: true);
    SharedPreferences.getInstance().then((prefs) async {
      try {
        await prefs.setString('library_sort_by', sortBy);
        await prefs.setBool('library_sort_ascending', ascending);
      } catch (e, st) {
        ErrorLogger.log('Failed to persist library sort',
            error: e, stackTrace: st, category: 'LibraryCubit');
      }
    }).catchError((e, st) {
      ErrorLogger.log('Failed to persist library sort',
          error: e, stackTrace: st, category: 'LibraryCubit');
    });
  }

  void toggleViewMode() {
    final nextMode = state.viewMode == LibraryViewMode.list
        ? LibraryViewMode.grid
        : LibraryViewMode.list;
    safeEmit(state.copyWith(viewMode: nextMode));
    SharedPreferences.getInstance().then((prefs) async {
      try {
        await prefs.setString('library_view_mode', nextMode.name);
      } catch (e, st) {
        ErrorLogger.log('Failed to persist view mode',
            error: e, stackTrace: st, category: 'LibraryCubit');
      }
    }).catchError((e, st) {
      ErrorLogger.log('Failed to persist view mode',
          error: e, stackTrace: st, category: 'LibraryCubit');
    });
  }

  final Map<int, int> _favoriteOpTokens = {};

  /// Optimistic favorite direction per song while a toggle use case is in
  /// flight (songId -> target isFavorite). Live favorites emissions are
  /// reconciled against it so the row does not flip back to the pre-toggle DB
  /// truth for the duration of the write.
  final Map<int, bool> _pendingFavoriteTargets = {};
  // B-1 & FIX-C02: Ref-counted per-song mutex serializes concurrent favorite writes
  // without losing serialization when a lock is released while callers wait.
  final Map<int, _SongLock> _favoriteLocks = {};

  Future<void> toggleFavorite(int songId) async {
    if (isClosed) return;
    final songLock = _favoriteLocks.putIfAbsent(songId, _SongLock.new);
    songLock.refCount++;
    await songLock.mutex.acquire();
    if (isClosed) {
      songLock.mutex.release();
      songLock.refCount--;
      if (songLock.refCount == 0 && _favoriteLocks[songId] == songLock) {
        _favoriteLocks.remove(songId);
      }
      return;
    }

    final opToken = (_favoriteOpTokens[songId] ?? 0) + 1;
    _favoriteOpTokens[songId] = opToken;

    try {
      List<SongsTableData> songsWith(bool isFavorite) => state.songs
          .map((s) => s.id == songId ? s.copyWith(isFavorite: isFavorite) : s)
          .toList();

      // Resolve the pre-toggle row. `state.favorites` is authoritative when
      // present, but a favorited song can be absent from a not-yet-loaded or
      // filtered list, so fall back to the songs page and finally a DB read
      // instead of assuming "not a favorite" (which would flip the wrong way).
      SongsTableData? known;
      for (final s in state.favorites) {
        if (s.id == songId) {
          known = s;
          break;
        }
      }
      known ??= state.songs.where((s) => s.id == songId).firstOrNull;
      if (known == null && _musicRepository != null) {
        try {
          final res = await _musicRepository!.getSongsByIds([songId]);
          known = res.fold((_) => null, (list) => list.firstOrNull);
        } catch (e, st) {
          ErrorLogger.log('Favorite toggle: song lookup failed for $songId',
              error: e, stackTrace: st, category: 'LibraryCubit');
        }
        // The repository lookup awaited: the favorites watch-stream may have
        // emitted during the gap. Bail if closed or superseded instead of
        // clobbering that update with the stale pre-await snapshot.
        if (isClosed || _favoriteOpTokens[songId] != opToken) return;
      }

      // Keep the actual pre-toggle row: rollback must restore it even when the
      // song is not visible in the current (possibly filtered) songs list.
      final preToggleFav = known;
      final wasFav = known?.isFavorite ?? false;

      if (wasFav) {
        _pendingFavoriteTargets[songId] = false;
        final favs = List<SongsTableData>.from(state.favorites)
          ..removeWhere((s) => s.id == songId);
        safeEmit(state.copyWith(favorites: favs, songs: songsWith(false)));
      } else {
        _pendingFavoriteTargets[songId] = true;
        if (known != null) {
          // Re-read favorites after any await so a watch emission that landed in
          // the gap is not overwritten by our optimistic emit.
          final favs = List<SongsTableData>.from(state.favorites);
          if (!favs.any((s) => s.id == songId)) {
            favs.add(known.copyWith(isFavorite: true));
          }
          safeEmit(state.copyWith(favorites: favs, songs: songsWith(true)));
        }
      }

      try {
        Result<bool> result;
        try {
          result = await _toggleFavoriteUseCase(songId);
        } catch (e, st) {
          // The use case normally returns Left; a raw throw must not leak the
          // in-flight bookkeeping or crash the awaiting UI.
          ErrorLogger.log('Favorite toggle failed for song $songId',
              error: e, stackTrace: st, category: 'LibraryCubit');
          result = Left(DatabaseFailure(
              L10nHolder.current?.saveFailed ?? 'Could not update favorite'));
        }

        if (isClosed || _favoriteOpTokens[songId] != opToken) return;

        final failureMessage =
            result.fold<String?>((l) => l.message, (_) => null);
        if (failureMessage == null) {
          safeEmit(state.copyWith(error: null));
          return;
        }

        // FIX-H02: Rollback restores from pre-toggle snapshot. If wasFav == false,
        // explicitly ensure song is removed from reconciled favorites AND emit songsWith(false).
        final reconciled = List<SongsTableData>.from(state.favorites);
        if (wasFav) {
          if (!reconciled.any((s) => s.id == songId) && preToggleFav != null) {
            reconciled.add(preToggleFav.copyWith(isFavorite: true));
          }
        } else {
          if (reconciled.any((s) => s.id == songId)) {
            reconciled.removeWhere((s) => s.id == songId);
          }
        }

        safeEmit(state.copyWith(
          favorites: reconciled,
          songs: songsWith(wasFav),
          error: uiError(failureMessage),
        ));
      } finally {
        // Bookkeeping is handled once in the outer finally below.
      }
    } finally {
      if (_favoriteOpTokens[songId] == opToken) {
        _favoriteOpTokens.remove(songId);
        _pendingFavoriteTargets.remove(songId);
      }
      songLock.mutex.release();
      songLock.refCount--;
      if (songLock.refCount == 0 && _favoriteLocks[songId] == songLock) {
        _favoriteLocks.remove(songId);
      }
    }
  }

  /// Atomically updates favorite state for every song in [songs].
  /// Uses a single [AppDatabase] transaction when available so batch
  /// favorite-all avoids N separate writes and partial failure states.
  Future<void> setSongsFavorite(
      List<SongsTableData> songs, bool targetFavorite) async {
    if (isClosed || songs.isEmpty) return;
    final targetIds = songs
        .where((s) => s.isFavorite != targetFavorite)
        .map((s) => s.id)
        .toList(growable: false);
    if (targetIds.isEmpty) return;

    if (getIt.isRegistered<AppDatabase>()) {
      final db = getIt<AppDatabase>();
      final idSet = targetIds.toSet();
      final prevFavorites = state.favorites;
      final prevSongs = state.songs;
      for (final id in targetIds) {
        _pendingFavoriteTargets[id] = targetFavorite;
      }

      final nextSongs = [
        for (final s in state.songs)
          idSet.contains(s.id) ? s.copyWith(isFavorite: targetFavorite) : s,
      ];
      final nextFavs = List<SongsTableData>.from(state.favorites);
      if (targetFavorite) {
        for (final s in songs) {
          if (!nextFavs.any((f) => f.id == s.id)) {
            nextFavs.add(s.copyWith(isFavorite: true));
          }
        }
      } else {
        nextFavs.removeWhere((f) => idSet.contains(f.id));
      }
      safeEmit(state.copyWith(favorites: nextFavs, songs: nextSongs));

      try {
        await db.transaction(() async {
          await (db.update(db.songsTable)..where((t) => t.id.isIn(targetIds)))
              .write(SongsTableCompanion(isFavorite: Value(targetFavorite)));
        });
        if (!isClosed) safeEmit(state.copyWith(error: null));
      } catch (e, st) {
        ErrorLogger.log('Batch setSongsFavorite failed',
            error: e, stackTrace: st, category: 'LibraryCubit');
        if (!isClosed) {
          safeEmit(state.copyWith(
            favorites: prevFavorites,
            songs: prevSongs,
            error: uiError(
                L10nHolder.current?.saveFailed ?? 'Could not update favorites'),
          ));
        }
      } finally {
        for (final id in targetIds) {
          _pendingFavoriteTargets.remove(id);
        }
      }
      return;
    }

    for (final id in targetIds) {
      if (isClosed) return;
      await toggleFavorite(id);
    }
  }

  Future<Result<void>> toggleFolderExclusion(String folderPath) async {
    final result = await _folderUseCases.toggleExcludeFolder(folderPath);
    if (isClosed) return result;
    final failureMessage = result.fold<String?>((l) => l.message, (_) => null);
    if (failureMessage != null) {
      safeEmit(state.copyWith(error: uiError(failureMessage)));
      return result;
    }
    await loadFolders();
    if (isClosed) return result;
    await _subscribeSongs();
    _subscribeGenres();
    _subscribeYears();
    _subscribeDownloaded();
    return result;
  }

  // Multi-select actions
  void toggleSongSelection(int songId) {
    final current = Set<int>.from(state.selectedSongIds);
    if (current.contains(songId)) {
      current.remove(songId);
    } else {
      current.add(songId);
    }
    safeEmit(state.copyWith(
      selectedSongIds: current,
      isMultiSelectMode: current.isNotEmpty,
    ));
  }

  /// Selects an explicit set of songs. Used by tab-scoped "Select all" so
  /// Favorites/Downloaded can never silently select the whole library.
  void selectSongs(Iterable<int> ids) {
    final selected = ids.toSet();
    if (selected.isEmpty) {
      clearSelection();
      return;
    }
    safeEmit(
        state.copyWith(selectedSongIds: selected, isMultiSelectMode: true));
  }

  /// Selects every song in the library. Bounded (gap 06-04): resolves IDs in a
  /// capped window (2000) so a 10k+ select-all stays instant and never
  /// materialises the whole library into memory at once.
  static const int selectAllCap = 2000;
  Future<void> selectAllSongs() async {
    if (!_hasMoreSongs) {
      final allIds = state.songs.map((s) => s.id).toSet();
      safeEmit(
          state.copyWith(selectedSongIds: allIds, isMultiSelectMode: true));
      return;
    }
    final repo = _musicRepository;
    if (repo == null) {
      final allIds = state.songs.map((s) => s.id).toSet();
      safeEmit(
          state.copyWith(selectedSongIds: allIds, isMultiSelectMode: true));
      return;
    }
    try {
      final excludedRes = await _folderUseCases.getExcludedFolders();
      final excluded = excludedRes.fold((_) => <String>[], (r) => r);
      if (isClosed) return;
      final res = await repo
          .watchAllSongs(limit: selectAllCap, excludedFolders: excluded)
          .first
          .timeout(const Duration(seconds: 3));
      if (isClosed) return;
      res.fold(
        (failure) => safeEmit(state.copyWith(error: failure)),
        (songs) {
          final capNotice = L10nHolder.current != null
              ? L10nHolder.current!.songsCount(selectAllCap)
              : 'Selected first $selectAllCap tracks (library exceeds cap)';
          safeEmit(state.copyWith(
            selectedSongIds: songs.map((s) => s.id).toSet(),
            isMultiSelectMode: true,
            infoMessage: songs.length >= selectAllCap ? capNotice : null,
          ));
        },
      );
    } catch (e, st) {
      if (isClosed) return;
      ErrorLogger.log('selectAllSongs failed, falling back to loaded songs',
          error: e, stackTrace: st, category: 'LibraryCubit');
      final allIds = state.songs.map((s) => s.id).toSet();
      safeEmit(
          state.copyWith(selectedSongIds: allIds, isMultiSelectMode: true));
    }
  }

  void clearSelection() {
    safeEmit(state.copyWith(selectedSongIds: {}, isMultiSelectMode: false));
  }

  /// Resolves the selected songs, fetching any that are outside the currently
  /// loaded page from the repository so batch actions are not silently
  /// truncated to the visible window.
  Future<List<SongsTableData>> getSelectedSongs() async {
    final ids = state.selectedSongIds;
    if (ids.isEmpty) return const [];
    final loaded = <int, SongsTableData>{
      for (final s in state.songs) s.id: s,
    };
    final result = <SongsTableData>[];
    final missing = <int>[];
    for (final id in ids) {
      final s = loaded[id];
      if (s != null) {
        result.add(s);
      } else {
        missing.add(id);
      }
    }
    final repo = _musicRepository;
    if (missing.isNotEmpty && repo != null) {
      final res = await repo.getSongsByIds(missing);
      if (isClosed) return result;
      res.fold((_) {}, result.addAll);
    }
    return result;
  }

  /// Permanently deletes the current selection from the database and, for
  /// local files, from disk. Returns the number removed, or -1 on failure.
  /// Clears the selection on success.
  Future<int> deleteSelectedSongs() async {
    if (isClosed) return 0;
    final selected = await getSelectedSongs();
    if (isClosed) return 0;
    if (selected.isEmpty) {
      clearSelection();
      return 0;
    }
    final repo = _musicRepository ??
        (getIt.isRegistered<IMusicRepository>()
            ? getIt<IMusicRepository>()
            : null);
    if (repo == null) {
      safeEmit(state.copyWith(
          error: uiError(L10nHolder.current?.deleteIsUnavailable ??
              'Delete is unavailable right now')));
      return -1;
    }
    final ids = selected.map((s) => s.id).toList();
    final result = await repo.deleteSongs(ids);
    if (isClosed) return 0;
    return result.fold(
      (failure) {
        safeEmit(state.copyWith(error: failure));
        return -1;
      },
      (_) {
        clearSelection();
        return ids.length;
      },
    );
  }

  /// Batch imports YouTube Music playlist tracks as Favorites.
  /// M-3: Returns -1 on repository failure (distinguishable from a genuine
  /// 0 tracks imported) so callers can surface the error to the UI.
  Future<int> importYtmTracksAsFavorites(List<YtmTrack> tracks) async {
    final repo = _musicRepository ??
        (getIt.isRegistered<IMusicRepository>()
            ? getIt<IMusicRepository>()
            : null);
    if (repo == null) return -1;
    final result = await repo.importOnlineTracksAsFavorites(tracks);
    return result.fold((failure) {
      ErrorLogger.log(
        'importYtmTracksAsFavorites failed: ${failure.message}',
        category: 'LibraryCubit',
      );
      return -1;
    }, (count) => count);
  }

  YtmService? get _resolvedYtmService => _ytmService ??
      (getIt.isRegistered<YtmService>() ? getIt<YtmService>() : null);

  YtmAccountService? get _resolvedYtmAccountService => _ytmAccountService ??
      (getIt.isRegistered<YtmAccountService>()
          ? getIt<YtmAccountService>()
          : null);

  bool get isYtmLoggedIn => _resolvedYtmAccountService?.isLoggedIn ?? false;

  /// Fetches a public YouTube Music playlist URL/ID (or liked music list `LM`/`LL`
  /// when signed in) and imports all tracks as favorites.
  Future<int> importYtmPlaylistAsFavorites(String rawUrl) async {
    final ytmService = _resolvedYtmService;
    if (ytmService == null) return -1;
    var tracks = await ytmService.getPlaylistTracks(rawUrl,
        limit: kYtmMaxPlaylistTracks);
    if (tracks.isEmpty &&
        (rawUrl.contains('list=LM') ||
            rawUrl.contains('list=LL') ||
            rawUrl == 'LM' ||
            rawUrl == 'LL')) {
      final ytmAccount = _resolvedYtmAccountService;
      if (ytmAccount != null && ytmAccount.isLoggedIn) {
        tracks = await ytmAccount.fetchLikedSongs(
            maxTracks: kYtmMaxPlaylistTracks);
      }
    }
    if (tracks.isEmpty) return 0;
    return importYtmTracksAsFavorites(tracks);
  }

  /// Synchronizes private Liked Music from the authenticated YouTube Music web account.
  ///
  /// Success returns the imported count. Failures set [LibraryState.errorMessage]
  /// and rethrow (auth failures as [YtmException] with `isAuth == true`) so the
  /// caller can present session-expired recovery instead of "Synced 0".
  Future<int> syncYtmAccountLikes() async {
    final accountService = _resolvedYtmAccountService;
    if (accountService == null || !accountService.isLoggedIn) {
      final msg = L10nHolder.current?.ytmSessionExpired ??
          'Not signed in to YouTube Music';
      safeEmit(state.copyWith(error: uiError(msg)));
      throw YtmException('SIGN_IN_REQUIRED', msg);
    }

    final List<YtmTrack> tracks;
    try {
      tracks =
          await accountService.fetchLikedSongs(maxTracks: kYtmMaxPlaylistTracks);
    } catch (e, st) {
      ErrorLogger.log('Failed to sync YTM account likes',
          error: e, stackTrace: st, category: 'LibraryCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(
            error: uiError(L10nHolder.current?.browseFailedToFetch ??
                'Failed to sync YouTube Music likes')));
      }
      rethrow;
    }

    final count = await importYtmTracksAsFavorites(tracks);
    if (count < 0) {
      if (!isClosed) {
        safeEmit(state.copyWith(
            error: uiError(L10nHolder.current?.importFailed ??
                'Failed to import YouTube Music liked songs')));
      }
      throw YtmException(
          'YTM_IMPORT_FAILED',
          L10nHolder.current?.importFailed ??
              'Failed to import liked songs');
    }
    return count;
  }

  @override
  Future<void> close() {
    _songsSub?.cancel();
    _albumsSub?.cancel();
    _artistsSub?.cancel();
    _genresSub?.cancel();
    _yearsSub?.cancel();
    _favoritesSub?.cancel();
    _downloadedSub?.cancel();
    _favoriteLocks.clear();
    totalSongCount.dispose();
    return super.close();
  }
}

class _SongLock {
  final Mutex mutex = Mutex();
  int refCount = 0;
}

/// Pure rating sort used both inline (small libraries) and inside
/// `Isolate.run` (large libraries). Returns song indices in display order.
@visibleForTesting
List<int> sortSongIndicesByRating(
  List<({int index, int rating, String title})> keys,
  bool ascending,
) {
  final sorted = List<int>.generate(keys.length, (i) => i);
  sorted.sort((ia, ib) {
    final a = keys[ia];
    final b = keys[ib];
    final cmp = a.rating.compareTo(b.rating);
    if (cmp != 0) return ascending ? cmp : -cmp;
    return a.title.compareTo(b.title);
  });
  return List<int>.generate(sorted.length, (i) => keys[sorted[i]].index);
}
