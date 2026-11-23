// lib/features/assistant/assistant_strings.dart
//
// Localized copy for the assistant / search surface, backed by ARB
// (`AppLocalizations`) with automatic English fallback in headless tests.

import 'dart:ui' show Locale;

import '../../core/utils/l10n_holder.dart';
import '../../l10n/generated/app_localizations.dart';

/// User-facing copy for the assistant / search surface.
abstract final class AssistantStrings {
  static final AppLocalizations _fallback =
      lookupAppLocalizations(const Locale('en'));

  static AppLocalizations _l10n([AppLocalizations? l10n]) =>
      l10n ?? L10nHolder.current ?? _fallback;

  /// Now-playing title used when the favourites request resolves.
  static String get favoritesTitle => _l10n().assistantFavoritesTitle;

  /// Now-playing title used when the last album resumes.
  static String get lastAlbumTitle => _l10n().assistantLastAlbumTitle;

  /// Now-playing title for an artist radio request.
  static String artistRadioTitle(String artist, [AppLocalizations? l10n]) {
    final l = _l10n(l10n);
    return artist.isEmpty
        ? l.assistantArtistRadioGeneric
        : l.assistantArtistRadioNamed(artist);
  }

  /// Message shown when a lookup found nothing for [term].
  static String nothingMatched(String term, [AppLocalizations? l10n]) {
    final l = _l10n(l10n);
    return term.isEmpty
        ? l.assistantNothingMatchedGeneric
        : l.assistantNothingMatchedTerm(term);
  }

  /// Message shown when the favourites list is empty.
  static String get noFavorites => _l10n().assistantNoFavorites;

  /// Message shown when there is no recent album to resume.
  static String get noLastAlbum => _l10n().assistantNoLastAlbum;

  /// Message shown when a library callback failed.
  static String get libraryUnavailable => _l10n().assistantLibraryUnavailable;

  /// Settings screen title.
  static String get settingsTitle => _l10n().assistantSettingsTitle;

  /// Suggestion toggle title.
  static String get suggestionsTitle => _l10n().assistantSuggestionsTitle;

  /// Suggestion toggle subtitle.
  static String get suggestionsSubtitle =>
      _l10n().assistantSuggestionsSubtitle;

  /// Section label above the toggle.
  static String get suggestionsSection => _l10n().assistantSuggestionsSection;

  /// Shown while suggestions are off and cached rows are removed.
  static String get suggestionsOffNotice =>
      _l10n().assistantSuggestionsOffNotice;
}
