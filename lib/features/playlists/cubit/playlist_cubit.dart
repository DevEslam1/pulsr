import 'dart:convert';
// lib/features/playlists/cubit/playlist_cubit.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/utils/error_logger.dart';
import '../../../domain/models/smart_playlist_criteria.dart';
import '../../../domain/models/ytm_track.dart';
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
      accountError: clearAccountError ? null : (accountError ?? this.accountError),
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
class PlaylistCubit extends Cubit<PlaylistState> {
  static const String _onlineCacheKey = 'ytm_cached_online_playlists_v1';
  final PlaylistUseCases _playlistUseCases;
  StreamSubscription? _playlistsSub;
  StreamSubscription? _playlistSongsSub;
  final Map<int, StreamSubscription> _smartSubscriptions = {};
  bool _isSeedingChecked = false;

  /// Reactive online-playlist state. Widgets use [ValueListenableBuilder]
  /// to rebuild only when this changes, without touching the freezed state.
  final ytmOnline = ValueNotifier<YtmOnlineState>(const YtmOnlineState());

  PlaylistCubit({required PlaylistUseCases playlistUseCases})
      : _playlistUseCases = playlistUseCases,
        super(const PlaylistState()) {
    _init();
  }

  void _init() {
    _loadOnlineCache();

    _playlistsSub = _playlistUseCases.watchPlaylists().listen((result) {
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message)),
        (playlists) {
          emit(state.copyWith(playlists: playlists, errorMessage: null));
          _updateSmartCounts(playlists);
          if (!_isSeedingChecked) {
            _isSeedingChecked = true;
            _checkSeeding(playlists);
          }
        },
      );
    });

    // Auto-update online playlists & liked songs in background on every restart
    if (AppConfig.ytmEnabled) {
      getIt<YtmAccountService>().loginState.removeListener(_onYtmLoginStateChanged);
      getIt<YtmAccountService>().loginState.addListener(_onYtmLoginStateChanged);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!isClosed) {
          autoFetchOnlineLibrary(force: true);
        }
      });
    }
  }

  void _onYtmLoginStateChanged() {
    if (!getIt<YtmAccountService>().isLoggedIn) {
      clearOnlinePlaylists();
    }
  }

  Future<void> _loadOnlineCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_onlineCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final likedTracks = (data['likedTracks'] as List<dynamic>? ?? [])
            .map((t) => YtmTrack.fromJson(t as Map<String, dynamic>))
            .toList();
        final accountPlaylists = (data['accountPlaylists'] as List<dynamic>? ?? [])
            .map((p) => YtmAccountPlaylist.fromJson(p as Map<String, dynamic>))
            .toList();
        final customPlaylists = (data['customPlaylists'] as List<dynamic>? ?? [])
            .map((p) => OnlinePlaylistEntry.fromJson(p as Map<String, dynamic>))
            .toList();

        ytmOnline.value = ytmOnline.value.copyWith(
          likedTracks: likedTracks,
          likedStatus: likedTracks.isNotEmpty ? YtmFetchStatus.done : YtmFetchStatus.idle,
          accountPlaylists: accountPlaylists,
          accountStatus: accountPlaylists.isNotEmpty ? YtmFetchStatus.done : YtmFetchStatus.idle,
          customPlaylists: customPlaylists,
          customStatus: customPlaylists.isNotEmpty ? YtmFetchStatus.done : YtmFetchStatus.idle,
        );
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to load online playlist cache', error: e, stackTrace: st, category: 'PlaylistCubit');
    }
  }

  Future<void> _saveOnlineCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'likedTracks': ytmOnline.value.likedTracks.map((t) => t.toJson()).toList(),
        'accountPlaylists': ytmOnline.value.accountPlaylists.map((p) => p.toJson()).toList(),
        'customPlaylists': ytmOnline.value.customPlaylists.map((p) => p.toJson()).toList(),
      };
      await prefs.setString(_onlineCacheKey, jsonEncode(data));
    } catch (e, st) {
      ErrorLogger.log('Failed to save online playlist cache', error: e, stackTrace: st, category: 'PlaylistCubit');
    }
  }

  Future<void> _checkSeeding(List playlists) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seeded = prefs.getBool('smart_playlists_seeded') ?? false;
      if (!seeded) {
        await prefs.setBool('smart_playlists_seeded', true);
        final hasSmart = playlists.any((p) => p.isSmart);
        if (!hasSmart) {
          await _playlistUseCases.seedDefaultSmartPlaylists();
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to check or seed default smart playlists', error: e, stackTrace: st, category: 'PlaylistCubit');
    }
  }

  void _updateSmartCounts(List playlists) {
    final currentSmartIds = <int>{};
    for (final playlist in playlists) {
      if (playlist.isSmart && playlist.smartCriteria != null) {
        currentSmartIds.add(playlist.id);
        if (!_smartSubscriptions.containsKey(playlist.id)) {
          final criteria = SmartCriteria.fromJsonString(playlist.smartCriteria!);
          _smartSubscriptions[playlist.id] =
              _playlistUseCases.watchSmartPlaylistSongs(criteria).listen((songs) {
            if (isClosed) return;
            final updatedCounts = Map<int, int>.from(state.smartPlaylistCounts);
            updatedCounts[playlist.id] = songs.length;
            emit(state.copyWith(smartPlaylistCounts: updatedCounts));
          });
        }
      }
    }
    // Remove subscriptions for deleted smart playlists
    final staleIds = _smartSubscriptions.keys.where((id) => !currentSmartIds.contains(id)).toList();
    for (final id in staleIds) {
      _smartSubscriptions[id]?.cancel();
      _smartSubscriptions.remove(id);
    }
  }

  void clearError() {
    emit(state.copyWith(errorMessage: null));
  }

  void loadPlaylistSongs(int playlistId) {
    _playlistSongsSub?.cancel();
    _playlistSongsSub = _playlistUseCases.watchPlaylistSongs(playlistId).listen((result) {
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message)),
        (songs) => emit(state.copyWith(currentPlaylistSongs: songs, errorMessage: null)),
      );
    });
  }

  Future<void> createPlaylist(String name, {bool isSmart = false, String? criteria}) async {
    final result = await _playlistUseCases.createPlaylist(name, isSmart: isSmart, smartCriteria: criteria);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> renamePlaylist(int playlistId, String newName) async {
    final result = await _playlistUseCases.renamePlaylist(playlistId, newName);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> deletePlaylist(int playlistId) async {
    final result = await _playlistUseCases.deletePlaylist(playlistId);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> addSongToPlaylist(int playlistId, int songId) async {
    final result = await _playlistUseCases.addSongToPlaylist(playlistId, songId);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> addSongsToPlaylist(int playlistId, List<int> songIds) async {
    final result = await _playlistUseCases.addSongsToPlaylist(playlistId, songIds);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> removeSongFromPlaylist(int playlistId, int songId) async {
    final result = await _playlistUseCases.removeSongFromPlaylist(playlistId, songId);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
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
        ytmOnline.value.likedStatus == YtmFetchStatus.done &&
        ytmOnline.value.accountStatus == YtmFetchStatus.done) {
      return;
    }

    ytmOnline.value = ytmOnline.value.copyWith(isAutoFetching: true);
    await Future.wait([
      fetchLikedSongsPlaylist(),
      fetchAccountPlaylists(),
    ]);
    ytmOnline.value = ytmOnline.value.copyWith(isAutoFetching: false);
  }

  /// Fetches the authenticated user's Liked Music from YouTube Music.
  Future<void> fetchLikedSongsPlaylist() async {
    if (!AppConfig.ytmEnabled) return;
    final account = getIt<YtmAccountService>();
    if (!account.isLoggedIn) {
      ytmOnline.value = ytmOnline.value.copyWith(
        likedStatus: YtmFetchStatus.error,
        likedError: 'Not signed in to YouTube Music',
      );
      return;
    }

    ytmOnline.value = ytmOnline.value.copyWith(
      likedStatus: YtmFetchStatus.loading,
      clearLikedError: true,
    );

    try {
      final tracks = await account.fetchLikedSongs();
      ytmOnline.value = ytmOnline.value.copyWith(
        likedStatus: tracks.isNotEmpty ? YtmFetchStatus.done : YtmFetchStatus.error,
        likedTracks: tracks,
        likedError: tracks.isEmpty
            ? 'No liked songs found. Try re-logging into YouTube Music.'
            : null,
      );
      if (tracks.isNotEmpty) {
        _saveOnlineCache();
      }
    } on YtmException catch (e) {
      ytmOnline.value = ytmOnline.value.copyWith(
        likedStatus: YtmFetchStatus.error,
        likedError: e.isAuth
            ? 'Session expired — please sign in again.'
            : (e.details ?? e.code),
      );
    } catch (e) {
      ytmOnline.value = ytmOnline.value.copyWith(
        likedStatus: YtmFetchStatus.error,
        likedError: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// Fetches the authenticated user's library playlists from YouTube Music.
  Future<void> fetchAccountPlaylists() async {
    if (!AppConfig.ytmEnabled) return;
    final account = getIt<YtmAccountService>();
    if (!account.isLoggedIn) {
      ytmOnline.value = ytmOnline.value.copyWith(
        accountStatus: YtmFetchStatus.error,
        accountError: 'Not signed in to YouTube Music',
      );
      return;
    }

    ytmOnline.value = ytmOnline.value.copyWith(
      accountStatus: YtmFetchStatus.loading,
      clearAccountError: true,
    );

    try {
      final playlists = await account.fetchAccountPlaylists();
      ytmOnline.value = ytmOnline.value.copyWith(
        accountStatus: YtmFetchStatus.done,
        accountPlaylists: playlists,
        clearAccountError: true,
      );
      if (playlists.isNotEmpty) {
        _saveOnlineCache();
      }
    } on YtmException catch (e) {
      ytmOnline.value = ytmOnline.value.copyWith(
        accountStatus: YtmFetchStatus.error,
        accountError: e.isAuth
            ? 'Session expired — please sign in again.'
            : (e.details ?? e.code),
      );
    } catch (e) {
      ytmOnline.value = ytmOnline.value.copyWith(
        accountStatus: YtmFetchStatus.error,
        accountError: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// Fetches a YouTube / YouTube Music playlist by URL or ID and appends it
  /// to the custom online playlists list.
  Future<void> fetchOnlinePlaylistByUrl(String urlOrId) async {
    if (!AppConfig.ytmEnabled) return;
    final input = urlOrId.trim();
    if (input.isEmpty) return;

    // Prevent duplicate fetches
    final existing = ytmOnline.value.customPlaylists.any((p) => p.id == input);
    if (existing) return;

    ytmOnline.value = ytmOnline.value.copyWith(
      customStatus: YtmFetchStatus.loading,
      clearCustomError: true,
    );

    try {
      final ytmService = getIt<YtmService>();
      final tracks = await ytmService.getPlaylistTracks(input, limit: 200);
      if (tracks.isEmpty) {
        ytmOnline.value = ytmOnline.value.copyWith(
          customStatus: YtmFetchStatus.error,
          customError: 'Playlist is empty or could not be fetched.',
        );
        return;
      }

      // Build a display name: try to extract playlist ID from URL
      String title = 'YouTube Playlist';
      if (input.contains('list=')) {
        final listId = Uri.tryParse(input)?.queryParameters['list'];
        if (listId != null && listId.isNotEmpty) {
          // Shorten long IDs to keep the label readable
          title = listId.length > 16 ? '${listId.substring(0, 16)}…' : listId;
        }
      } else if (!input.startsWith('http')) {
        final short = input.length > 16 ? '${input.substring(0, 16)}…' : input;
        title = 'Playlist ($short)';
      }

      final entry = OnlinePlaylistEntry(
        id: input,
        title: title,
        uploader: tracks.first.artist,
        tracks: tracks,
      );

      final updated = List<OnlinePlaylistEntry>.from(ytmOnline.value.customPlaylists)..add(entry);
      ytmOnline.value = ytmOnline.value.copyWith(
        customStatus: YtmFetchStatus.done,
        customPlaylists: updated,
        clearCustomError: true,
      );
      _saveOnlineCache();
    } catch (e) {
      ytmOnline.value = ytmOnline.value.copyWith(
        customStatus: YtmFetchStatus.error,
        customError: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// Removes a previously fetched custom online playlist.
  void removeCustomPlaylist(String id) {
    final updated = ytmOnline.value.customPlaylists.where((p) => p.id != id).toList();
    ytmOnline.value = ytmOnline.value.copyWith(customPlaylists: updated);
    _saveOnlineCache();
  }

  /// Resets all online playlist state (liked + fetched list).
  void clearOnlinePlaylists() {
    ytmOnline.value = const YtmOnlineState();
    _saveOnlineCache();
  }

  @override
  Future<void> close() {
    if (AppConfig.ytmEnabled) {
      try {
        getIt<YtmAccountService>().loginState.removeListener(_onYtmLoginStateChanged);
      } catch (_) {}
    }
    ytmOnline.dispose();
    _playlistsSub?.cancel();
    _playlistSongsSub?.cancel();
    for (final sub in _smartSubscriptions.values) {
      sub.cancel();
    }
    _smartSubscriptions.clear();
    return super.close();
  }
}
