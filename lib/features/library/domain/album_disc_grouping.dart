// lib/features/library/domain/album_disc_grouping.dart

/// A track projected into the shape disc grouping needs.
///
/// [track] keeps the caller's original record (for example a
/// `SongsTableData`), so a grouped disc can be rendered without a second
/// lookup by id.
class AlbumDiscTrack<T> {
  const AlbumDiscTrack({
    required this.track,
    required this.id,
    required this.title,
    this.discNumber,
    this.trackNumber,
  });

  /// The caller's original record.
  final T track;

  /// Stable identity, used as the final ordering tie-breaker.
  final String id;

  /// Display title, used to order tracks that share a track number.
  final String title;

  /// Raw disc number; null or <= 0 means unnumbered.
  final int? discNumber;

  /// Raw track number; null sorts after numbered tracks.
  final int? trackNumber;
}

/// One disc of an album with its tracks in playback order.
class AlbumDiscGroup<T> {
  const AlbumDiscGroup({
    required this.discNumber,
    required this.label,
    required this.tracks,
  });

  /// Normalized disc number, or null for the trailing `Unnumbered` group.
  final int? discNumber;

  /// Display label: `Disc <n>` for numbered groups, `Unnumbered` otherwise.
  final String label;

  /// Original records, ordered by track number then title.
  final List<T> tracks;

  bool get isUnnumbered => discNumber == null;
}

extension AlbumDiscGroupList<T> on List<AlbumDiscGroup<T>> {
  /// Whether disc headers should be shown. A single group - including an
  /// album whose tracks carry no disc numbers at all - is a single-disc album.
  bool get isMultiDisc => length > 1;
}

/// Splits [tracks] into album disc groups.
///
/// Rules:
/// * A null (or <= 0) disc number is unnumbered.
/// * All-unnumbered input yields a single group, so no headers are shown.
/// * Unnumbered tracks join disc 1 when disc 1 has no explicit tracks;
///   otherwise they form a trailing `Unnumbered` group.
/// * Groups are ordered by disc number; tracks by track number (nulls last),
///   then case-insensitive title, then id. Ties keep input order and the
///   input list is never mutated.
List<AlbumDiscGroup<T>> groupAlbumDiscs<T>(
  Iterable<AlbumDiscTrack<T>> tracks,
) {
  final numbered = <int, List<AlbumDiscTrack<T>>>{};
  final unnumbered = <AlbumDiscTrack<T>>[];
  for (final track in tracks) {
    final disc = track.discNumber;
    if (disc == null || disc <= 0) {
      unnumbered.add(track);
    } else {
      (numbered[disc] ??= <AlbumDiscTrack<T>>[]).add(track);
    }
  }

  final discNumbers = numbered.keys.toList()..sort();
  final mergeIntoDiscOne =
      unnumbered.isNotEmpty && numbered.isNotEmpty && !numbered.containsKey(1);
  final groups = <AlbumDiscGroup<T>>[];

  // Disc 1 exists only implicitly when unnumbered tracks are folded into it.
  if (mergeIntoDiscOne) {
    groups.add(_buildGroup(1, List<AlbumDiscTrack<T>>.of(unnumbered)));
  }

  for (final disc in discNumbers) {
    groups.add(_buildGroup(disc, List<AlbumDiscTrack<T>>.of(numbered[disc]!)));
  }

  if (unnumbered.isNotEmpty && !mergeIntoDiscOne) {
    // Disc 1 has explicit tracks, so unnumbered ones cannot be folded into it.
    groups.add(_buildGroup(null, List<AlbumDiscTrack<T>>.of(unnumbered)));
  } else if (groups.isEmpty && unnumbered.isNotEmpty) {
    // No numbered tracks at all: a single unnumbered group.
    groups.add(_buildGroup(null, List<AlbumDiscTrack<T>>.of(unnumbered)));
  }

  return List<AlbumDiscGroup<T>>.unmodifiable(groups);
}

AlbumDiscGroup<T> _buildGroup<T>(
  int? discNumber,
  List<AlbumDiscTrack<T>> members,
) {
  // Pair each track with its input index so equal keys keep input order
  // (`List.sort` is not stable on its own).
  final indexed = [
    for (var i = 0; i < members.length; i++) (index: i, entry: members[i]),
  ];
  indexed.sort((a, b) {
    final byTrack = _compareForPlayback(a.entry, b.entry);
    return byTrack != 0 ? byTrack : a.index.compareTo(b.index);
  });

  return AlbumDiscGroup<T>(
    discNumber: discNumber,
    label: discNumber == null ? 'Unnumbered' : 'Disc $discNumber',
    tracks: List<T>.unmodifiable(indexed.map((item) => item.entry.track)),
  );
}

int _compareForPlayback<T>(AlbumDiscTrack<T> a, AlbumDiscTrack<T> b) {
  final aTrack = a.trackNumber;
  final bTrack = b.trackNumber;
  if (aTrack != bTrack) {
    if (aTrack == null) return 1;
    if (bTrack == null) return -1;
    return aTrack.compareTo(bTrack);
  }

  final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  if (byTitle != 0) return byTitle;
  return a.id.compareTo(b.id);
}
