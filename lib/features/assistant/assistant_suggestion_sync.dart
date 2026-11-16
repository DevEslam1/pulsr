// lib/features/assistant/assistant_suggestion_sync.dart
//
// Keeps the Android search-suggestion cache warm.
//
// The exported `SearchSuggestionsProvider` serves rows that MainActivity caches
// through `com.pulsr.music/assistant#updateSuggestions`. Nothing populates that
// cache on its own, so a system search box would stay empty forever. This tiny
// sync pushes a bounded, privacy-safe set (title / artist · album / query) after
// startup and never throws: a missing platform channel simply means the
// suggestion surface is unavailable in this build.

import '../../core/utils/error_logger.dart';
import '../../data/db/app_database.dart';
import '../../domain/repositories/music_repository_interface.dart';
import 'assistant_search_channel.dart';

/// Pushes recent-library rows into the native suggestion cache.
class AssistantSuggestionSync {
  AssistantSuggestionSync({
    required IMusicRepository repository,
    AssistantSearchChannel? channel,
  })  : _repository = repository,
        _channel = channel ?? AssistantSearchChannel();

  final IMusicRepository _repository;
  final AssistantSearchChannel _channel;

  /// Number of rows pushed. Bounded by [AssistantSearchChannel.maxSuggestions].
  Future<int> pushRecent({int limit = AssistantSearchChannel.maxSuggestions}) async {
    final capped = limit.clamp(1, AssistantSearchChannel.maxSuggestions);
    try {
      final recent = await _repository.getRecentlyPlayed(limit: capped);
      final songs = recent.fold<List<SongsTableData>>(
        (_) => const [],
        (rows) => rows,
      );
      if (songs.isEmpty) return 0;
      final suggestions = <AssistantSuggestion>[];
      final seen = <String>{};
      for (final song in songs) {
        final title = song.title.trim();
        if (title.isEmpty || !seen.add(title.toLowerCase())) continue;
        suggestions.add(
          AssistantSuggestion(
            title: title,
            subtitle: '${song.artist} · ${song.album}',
            query: title,
          ),
        );
        if (suggestions.length >= capped) break;
      }
      if (suggestions.isEmpty) return 0;
      final pushed = await _channel.updateSuggestions(suggestions);
      return pushed ? suggestions.length : 0;
    } catch (e, st) {
      ErrorLogger.log(
        'Search suggestion sync failed',
        error: e,
        stackTrace: st,
        category: 'Assistant',
      );
      return 0;
    }
  }

  /// Clears the native cache (e.g. after the library is wiped).
  Future<void> clear() async {
    try {
      await _channel.clear();
    } catch (e, st) {
      ErrorLogger.log(
        'Search suggestion clear failed',
        error: e,
        stackTrace: st,
        category: 'Assistant',
      );
    }
  }
}
