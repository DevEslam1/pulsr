// lib/domain/services/playlist_share_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import '../../data/db/app_database.dart';
import '../../core/utils/error_logger.dart';

class SharedPlaylistBundle {
  final String name;
  final List<Map<String, dynamic>> tracks;
  final String appVersion;
  final int exportTimestamp;

  const SharedPlaylistBundle({
    required this.name,
    required this.tracks,
    this.appVersion = '1.0.0',
    required this.exportTimestamp,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'appVersion': appVersion,
        'exportTimestamp': exportTimestamp,
        'tracks': tracks,
      };

  factory SharedPlaylistBundle.fromJson(Map<String, dynamic> json) =>
      SharedPlaylistBundle(
        name: json['name'] as String? ?? 'Shared Playlist',
        appVersion: json['appVersion'] as String? ?? '1.0.0',
        exportTimestamp: (json['exportTimestamp'] as num?)?.toInt() ?? 0,
        tracks: (json['tracks'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map((e) {
              final src = e['source'] as String?;
              final String validSource;
              if (src == SongSource.youtube || src == SongSource.local) {
                validSource = src!;
              } else {
                // Unknown source type — warn so future source additions are
                // caught at import time rather than silently misclassifying.
                debugPrint(
                  '[PlaylistShareService] Unknown source type "$src" in imported playlist; '
                  'defaulting to ${SongSource.local}.',
                );
                validSource = SongSource.local;
              }
              return {
                'title': e['title'] as String? ?? 'Unknown Title',
                'artist': e['artist'] as String? ?? 'Unknown Artist',
                'album': e['album'] as String? ?? 'Unknown Album',
                'durationMs': (e['durationMs'] as num?)?.toInt() ?? 0,
                'remoteId': e['remoteId'] as String?,
                'source': validSource,
              };
            }).toList() ??
            [],
      );
}

@singleton
class PlaylistShareService {
  /// Exports a playlist and its songs to a portable JSON bundle.
  String exportPlaylist(String playlistName, List<SongsTableData> songs) {
    final bundle = SharedPlaylistBundle(
      name: playlistName,
      exportTimestamp: DateTime.now().millisecondsSinceEpoch,
      tracks: songs
          .map((s) => {
                'title': s.title,
                'artist': s.artist,
                'album': s.album,
                'durationMs': s.durationMs,
                'remoteId': s.remoteId,
                'source': s.source,
              })
          .toList(),
    );
    return json.encode(bundle.toJson());
  }

  /// Parses a shared playlist bundle from JSON.
  SharedPlaylistBundle? importPlaylist(String jsonString) {
    try {
      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      return SharedPlaylistBundle.fromJson(decoded);
    } catch (e, st) {
      ErrorLogger.log('Failed to parse shared playlist',
          error: e, stackTrace: st, category: 'PlaylistShareService');
      return null;
    }
  }
}

