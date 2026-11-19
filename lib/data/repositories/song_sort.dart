// lib/data/repositories/song_sort.dart
//
// Ordering policy for library queries (songs, albums, artists). Kept out of
// `MusicRepository` for two reasons: the repository is already over its size
// ratchet, and the SQL shape is worth testing in isolation.
import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Leading quote/bracket characters that rips commonly put in front of an
/// article (`"The Beatles`, `(A Perfect Circle)`). They are stripped only for
/// article detection; the original text is kept when no article follows.
const Set<String> kArticleWrappers = {
  '"',
  "'",
  '(',
  '[',
  '{',
  '\u201c', // left double quotation mark
  '\u2018', // left single quotation mark
};

/// SQL expression ordering [column] as if a leading English article
/// (`the `, `a `, `an `, case-insensitive) were removed. The article is also
/// recognised after a leading quote or opening bracket.
///
/// This stays inside SQLite instead of being sorted in Dart so `LIMIT` /
/// `OFFSET` paging keeps a globally correct order rather than sorting a page.
Expression<String> articleInsensitive(Expression<String> column) {
  final lower = column.lower();
  // `column` with a leading quote/bracket removed, and its lowercase form.
  final unwrapped = column.substr(2);
  final lowerUnwrapped = unwrapped.lower();
  final wrapped = column.substr(1, 1).isIn(kArticleWrappers);

  Expression<bool> startsWith(Expression<String> text, String prefix) =>
      text.substr(1, prefix.length).equals(prefix);

  return CaseWhenExpression<String>(
    cases: [
      // Article behind a leading quote/bracket: `"The Beatles` -> `Beatles`.
      CaseWhen(wrapped & startsWith(lowerUnwrapped, 'the '),
          then: unwrapped.substr(5)),
      CaseWhen(wrapped & startsWith(lowerUnwrapped, 'an '),
          then: unwrapped.substr(4)),
      CaseWhen(wrapped & startsWith(lowerUnwrapped, 'a '),
          then: unwrapped.substr(3)),
      // Bare article: `The Beatles` -> `Beatles`.
      CaseWhen(startsWith(lower, 'the '), then: column.substr(5)),
      CaseWhen(startsWith(lower, 'an '), then: column.substr(4)),
      CaseWhen(startsWith(lower, 'a '), then: column.substr(3)),
    ],
    orElse: column,
  );
}

/// Ordering terms for the album library: article-insensitive title, then `id`
/// so identically-named albums keep a stable order.
///
/// Mirrors the songs tab, where `The Beatles` sorts under `B`.
List<OrderingTerm Function($AlbumsTableTable)> albumSortOrder() => [
      (t) => OrderingTerm(expression: articleInsensitive(t.title)),
      (t) => OrderingTerm.asc(t.id),
    ];

/// Ordering terms for the artist library: article-insensitive name, then `id`.
///
/// Mirrors the songs tab, where `The Beatles` sorts under `B`.
List<OrderingTerm Function($ArtistsTableTable)> artistSortOrder() => [
      (t) => OrderingTerm(expression: articleInsensitive(t.name)),
      (t) => OrderingTerm.asc(t.id),
    ];

/// Applies the library's song ordering to [query].
///
/// `title`, `artist` and `album` order article-insensitively; every other key
/// keeps its historical column ordering, and an unknown key falls back to the
/// plain title so an old persisted preference can never break a query.
void applySongSort(
  SimpleSelectStatement<$SongsTableTable, SongsTableData> query,
  String sortBy,
  bool ascending,
) {
  final mode = ascending ? OrderingMode.asc : OrderingMode.desc;
  final OrderingTerm Function($SongsTableTable) primary = switch (sortBy) {
    'artist' =>
      (t) => OrderingTerm(expression: articleInsensitive(t.artist), mode: mode),
    'dateAdded' => (t) => OrderingTerm(expression: t.dateAdded, mode: mode),
    'duration' => (t) => OrderingTerm(expression: t.durationMs, mode: mode),
    'album' =>
      (t) => OrderingTerm(expression: articleInsensitive(t.album), mode: mode),
    'playCount' => (t) => OrderingTerm(expression: t.playCount, mode: mode),
    'lastPlayed' => (t) => OrderingTerm(expression: t.lastPlayed, mode: mode),
    'fileSize' => (t) => OrderingTerm(expression: t.fileSize, mode: mode),
    'year' => (t) => OrderingTerm(expression: t.year, mode: mode),
    'sampleRate' => (t) => OrderingTerm(expression: t.sampleRate, mode: mode),
    'title' =>
      (t) => OrderingTerm(expression: articleInsensitive(t.title), mode: mode),
    // Unknown keys keep the historical plain-title fallback unchanged.
    _ => (t) => OrderingTerm(expression: t.title, mode: mode),
  };
  final bool articleOrdered =
      sortBy == 'title' || sortBy == 'artist' || sortBy == 'album';
  query.orderBy([
    primary,
    // `The Beatles` and `Beatles` tie on the primary term; break it with the
    // article-insensitive title instead of falling straight through to id.
    if (articleOrdered && sortBy != 'title')
      (t) => OrderingTerm(expression: articleInsensitive(t.title), mode: mode),
    (t) => OrderingTerm.asc(t.id),
  ]);
}
