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

  /// MP3 (LAME): 576-sample encoder delay (@44.1kHz ~13.06ms).
  static const Duration mp3EncoderDelay = Duration(microseconds: 13061);
  /// MP3 (LAME): 529-sample encoder padding (@44.1kHz ~11.99ms).
  static const Duration mp3EncoderPadding = Duration(microseconds: 11995);
  /// AAC/iTunes gapless priming: 2048-sample encoder delay + 64 lead-in
  /// (@44.1kHz ~47.9ms).
  static const Duration aacEncoderDelay = Duration(microseconds: 47873);

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
    final isOpus = c.contains('opus') ||
        lower.endsWith('.opus') ||
        (lower.endsWith('.ogg') && (c.isEmpty || c.contains('opus') || lower.contains('opus')));
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
    final isMp3 = c.contains('mp3') || lower.endsWith('.mp3');
    if (isMp3) {
      return const GaplessTrim(
        preSkip: mp3EncoderDelay,
        postTrim: mp3EncoderPadding,
      );
    }
    final isAac = c.contains('aac') ||
        c.contains('mp4a') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.m4b');
    if (isAac) {
      return const GaplessTrim(preSkip: aacEncoderDelay);
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
