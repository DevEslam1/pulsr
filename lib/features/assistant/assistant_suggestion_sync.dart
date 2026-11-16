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
import 'assistant_intent_bootstrap.dart';
import 'assistant_search_channel.dart';
import 'assistant_settings.dart';

/// Pushes recent-library rows into the native suggestion cache.
///
/// Pushing is opt-in through [AssistantSettings]. While the toggle is off this
/// class clears any previously cached rows instead of publishing library
/// titles. Constructing it also installs the assistant intent channel when the
/// app dependencies are ready, so the startup path that already creates this
/// object lights up voice search without a second bootstrap call.
class AssistantSuggestionSync {
  AssistantSuggestionSync({
    required IMusicRepository repository,
    AssistantSearchChannel? channel,
    AssistantSettings? settings,
  })  : _repository = repository,
        _channel = channel ?? AssistantSearchChannel(),
        _settings = settings {
    AssistantIntentBootstrap.ensureInstalled();
  }

  final IMusicRepository _repository;
  final AssistantSearchChannel _channel;
  AssistantSettings? _settings;

  /// Number of rows pushed. Bounded by [AssistantSearchChannel.maxSuggestions].
  ///
  /// Returns 0 and clears the native cache when suggestions are disabled, so a
  /// user who turns the toggle off does not keep titles cached forever.
  Future<int> pushRecent(
      {int limit = AssistantSearchChannel.maxSuggestions}) async {
    // Retry the install in case the player cubit finished registering between
    // this object's construction and the first startup sync.
    AssistantIntentBootstrap.ensureInstalled();
    final settings = await _resolveSettings();
    if (!settings.suggestionsEnabled) {
      await clear();
      return 0;
    }
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

  /// Clears the native cache (e.g. after the library is wiped or the toggle is
  /// turned off). Clearing is always allowed: it only removes data.
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

  Future<AssistantSettings> _resolveSettings() async =>
      _settings ??= await AssistantSettings.load();
}
