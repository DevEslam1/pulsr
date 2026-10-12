// lib/services/canvas/canvas_artwork.dart
import '../../core/utils/search_algorithm_utils.dart';

/// Represents a Spotify Canvas, Apple Music motion artwork, or Tidal video cover.
class CanvasArtwork {
  final String videoUrl;
  final String? fallbackUrl;
  final String? localFilePath;
  final String? title;
  final String? artist;
  final String? album;
  final String source;

  const CanvasArtwork({
    required this.videoUrl,
    this.fallbackUrl,
    this.localFilePath,
    this.title,
    this.artist,
    this.album,
    this.source = 'unknown',
  });

  CanvasArtwork copyWith({
    String? videoUrl,
    String? fallbackUrl,
    String? localFilePath,
    String? title,
    String? artist,
    String? album,
    String? source,
  }) {
    return CanvasArtwork(
      videoUrl: videoUrl ?? this.videoUrl,
      fallbackUrl: fallbackUrl ?? this.fallbackUrl,
      localFilePath: localFilePath ?? this.localFilePath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      source: source ?? this.source,
    );
  }

  /// Whether this artwork genuinely matches the target track metadata.
  bool matches(String wantTitle, String wantArtist, String? wantAlbum) {
    final cleanWantTitle = cleanNoise(wantTitle);
    final normWantTitle = normalizeForMatch(cleanWantTitle);
    final ourTitle = title != null ? normalizeForMatch(cleanNoise(title!)) : null;

    final titleOk = ourTitle == null ||
        normWantTitle.isEmpty ||
        ourTitle == normWantTitle ||
        ourTitle.contains(normWantTitle) ||
        normWantTitle.contains(ourTitle);

    final titleArtists = splitArtists(wantArtist);
    final ourArtists = splitArtists(artist ?? '');
    final artistOk = artist == null ||
        wantArtist.trim().isEmpty ||
        (titleArtists.isNotEmpty &&
            ourArtists.isNotEmpty &&
            titleArtists.any((want) =>
                ourArtists.any((our) => our == want || our.contains(want) || want.contains(our))));

    final albumOk = album == null ||
        album!.trim().isEmpty ||
        wantAlbum == null ||
        wantAlbum.trim().isEmpty ||
        normalizeForMatch(album!) == normalizeForMatch(wantAlbum);

    return titleOk && artistOk && albumOk;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasArtwork &&
          runtimeType == other.runtimeType &&
          videoUrl == other.videoUrl &&
          localFilePath == other.localFilePath &&
          title == other.title &&
          artist == other.artist &&
          album == other.album &&
          source == other.source;

  @override
  int get hashCode =>
      videoUrl.hashCode ^
      localFilePath.hashCode ^
      title.hashCode ^
      artist.hashCode ^
      album.hashCode ^
      source.hashCode;

  @override
  String toString() =>
      'CanvasArtwork(source: $source, title: $title, artist: $artist, url: $videoUrl, local: $localFilePath)';
}

/// Normalizes text by removing diacritics, lowercase folding, and collapsing punctuation.
String normalizeForMatch(String s) {
  var str = SearchAlgorithmUtils.normalize(s);
  str = str.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  str = str.replaceAll(RegExp(r'\s+'), ' ');
  return str.trim();
}

/// Strips common video/remaster noise from song titles (matching BitChord).
String cleanNoise(String title) {
  final noise = RegExp(
    r'\((?:from|official|lyrical|video|audio)[^)]*\)|\[[^\]]*\]|\b(?:official (?:video|audio|music video)|lyrical|full song|4k video)\b',
    caseSensitive: false,
  );
  var res = title.replaceAll(noise, ' ');
  if (res.contains(' | ')) {
    res = res.substring(0, res.indexOf(' | '));
  }
  res = res.replaceAll(RegExp(r'\s+'), ' ').trim();
  return res.isEmpty ? title : res;
}

/// Splits credited artist string by commas, &, feat, ft, x, with.
List<String> splitArtists(String raw) {
  final separator = RegExp(
    r'(?:\s*,\s*|\s*&\s*|\s+×\s+|\s+x\s+|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bwith\b)',
    caseSensitive: false,
  );
  return raw
      .split(separator)
      .map((s) => normalizeForMatch(s))
      .where((s) => s.isNotEmpty)
      .toList();
}
