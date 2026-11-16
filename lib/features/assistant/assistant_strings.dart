// lib/features/assistant/assistant_strings.dart
//
// Single translation point for every English string the assistant module
// shows or logs as user copy. A localisation pass only touches this file.

/// User-facing copy for the assistant / search surface.
abstract final class AssistantStrings {
  /// Now-playing title used when the favourites request resolves.
  static const String favoritesTitle = 'Favorites';

  /// Now-playing title used when the last album resumes.
  static const String lastAlbumTitle = 'Last album';

  /// Now-playing title for an artist radio request.
  static String artistRadioTitle(String artist) =>
      artist.isEmpty ? 'Artist radio' : '$artist radio';

  /// Message shown when a lookup found nothing for [term].
  static String nothingMatched(String term) => term.isEmpty
      ? 'Nothing in your library matched that request.'
      : 'Nothing in your library matched "$term".';

  /// Message shown when the favourites list is empty.
  static const String noFavorites = 'No favorite tracks yet.';

  /// Message shown when there is no recent album to resume.
  static const String noLastAlbum = 'No recent album to resume.';

  /// Message shown when a library callback failed.
  static const String libraryUnavailable =
      'Could not read your library. Try again.';

  /// Settings screen title.
  static const String settingsTitle = 'Assistant & search';

  /// Suggestion toggle title.
  static const String suggestionsTitle = 'Search suggestions';

  /// Suggestion toggle subtitle.
  static const String suggestionsSubtitle =
      'Show recent library tracks in the system search box. Off by default: '
      'the cache is readable by the privileged search UI.';

  /// Section label above the toggle.
  static const String suggestionsSection = 'System search';

  /// Shown while suggestions are off and cached rows are removed.
  static const String suggestionsOffNotice =
      'Suggestions are off. Any cached rows were cleared.';
}
