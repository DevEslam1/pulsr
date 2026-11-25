// lib/features/assistant/assistant_query.dart
//
// Pure parsing for the assistant / search surface. Two entry points:
//   * [parseSearchExtras]  - Android search-intent extras
//     (android.media.action.MEDIA_PLAY_FROM_SEARCH)
//   * [parseAssistantText] - short natural-language commands ("play X")
// Nothing here touches Flutter, the database or the player, so the rules stay
// unit-testable and can be reused from every entry point.

/// The intents the assistant can act on without asking a follow-up question.
enum AssistantIntentKind {
  /// `play <playlist>`: resolve a user playlist by name.
  playPlaylist,

  /// `resume last album`: continue the most recently played album.
  resumeLastAlbum,

  /// `shuffle favourites`: play the favourite tracks in a random order.
  shuffleFavorites,

  /// `play <artist> radio`: an artist-flavoured mix.
  playArtistRadio,

  /// Anything else: treat the text as a library search.
  searchSongs,
}

/// Which search-intent extra supplied the term.
///
/// Declaration order is also the precedence order used by
/// [parseSearchExtras]: playlist, then album, artist, genre, song, title and
/// finally the free-text query. A concrete media field always wins over the
/// generic query field, because assistants send both ("play Kind of Blue"
/// arrives as ALBUM + QUERY).
enum AssistantExtraField { playlist, album, artist, genre, song, title, query }

/// Why an assistant request could not be parsed.
enum AssistantQueryErrorKind {
  /// The request carried no text at all.
  empty,

  /// The request had text but no usable target, e.g. a bare "play".
  unparseable,
}

/// Raised when an assistant request has no usable target.
///
/// [reason] is developer-facing (logging only). User-facing copy lives in
/// `AssistantStrings` and is produced by the resolver, never here.
final class AssistantQueryError implements Exception {
  /// Creates an error of [kind] carrying a technical [reason].
  const AssistantQueryError(this.kind, this.reason);

  /// What went wrong.
  final AssistantQueryErrorKind kind;

  /// Technical explanation; never shown to the user verbatim.
  final String reason;

  @override
  String toString() => 'AssistantQueryError(${kind.name}): $reason';
}

/// A play request built from Android search-intent extras.
final class AssistantPlayRequest {
  /// Creates a request for [field].
  const AssistantPlayRequest({
    required this.field,
    required this.term,
    required this.display,
    this.mimeType = '',
  });

  /// The extra that supplied the term; also tells the resolver how to look it
  /// up.
  final AssistantExtraField field;

  /// Lowercased, whitespace-collapsed matching term with a leading article
  /// removed. Used for lookups only.
  final String term;

  /// Original casing with quotes and the command prefix removed. Used for the
  /// now-playing title so a spoken "Chill Mix" does not become "chill mix".
  final String display;

  /// The `MIME_TYPE` extra, empty when absent. Carried for the player adapter;
  /// the resolver does not branch on it.
  final String mimeType;

  /// Whether the request targets a single song or track title.
  bool get isTitleScoped =>
      field == AssistantExtraField.song || field == AssistantExtraField.title;

  @override
  String toString() =>
      'AssistantPlayRequest(${field.name}, "$term", mime: "$mimeType")';
}

/// A request parsed from natural-language text.
final class AssistantTextIntent {
  /// Creates a parsed text intent.
  const AssistantTextIntent({
    required this.kind,
    required this.term,
    required this.display,
    required this.rawText,
    this.wantsShuffle = false,
  });

  /// The intent the text expressed.
  final AssistantIntentKind kind;

  /// Lowercased matching term; empty for [AssistantIntentKind.resumeLastAlbum].
  final String term;

  /// Original casing of the term, for titles and messages.
  final String display;

  /// The flattened input text, for logging and telemetry only.
  final String rawText;

  /// True when the user said "shuffle", which applies to playlists too
  /// ("shuffle rock").
  final bool wantsShuffle;

  @override
  String toString() =>
      'AssistantTextIntent(${kind.name}, "$term", shuffle: $wantsShuffle)';
}

/// Parses search-intent extras into a play request.
///
/// Accepts both the canonical upper-case keys sent by the native layer
/// (`QUERY`, `PLAYLIST`, ...) and their lower-case spellings. Throws
/// [AssistantQueryError] with kind [AssistantQueryErrorKind.empty] when no
/// key carries a usable term, so callers can log and drop the request.
AssistantPlayRequest parseSearchExtras(Map<String, String?> extras) {
  final rawMimeType = _readExtra(extras, 'MIME_TYPE');
  final mimeType = rawMimeType == null ? '' : _flatten(rawMimeType);
  for (final field in AssistantExtraField.values) {
    final raw = _readExtra(extras, _keyFor(field));
    if (raw == null) continue;
    final segment = _segment(raw);
    if (segment.term.isEmpty) continue;
    return AssistantPlayRequest(
      field: field,
      term: segment.term,
      display: segment.display,
      mimeType: mimeType,
    );
  }
  throw const AssistantQueryError(
    AssistantQueryErrorKind.empty,
    'No search term in the intent extras.',
  );
}

/// Classifies [query] without building a request.
///
/// Throws [AssistantQueryError] for empty or target-less input; see
/// [parseAssistantText] when the extracted term is needed as well.
AssistantIntentKind classify(String query) => parseAssistantText(query).kind;

/// Parses natural-language [query] into an intent plus its extracted term.
///
/// Recognised shapes, in match order: `resume/continue [the] [last] album`,
/// `shuffle favourites`, `play <artist> radio` / `radio <artist>`,
/// `play <playlist>`, `shuffle <playlist>`, then bare text as a song search.
/// Throws [AssistantQueryError] for empty text or a command with no target.
AssistantTextIntent parseAssistantText(String query) {
  final flat = _flatten(query);
  if (flat.isEmpty) {
    throw const AssistantQueryError(
      AssistantQueryErrorKind.empty,
      'The assistant request was empty.',
    );
  }

  final prefix = _commandPrefix.firstMatch(flat);
  final commandless = prefix == null ? flat : flat.substring(prefix.end).trim();
  if (commandless.isEmpty) {
    throw AssistantQueryError(
      AssistantQueryErrorKind.unparseable,
      '"$flat" has no target.',
    );
  }
  if (_commandOnlyPattern.hasMatch(flat)) {
    throw AssistantQueryError(
      AssistantQueryErrorKind.unparseable,
      '"$flat" is a command without a target.',
    );
  }

  final lower = commandless.toLowerCase();

  if (_resumePattern.hasMatch(lower) || _lastAlbumPattern.hasMatch(lower)) {
    return AssistantTextIntent(
      kind: AssistantIntentKind.resumeLastAlbum,
      term: '',
      display: '',
      rawText: flat,
    );
  }

  final shuffleMatch = _shufflePrefix.firstMatch(lower);
  if (shuffleMatch != null) {
    if (_favoritesWord.hasMatch(lower)) {
      return AssistantTextIntent(
        kind: AssistantIntentKind.shuffleFavorites,
        term: '',
        display: '',
        rawText: flat,
        wantsShuffle: true,
      );
    }
    final rest = commandless.substring(shuffleMatch.end).trim();
    if (rest.isEmpty) {
      return AssistantTextIntent(
        kind: AssistantIntentKind.shuffleFavorites,
        term: '',
        display: '',
        rawText: flat,
        wantsShuffle: true,
      );
    }
    final segment = _segment(rest);
    if (segment.term.isEmpty) {
      throw AssistantQueryError(
        AssistantQueryErrorKind.unparseable,
        '"$flat" has no target.',
      );
    }
    return AssistantTextIntent(
      kind: AssistantIntentKind.playPlaylist,
      term: segment.term,
      display: segment.display,
      rawText: flat,
      wantsShuffle: true,
    );
  }

  if (_favoritesCommandPattern.hasMatch(lower)) {
    return AssistantTextIntent(
      kind: AssistantIntentKind.shuffleFavorites,
      term: '',
      display: '',
      rawText: flat,
      wantsShuffle: false,
    );
  }

  final radioSuffix = _radioSuffix.firstMatch(lower);
  if (radioSuffix != null) {
    final artist = commandless.substring(0, radioSuffix.start).trim();
    if (artist.isNotEmpty) {
      final segment = _segment(artist);
      return AssistantTextIntent(
        kind: AssistantIntentKind.playArtistRadio,
        term: segment.term,
        display: segment.display,
        rawText: flat,
      );
    }
  }

  final radioPrefix = _radioPrefix.firstMatch(lower);
  if (radioPrefix != null) {
    final artist = commandless.substring(radioPrefix.end).trim();
    if (artist.isNotEmpty) {
      final segment = _segment(artist);
      return AssistantTextIntent(
        kind: AssistantIntentKind.playArtistRadio,
        term: segment.term,
        display: segment.display,
        rawText: flat,
      );
    }
  }

  if (prefix != null) {
    final segment = _segment(commandless);
    if (segment.term.isEmpty) {
      throw AssistantQueryError(
        AssistantQueryErrorKind.unparseable,
        '"$flat" has no target.',
      );
    }
    return AssistantTextIntent(
      kind: AssistantIntentKind.playPlaylist,
      term: segment.term,
      display: segment.display,
      rawText: flat,
    );
  }

  final segment = _segment(commandless);
  if (segment.term.isEmpty) {
    throw AssistantQueryError(
      AssistantQueryErrorKind.unparseable,
      '"$flat" has no searchable term.',
    );
  }
  return AssistantTextIntent(
    kind: AssistantIntentKind.searchSongs,
    term: segment.term,
    display: segment.display,
    rawText: flat,
  );
}

/// Normalises one term for matching: trim, collapse whitespace, strip
/// surrounding quotes, drop a leading command ("play ") and a leading English
/// article ("the", "a", "an"), then lowercase.
///
/// Lowercasing uses Dart's default Unicode mapping, which is locale
/// independent, so a Turkish device does not turn "I" into "ı".
String normalizeTerm(String input) => _segment(input).term;

/// Flattens user input: trims, removes one layer of matching quotes and
/// collapses internal whitespace to single spaces. Keeps the original casing.
String _flatten(String input) =>
    _stripQuotes(input.trim()).replaceAll(_whitespace, ' ').trim();

/// Splits flattened [text] into the matching term and the display form.
/// A leading command word is dropped from both, so a voice recogniser that
/// submits the whole phrase ("play chill mix") still matches "chill mix".
({String term, String display}) _segment(String text) {
  final flat = _flatten(text);
  final command = _commandPrefix.firstMatch(flat);
  final unquoted = _stripQuotes(
    command == null ? flat : flat.substring(command.end).trim(),
  );
  final display = unquoted.trim();
  if (display.isEmpty) return (term: '', display: '');
  return (term: _stripArticle(display.toLowerCase()), display: display);
}

/// Removes a leading English article when something follows it.
String _stripArticle(String lower) {
  final stripped = lower.replaceFirst(_articlePrefix, '');
  return stripped.isEmpty ? lower : stripped;
}

/// Removes one or more layers of matching straight or typographic quotes.
String _stripQuotes(String input) {
  var text = input;
  var changed = true;
  while (changed && text.length >= 2) {
    changed = false;
    final first = text[0];
    final last = text[text.length - 1];
    final paired = (first == '"' && last == '"') ||
        (first == "'" && last == "'") ||
        (first == '\u201c' && last == '\u201d') ||
        (first == '\u2018' && last == '\u2019');
    if (paired) {
      text = text.substring(1, text.length - 1).trim();
      changed = true;
    }
  }
  return text;
}

/// Reads [key] from [extras], accepting both the canonical upper-case key and
/// its lower-case spelling.
String? _readExtra(Map<String, String?> extras, String key) {
  final upper = extras[key];
  if (upper != null && upper.trim().isNotEmpty) return upper;
  final lower = extras[key.toLowerCase()];
  if (lower != null && lower.trim().isNotEmpty) return lower;
  return null;
}

/// The canonical (upper-case) extras key for [field].
String _keyFor(AssistantExtraField field) => switch (field) {
      AssistantExtraField.playlist => 'PLAYLIST',
      AssistantExtraField.album => 'ALBUM',
      AssistantExtraField.artist => 'ARTIST',
      AssistantExtraField.genre => 'GENRE',
      AssistantExtraField.song => 'SONG',
      AssistantExtraField.title => 'TITLE',
      AssistantExtraField.query => 'QUERY',
    };

final RegExp _whitespace = RegExp(r'\s+');
final RegExp _articlePrefix = RegExp(r'^(?:the|a|an|el|la|los|las|un|una)\s+');
final RegExp _commandPrefix = RegExp(
  r'^(?:play|listen to|put on|start playing|reproduce|reproducir|pon|poner|escucha|escuchar|toca|tocar|شغل|شغّل|تشغيل|اسمع|استمع|استماع)\s+',
  caseSensitive: false,
);
final RegExp _commandOnlyPattern = RegExp(
  r'^(?:play|play music|listen to|put on|start playing|reproduce|reproducir|pon|pon m[uú]sica|poner m[uú]sica|escuchar m[uú]sica|toca|شغل|شغّل|شغل موسيقى|شغّل موسيقى|تشغيل|تشغيل موسيقى|اسمع|استمع)$',
  caseSensitive: false,
);
final RegExp _shufflePrefix = RegExp(
  r'^(?:shuffle|mezclar?|modo aleatorio|aleatorio|خلط|اخلط|تشغيل عشوائي|عشوائي)(?=\s|$)',
  caseSensitive: false,
);
final RegExp _favoritesWord = RegExp(
  r'(?:^|\s)(?:my\s+|mis\s+)?(?:favourites?|favorites?|liked(?:\s+songs)?|loved(?:\s+songs)?|heart|favoritos|favoritas|canciones favoritas|me gusta|preferidas?|المفضلة|المفضله|مفضلتي|أغاني المفضلة|أغانيي المفضلة|الإعجابات|المحبوبة)(?=\s|$)',
  caseSensitive: false,
);
final RegExp _favoritesCommandPattern = RegExp(
  r'^(?:(?:the|my|mis)\s+)?(?:favourites?|favorites?|liked(?:\s+songs)?|loved(?:\s+songs)?|favoritos|favoritas|canciones favoritas|المفضلة|المفضله|مفضلتي|أغاني المفضلة|أغانيي المفضلة)$',
  caseSensitive: false,
);
final RegExp _resumePattern = RegExp(
  r'^(?:(?:resume|continue)(?:\s+(?:the|my))?(?:\s+(?:last|previous))?(?:\s+(?:played|listened))?(?:\s+(?:album|record))?'
  r'|(?:reanuda|reanudar|contin[uú]a|continuar)(?:\s+(?:el|mi))?(?:\s+(?:[uú]ltimo|anterior))?(?:\s+(?:[aá]lbum|disco))?'
  r'|(?:استأنف|استئناف|أكمل|اكمل|واصل|مواصلة)(?:\s+(?:آخر|اخر))?(?:\s*(?:ألبوم|البوم|الألبوم|الالبوم))?)$',
  caseSensitive: false,
);
final RegExp _lastAlbumPattern = RegExp(
  r'^(?:(?:the\s+)?(?:last|previous)\s+(?:played\s+)?(?:album|record)'
  r'|(?:el\s+)?(?:[uú]ltimo|anterior)\s+(?:[aá]lbum|disco)'
  r'|(?:آخر|اخر)\s+(?:ألبوم|البوم)|(?:الألبوم|الالبوم)\s+(?:الأخير|الاخير))$',
  caseSensitive: false,
);
final RegExp _radioSuffix =
    RegExp(r'\s+(?:radio|راديو|إذاعة)$', caseSensitive: false);
final RegExp _radioPrefix =
    RegExp(r'^(?:radio(?:\s+de)?|راديو|إذاعة)\s+', caseSensitive: false);
