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
import '../../../core/services/sound_feedback_service.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/utils/error_logger.dart';
import '../../../data/db/tables.dart' show OnlineLibraryKind;
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

/// One playlist queued for the background full-metadata cache.
class _OnlineCacheJob {
  final String playlistId;
  final String kind;
  final String title;
  final String author;
  final String? artworkUrl;
  final int sortOrder;

  const _OnlineCacheJob({
    required this.playlistId,
    required this.kind,
    required this.title,
    this.author = '',
    this.artworkUrl,
    this.sortOrder = 0,
  });

  _OnlineCacheJob copyWithPlaylistId(String id) => _OnlineCacheJob(
        playlistId: id,
        kind: kind,
        title: title,
        author: author,
        artworkUrl: artworkUrl,
        sortOrder: sortOrder,
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

  /// Background full-metadata cache progress for the online library.
  final bool isCachingLibrary;
  final int cacheCompleted;
  final int cacheTotal;
  final String? cacheError;

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
    this.isCachingLibrary = false,
    this.cacheCompleted = 0,
    this.cacheTotal = 0,
    this.cacheError,
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
    bool? isCachingLibrary,
    int? cacheCompleted,
    int? cacheTotal,
    String? cacheError,
    bool clearLikedError = false,
    bool clearAccountError = false,
    bool clearCustomError = false,
    bool clearCacheError = false,
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
      isCachingLibrary: isCachingLibrary ?? this.isCachingLibrary,
      cacheCompleted: cacheCompleted ?? this.cacheCompleted,
      cacheTotal: cacheTotal ?? this.cacheTotal,
      cacheError: clearCacheError ? null : (cacheError ?? this.cacheError),
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
  final Queue<Future<void> Function()> _cacheSaveQueue =
      Queue<Future<void> Function()>();
  bool _cacheSaveRunning = false;
  bool _isSeedingChecked = false;

  /// Coalesces overlapping auto-fetch triggers (tab switch, sync button,
  /// post-frame timer) into a single in-flight run.
  Future<void>? _autoFetchInFlight;

  /// Coalesces identical custom-playlist fetches submitted in quick succession.
  final Map<String, Future<void>> _customFetchInFlight = {};

  /// Coalesces the background full-metadata cache into one sequential run.
  Future<void>? _cacheSyncInFlight;

  /// Reactive online-playlist state. Widgets use [ValueListenableBuilder]
  /// to rebuild only when this changes, without touching the freezed state.
  final ytmOnline = ValueNotifier<YtmOnlineState>(const YtmOnlineState());

  /// H-08: Set before [ytmOnline] is disposed so late async callbacks bail out
  /// instead of writing to (or reading) a disposed notifier.
  bool _disposed = false;

  /// Safe accessor that returns default state if cubit/notifier is disposed.
  YtmOnlineState get onlineState =>
      _disposed ? const YtmOnlineState() : ytmOnline.value;

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
    // Re-subscribe / refresh pattern: without this, each reloadPlaylists() would
    // leave the cancelled subscription registered in the composite, permanently
    // inflating activeSubscriptionCount (see PulsrCubit.removeFromComposite).
    removeFromComposite(_playlistsSub);
    _playlistsSub = autoSub(_playlistUseCases.watchPlaylists(), (result) {
      result.fold(
        (failure) => safeEmit(
            state.copyWith(errorMessage: failure.message, isLoading: false)),
        (playlists) {
          safeEmit(state.copyWith(
              playlists: List.unmodifiable(playlists),
              errorMessage: null,
              isLoading: false));
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
    if (AppConfig.ytmEnabled && getIt.isRegistered<YtmAccountService>()) {
      final account = getIt<YtmAccountService>();
      account.loginState.removeListener(_onYtmLoginStateChanged);
      account.loginState.addListener(_onYtmLoginStateChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed || isClosed) return;
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
    if (getIt.isRegistered<YtmAccountService>() &&
        !getIt<YtmAccountService>().isLoggedIn) {
      clearOnlinePlaylists();
    }
  }

  Future<void> _loadOnlineCache() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (isClosed) return;
      final raw = prefs.getString(_onlineCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException(
              'Root of online playlist cache must be a JSON object');
        }
        final data = decoded;
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
      ErrorLogger.log('Corrupted JSON in online playlist cache, clearing cache',
          error: e, stackTrace: st, category: 'PlaylistCubit');
      try {
        await prefs?.remove(_onlineCacheKey);
      } catch (_) {}
    } on TypeError catch (e, st) {
      ErrorLogger.log(
          'Type schema mismatch in online playlist cache, clearing cache',
          error: e,
          stackTrace: st,
          category: 'PlaylistCubit');
      try {
        await prefs?.remove(_onlineCacheKey);
      } catch (_) {}
    } catch (e, st) {
      ErrorLogger.log('Failed to load online playlist cache, clearing cache',
          error: e, stackTrace: st, category: 'PlaylistCubit');
      try {
        await prefs?.remove(_onlineCacheKey);
      } catch (_) {}
    }
  }

  @visibleForTesting
  static const String onlineCacheKey = _onlineCacheKey;

  @visibleForTesting
  Future<void> loadOnlineCacheForTesting() => _loadOnlineCache();

  /// H-06: Cap queue size to prevent unbounded memory growth during rapid operations.
  @visibleForTesting
  static const int maxCacheSaveQueueSize = 50;

  @visibleForTesting
  int get cacheSaveQueueLength => _cacheSaveQueue.length;

  @visibleForTesting
  void enqueueCacheSaveForTesting(Future<void> Function() task) =>
      _enqueueCacheSave(task);

  void _enqueueCacheSave(Future<void> Function() task) {
    if (_disposed || isClosed) return;
    if (_cacheSaveQueue.length >= maxCacheSaveQueueSize) {
      _cacheSaveQueue.removeFirst();
    }
    _cacheSaveQueue.add(task);
  }

  /// Serializes cache writes so concurrent callers cannot persist a snapshot
  /// taken before another section landed.
  Future<void> _saveOnlineCache() {
    if (_disposed || isClosed) return Future.value();
    // H-06: Coalesce saves and cap queue size to maxCacheSaveQueueSize.
    // If a write is already queued, redundant saves are coalesced since
    // _writeOnlineCache persists the full latest snapshot.
    if (_cacheSaveQueue.isEmpty) {
      _enqueueCacheSave(_writeOnlineCache);
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
      if (_cacheSaveQueue.isNotEmpty && !_disposed && !isClosed) {
        unawaited(_drainCacheSaveQueue());
      }
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
      final cappedCustoms =
          customs.length > 10 ? customs.sublist(customs.length - 10) : customs;
      final data = {
        'likedTracks': liked.take(200).map((t) => t.toJson()).toList(),
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
      (failure) {
        SoundFeedbackService.playError(mirrorHaptics: true);
        safeEmit(state.copyWith(errorMessage: failure.message));
      },
      (_) {
        SoundFeedbackService.playSuccess(mirrorHaptics: true);
        safeEmit(state.copyWith(errorMessage: null));
      },
    );
  }

  Future<void> renamePlaylist(int playlistId, String newName) async {
    final result = await _playlistUseCases.renamePlaylist(playlistId, newName);
    result.fold(
      (failure) {
        SoundFeedbackService.playError(mirrorHaptics: true);
        safeEmit(state.copyWith(errorMessage: failure.message));
      },
      (_) {
        SoundFeedbackService.playSuccess(mirrorHaptics: true);
        safeEmit(state.copyWith(errorMessage: null));
      },
    );
  }

  /// Undo helper for a deleted playlist: recreates it and restores its songs.
  /// Returns the new playlist id, or null when creation fails.
  Future<int?> restorePlaylist(
    String name, {
    bool isSmart = false,
    String? criteria,
    List<int> songIds = const [],
  }) async {
    final result = await _playlistUseCases.createPlaylist(name,
        isSmart: isSmart, smartCriteria: criteria);
    final newId = result.getOrElse((_) => -1);
    if (newId <= 0) {
      SoundFeedbackService.playError(mirrorHaptics: true);
      final message = result.fold((failure) => failure.message, (_) => '');
      safeEmit(state.copyWith(errorMessage: message));
      return null;
    }
    SoundFeedbackService.playSuccess(mirrorHaptics: true);
    if (!isSmart && songIds.isNotEmpty) {
      final addResult =
          await _playlistUseCases.addSongsToPlaylist(newId, songIds);
      addResult.fold(
        (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
        (_) => safeEmit(state.copyWith(errorMessage: null)),
      );
    } else {
      safeEmit(state.copyWith(errorMessage: null));
    }
    return newId;
  }

  Future<bool> deletePlaylist(int playlistId) async {
    SoundFeedbackService.playWarning(mirrorHaptics: true);
    final removedSub = _smartSubscriptions.remove(playlistId);
    removedSub?.cancel();
    removeFromComposite(removedSub);
    _smartCriteriaJson.remove(playlistId);
    final updatedCounts = Map<int, int>.from(state.smartPlaylistCounts)
      ..remove(playlistId);
    safeEmit(state.copyWith(smartPlaylistCounts: updatedCounts));
    final result = await _playlistUseCases.deletePlaylist(playlistId);
    return result.fold(
      (failure) {
        safeEmit(state.copyWith(errorMessage: failure.message));
        if (!isClosed) {
          _updateSmartCounts(state.playlists);
        }
        return false;
      },
      (_) {
        safeEmit(state.copyWith(errorMessage: null));
        return true;
      },
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
  Future<void> autoFetchOnlineLibrary({bool force = false}) {
    if (!AppConfig.ytmEnabled) return Future.value();
    return _autoFetchOnlineLibrary(force: force);
  }

  @visibleForTesting
  Future<void> autoFetchOnlineLibraryForTesting({bool force = false}) =>
      _autoFetchOnlineLibrary(force: force);

  Future<void> _autoFetchOnlineLibrary({required bool force}) {
    final account = getIt<YtmAccountService>();
    if (!account.isLoggedIn) return Future.value();

    final inFlight = _autoFetchInFlight;
    if (inFlight != null) return inFlight;

    if (!force &&
        onlineState.likedStatus == YtmFetchStatus.done &&
        onlineState.accountStatus == YtmFetchStatus.done) {
      return Future.value();
    }

    final future = _runAutoFetchOnlineLibrary();
    _autoFetchInFlight = future;
    future.whenComplete(() {
      if (identical(_autoFetchInFlight, future)) {
        _autoFetchInFlight = null;
      }
    });
    return future;
  }

  Future<void> _runAutoFetchOnlineLibrary() async {
    if (!await ConnectivityGuard.hasConnection()) {
      ErrorLogger.log(
          'Skipping autoFetchOnlineLibrary: no network connectivity',
          category: 'PlaylistCubit');
      return;
    }

    _setOnlineState((s) => s.copyWith(isAutoFetching: true));
    try {
      // M-12: Run both independently so one throwing does not cancel or discard the other
      await Future.wait([
        _fetchLikedSongsPlaylist().catchError((e, st) {
          ErrorLogger.log('fetchLikedSongsPlaylist failed during autoFetch',
              error: e, stackTrace: st, category: 'PlaylistCubit');
        }),
        fetchAccountPlaylists().catchError((e, st) {
          ErrorLogger.log('fetchAccountPlaylists failed during autoFetch',
              error: e, stackTrace: st, category: 'PlaylistCubit');
        }),
      ]);
    } catch (e, st) {
      ErrorLogger.log('autoFetchOnlineLibrary failed',
          error: e, stackTrace: st, category: 'PlaylistCubit');
    } finally {
      _setOnlineState((s) => s.copyWith(isAutoFetching: false));
      if (!_disposed && !isClosed) {
        unawaited(syncOnlineLibraryCache());
      }
    }
  }

  /// Refreshes the library listing and forces a full metadata re-cache.
  ///
  /// Used by the Online tab's refresh action. Normal startup only caches
  /// playlists that are missing or older than [_onlineCacheMaxAge].
  Future<void> refreshOnlineLibrary() async {
    await autoFetchOnlineLibrary(force: true);
    await syncOnlineLibraryCache(force: true);
  }

  static const Duration _onlineCacheMaxAge = Duration(hours: 24);

  /// Fetches and stores the complete track list of every online playlist so
  /// the library stays browsable offline and hand-set orders survive.
  ///
  /// Runs sequentially to stay well inside YouTube's rate limits and stops on
  /// an auth/bot/throttle signal instead of retrying the whole library.
  Future<void> syncOnlineLibraryCache({bool force = false}) {
    if (_disposed || isClosed || !AppConfig.ytmEnabled) return Future.value();
    if (!getIt.isRegistered<YtmAccountService>() ||
        !getIt<YtmAccountService>().isLoggedIn) {
      return Future.value();
    }

    final inFlight = _cacheSyncInFlight;
    if (inFlight != null) return inFlight;

    final future = _runSyncOnlineLibraryCache(force: force)
        .catchError((Object e, StackTrace st) {
      ErrorLogger.log('Online library cache sync failed',
          error: e, stackTrace: st, category: 'PlaylistCubit');
      _setOnlineState((s) => s.copyWith(
            isCachingLibrary: false,
            cacheError: e.toString().replaceAll('Exception: ', ''),
          ));
    });
    _cacheSyncInFlight = future;
    future.whenComplete(() {
      if (identical(_cacheSyncInFlight, future)) {
        _cacheSyncInFlight = null;
      }
    });
    return future;
  }

  Future<void> _runSyncOnlineLibraryCache({required bool force}) async {
    if (!getIt.isRegistered<IMusicRepository>()) return;
    if (!getIt.isRegistered<YtmAccountService>()) return;
    final repo = getIt<IMusicRepository>();
    final cachedResult = await repo.getOnlinePlaylists();
    if (_disposed || isClosed) return;
    final cachedAtById = <String, DateTime?>{};
    cachedResult.fold(
      (_) {},
      (playlists) {
        for (final playlist in playlists) {
          cachedAtById[playlist.playlistId] = playlist.cachedAt;
        }
      },
    );

    bool isStale(String playlistId) {
      if (force) return true;
      final cachedAt = cachedAtById[playlistId];
      return cachedAt == null ||
          DateTime.now().difference(cachedAt) > _onlineCacheMaxAge;
    }

    final account = getIt<YtmAccountService>();
    final work = <_OnlineCacheJob>[];
    final seenIds = <String>{};

    void addJob(_OnlineCacheJob job) {
      final canonical = canonicalYtmPlaylistId(job.playlistId);
      if (canonical.isEmpty || !seenIds.add(canonical)) return;
      if (!isStale(canonical)) return;
      work.add(job.copyWithPlaylistId(canonical));
    }

    addJob(const _OnlineCacheJob(
      playlistId: kLikedMusicPlaylistId,
      kind: OnlineLibraryKind.liked,
      title: 'Liked Music',
      author: 'YouTube Music',
    ));
    for (var i = 0; i < onlineState.accountPlaylists.length; i++) {
      final playlist = onlineState.accountPlaylists[i];
      addJob(_OnlineCacheJob(
        playlistId: playlist.playlistId,
        kind: OnlineLibraryKind.account,
        title: playlist.title,
        author: playlist.subtitle,
        artworkUrl: playlist.artworkUrl,
        sortOrder: i,
      ));
    }
    for (var i = 0; i < onlineState.customPlaylists.length; i++) {
      final playlist = onlineState.customPlaylists[i];
      addJob(_OnlineCacheJob(
        playlistId: playlist.id,
        kind: OnlineLibraryKind.custom,
        title: playlist.title,
        author: playlist.uploader,
        artworkUrl: playlist.tracks.firstOrNull?.artworkUrl,
        sortOrder: i,
      ));
    }

    if (work.isEmpty) {
      _setOnlineState((s) => s.copyWith(
            isCachingLibrary: false,
            cacheCompleted: 0,
            cacheTotal: 0,
            clearCacheError: true,
          ));
      return;
    }

    _setOnlineState((s) => s.copyWith(
          isCachingLibrary: true,
          cacheCompleted: 0,
          cacheTotal: work.length,
          clearCacheError: true,
        ));

    final ytmService =
        getIt.isRegistered<YtmService>() ? getIt<YtmService>() : null;
    var completed = 0;
    String? firstError;

    for (final job in work) {
      if (_disposed || isClosed || !account.isLoggedIn) break;
      try {
        var tracks = <YtmTrack>[];
        String title = job.title;
        String author = job.author;
        String? artworkUrl = job.artworkUrl;

        if (job.kind == OnlineLibraryKind.liked) {
          tracks =
              await account.fetchLikedSongs(maxTracks: kYtmMaxPlaylistTracks);
          if (tracks.isNotEmpty) {
            _setOnlineState((s) => s.copyWith(likedTracks: tracks));
          }
        } else {
          final details = await account.fetchPlaylistDetails(
            job.playlistId,
            maxTracks: kYtmMaxPlaylistTracks,
          );
          if (details != null && details.tracks.isNotEmpty) {
            tracks = details.tracks;
            if (details.title.isNotEmpty) title = details.title;
            if (details.author.isNotEmpty) author = details.author;
            artworkUrl ??= details.artworkUrl;
          }
          if (tracks.isEmpty && ytmService != null) {
            tracks = await ytmService.getPlaylistTracks(
              job.playlistId,
              limit: kYtmMaxPlaylistTracks,
            );
          }
        }

        if (_disposed || isClosed || !account.isLoggedIn) break;

        if (tracks.isNotEmpty) {
          artworkUrl ??= tracks.firstOrNull?.artworkUrl;
          await repo.cacheOnlinePlaylist(
            playlistId: job.playlistId,
            kind: job.kind,
            title: title,
            author: author,
            artworkUrl: artworkUrl,
            sortOrder: job.sortOrder,
            tracks: tracks,
          );
        }
      } on YtmException catch (e, st) {
        ErrorLogger.log(
          'Online library cache failed for ${job.playlistId}: ${e.code}',
          error: e,
          stackTrace: st,
          category: 'PlaylistCubit',
        );
        firstError ??= e.details ?? e.code;
        if (e.isAuth || e.isBotBlocked || e.isThrottled || e.isIpBlocked) {
          break;
        }
      } catch (e, st) {
        ErrorLogger.log(
          'Online library cache failed for ${job.playlistId}',
          error: e,
          stackTrace: st,
          category: 'PlaylistCubit',
        );
        firstError ??= e.toString().replaceAll('Exception: ', '');
      }

      completed++;
      _setOnlineState((s) => s.copyWith(
            isCachingLibrary: true,
            cacheCompleted: completed,
            cacheTotal: work.length,
          ));
      if (completed < work.length) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }

    if (_disposed || isClosed) return;
    _setOnlineState((s) => s.copyWith(
          isCachingLibrary: false,
          cacheCompleted: completed,
          cacheTotal: work.length,
          cacheError: firstError,
        ));
    if (completed > 0) {
      await _saveOnlineCache();
    }
  }

  /// Fetches the authenticated user's Liked Music from YouTube Music.
  Future<void> fetchLikedSongsPlaylist() async {
    if (!AppConfig.ytmEnabled) return;
    await _fetchLikedSongsPlaylist();
  }

  @visibleForTesting
  Future<void> fetchLikedSongsPlaylistForTesting() =>
      _fetchLikedSongsPlaylist();

  Future<void> _fetchLikedSongsPlaylist() async {
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
      // An empty result is a valid "nothing liked" state, not a failure:
      // reserve the error state for auth/network problems so the card does
      // not demand a re-login for an empty library.
      _setOnlineState((s) => s.copyWith(
            likedStatus: YtmFetchStatus.done,
            likedTracks: tracks,
            clearLikedError: true,
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
  Future<void> fetchOnlinePlaylistByUrl(String urlOrId) {
    if (!AppConfig.ytmEnabled) return Future.value();
    return _fetchOnlinePlaylistByUrl(urlOrId);
  }

  @visibleForTesting
  Future<void> fetchOnlinePlaylistByUrlForTesting(String urlOrId) =>
      _fetchOnlinePlaylistByUrl(urlOrId);

  Future<void> _fetchOnlinePlaylistByUrl(String urlOrId) {
    final input = urlOrId.trim();
    if (input.isEmpty) return Future.value();

    // Prevent duplicate fetches (already saved).
    if (onlineState.customPlaylists.any((p) => p.id == input)) {
      return Future.value();
    }
    // Two rapid submits both pass the check above before the first await, so
    // identical requests join the in-flight future instead of fetching twice.
    final inFlight = _customFetchInFlight[input];
    if (inFlight != null) return inFlight;

    final future = _runFetchOnlinePlaylistByUrl(input);
    _customFetchInFlight[input] = future;
    future.whenComplete(() {
      if (identical(_customFetchInFlight[input], future)) {
        _customFetchInFlight.remove(input);
      }
    });
    return future;
  }

  Future<void> _runFetchOnlinePlaylistByUrl(String input) async {
    _setOnlineState((s) => s.copyWith(
          customStatus: YtmFetchStatus.loading,
          clearCustomError: true,
        ));

    try {
      final accountService = getIt.isRegistered<YtmAccountService>()
          ? getIt<YtmAccountService>()
          : null;
      final details =
          await accountService?.fetchPlaylistDetails(input, maxTracks: 200);
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
          final short =
              input.length > 16 ? '${input.substring(0, 16)}…' : input;
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

      // Re-dedupe after the awaits: a concurrent path may have landed the same
      // entry while this fetch was running.
      final updated = List<OnlinePlaylistEntry>.from(
          onlineState.customPlaylists.where((p) => p.id != input))
        ..add(entry);
      _setOnlineState((s) => s.copyWith(
            customStatus: YtmFetchStatus.done,
            customPlaylists: updated,
            clearCustomError: true,
          ));
      await _saveOnlineCache();
      // Seed the cache so the detail screen can open offline immediately; the
      // background sync then replaces this preview with the full track list.
      try {
        if (getIt.isRegistered<IMusicRepository>()) {
          await getIt<IMusicRepository>().cacheOnlinePlaylist(
            playlistId: canonicalYtmPlaylistId(input),
            kind: OnlineLibraryKind.custom,
            title: entry.title,
            author: entry.uploader,
            artworkUrl: entry.tracks.firstOrNull?.artworkUrl,
            tracks: entry.tracks,
            fullSnapshot: false,
          );
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to cache imported online playlist',
            error: e, stackTrace: st, category: 'PlaylistCubit');
      }
      unawaited(syncOnlineLibraryCache());
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
    unawaited(_removeCachedOnlinePlaylist(canonicalYtmPlaylistId(id)));
  }

  Future<void> _removeCachedOnlinePlaylist(String playlistId) async {
    if (!getIt.isRegistered<IMusicRepository>()) return;
    try {
      await getIt<IMusicRepository>().removeOnlinePlaylist(playlistId);
    } catch (e, st) {
      ErrorLogger.log('Failed to remove cached online playlist',
          error: e, stackTrace: st, category: 'PlaylistCubit');
    }
  }

  Future<void> _clearCachedOnlineLibrary() async {
    if (!getIt.isRegistered<IMusicRepository>()) return;
    try {
      await getIt<IMusicRepository>().clearOnlineLibraryCache();
    } catch (e, st) {
      ErrorLogger.log('Failed to clear cached online library',
          error: e, stackTrace: st, category: 'PlaylistCubit');
    }
  }

  /// Re-inserts a previously removed custom online playlist (Undo). No-op when
  /// an entry with the same id is already present.
  void restoreCustomPlaylist(OnlinePlaylistEntry entry) {
    if (onlineState.customPlaylists.any((p) => p.id == entry.id)) return;
    final updated = List<OnlinePlaylistEntry>.from(onlineState.customPlaylists)
      ..add(entry);
    _setOnlineState((s) => s.copyWith(customPlaylists: updated));
    unawaited(_saveOnlineCache());
  }

  /// Resets all online playlist state (liked + fetched list) and drops the
  /// cached track lists so a different account never sees the previous
  /// account's library.
  void clearOnlinePlaylists() {
    _setOnlineStateDirect(const YtmOnlineState());
    unawaited(_saveOnlineCache());
    unawaited(_clearCachedOnlineLibrary());
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
    _autoFetchInFlight = null;
    _cacheSyncInFlight = null;
    _customFetchInFlight.clear();
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
