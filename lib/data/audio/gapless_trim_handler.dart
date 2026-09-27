import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

  static final Map<String, GaplessTrim> _headerTrimCache = {};

  /// Reads actual header-derived gapless metadata (LAME Xing header or M4A iTunSMPB).
  static Future<GaplessTrim?> readHeaderGaplessTrim(String filePath, {int sampleRate = 44100}) async {
    if (_headerTrimCache.containsKey(filePath)) {
      return _headerTrimCache[filePath];
    }
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final lower = filePath.toLowerCase();
      GaplessTrim? trim;
      if (lower.endsWith('.mp3')) {
        trim = await _readMp3LameGapless(file, sampleRate);
      } else if (lower.endsWith('.m4a') || lower.endsWith('.mp4') || lower.endsWith('.aac')) {
        trim = await _readM4aItunSmpb(file, sampleRate);
      }
      if (trim != null) {
        _headerTrimCache[filePath] = trim;
      }
      return trim;
    } catch (_) {}
    return null;
  }

  static Future<GaplessTrim?> _readMp3LameGapless(File file, int sampleRate) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final bytes = await raf.read(8192);
      final len = bytes.length;
      if (len < 64) return null;

      // Scan for 'Xing' or 'Info'
      for (int i = 0; i <= len - 32; i++) {
        final isXing = bytes[i] == 0x58 && bytes[i + 1] == 0x69 && bytes[i + 2] == 0x6E && bytes[i + 3] == 0x67;
        final isInfo = bytes[i] == 0x49 && bytes[i + 1] == 0x6E && bytes[i + 2] == 0x66 && bytes[i + 3] == 0x6F;
        if (isXing || isInfo) {
          final flags = (bytes[i + 4] << 24) | (bytes[i + 5] << 16) | (bytes[i + 6] << 8) | bytes[i + 7];
          var offset = 8;
          if ((flags & 0x01) != 0) offset += 4; // frames
          if ((flags & 0x02) != 0) offset += 4; // bytes
          if ((flags & 0x04) != 0) offset += 100; // TOC
          if ((flags & 0x08) != 0) offset += 4; // vbr scale

          final lameStart = i + offset;
          if (lameStart + 24 <= len) {
            // Check 'LAME' tag
            final isLame = bytes[lameStart] == 0x4C &&
                bytes[lameStart + 1] == 0x41 &&
                bytes[lameStart + 2] == 0x4D &&
                bytes[lameStart + 3] == 0x45;
            if (isLame) {
              final b0 = bytes[lameStart + 21];
              final b1 = bytes[lameStart + 22];
              final b2 = bytes[lameStart + 23];
              final delaySamples = (b0 << 4) | (b1 >> 4);
              final paddingSamples = ((b1 & 0x0F) << 8) | b2;
              if (delaySamples > 0 || paddingSamples > 0) {
                final preSkipUs = ((delaySamples * 1000000) / sampleRate).round();
                final postTrimUs = ((paddingSamples * 1000000) / sampleRate).round();
                return GaplessTrim(
                  preSkip: Duration(microseconds: preSkipUs),
                  postTrim: Duration(microseconds: postTrimUs),
                );
              }
            }
          }
        }
      }
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
    return null;
  }

  static Future<GaplessTrim?> _readM4aItunSmpb(File file, int sampleRate) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final bytes = await raf.read(65536);
      final text = latin1.decode(bytes);
      final idx = text.indexOf('iTunSMPB');
      if (idx != -1) {
        final window = text.substring(idx, math.min(text.length, idx + 256));
        final match = RegExp(r'00000000\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)').firstMatch(window);
        if (match != null) {
          final delaySamples = int.tryParse(match.group(1)!, radix: 16) ?? 0;
          final paddingSamples = int.tryParse(match.group(2)!, radix: 16) ?? 0;
          if (delaySamples > 0 || paddingSamples > 0) {
            final preSkipUs = ((delaySamples * 1000000) / sampleRate).round();
            final postTrimUs = ((paddingSamples * 1000000) / sampleRate).round();
            return GaplessTrim(
              preSkip: Duration(microseconds: preSkipUs),
              postTrim: Duration(microseconds: postTrimUs),
            );
          }
        }
      }
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
    return null;
  }

  /// Synchronously inspects local audio file header for LAME Xing / M4A iTunSMPB atoms.
  static GaplessTrim? readHeaderGaplessTrimSync(String filePath, {int sampleRate = 44100}) {
    if (_headerTrimCache.containsKey(filePath)) {
      return _headerTrimCache[filePath];
    }
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final lower = filePath.toLowerCase();
      if (lower.endsWith('.mp3')) {
        final raf = file.openSync(mode: FileMode.read);
        try {
          final bytes = raf.readSync(8192);
          final len = bytes.length;
          if (len >= 64) {
            for (int i = 0; i <= len - 32; i++) {
              final isXing = bytes[i] == 0x58 && bytes[i + 1] == 0x69 && bytes[i + 2] == 0x6E && bytes[i + 3] == 0x67;
              final isInfo = bytes[i] == 0x49 && bytes[i + 1] == 0x6E && bytes[i + 2] == 0x66 && bytes[i + 3] == 0x6F;
              if (isXing || isInfo) {
                final flags = (bytes[i + 4] << 24) | (bytes[i + 5] << 16) | (bytes[i + 6] << 8) | bytes[i + 7];
                var offset = 8;
                if ((flags & 0x01) != 0) offset += 4;
                if ((flags & 0x02) != 0) offset += 4;
                if ((flags & 0x04) != 0) offset += 100;
                if ((flags & 0x08) != 0) offset += 4;
                final lameStart = i + offset;
                if (lameStart + 24 <= len) {
                  final isLame = bytes[lameStart] == 0x4C &&
                      bytes[lameStart + 1] == 0x41 &&
                      bytes[lameStart + 2] == 0x4D &&
                      bytes[lameStart + 3] == 0x45;
                  if (isLame) {
                    final b0 = bytes[lameStart + 21];
                    final b1 = bytes[lameStart + 22];
                    final b2 = bytes[lameStart + 23];
                    final delaySamples = (b0 << 4) | (b1 >> 4);
                    final paddingSamples = ((b1 & 0x0F) << 8) | b2;
                    if (delaySamples > 0 || paddingSamples > 0) {
                      final preSkipUs = ((delaySamples * 1000000) / sampleRate).round();
                      final postTrimUs = ((paddingSamples * 1000000) / sampleRate).round();
                      final trim = GaplessTrim(
                        preSkip: Duration(microseconds: preSkipUs),
                        postTrim: Duration(microseconds: postTrimUs),
                      );
                      _headerTrimCache[filePath] = trim;
                      return trim;
                    }
                  }
                }
              }
            }
          }
        } finally {
          raf.closeSync();
        }
      } else if (lower.endsWith('.m4a') || lower.endsWith('.mp4') || lower.endsWith('.aac')) {
        final raf = file.openSync(mode: FileMode.read);
        try {
          final bytes = raf.readSync(65536);
          final text = latin1.decode(bytes);
          final idx = text.indexOf('iTunSMPB');
          if (idx != -1) {
            final window = text.substring(idx, math.min(text.length, idx + 256));
            final match = RegExp(r'00000000\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)').firstMatch(window);
            if (match != null) {
              final delaySamples = int.tryParse(match.group(1)!, radix: 16) ?? 0;
              final paddingSamples = int.tryParse(match.group(2)!, radix: 16) ?? 0;
              if (delaySamples > 0 || paddingSamples > 0) {
                final preSkipUs = ((delaySamples * 1000000) / sampleRate).round();
                final postTrimUs = ((paddingSamples * 1000000) / sampleRate).round();
                final trim = GaplessTrim(
                  preSkip: Duration(microseconds: preSkipUs),
                  postTrim: Duration(microseconds: postTrimUs),
                );
                _headerTrimCache[filePath] = trim;
                return trim;
              }
            }
          }
        } finally {
          raf.closeSync();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Detects container/codec from a file path and returns the trim.
  /// [preSkipOverrideMs]/[postTrimOverrideMs] come from parsed headers
  /// (OpusHead pre-skip, granule end-trim) when available.
  static GaplessTrim trimFor({
    required String path,
    String? codec,
    int? preSkipOverrideMs,
    int? postTrimOverrideMs,
  }) {
    if (preSkipOverrideMs != null || postTrimOverrideMs != null) {
      return GaplessTrim(
        preSkip: Duration(milliseconds: (preSkipOverrideMs ?? 0).clamp(0, 5000)),
        postTrim: Duration(milliseconds: (postTrimOverrideMs ?? 0).clamp(0, 5000)),
      );
    }
    final headerTrim = readHeaderGaplessTrimSync(path);
    if (headerTrim != null) {
      return headerTrim;
    }
    final lower = path.toLowerCase();
    final c = (codec ?? '').toLowerCase();
    final isOpus = c.contains('opus') ||
        lower.endsWith('.opus') ||
        (lower.endsWith('.ogg') && (c.isEmpty || c.contains('opus') || lower.contains('opus')));
    final isOgg = lower.endsWith('.ogg') || lower.endsWith('.oga');
    final isVorbis = c.contains('vorbis') || (isOgg && !isOpus);
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

/// Monitors track transitions for gapless continuity and logs position glitches.
class GaplessTransitionMonitor {
  int _gapEventCount = 0;
  int get gapEventCount => _gapEventCount;

  Duration _lastPosition = Duration.zero;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<Duration>? _positionSub;

  void onTrackTransition(int? index) {
    _lastPosition = Duration.zero;
  }

  void onPositionUpdate(Duration pos) {
    if (_lastPosition > const Duration(milliseconds: 5) &&
        pos < _lastPosition - const Duration(milliseconds: 5) &&
        pos > Duration.zero) {
      _gapEventCount++;
    }
    _lastPosition = pos;
  }

  void attach({
    required Stream<int?> currentIndexStream,
    required Stream<Duration> positionStream,
  }) {
    dispose();
    _indexSub = currentIndexStream.listen(onTrackTransition);
    _positionSub = positionStream.listen(onPositionUpdate);
  }

  void reset() {
    _gapEventCount = 0;
    _lastPosition = Duration.zero;
  }

  void dispose() {
    _indexSub?.cancel();
    _indexSub = null;
    _positionSub?.cancel();
    _positionSub = null;
  }
}
