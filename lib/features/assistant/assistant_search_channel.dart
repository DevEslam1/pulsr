// lib/features/assistant/assistant_search_channel.dart
//
// Pushes search-suggestion rows to the native suggestion provider so the
// system search surface can show library rows without waking Dart. This is a
// best-effort side channel: the app keeps working when the host has no
// handler (tests, desktop, an old APK), so every call is guarded and logged.

import 'package:flutter/services.dart';

import '../../core/utils/error_logger.dart';

/// One suggestion row shown by the system search surface.
final class AssistantSuggestion {
  /// Creates a row. [query] is what gets submitted when the row is tapped.
  const AssistantSuggestion({
    required this.title,
    this.subtitle = '',
    required this.query,
  });

  /// Primary line, e.g. a song title.
  final String title;

  /// Secondary line, e.g. "Artist - Album".
  final String subtitle;

  /// Text submitted through `android.media.action.MEDIA_PLAY_FROM_SEARCH`.
  final String query;

  /// Converts the row into the map shape the native provider parses.
  Map<String, String> toMap() => {
        'title': title,
        'subtitle': subtitle,
        'query': query,
      };

  @override
  String toString() => 'AssistantSuggestion("$title", "$query")';
}

/// Native bridge for the suggestion cache behind `SearchSuggestionsProvider`.
///
/// Methods pushed to the host:
///  * `updateSuggestions` - a `List<Map<String, String>>` of
///    `{title, subtitle, query}` rows.
///  * `clear` - drop every cached row.
class AssistantSearchChannel {
  /// Creates the bridge, optionally over a test channel.
  AssistantSearchChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// Channel shared with the assistant intent service and the native side.
  static const String channelName = 'com.pulsr.music/assistant';

  /// Method that replaces the cached suggestion rows.
  static const String methodUpdateSuggestions = 'updateSuggestions';

  /// Method that clears the cached suggestion rows.
  static const String methodClear = 'clear';

  /// Upper bound on rows per push, so a large library cannot bloat the
  /// platform payload or the provider's prefs entry.
  static const int maxSuggestions = 24;

  final MethodChannel _channel;

  /// Replaces the native suggestion cache with [suggestions].
  ///
  /// Rows with an empty query are dropped (they would submit nothing).
  /// Returns true when the host accepted the push, false when it is missing or
  /// failed; the failure is logged, never thrown.
  Future<bool> updateSuggestions(List<AssistantSuggestion> suggestions) async {
    final rows = suggestions
        .where((suggestion) => suggestion.query.trim().isNotEmpty)
        .take(maxSuggestions)
        .map((suggestion) => suggestion.toMap())
        .toList(growable: false);
    try {
      await _channel.invokeMethod<void>(methodUpdateSuggestions, rows);
      return true;
    } on MissingPluginException {
      ErrorLogger.log(
        'Suggestion channel is not available on this host',
        category: 'Assistant',
      );
      return false;
    } on PlatformException catch (e, st) {
      ErrorLogger.log(
        'Suggestion push failed: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'Assistant',
      );
      return false;
    } catch (e, st) {
      ErrorLogger.log(
        'Suggestion push failed unexpectedly',
        error: e,
        stackTrace: st,
        category: 'Assistant',
      );
      return false;
    }
  }

  /// Clears the native suggestion cache.
  ///
  /// Returns true when the host accepted the call, false when it is missing or
  /// failed; the failure is logged, never thrown.
  Future<bool> clear() async {
    try {
      await _channel.invokeMethod<void>(methodClear);
      return true;
    } on MissingPluginException {
      ErrorLogger.log(
        'Suggestion channel is not available on this host',
        category: 'Assistant',
      );
      return false;
    } on PlatformException catch (e, st) {
      ErrorLogger.log(
        'Suggestion clear failed: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'Assistant',
      );
      return false;
    } catch (e, st) {
      ErrorLogger.log(
        'Suggestion clear failed unexpectedly',
        error: e,
        stackTrace: st,
        category: 'Assistant',
      );
      return false;
    }
  }
}
