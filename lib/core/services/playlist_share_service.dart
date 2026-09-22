// lib/core/services/playlist_share_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import '../../data/db/app_database.dart';
import '../utils/error_logger.dart';

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

  /// Computes the nesting depth of a JSON object tree.
  static int computeDepth(Object? object, [int currentDepth = 1]) {
    if (currentDepth > 5) return currentDepth;
    if (object is Map) {
      var maxChild = currentDepth;
      for (final value in object.values) {
        final d = computeDepth(value, currentDepth + 1);
        if (d > maxChild) maxChild = d;
        if (maxChild > 5) return maxChild;
      }
      return maxChild;
    } else if (object is List) {
      var maxChild = currentDepth;
      for (final item in object) {
        final d = computeDepth(item, currentDepth + 1);
        if (d > maxChild) maxChild = d;
        if (maxChild > 5) return maxChild;
      }
      return maxChild;
    }
    return currentDepth;
  }

  /// Parses a shared playlist bundle from JSON.
  SharedPlaylistBundle? importPlaylist(String jsonString) {
    try {
      final decoded = json.decode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        ErrorLogger.log('Invalid JSON root format in shared playlist',
            category: 'PlaylistShareService');
        return null;
      }
      final depth = computeDepth(decoded);
      if (depth > 5) {
        ErrorLogger.log(
          'Shared playlist JSON exceeds maximum nesting depth ($depth > 5)',
          category: 'PlaylistShareService',
        );
        return null;
      }
      return SharedPlaylistBundle.fromJson(decoded);
    } catch (e, st) {
      ErrorLogger.log('Failed to parse shared playlist',
          error: e, stackTrace: st, category: 'PlaylistShareService');
      return null;
    }
  }
}
