// lib/core/services/stream_url_verifier.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Verdict of one cheap pre-flight request against a resolved media URL.
enum StreamUrlProbeStatus {
  /// The CDN answered 2xx: the URL serves bytes right now.
  ok,

  /// The CDN answered a status that says this URL will never serve audio
  /// again: 401, 403, 404 or 410.
  rejected,

  /// Nothing conclusive: DNS/TLS/socket failure, a timeout, a 5xx, throttling,
  /// or a URL this class deliberately does not probe.
  unknown,
}

/// Result of [StreamUrlVerifier.probe].
///
/// The three-way answer is the point: [rejected] is the only verdict worth
/// spending a re-resolve on. A probe that cannot tell a dead signature from a
/// flaky network must say so rather than guess, or it would throw away a URL
/// that still works and pay for a fresh resolve (and, under a bot cooldown, a
/// poToken mint) on every hiccup.
@immutable
class StreamUrlProbe {
  final StreamUrlProbeStatus status;

  /// The HTTP status behind a [StreamUrlProbeStatus.rejected] verdict.
  final int? statusCode;

  /// Short, non-URL diagnostic tag (e.g. `timeout`, `http_503`). Never shown
  /// to the user.
  final String? reason;

  const StreamUrlProbe._(this.status, {this.statusCode, this.reason});

  const StreamUrlProbe.ok() : this._(StreamUrlProbeStatus.ok);

  const StreamUrlProbe.rejected(int code)
      : this._(StreamUrlProbeStatus.rejected, statusCode: code);

  const StreamUrlProbe.unknown([String? reason])
      : this._(StreamUrlProbeStatus.unknown, reason: reason);

  bool get isOk => status == StreamUrlProbeStatus.ok;

  bool get isRejected => status == StreamUrlProbeStatus.rejected;

  bool get isUnknown => status == StreamUrlProbeStatus.unknown;

  @override
  String toString() => 'StreamUrlProbe(${status.name}'
      '${statusCode != null ? ', $statusCode' : ''}'
      '${reason != null ? ', $reason' : ''})';
}

/// Signature of the injectable probe used by [StreamUrlVerifier.debugProbeOverride].
typedef StreamUrlProbeFn = Future<StreamUrlProbe> Function(
  String url, {
  String? userAgent,
  String? referer,
  String? cookie,
});

/// One-attempt reachability probe for resolved YouTube Music media URLs.
///
/// A stream URL can outlive its usefulness while still sitting happily inside
/// [YtmUrlCache]'s TTL — restored from a previous launch, minted for another
/// egress, or simply past the CDN's own signature expiry. The byte request is
/// the only other thing that finds out, and by then the player has already paid
/// the multi-second re-resolve this class exists to avoid.
///
/// Deliberately not `@injectable`: construction is free and the class carries
/// no per-instance mutable state, so callers build one on demand the way they
/// build [YtmCacheManager].
class StreamUrlVerifier {
  /// The whole budget for one probe. A cached URL that cannot answer a two-byte
  /// range inside this window is not worth waiting on: the re-resolve is
  /// already the fallback, and a slow probe would just add its latency to it.
  static const Duration timeout = Duration(seconds: 2);

  /// Statuses that mean this URL will never serve audio again. Everything else
  /// that is not 2xx — 408, 429, 5xx — is YouTube (or the path) having a bad
  /// minute and says nothing about the signature.
  static const List<int> rejectedStatuses = [401, 403, 404, 410];

  /// Shared by every instance so a probe reuses an existing connection instead
  /// of paying a fresh TCP/TLS handshake. Created under the app's
  /// [HttpOverrides], so the user's proxy configuration applies.
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = timeout
    ..idleTimeout = const Duration(seconds: 15)
    ..maxConnectionsPerHost = 4;

  /// In-flight probes keyed by URL, shared across instances so two sources for
  /// the same track cannot send two probes for the same URL.
  static final Map<String, Future<StreamUrlProbe>> _inFlight =
      <String, Future<StreamUrlProbe>>{};

  /// Test seam replacing the HTTP round trip. Production leaves it null.
  @visibleForTesting
  static StreamUrlProbeFn? debugProbeOverride;

  /// Probes [url] and never throws.
  ///
  /// A URL that is not a YouTube media CDN endpoint answers [StreamUrlProbe.ok]
  /// without a request: a 403 from a self-hosted proxy or a local file says
  /// nothing this class knows how to interpret.
  Future<StreamUrlProbe> probe(
    String url, {
    String? userAgent,
    String? referer,
    String? cookie,
  }) {
    if (!isProbeable(url)) {
      return Future<StreamUrlProbe>.value(const StreamUrlProbe.ok());
    }
    final inFlight = _inFlight[url];
    if (inFlight != null) return inFlight;
    final future = _probe(url,
            userAgent: userAgent, referer: referer, cookie: cookie)
        // The connect and response waits each carry their own timeout; this caps
        // the whole probe so a stalled body cannot hold the playback path past
        // the budget the player set for it.
        .timeout(timeout,
            onTimeout: () => const StreamUrlProbe.unknown('timeout'));
    _inFlight[url] = future;
    return future.whenComplete(() {
      if (identical(_inFlight[url], future)) _inFlight.remove(url);
    });
  }

  /// Whether [url] is a YouTube media CDN endpoint worth probing.
  ///
  /// Only verified YouTube/Google CDN domains answer the question this class
  /// asks. Anything else returns [StreamUrlProbe.ok] untouched.
  static bool isProbeable(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host == 'googlevideo.com' || host.endsWith('.googlevideo.com')) {
      return true;
    }
    if (host.endsWith('.c.youtube.com')) return true;
    if ((host == 'youtube.com' ||
            host.endsWith('.youtube.com') ||
            host == 'youtube-nocookie.com' ||
            host.endsWith('.youtube-nocookie.com')) &&
        uri.path.contains('/videoplayback')) {
      return true;
    }
    return false;
  }

  /// Maps an HTTP status to a verdict. Exposed for tests: the mapping is the
  /// rule, and it is the only part of a live probe worth asserting on without
  /// a network.
  @visibleForTesting
  static StreamUrlProbe verdictForStatus(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      return const StreamUrlProbe.ok();
    }
    if (rejectedStatuses.contains(statusCode)) {
      return StreamUrlProbe.rejected(statusCode);
    }
    return StreamUrlProbe.unknown('http_$statusCode');
  }

  static Future<StreamUrlProbe> _probe(
    String url, {
    String? userAgent,
    String? referer,
    String? cookie,
  }) async {
    final override = debugProbeOverride;
    if (override != null) {
      try {
        return await override(url,
            userAgent: userAgent, referer: referer, cookie: cookie);
      } catch (e) {
        return const StreamUrlProbe.unknown('probe_override_failed');
      }
    }

    HttpClientRequest? request;
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty) {
        return const StreamUrlProbe.unknown('bad_url');
      }
      request = await _client.getUrl(uri).timeout(timeout);
      // One byte is enough to make the CDN validate the signature, and it keeps
      // the probe's cost off the metered connection budget of the track.
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1');
      if (userAgent != null && userAgent.isNotEmpty) {
        request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      }
      if (referer != null && referer.isNotEmpty) {
        request.headers.set(HttpHeaders.refererHeader, referer);
      }
      if (cookie != null && cookie.isNotEmpty && isProbeable(url)) {
        request.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      final response = await request.close().timeout(timeout);
      final verdict = verdictForStatus(response.statusCode);
      await _discardBody(response);
      return verdict;
    } on TimeoutException {
      _abortQuietly(request);
      return const StreamUrlProbe.unknown('timeout');
    } catch (e) {
      _abortQuietly(request);
      return StreamUrlProbe.unknown(e.runtimeType.toString());
    }
  }

  /// Drops an in-flight probe request without letting the teardown failure
  /// replace the verdict the caller is waiting for.
  static void _abortQuietly(HttpClientRequest? request) {
    if (request == null) return;
    try {
      request.abort();
    } catch (e) {
      debugPrint('[StreamUrlVerifier] Probe abort failed: $e');
    }
  }

  /// Releases a probe response without pulling the track.
  ///
  /// A CDN that ignores `Range` answers with the whole body; draining that
  /// would download megabytes to learn one status code, so such a response is
  /// detached and its socket destroyed instead.
  static Future<void> _discardBody(HttpClientResponse response) async {
    final length = response.contentLength;
    final bounded = length == 0 || (length > 0 && length <= 4096);
    if (!bounded) {
      try {
        final socket = await response.detachSocket();
        socket.destroy();
        return;
      } catch (_) {
        // Fall through to a capped drain.
      }
    }
    try {
      await response.drain<void>().timeout(const Duration(seconds: 1));
    } catch (_) {
      // Best-effort: the verdict has already been read from the status line.
    }
  }
}
