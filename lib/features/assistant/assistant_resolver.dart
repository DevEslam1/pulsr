// lib/features/assistant/assistant_resolver.dart
//
// Turns a parsed assistant request into a concrete play plan. The four library
// lookups are injected callbacks, so the resolver is unit-testable without the
// database, the repositories or a running player.
//
// Contract: [AssistantResolver] never throws. Every failure - empty result,
// thrown callback, bad term - comes back as an [AssistantResolutionFailure]
// carrying a message that is safe to show to the user.

import '../../core/utils/error_logger.dart';
import 'assistant_query.dart';
import 'assistant_strings.dart';

/// Where a resolved plan came from. The player adapter can use it for
/// telemetry or for picking a queue icon.
enum AssistantPlanSource {
  /// A user playlist matched by name.
  playlist,

  /// An album field in the intent extras.
  album,

  /// An artist field in the intent extras.
  artist,

  /// An artist radio request.
  artistRadio,

  /// A genre field in the intent extras.
  genre,

  /// A song field in the intent extras.
  song,

  /// A track title field in the intent extras.
  title,

  /// A free-text song search.
  search,

  /// The favourite tracks.
  favorites,

  /// The most recently played album.
  lastAlbum,
}

/// Result of resolving an assistant request: either a plan or a failure.
sealed class AssistantResolution {
  const AssistantResolution();
}

/// A concrete queue to hand to the player.
final class AssistantPlayPlan extends AssistantResolution {
  /// Creates a plan. [startIndex] is clamped into range so a stale index from
  /// the caller can never crash the player.
  AssistantPlayPlan({
    required List<int> songIds,
    required this.title,
    required this.source,
    int startIndex = 0,
    this.shuffle = false,
  })  : songIds = List<int>.unmodifiable(songIds),
        startIndex = _clampIndex(startIndex, songIds.length);

  /// Clamps [index] into `0 .. length - 1`, or 0 for an empty queue.
  static int _clampIndex(int index, int length) {
    if (length <= 0 || index < 0) return 0;
    return index >= length ? length - 1 : index;
  }

  /// Song ids in play order.
  final List<int> songIds;

  /// Index of the song that should start playing.
  final int startIndex;

  /// Whether the queue should be shuffled.
  final bool shuffle;

  /// Title to show for the queue, already user-ready.
  final String title;

  /// Where the plan came from.
  final AssistantPlanSource source;

  /// Number of songs in the plan.
  int get length => songIds.length;

  @override
  String toString() => 'AssistantPlayPlan(${source.name}, "$title", '
      '${songIds.length} songs from $startIndex, shuffle: $shuffle)';
}

/// A request that could not be turned into a plan.
final class AssistantResolutionFailure extends AssistantResolution {
  /// Creates a failure carrying a user-facing [message].
  const AssistantResolutionFailure(this.message);

  /// Message that can be shown as-is (snackbar, toast, assistant bubble).
  final String message;

  @override
  String toString() => 'AssistantResolutionFailure("$message")';
}

/// Resolves parsed assistant requests against the library.
///
/// Every dependency is a callback so the class stays free of database, cubit
/// and platform imports. The main agent supplies the adapters; a callback may
/// throw - the resolver converts that into a failure.
class AssistantResolver {
  /// Creates a resolver over the four library lookups.
  AssistantResolver({
    required Future<List<int>> Function(String query) searchSongIds,
    required Future<List<int>> Function(String name) playlistSongIds,
    required Future<List<int>> Function() favoritesSongIds,
    required Future<List<int>> Function() lastAlbumSongIds,
  })  : _searchSongIds = searchSongIds,
        _playlistSongIds = playlistSongIds,
        _favoritesSongIds = favoritesSongIds,
        _lastAlbumSongIds = lastAlbumSongIds;

  final Future<List<int>> Function(String query) _searchSongIds;
  final Future<List<int>> Function(String name) _playlistSongIds;
  final Future<List<int>> Function() _favoritesSongIds;
  final Future<List<int>> Function() _lastAlbumSongIds;

  /// Resolves a request built from Android search-intent extras.
  Future<AssistantResolution> resolveSearchExtras(AssistantPlayRequest request) {
    if (request.term.isEmpty) {
      return Future<AssistantResolution>.value(
        AssistantResolutionFailure(AssistantStrings.nothingMatched('')),
      );
    }
    return _guard(
      'extras:${request.field.name}',
      () => _resolveExtra(request),
    );
  }

  /// Resolves a request parsed from natural-language text.
  Future<AssistantResolution> resolveText(AssistantTextIntent intent) {
    if (intent.kind != AssistantIntentKind.resumeLastAlbum &&
        intent.kind != AssistantIntentKind.shuffleFavorites &&
        intent.term.isEmpty) {
      return Future<AssistantResolution>.value(
        AssistantResolutionFailure(AssistantStrings.nothingMatched('')),
      );
    }
    return _guard('text:${intent.kind.name}', () => _resolveIntent(intent));
  }

  /// Resolves the favourite tracks, shuffled when [shuffle] is true.
  Future<AssistantResolution> resolveFavorites({bool shuffle = false}) =>
      _guard('favorites', () => _favorites(shuffle: shuffle));

  /// Resolves the most recently played album.
  Future<AssistantResolution> resolveLastAlbum() =>
      _guard('lastAlbum', _lastAlbum);

  Future<AssistantResolution> _resolveExtra(AssistantPlayRequest request) {
    if (request.field == AssistantExtraField.playlist) {
      return _playlistOrSearch(
        term: request.term,
        display: request.display,
        shuffle: false,
      );
    }
    return _search(
      term: request.term,
      display: request.display,
      source: _sourceFor(request.field),
    );
  }

  Future<AssistantResolution> _resolveIntent(AssistantTextIntent intent) {
    switch (intent.kind) {
      case AssistantIntentKind.playPlaylist:
        return _playlistOrSearch(
          term: intent.term,
          display: intent.display,
          shuffle: intent.wantsShuffle,
        );
      case AssistantIntentKind.resumeLastAlbum:
        return _lastAlbum();
      case AssistantIntentKind.shuffleFavorites:
        return _favorites(shuffle: true);
      case AssistantIntentKind.playArtistRadio:
        return _search(
          term: intent.term,
          display: intent.display,
          source: AssistantPlanSource.artistRadio,
          shuffle: true,
          radio: true,
        );
      case AssistantIntentKind.searchSongs:
        return _search(
          term: intent.term,
          display: intent.display,
          source: AssistantPlanSource.search,
        );
    }
  }

  /// A spoken "play &lt;words&gt;" is often not a playlist name, so an empty
  /// playlist result falls back to a free-text song search before failing.
  Future<AssistantResolution> _playlistOrSearch({
    required String term,
    required String display,
    required bool shuffle,
  }) async {
    final playlistIds = await _playlistSongIds(term);
    if (playlistIds.isNotEmpty) {
      return AssistantPlayPlan(
        songIds: playlistIds,
        title: display,
        source: AssistantPlanSource.playlist,
        shuffle: shuffle,
      );
    }
    final songIds = await _searchSongIds(term);
    if (songIds.isNotEmpty) {
      return AssistantPlayPlan(
        songIds: songIds,
        title: display,
        source: AssistantPlanSource.search,
        shuffle: shuffle,
      );
    }
    return AssistantResolutionFailure(AssistantStrings.nothingMatched(display));
  }

  Future<AssistantResolution> _search({
    required String term,
    required String display,
    required AssistantPlanSource source,
    bool shuffle = false,
    bool radio = false,
  }) async {
    final songIds = await _searchSongIds(term);
    if (songIds.isEmpty) {
      return AssistantResolutionFailure(
        AssistantStrings.nothingMatched(display),
      );
    }
    return AssistantPlayPlan(
      songIds: songIds,
      title:
          radio ? AssistantStrings.artistRadioTitle(display) : display,
      source: source,
      shuffle: shuffle,
    );
  }

  Future<AssistantResolution> _favorites({required bool shuffle}) async {
    final songIds = await _favoritesSongIds();
    if (songIds.isEmpty) {
      return AssistantResolutionFailure(AssistantStrings.noFavorites);
    }
    return AssistantPlayPlan(
      songIds: songIds,
      title: AssistantStrings.favoritesTitle,
      source: AssistantPlanSource.favorites,
      shuffle: shuffle,
    );
  }

  Future<AssistantResolution> _lastAlbum() async {
    final songIds = await _lastAlbumSongIds();
    if (songIds.isEmpty) {
      return AssistantResolutionFailure(AssistantStrings.noLastAlbum);
    }
    return AssistantPlayPlan(
      songIds: songIds,
      title: AssistantStrings.lastAlbumTitle,
      source: AssistantPlanSource.lastAlbum,
    );
  }

  /// Runs [body] and converts anything it throws into a failure, so callers
  /// never need their own try/catch.
  Future<AssistantResolution> _guard(
    String what,
    Future<AssistantResolution> Function() body,
  ) async {
    try {
      return await body();
    } catch (e, st) {
      ErrorLogger.log(
        'Assistant resolution failed for $what',
        error: e,
        stackTrace: st,
        category: 'Assistant',
      );
      return AssistantResolutionFailure(
        AssistantStrings.libraryUnavailable,
      );
    }
  }

  AssistantPlanSource _sourceFor(AssistantExtraField field) => switch (field) {
        AssistantExtraField.playlist => AssistantPlanSource.playlist,
        AssistantExtraField.album => AssistantPlanSource.album,
        AssistantExtraField.artist => AssistantPlanSource.artist,
        AssistantExtraField.genre => AssistantPlanSource.genre,
        AssistantExtraField.song => AssistantPlanSource.song,
        AssistantExtraField.title => AssistantPlanSource.title,
        AssistantExtraField.query => AssistantPlanSource.search,
      };
}
