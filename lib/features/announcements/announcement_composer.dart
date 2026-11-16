// lib/features/announcements/announcement_composer.dart

/// Pure announcement-text composition.
///
/// This file deliberately imports nothing from Flutter so the wording rules
/// (element order, missing-field handling, truncation) can be unit-tested
/// without a binding, a platform channel or a device.
library;

/// One piece of metadata an announcement can read aloud.
///
/// The enum name is the value persisted in preferences, so renaming a value
/// changes the stored format; `AnnouncementSettings` tolerates unknown names
/// from older builds instead of crashing on them.
enum AnnouncementElement {
  /// The track title.
  title,

  /// The track artist, skipped when it duplicates the title.
  artist,

  /// The album name.
  album,

  /// The release year, spoken as `from 1999`.
  year,

  /// The track position, spoken as `track 4`.
  trackNumber,
}

/// Default maximum announcement length, in characters.
///
/// Lives here (not in the settings file) so the composer stays free of the
/// Flutter-dependent settings class.
const int kDefaultAnnouncementMaxLength = 160;

/// The metadata an announcement is composed from.
///
/// A plain value object: the announcer maps audio_service `MediaItem`s onto it,
/// and tests build it directly.
class AnnouncementTrack {
  /// Creates an announcement source track.
  const AnnouncementTrack({
    required this.title,
    required this.artist,
    this.album,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.duration,
  });

  /// Track title. Empty when the file carries no title tag.
  final String title;

  /// Track artist. Empty when the file carries no artist tag.
  final String artist;

  /// Album name, or `null` when unknown.
  final String? album;

  /// Release year, or `null` when unknown.
  final int? year;

  /// One-based position inside [discNumber], or `null` when unknown.
  final int? trackNumber;

  /// One-based disc number, retained for multi-disc announcements.
  final int? discNumber;

  /// Track duration, retained for callers that gate on track length.
  final Duration? duration;
}

/// Joins the requested [elements] of [track] into one spoken sentence.
///
/// Parts appear in the order given by [elements], separated by `, `.
/// Empty parts are dropped, `artist` is dropped when it duplicates the title
/// (case-insensitive), and `year` / `trackNumber` are dropped when unknown.
/// The result is truncated to [maxLength] characters on a word boundary and
/// marked with an ellipsis when it does not fit.
String composeAnnouncement(
  List<AnnouncementElement> elements,
  AnnouncementTrack track, {
  int maxLength = kDefaultAnnouncementMaxLength,
}) {
  final title = track.title.trim();
  final parts = <String>[];
  for (final element in elements) {
    final part = _partFor(element, track, title);
    if (part != null) parts.add(part);
  }
  return truncateOnWordBoundary(parts.join(', '), maxLength);
}

/// Cuts [text] to at most [maxLength] characters without splitting a word.
///
/// A single word longer than the limit is hard-cut, because a partially spoken
/// word is worse than a short one. Returns [text] unchanged when it already
/// fits.
String truncateOnWordBoundary(String text, int maxLength) {
  if (maxLength <= 0) return '';
  if (text.length <= maxLength) return text;
  // Reserve one character for the ellipsis so the result never exceeds the
  // caller's budget.
  final limit = maxLength - 1;
  if (limit <= 0) return text.substring(0, maxLength);
  final window = text.substring(0, limit);
  final lastSpace = window.lastIndexOf(' ');
  var cut = lastSpace > 0 ? lastSpace : limit;
  while (cut > 0 && _isSeparator(window.codeUnitAt(cut - 1))) {
    cut--;
  }
  if (cut <= 0) cut = limit;
  return '${text.substring(0, cut)}…';
}

String? _partFor(
  AnnouncementElement element,
  AnnouncementTrack track,
  String title,
) {
  switch (element) {
    case AnnouncementElement.title:
      return title.isEmpty ? null : title;
    case AnnouncementElement.artist:
      final artist = track.artist.trim();
      if (artist.isEmpty) return null;
      if (title.isNotEmpty && artist.toLowerCase() == title.toLowerCase()) {
        return null;
      }
      return artist;
    case AnnouncementElement.album:
      final album = track.album?.trim();
      if (album == null || album.isEmpty) return null;
      return album;
    case AnnouncementElement.year:
      final year = track.year;
      return year == null ? null : 'from $year';
    case AnnouncementElement.trackNumber:
      final trackNumber = track.trackNumber;
      return trackNumber == null ? null : 'track $trackNumber';
  }
}

bool _isSeparator(int codeUnit) =>
    codeUnit == 0x20 || codeUnit == 0x2C || codeUnit == 0x2D;
