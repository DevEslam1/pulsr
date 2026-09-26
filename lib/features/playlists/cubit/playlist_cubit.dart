// lib/features/playlists/cubit/playlist_cubit.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/bloc/base_cubit.dart';
import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/network/connectivity_guard.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/utils/error_logger.dart';
import '../../../domain/models/smart_playlist_criteria.dart';
import '../../../domain/models/ytm_track.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import 'playlist_state.dart';

// ---------------------------------------------------------------------------
// Online-playlist value objects (Cached locally in SharedPreferences)
// ---------------------------------------------------------------------------

enum YtmFetchStatus { idle, loading, error, done }

/// A single fetched online (YouTube Music) playlist held in memory.
class OnlinePlaylistEntry {
  final String id; // playlist URL or 'liked'
  final String title;
  final String uploader;
  final List<YtmTrack> tracks;

  const OnlinePlaylistEntry({
    required this.id,
    required this.title,
    required this.uploader,
    required this.tracks,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'uploader': uploader,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory OnlinePlaylistEntry.fromJson(Map<String, dynamic> json) =>
      OnlinePlaylistEntry(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'YouTube Playlist',
        uploader: json['uploader'] as String? ?? '',
        tracks: (json['tracks'] as List<dynamic>? ?? [])
            .map((t) => YtmTrack.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}

/// Reactive state for the online-playlists section, exposed as a
/// [ValueNotifier] so the UI can subscribe without touching the freezed state.
class YtmOnlineState {
  final YtmFetchStatus likedStatus;
  final String? likedError;
  final List<YtmTrack> likedTracks;

  final YtmFetchStatus accountStatus;
  final String? accountError;
  final List<YtmAccountPlaylist> accountPlaylists;

  final YtmFetchStatus customStatus;
  final String? customError;
  final List<OnlinePlaylistEntry> customPlaylists;

  final bool isAutoFetching;

  const YtmOnlineState({
    this.likedStatus = YtmFetchStatus.idle,
    this.likedError,
    this.likedTracks = const [],
    this.accountStatus = YtmFetchStatus.idle,
    this.accountError,
    this.accountPlaylists = const [],
    this.customStatus = YtmFetchStatus.idle,
    this.customError,
    this.customPlaylists = const [],
    this.isAutoFetching = false,
  });

  YtmOnlineState copyWith({
    YtmFetchStatus? likedStatus,
    String? likedError,
    List<YtmTrack>? likedTracks,
    YtmFetchStatus? accountStatus,
    String? accountError,
    List<YtmAccountPlaylist>? accountPlaylists,
    YtmFetchStatus? customStatus,
    String? customError,
    List<OnlinePlaylistEntry>? customPlaylists,
    bool? isAutoFetching,
    bool clearLikedError = false,
    bool clearAccountError = false,
    bool clearCustomError = false,
  }) {
    return YtmOnlineState(
      likedStatus: likedStatus ?? this.likedStatus,
      likedError: clearLikedError ? null : (likedError ?? this.likedError),
      likedTracks: likedTracks ?? this.likedTracks,
      accountStatus: accountStatus ?? this.accountStatus,
      accountError:
          clearAccountError ? null : (accountError ?? this.accountError),
      accountPlaylists: accountPlaylists ?? this.accountPlaylists,
      customStatus: customStatus ?? this.customStatus,
      customError: clearCustomError ? null : (customError ?? this.customError),
      customPlaylists: customPlaylists ?? this.customPlaylists,
      isAutoFetching: isAutoFetching ?? this.isAutoFetching,
    );
  }
}

// ---------------------------------------------------------------------------
// Cubit
// ---------------------------------------------------------------------------

@injectable
class PlaylistCubit extends PulsrCubit<PlaylistState> {
  static const String _onlineCacheKey = 'ytm_cached_online_playlists_v1';
  final PlaylistUseCases _playlistUseCases;
  StreamSubscription? _playlistsSub;
  StreamSubscription? _playlistSongsSub;
  final Map<int, StreamSubscription> _smartSubscriptions = {};
  final Map<int, String> _smartCriteriaJson = {};
  final Queue<Future<void> Function()> _cacheSaveQueue = Queue<Future<void> Function()>();
  bool _cacheSaveRunning = false;
  bool _isSeedingChecked = false;

  /// Reactive online-playlist state. Widgets use [ValueListenableBuilder]
  /// to rebuild only when this changes, without touching the freezed state.
  final ytmOnline = ValueNotifier<YtmOnlineState>(const YtmOnlineState());

  /// H-08: Set before [ytmOnline] is disposed so late async callbacks bail out
  /// instead of writing to (or reading) a disposed notifier.
  bool _disposed = false;

  /// Safe accessor that returns default state if cubit/notifier is disposed.
  YtmOnlineState get onlineState => _disposed ? const YtmOnlineState() : ytmOnline.value;

  /// Safe state mutator guarded against post-dispose execution (C2).
  void _setOnlineState(YtmOnlineState Function(YtmOnlineState current) update) {
    if (_disposed || isClosed) return;
    try {
      ytmOnline.value = update(ytmOnline.value);
    } catch (_) {}
  }

  void _setOnlineStateDirect(YtmOnlineState newState) {
    if (_disposed || isClosed) return;
    try {
      ytmOnline.value = newState;
    } catch (_) {}
  }

  PlaylistCubit({required PlaylistUseCases playlistUseCases})
      : _playlistUseCases = playlistUseCases,
        super(const PlaylistState(isLoading: true)) {
    _init();
  }

  void _init() {
    _subscribePlaylists();
    unawaited(_initOnline());
  }

  void _subscribePlaylists() {
    _playlistsSub?.cancel();
    _playlistsSub = autoSub(_playlistUseCases.watchPlaylists(), (result) {
      result.fold(
        (failure) => safeEmit(state.copyWith(
            errorMessage: failure.message, isLoading: false)),
        (playlists) {
          safeEmit(state.copyWith(
              playlists: playlists, errorMessage: null, isLoading: false));
          _updateSmartCounts(playlists);
          if (!_isSeedingChecked) {
            _isSeedingChecked = true;
            _checkSeeding(playlists);
          }
        },
      );
    });
  }

  /// Re-subscribes to the playlists stream after a failure so the UI can offer
  /// a retry action instead of leaving a stale error on screen.
  void reloadPlaylists() {
    safeEmit(state.copyWith(errorMessage: null));
    _subscribePlaylists();
  }

  /// Restores the cached online library before any live fetch is scheduled.
  Future<void> _initOnline() async {
    await _loadOnlineCache();
    if (isClosed) return;

    // Auto-update online playlists & liked songs in background on every restart
    if (AppConfig.ytmEnabled) {
      getIt<YtmAccountService>()
          .loginState
          .removeListener(_onYtmLoginStateChanged);
      getIt<YtmAccountService>()
          .loginState
          .addListener(_onYtmLoginStateChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        autoTimer(Timer(const Duration(seconds: 2), () {
          if (!isClosed) {
            autoFetchOnlineLibrary(force: true);
          }
        }));
      });
    }
  }

  void _onYtmLoginStateChanged() {
    if (_disposed || isClosed) return;
    if (!getIt<YtmAccountService>().isLoggedIn) {
      clearOnlinePlaylists();
    }
  }

  Future<void> _loadOnlineCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (isClosed) return;
      final raw = prefs.getString(_onlineCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final likedTracks = (data['likedTracks'] as List<dynamic>? ?? [])
            .map((t) => YtmTrack.fromJson(t as Map<String, dynamic>))
            .toList();
        final accountPlaylists = (data['accountPlaylists'] as List<dynamic>? ??
                [])
            .map((p) => YtmAccountPlaylist.fromJson(p as Map<String, dynamic>))
            .toList();
        var rawCustomList = (data['customPlaylists'] as List<dynamic>? ?? [])
            .map((p) => OnlinePlaylistEntry.fromJson(p as Map<String, dynamic>))
            .toList();
        // B-19: Validate loaded custom playlists count <= 10 and tracks per playlist <= 50
        if (rawCustomList.length > 10) {
          ErrorLogger.log(
            'Loaded custom playlists exceeded cap of 10 (${rawCustomList.length}), truncating',
            category: 'PlaylistCubit',
          );
          rawCustomList = rawCustomList.take(10).toList();
        }
        final customPlaylists = rawCustomList.map((entry) {
          if (entry.tracks.length > 50) {
            ErrorLogger.log(
              'Playlist "${entry.title}" tracks exceeded cap of 50 (${entry.tracks.length}), truncating',
              category: 'PlaylistCubit',
            );
            return OnlinePlaylistEntry(
              id: entry.id,
              title: entry.title,
              uploader: entry.uploader,
              tracks: entry.tracks.take(50).toList(),
            );
          }
          return entry;
        }).toList();

        _setOnlineStateDirect(onlineState.copyWith(
          likedTracks: likedTracks,
          likedStatus: likedTracks.isNotEmpty
              ? YtmFetchStatus.done
              : YtmFetchStatus.idle,
          accountPlaylists: accountPlaylists,
          accountStatus: accountPlaylists.isNotEmpty
              ? YtmFetchStatus.done
              : YtmFetchStatus.idle,
          customPlaylists: customPlaylists,
          customStatus: customPlaylists.isNotEmpty
              ? YtmFetchStatus.done
              : YtmFetchStatus.idle,
        ));
      }
    } on FormatException catch (e, st) {
      ErrorLogger.log('Corrupted JSON in online playlist cache',
          error: e, stackTrace: st, category: 'PlaylistCubit');
    } on TypeError catch (e, st) {
      ErrorLogger.log('Type schema mismatch in online playlist cache',
          error: e, stackTrace: st, category: 'PlaylistCubit');
    } catch (e, st) {
      ErrorLogger.log('Failed to load online playlist cache',
          error: e, stackTrace: st, category: 'PlaylistCubit');
    }
  }

  /// Serializes cache writes so concurrent callers cannot persist a snapshot
  /// taken before another section landed.
  Future<void> _saveOnlineCache() {
    if (_disposed || isClosed) return Future.value();
    // H-03: Coalesce saves — only 1 queued write is needed since _writeOnlineCache
    // persists the full latest snapshot.
    if (_cacheSaveQueue.isEmpty) {
      _cacheSaveQueue.add(_writeOnlineCache);
    }
    return _drainCacheSaveQueue();
  }

  Future<void> _drainCacheSaveQueue() async {
    if (_cacheSaveRunning || _disposed || isClosed) return;
    _cacheSaveRunning = true;
    try {
      while (_cacheSaveQueue.isNotEmpty && !_disposed && !isClosed) {
        final fn = _cacheSaveQueue.removeFirst();
        try {
          await fn().timeout(const Duration(seconds: 7));
        } catch (e, st) {
          ErrorLogger.log('Online cache save queue task failed',
              error: e, stackTrace: st, category: 'PlaylistCubit');
        }
      }
    } finally {
      _cacheSaveRunning = false;
    }
  }

  Future<void> _writeOnlineCache() async {
    if (_disposed || isClosed) return;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('SharedPreferences timeout'),
      );
      if (_disposed || isClosed) return;
      // Bounded cache: prefs is not a database. Liked tracks capped at 200,
      // custom playlists at the 10 most recent with 50 tracks each — full
      // track lists are re-fetched on open, so the cache only needs enough
      // for instant paint.
      final onlineValue = onlineState;
      final liked = onlineValue.likedTracks;
      final customs = onlineValue.customPlaylists;
      final cappedCustoms = customs.length > 10
          ? customs.sublist(customs.length - 10)
          : customs;
      final data = {
        'likedTracks': liked
            .take(200)
            .map((t) => t.toJson())
            .toList(),
        'accountPlaylists':
            onlineValue.accountPlaylists.map((p) => p.toJson()).toList(),
        'customPlaylists': [
          for (final p in cappedCustoms)
            () {
              final json = Map<String, dynamic>.from(p.toJson());
              final tracks = (json['tracks'] as List? ?? []);
              json['tracks'] = tracks.take(50).toList();
              return json;
            }(),
        ],
      };
      await prefs.setString(_onlineCacheKey, jsonEncode(data)).timeout(
        const Duration(seconds: 5),
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to save online playlist cache',
          error: e, stackTrace: st, category: 'PlaylistCubit');
    }
  }

  Future<void> _checkSeeding(List playlists) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seeded = prefs.getBool('smart_playlists_seeded') ?? false;
      if (!seeded) {
        final hasSmart = playlists.any((p) => p.isSmart);
        if (!hasSmart) {
          await _playlistUseCases.seedDefaultSmartPlaylists();
        }
        await prefs.setBool('smart_playlists_seeded', true);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to check or seed default smart playlists',
          error: e, stackTrace: st, category: 'PlaylistCubit');
    }
  }

  void _updateSmartCounts(List playlists) {
    final currentSmartIds = <int>{};
    for (final playlist in playlists) {
      if (playlist.isSmart && playlist.smartCriteria != null) {
        final int id = playlist.id;
        final String criteriaJson = playlist.smartCriteria;
        currentSmartIds.add(id);
        final existing = _smartSubscriptions[id];
        if (existing == null || _smartCriteriaJson[id] != criteriaJson) {
          existing?.cancel();
          removeFromComposite(existing);
          _smartCriteriaJson[id] = criteriaJson;
          final criteria = SmartCriteria.fromJsonString(criteriaJson);
          _smartSubscriptions[id] = autoSub(
            _playlistUseCases.watchSmartPlaylistSongs(criteria),
            (songs) {
              final updatedCounts =
                  Map<int, int>.from(state.smartPlaylistCounts);
              updatedCounts[id] = songs.length;
              safeEmit(state.copyWith(smartPlaylistCounts: updatedCounts));
            },
          );
        }
      }
    }
    // Remove subscriptions for deleted smart playlists
    final staleIds = _smartSubscriptions.keys
        .where((id) => !currentSmartIds.contains(id))
        .toList();
    for (final id in staleIds) {
      final sub = _smartSubscriptions.remove(id);
      sub?.cancel();
      removeFromComposite(sub);
      _smartCriteriaJson.remove(id);
    }
  }

  void clearError() {
    safeEmit(state.copyWith(errorMessage: null));
  }

  void loadPlaylistSongs(int playlistId) {
    _playlistSongsSub?.cancel();
    removeFromComposite(_playlistSongsSub);
    _playlistSongsSub =
        autoSub(_playlistUseCases.watchPlaylistSongs(playlistId), (result) {
      result.fold(
        (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
        (songs) => safeEmit(
            state.copyWith(currentPlaylistSongs: songs, errorMessage: null)),
      );
    });
  }

  Future<void> createPlaylist(String name,
      {bool isSmart = false, String? criteria}) async {
    final result = await _playlistUseCases.createPlaylist(name,
        isSmart: isSmart, smartCriteria: criteria);
    result.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (_) => safeEmit(state.copyWith(errorMessage: null)),
    );
  }

  Future<void> renamePlaylist(int playlistId, String newName) async {
    final result = await _playlistUseCases.renamePlaylist(playlistId, newName);
    result.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (_) => safeEmit(state.copyWith(errorMessage: null)),
    );
  }

  Future<void> deletePlaylist(int playlistId) async {    final removedSub = _smartSubscriptions.remove(playlistId);
    removedSub?.cancel();
    removeFromComposite(removedSub);
    _smartCriteriaJson.remove(playlistId);
    final updatedCounts = Map<int, int>.from(state.smartPlaylistCounts)
      ..remove(playlistId);
    safeEmit(state.copyWith(smartPlaylistCounts: updatedCounts));
    final result = await _playlistUseCases.deletePlaylist(playlistId);
    result.fold(
      (failure) {
        safeEmit(state.copyWith(errorMessage: failure.message));
        if (!isClosed) {
          _updateSmartCounts(state.playlists);
        }
      },
      (_) => safeEmit(state.copyWith(errorMessage: null)),
    );
  }

  /// Updates a smart playlist's name and/or rule criteria. The live
  /// playlists watch picks up the change and [_updateSmartCounts]
  /// re-subscribes the count query for the new criteria automatically.
  Future<bool> updateSmartPlaylist(
      int playlistId, String name, String smartCriteria) async {
    final result = await _playlistUseCases.updateSmartPlaylist(
        playlistId, name, smartCriteria);
    return result.fold(
      (failure) {
        safeEmit(state.copyWith(errorMessage: failure.message));
        return false;
      },
      (_) {
        safeEmit(state.copyWith(errorMessage: null));
        return true;
      },
    );
  }

  Future<void> addSongToPlaylist(int playlistId, int songId) async {
    final result =
        await _playlistUseCases.addSongToPlaylist(playlistId, songId);
    result.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (_) => safeEmit(state.copyWith(errorMessage: null)),
    );
  }

  Future<void> addSongsToPlaylist(int playlistId, List<int> songIds) async {
    final result =
        await _playlistUseCases.addSongsToPlaylist(playlistId, songIds);
    result.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (_) => safeEmit(state.copyWith(errorMessage: null)),
    );
  }

  Future<void> removeSongFromPlaylist(int playlistId, int songId) async {
    final result =
        await _playlistUseCases.removeSongFromPlaylist(playlistId, songId);
    result.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (_) => safeEmit(state.copyWith(errorMessage: null)),
    );
  }

  Future<void> reorderPlaylistSongs(
      int playlistId, List<int> orderedSongIds) async {
    final result = await _playlistUseCases.reorderPlaylistSongs(
        playlistId, orderedSongIds);
    result.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (_) => safeEmit(state.copyWith(errorMessage: null)),
    );
  }

  // ---------------------------------------------------------------------------
  // Online (YTM) playlist fetching
  // ---------------------------------------------------------------------------

  /// Automatically triggers fetching liked songs and account playlists if
  /// logged in and not already fetched.
  Future<void> autoFetchOnlineLibrary({bool force = false}) async {
    if (!AppConfig.ytmEnabled) return;
    final account = getIt<YtmAccountService>();
    if (!account.isLoggedIn) return;

    if (!force &&
        onlineState.likedStatus == YtmFetchStatus.done &&
        onlineState.accountStatus == YtmFetchStatus.done) {
      return;
    }

    if (!await ConnectivityGuard.hasConnection()) {
      ErrorLogger.log('Skipping autoFetchOnlineLibrary: no network connectivity',
          category: 'PlaylistCubit');
      return;
    }

    _setOnlineState((s) => s.copyWith(isAutoFetching: true));
    try {
      // M-12: Run both independently so one throwing does not cancel or discard the other
      await Future.wait([
        fetchLikedSongsPlaylist().catchError((e, st) {
          ErrorLogger.log('fetchLikedSongsPlaylist failed during autoFetch',
              error: e, stackTrace: st, category: 'PlaylistCubit');
        }),
        fetchAccountPlaylists().catchError((e, st) {
          ErrorLogger.log('fetchAccountPlaylists failed during autoFetch',
              error: e, stackTrace: st, category: 'PlaylistCubit');
        }),
      ]);
    } finally {
      _setOnlineState((s) => s.copyWith(isAutoFetching: false));
    }
  }

  /// Fetches the authenticated user's Liked Music from YouTube Music.
  Future<void> fetchLikedSongsPlaylist() async {
    if (!AppConfig.ytmEnabled) return;
    final account = getIt<YtmAccountService>();
    if (!account.isLoggedIn) {
      _setOnlineState((s) => s.copyWith(
        likedStatus: YtmFetchStatus.error,
        likedError: 'Not signed in to YouTube Music',
      ));
      return;
    }

    _setOnlineState((s) => s.copyWith(
      likedStatus: YtmFetchStatus.loading,
      clearLikedError: true,
    ));

    try {
      final tracks = await account.fetchLikedSongs();
      if (_disposed || isClosed) return;
      _setOnlineState((s) => s.copyWith(
        likedStatus:
            tracks.isNotEmpty ? YtmFetchStatus.done : YtmFetchStatus.error,
        likedTracks: tracks,
        likedError: tracks.isEmpty
            ? 'No liked songs found. Try re-logging into YouTube Music.'
            : null,
        clearLikedError: tracks.isNotEmpty,
      ));
      if (tracks.isNotEmpty) {
        await _saveOnlineCache();
        try {
          final repo = getIt.isRegistered<IMusicRepository>()
              ? getIt<IMusicRepository>()
              : null;
          await repo?.importOnlineTracksAsFavorites(tracks);
        } catch (_) {}
      }
    } on YtmException catch (e) {
      if (_disposed || isClosed) return;
      _setOnlineState((s) => s.copyWith(
        likedStatus: YtmFetchStatus.error,
        likedError: e.isAuth
            ? 'Session expired — please sign in again.'
            : (e.details ?? e.code),
      ));
    } catch (e) {
      if (_disposed || isClosed) return;
      _setOnlineState((s) => s.copyWith(
        likedStatus: YtmFetchStatus.error,
        likedError: e.toString().replaceAll('Exception: ', ''),
      ));
    }
  }

  /// Fetches the authenticated user's library playlists from YouTube Music.
  Future<void> fetchAccountPlaylists() async {
    if (!AppConfig.ytmEnabled) return;
    final account = getIt<YtmAccountService>();
    if (!account.isLoggedIn) {
      _setOnlineState((s) => s.copyWith(
        accountStatus: YtmFetchStatus.error,
        accountError: 'Not signed in to YouTube Music',
      ));
      return;
    }

    _setOnlineState((s) => s.copyWith(
      accountStatus: YtmFetchStatus.loading,
      clearAccountError: true,
    ));

    try {
      final playlists = await account.fetchAccountPlaylists();
      if (_disposed || isClosed) return;
      _setOnlineState((s) => s.copyWith(
        accountStatus: YtmFetchStatus.done,
        accountPlaylists: playlists,
        clearAccountError: true,
      ));
      if (playlists.isNotEmpty) {
        await _saveOnlineCache();
      }
    } on YtmException catch (e) {
      if (_disposed || isClosed) return;
      _setOnlineState((s) => s.copyWith(
        accountStatus: YtmFetchStatus.error,
        accountError: e.isAuth
            ? 'Session expired — please sign in again.'
            : (e.details ?? e.code),
      ));
    } catch (e) {
      if (_disposed || isClosed) return;
      _setOnlineState((s) => s.copyWith(
        accountStatus: YtmFetchStatus.error,
        accountError: e.toString().replaceAll('Exception: ', ''),
      ));
    }
  }

  /// Fetches a YouTube / YouTube Music playlist by URL or ID and appends it
  /// to the custom online playlists list.
  Future<void> fetchOnlinePlaylistByUrl(String urlOrId) async {
    if (!AppConfig.ytmEnabled) return;
    final input = urlOrId.trim();
    if (input.isEmpty) return;

    // Prevent duplicate fetches
    final existing = onlineState.customPlaylists.any((p) => p.id == input);
    if (existing) return;

    _setOnlineState((s) => s.copyWith(
      customStatus: YtmFetchStatus.loading,
      clearCustomError: true,
    ));

    try {
      final accountService = getIt.isRegistered<YtmAccountService>()
          ? getIt<YtmAccountService>()
          : null;
      final details = await accountService?.fetchPlaylistDetails(input, maxTracks: 200);
      if (_disposed || isClosed) return;

      List<YtmTrack> tracks = details?.tracks ?? const [];
      if (tracks.isEmpty) {
        final ytmService = getIt<YtmService>();
        tracks = await ytmService.getPlaylistTracks(input, limit: 200);
        if (_disposed || isClosed) return;
      }

      if (tracks.isEmpty) {
        _setOnlineState((s) => s.copyWith(
          customStatus: YtmFetchStatus.error,
          customError: 'Playlist is empty or could not be fetched.',
        ));
        return;
      }

      // Build display name from rich details or fallback to URL extraction
      String title = details?.title ?? 'YouTube Playlist';
      if (title == 'YouTube Playlist') {
        if (input.contains('list=')) {
          final listId = Uri.tryParse(input)?.queryParameters['list'];
          if (listId != null && listId.isNotEmpty) {
            title = listId.length > 16 ? '${listId.substring(0, 16)}…' : listId;
          }
        } else if (!input.startsWith('http')) {
          final short = input.length > 16 ? '${input.substring(0, 16)}…' : input;
          title = 'Playlist ($short)';
        }
      }

      final entry = OnlinePlaylistEntry(
        id: input,
        title: title,
        uploader: details?.author.isNotEmpty == true
            ? details!.author
            : tracks.first.artist,
        tracks: tracks,
      );

      final updated =
          List<OnlinePlaylistEntry>.from(onlineState.customPlaylists)
            ..add(entry);
      _setOnlineState((s) => s.copyWith(
        customStatus: YtmFetchStatus.done,
        customPlaylists: updated,
        clearCustomError: true,
      ));
      await _saveOnlineCache();
    } catch (e) {
      if (_disposed || isClosed) return;
      _setOnlineState((s) => s.copyWith(
        customStatus: YtmFetchStatus.error,
        customError: e.toString().replaceAll('Exception: ', ''),
      ));
    }
  }

  /// Removes a previously fetched custom online playlist.
  void removeCustomPlaylist(String id) {
    final updated =
        onlineState.customPlaylists.where((p) => p.id != id).toList();
    _setOnlineState((s) => s.copyWith(customPlaylists: updated));
    unawaited(_saveOnlineCache());
  }

  /// Resets all online playlist state (liked + fetched list).
  void clearOnlinePlaylists() {
    _setOnlineStateDirect(const YtmOnlineState());
    unawaited(_saveOnlineCache());
  }

  @override
  Future<void> close() async {
    _disposed = true;
    if (AppConfig.ytmEnabled) {
      try {
        getIt<YtmAccountService>()
            .loginState
            .removeListener(_onYtmLoginStateChanged);
      } catch (_) {}
    }
    _cacheSaveQueue.clear();
    _playlistsSub?.cancel();
    _playlistSongsSub?.cancel();
    for (final sub in _smartSubscriptions.values) {
      sub.cancel();
    }
    _smartSubscriptions.clear();
    _smartCriteriaJson.clear();
    try {
      ytmOnline.value = const YtmOnlineState();
    } catch (_) {}
    ytmOnline.dispose();
    return super.close();
  }
}
