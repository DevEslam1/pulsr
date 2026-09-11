library;

/// Trim to apply at the head/tail of a track for seamless joins.
/// F6: OGG/Opus pre-skip (312 samples at 48kHz) and end-trim handling.
class GaplessTrim {
  final Duration preSkip;
  final Duration postTrim;
  const GaplessTrim({this.preSkip = Duration.zero, this.postTrim = Duration.zero});

  bool get isEmpty => preSkip == Duration.zero && postTrim == Duration.zero;
  Duration get total => preSkip + postTrim;

  /// Clamp so the trim never eats the whole track.
  GaplessTrim clampedTo(Duration trackDuration) {
    if (trackDuration <= Duration.zero || isEmpty) return this;
    final maxTrimMs = (trackDuration.inMilliseconds * 0.2).round();
    var pre = preSkip;
    var post = postTrim;
    if (total.inMilliseconds > maxTrimMs) {
      final scale = maxTrimMs / total.inMilliseconds;
      pre = Duration(milliseconds: (pre.inMilliseconds * scale).round());
      post = Duration(milliseconds: (post.inMilliseconds * scale).round());
    }
    return GaplessTrim(preSkip: pre, postTrim: post);
  }
}

class GaplessTrimHandler {
  /// Opus encoder delay: 312 samples @ 48kHz.
  static const Duration opusPreSkip = Duration(microseconds: 6500);

  /// Detects container/codec from a file path and returns the trim.
  /// [preSkipOverrideMs]/[postTrimOverrideMs] come from parsed headers
  /// (OpusHead pre-skip, granule end-trim) when available.
  static GaplessTrim trimFor({
    required String path,
    String? codec,
    int? preSkipOverrideMs,
    int? postTrimOverrideMs,
  }) {
    final lower = path.toLowerCase();
    final c = (codec ?? '').toLowerCase();
    final isOpus = c.contains('opus') || lower.endsWith('.opus') || lower.endsWith('.ogg') && c.isEmpty && lower.contains('opus');
    final isOgg = lower.endsWith('.ogg') || lower.endsWith('.oga');
    final isVorbis = c.contains('vorbis') || (isOgg && !isOpus);

    if (preSkipOverrideMs != null || postTrimOverrideMs != null) {
      return GaplessTrim(
        preSkip: Duration(milliseconds: (preSkipOverrideMs ?? 0).clamp(0, 5000)),
        postTrim: Duration(milliseconds: (postTrimOverrideMs ?? 0).clamp(0, 5000)),
      );
    }
    if (isOpus) {
      return const GaplessTrim(preSkip: opusPreSkip);
    }
    if (isVorbis) {
      // Vorbis codec delay: ~2 short blocks (~512 samples @44.1k ≈ 11.6ms).
      return const GaplessTrim(
          preSkip: Duration(microseconds: 11600));
    }
    return const GaplessTrim();
  }

  /// Start offset to seek to when joining into this track.
  static Duration startOffset(GaplessTrim trim) => trim.preSkip;

  /// Effective end position (track end minus post-trim) for crossfade math.
  static Duration effectiveEnd(Duration trackDuration, GaplessTrim trim) {
    final end = trackDuration - trim.postTrim;
    return end.isNegative ? Duration.zero : end;
  }
}
