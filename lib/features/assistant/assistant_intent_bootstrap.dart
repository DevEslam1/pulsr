// lib/features/assistant/assistant_intent_bootstrap.dart
//
// Process-wide startup hook for the Android assistant surface.
//
// MainActivity forwards MEDIA_PLAY_FROM_SEARCH / ACTION_SEARCH extras over
// 'com.pulsr.music/assistant'; this file builds the resolver + player adapter
// from the DI container and installs [AssistantIntentService] on that channel.
// It is idempotent and a no-op until both the repository and the player cubit
// are ready, so the existing `AssistantSuggestionSync` startup path can call it
// without owning the wiring itself.

import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/di/injection.dart';
import '../../core/errors/failures.dart';
import '../../core/utils/error_logger.dart';
import '../../data/db/app_database.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../player/cubit/player_cubit.dart';
import 'assistant_intent_service.dart';
import 'assistant_resolver.dart';

/// Installs the assistant intent channel once the app dependencies exist.
abstract final class AssistantIntentBootstrap {
  static AssistantIntentService? _service;
  static bool _installing = false;

  /// Whether the channel handler is installed.
  static bool get isInstalled => _service != null;

  /// Installs the handler when possible; safe to call repeatedly.
  static void ensureInstalled() {
    if (_service != null || _installing) return;
    if (!getIt.isRegistered<IMusicRepository>() ||
        !getIt.isRegistered<PlayerCubit>()) {
      return;
    }
    _installing = true;
    try {
      final repository = getIt<IMusicRepository>();
      final player = getIt<PlayerCubit>();
      _service = AssistantIntentService(
        resolver: AssistantResolver(
          searchSongIds: (query) async => _songIdsOf(
            await repository.watchAllSongs(searchQuery: query, limit: 50).first,
          ),
          playlistSongIds: (name) async {
            final lists = (await repository.getPlaylists())
                .fold<List<PlaylistsTableData>>((_) => const [], (r) => r);
            final lower = name.trim().toLowerCase();
            if (lower.isEmpty) return const <int>[];
            PlaylistsTableData? match;
            for (final playlist in lists) {
              if (playlist.name.trim().toLowerCase() == lower) {
                match = playlist;
                break;
              }
            }
            if (match == null) {
              for (final playlist in lists) {
                if (playlist.name.toLowerCase().contains(lower)) {
                  match = playlist;
                  break;
                }
              }
            }
            if (match == null) return const <int>[];
            return _songIdsOf(await repository.getPlaylistSongs(match.id));
          },
          favoritesSongIds: () async =>
              _songIdsOf(await repository.getFavorites()),
          lastAlbumSongIds: () async {
            final recent = (await repository.getRecentlyPlayed(limit: 50))
                .fold<List<SongsTableData>>((_) => const [], (r) => r);
            if (recent.isEmpty) return const <int>[];
            final albumId = recent.first.albumId;
            if (albumId == null) {
              return recent.map((song) => song.id).toList();
            }
            return recent
                .where((song) => song.albumId == albumId)
                .map((song) => song.id)
                .toList();
          },
        ),
        playPlan: (plan) async {
          final songs = (await repository.getSongsByIds(plan.songIds))
              .fold<List<SongsTableData>>((_) => const [], (r) => r);
          if (songs.isEmpty) return;
          final queue = plan.shuffle
              ? (List<SongsTableData>.from(songs)..shuffle())
              : songs;
          final index = plan.startIndex.clamp(0, queue.length - 1);
          await player.playSong(queue[index], queue: queue, queueIndex: index);
        },
      );
      // Native only switches warm MEDIA_PLAY_FROM_SEARCH intents to the
      // extras channel after this handshake, so an uninstalled handler falls
      // back to the legacy query path instead of silently swallowing them.
      unawaited(_announceReady());
    } on StateError {
      // Registered but still warming up. The post-warm-up call retries; this
      // is expected at cold start and is not a crash.
    } catch (e, st) {
      ErrorLogger.log(
        'Assistant intent channel could not be installed',
        error: e,
        stackTrace: st,
        category: 'Assistant',
      );
    } finally {
      _installing = false;
    }
  }

  /// Removes the channel handler (tests and process teardown).
  static void dispose() {
    _service?.dispose();
    _service = null;
  }

  static List<int> _songIdsOf(Result<List<SongsTableData>> result) =>
      result.fold(
        (_) => const <int>[],
        (songs) => songs.map((song) => song.id).toList(),
      );

  static Future<void> _announceReady() async {
    try {
      await const MethodChannel(AssistantIntentService.channelName)
          .invokeMethod<void>('assistantReady');
    } on MissingPluginException {
      // No native assistant bridge in this build (desktop, tests, old APK).
    } catch (e, st) {
      ErrorLogger.log(
        'Assistant channel handshake failed',
        error: e,
        stackTrace: st,
        category: 'Assistant',
      );
    }
  }
}
