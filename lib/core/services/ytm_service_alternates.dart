// lib/core/services/ytm_service_alternates.dart
//
// Split out of ytm_service.dart: substitute-upload recovery and the
// recording-identity checks it depends on. This is a file split, not a new
// abstraction boundary — the extension lives in the same library, so it
// still reaches the service's private alternate-id map, clock and search
// entry point.
part of 'ytm_service.dart';

/// Recovers a track by resolving a different upload of the same recording.
extension YtmServiceAlternates on YtmService {
  Future<YtmStream?> resolveAlternateStream(
    String title,
    String? artist, {
    String? originalVideoId,
    String quality = 'high',
    bool preferM4a = false,
    Duration? expectedDuration,
  }) async {
    final cleanTitle = title
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleanTitle.isEmpty) return null;

    final cleanArtist = (artist ?? '')
        .replaceAll(RegExp(r'- Topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // A route that is already refusing us cannot resolve a substitute either.
    // Searching through it only adds request volume to a challenged egress —
    // the mechanism that turns one blocked track into a queue-wide cooldown.
    if (isBotCoolingDown) {
      debugPrint(
          '[YTM_SERVICE] Skipping alternate search for "$title": egress is cooling down');
      return null;
    }

    // 1. Check if we already found and cached a working alternate ID for this video
    if (originalVideoId != null && originalVideoId.isNotEmpty) {
      final cachedAltId = _alternateVideoIds[originalVideoId];
      if (cachedAltId != null && cachedAltId != originalVideoId) {
        try {
          final stream = await resolveStream(
            cachedAltId,
            quality: quality,
            preferM4a: preferM4a,
            allowAlternateFallback: false,
          );
          if (stream.url.trim().isNotEmpty &&
              _durationMatches(expectedDuration, stream.duration)) {
            return stream;
          }
          // The remembered substitute no longer matches the track (a different
          // upload took the id, or the durations never lined up): drop it and
          // search afresh instead of serving the wrong recording again.
          _alternateVideoIds.remove(originalVideoId);
        } catch (_) {
          _alternateVideoIds.remove(originalVideoId);
        }
      }
    }

    // 2. Build search queries
    final queryList = <String>[
      if (cleanArtist.isNotEmpty) '$cleanArtist $cleanTitle' else cleanTitle,
      if (cleanArtist.isNotEmpty)
        '$cleanArtist $cleanTitle audio'
      else
        '$cleanTitle audio',
      if (cleanArtist.isNotEmpty) '$cleanArtist $title' else title,
    ];

    final testedIds = <String>{
      if (originalVideoId != null && originalVideoId.isNotEmpty)
        originalVideoId,
    };

    // Bound the whole substitute search. Queries × candidates × a full
    // multi-tier resolve each is not a budget, it is a hang; once the deadline
    // or the attempt cap is reached the caller surfaces the original,
    // actionable failure instead of stalling the queue — and instead of adding
    // request volume to a route that may already be refusing us.
    final deadline = _now().add(const Duration(seconds: 12));
    bool outOfBudget() => _now().isAfter(deadline);
    var resolveAttempts = 0;

    for (final q in queryList) {
      if (outOfBudget() || isBotCoolingDown) break;
      try {
        final tracks = await searchWithFallback(q, limit: 4);
        for (final cand in tracks) {
          if (outOfBudget() || isBotCoolingDown || resolveAttempts >= 4) break;
          final candId = cand.videoId;
          if (candId.isEmpty || testedIds.contains(candId)) continue;
          testedIds.add(candId);

          // Cheap rejection before spending a resolve: a hit whose length does
          // not match the track we failed to play is a different recording
          // (live take, extended mix, loop), not a mirror of the same upload.
          if (!_durationMatches(expectedDuration, cand.duration)) {
            debugPrint(
                '[YTM_SERVICE] Skipping alternate "$candId" (${cand.title}) — duration ${cand.duration.inSeconds}s does not match the requested track');
            continue;
          }
          // Reject on the search metadata before spending a resolve: a hit
          // with a different title or artist will not become the right
          // recording by being fetched.
          if (!_metadataMatches(
            requestedTitle: title,
            requestedArtist: artist,
            candidateTitle: cand.title,
            candidateArtist: cand.artist,
          )) {
            debugPrint(
                '[YTM_SERVICE] Skipping alternate "$candId" (${cand.title}) — different title/artist');
            continue;
          }

          resolveAttempts++;
          try {
            final stream = await resolveStream(
              candId,
              quality: quality,
              preferM4a: preferM4a,
              allowAlternateFallback: false,
            );
            if (stream.url.trim().isNotEmpty) {
              if (!_isSameRecording(
                requestedTitle: title,
                requestedArtist: artist,
                candidate: cand,
                stream: stream,
                expectedDuration: expectedDuration,
              )) {
                debugPrint(
                    '[YTM_SERVICE] Rejected alternate "$candId" (${cand.title}) — resolved stream is a different recording');
                continue;
              }
              if (originalVideoId != null && originalVideoId.isNotEmpty) {
                _capMap(_alternateVideoIds, originalVideoId, candId);
                final urlCache = getIt.isRegistered<YtmUrlCache>()
                    ? getIt<YtmUrlCache>()
                    : null;
                final cacheQuality =
                    YtmUrlCache.qualitySlot(quality, preferM4a: preferM4a);
                urlCache?.putStream(stream, quality: cacheQuality);
              }
              debugPrint(
                  '[YTM_SERVICE] Alternate track resolved: "$originalVideoId" -> "$candId" (${cand.title})');
              return stream;
            }
          } catch (_) {
            continue;
          }
        }
      } catch (e) {
        debugPrint('[YTM_SERVICE] Alternate track search failed for "$q": $e');
      }
    }
    return null;
  }
}

/// Tolerance for "same recording" duration comparisons.
///
/// YouTube reports rounded lengths and a re-upload can differ by a second or
/// two of leading silence without being a different take, so an exact match
/// would reject valid mirrors.
const Duration _sameRecordingTolerance = Duration(seconds: 5);

/// Whether [candidate]'s length is compatible with [expected].
///
/// Unknown on either side answers true: a missing duration is not evidence of
/// a mismatch, and the search query already carries title and artist.
bool _durationMatches(Duration? expected, Duration candidate) {
  if (expected == null || expected <= Duration.zero) return true;
  if (candidate <= Duration.zero) return true;
  return (expected - candidate).abs() <= _sameRecordingTolerance;
}

/// Whether a resolved substitute is plausibly the track that was asked for.
///
/// The substitute path used to accept the first search hit that produced a
/// URL, so a blocked track could silently play a cover, a live version or a
/// ten-hour loop. Duration is the strongest cheap signal and is checked
/// first; title and artist only run when both sides carry something
/// comparable, because a missing name is not a mismatch either.
bool _isSameRecording({
  required String requestedTitle,
  required String? requestedArtist,
  required YtmTrack candidate,
  required YtmStream stream,
  Duration? expectedDuration,
}) {
  if (!_durationMatches(expectedDuration, candidate.duration) ||
      !_durationMatches(expectedDuration, stream.duration)) {
    return false;
  }
  return _metadataMatches(
    requestedTitle: requestedTitle,
    requestedArtist: requestedArtist,
    candidateTitle:
        stream.title.trim().isNotEmpty ? stream.title : candidate.title,
    candidateArtist:
        stream.artist.trim().isNotEmpty ? stream.artist : candidate.artist,
  );
}

/// Whether [candidateTitle] / [candidateArtist] plausibly describe the
/// requested track.
///
/// Placeholders are treated as absent, so a missing name never rejects a hit;
/// when both sides carry a real value, one must contain the other.
bool _metadataMatches({
  required String requestedTitle,
  required String? requestedArtist,
  required String candidateTitle,
  required String candidateArtist,
}) {
  final wanted = _knownName(requestedTitle);
  final got = _knownName(candidateTitle);
  if (wanted.isNotEmpty &&
      got.isNotEmpty &&
      !got.contains(wanted) &&
      !wanted.contains(got)) {
    return false;
  }

  final wantedArtist = _knownName(requestedArtist ?? '');
  final gotArtist = _knownName(candidateArtist);
  if (wantedArtist.isNotEmpty &&
      gotArtist.isNotEmpty &&
      !gotArtist.contains(wantedArtist) &&
      !wantedArtist.contains(gotArtist)) {
    return false;
  }
  return true;
}

/// Values the extraction channels emit when they have no metadata.
///
/// Treating them as evidence rejected every substitute whose native resolve
/// did not echo the title or artist back: `YtmStream.fromChannel` fills a
/// missing artist with "Unknown Artist", which matches nothing.
const Set<String> _metadataPlaceholders = {
  'unknown artist',
  'unknown title',
  'youtube music',
  'youtube track',
};

/// Normalised name, or empty when it is only a placeholder.
String _knownName(String input) {
  final normalized = _normalizeForMatch(input);
  return _metadataPlaceholders.contains(normalized) ? '' : normalized;
}

/// Lowercase, drop bracketed suffixes ("(Official Audio)", "[Live]") and
/// punctuation, and collapse whitespace. Deliberately script-agnostic: the
/// app ships in Arabic and Spanish, and stripping non-Latin characters would
/// make every comparison pass vacuously.
String _normalizeForMatch(String input) => input
    .toLowerCase()
    .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
    .replaceAll(RegExp(r'''[.,\-_/\|:;!?()\[\]{}"'`~*&+]+'''), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
