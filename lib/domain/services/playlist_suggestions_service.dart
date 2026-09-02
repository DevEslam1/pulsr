// lib/domain/services/playlist_suggestions_service.dart
import 'package:injectable/injectable.dart';
import '../../data/db/app_database.dart';

class PlaylistSuggestion {
  final String title;
  final String description;
  final List<SongsTableData> songs;

  const PlaylistSuggestion({
    required this.title,
    required this.description,
    required this.songs,
  });
}

@singleton
class PlaylistSuggestionsService {
  /// Generates smart suggested mixes based on library tracks and playback history.
  List<PlaylistSuggestion> generateSuggestions(List<SongsTableData> allSongs) {
    if (allSongs.isEmpty) return [];

    final suggestions = <PlaylistSuggestion>[];

    // 1. Heavy Rotation (Top played)
    final topPlayed = List<SongsTableData>.from(allSongs)
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    final heavyRotation =
        topPlayed.where((s) => s.playCount > 0).take(25).toList();
    if (heavyRotation.isNotEmpty) {
      suggestions.add(PlaylistSuggestion(
        title: 'Heavy Rotation Mix',
        description: 'Your most played tracks on repeat',
        songs: heavyRotation,
      ));
    }

    // 2. Rediscover & Forgotten Favorites
    final forgotten = allSongs
        .where((s) => s.isFavorite && (s.playCount < 3))
        .take(20)
        .toList();
    if (forgotten.isNotEmpty) {
      suggestions.add(PlaylistSuggestion(
        title: 'Forgotten Favorites',
        description: 'Starred gems you haven\'t heard in a while',
        songs: forgotten,
      ));
    }

    // 3. Audiophile Master Lossless Mix
    final audiophile = allSongs
        .where((s) =>
            s.codec == 'FLAC' ||
            s.codec == 'ALAC' ||
            (s.bitDepth != null && s.bitDepth! >= 24))
        .take(30)
        .toList();
    if (audiophile.isNotEmpty) {
      suggestions.add(PlaylistSuggestion(
        title: 'Hi-Res Audiophile Showcase',
        description: 'Studio master 24-bit lossless fidelity',
        songs: audiophile,
      ));
    }

    // 4. Quick Energy Boost (Short upbeat tracks)
    final upbeat = allSongs
        .where((s) => s.durationMs > 120000 && s.durationMs < 240000)
        .take(25)
        .toList();
    if (upbeat.isNotEmpty) {
      suggestions.add(PlaylistSuggestion(
        title: 'Quick Energy Boost',
        description: 'High-energy fast tracks to power your day',
        songs: upbeat,
      ));
    }

    return suggestions;
  }
}

