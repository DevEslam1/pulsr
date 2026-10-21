import 'dart:io';

import '../constants/embedded_browser_ua.dart';

/// Request shaping and chunk planning shared by download transfers.
class YtDownloadTransferPolicy {
  static const int minChunkThreshold = 512 * 1024;

  /// googlevideo URLs are minted for a specific client's User-Agent; sending
  /// the Dart default trips YouTube's bot heuristics with 403s.
  static void applyHeaders(
    HttpClientRequest request,
    String? userAgent, {
    String? cookies,
    String? range,
  }) {
    final ua = userAgent?.trim();
    if (ua != null && ua.isNotEmpty) {
      request.headers.set(HttpHeaders.userAgentHeader, ua);
    } else {
      request.headers
          .set(HttpHeaders.userAgentHeader, EmbeddedBrowserUa.desktop);
    }
    if (cookies != null && cookies.isNotEmpty && cookiesBelongOn(request.uri)) {
      request.headers.set(HttpHeaders.cookieHeader, cookies);
    }
    request.headers
        .set(HttpHeaders.refererHeader, 'https://music.youtube.com/');
    if (range != null) {
      request.headers.set(HttpHeaders.rangeHeader, range);
    }
  }

  /// A googlevideo edge authenticates from the URL signature, and a browser
  /// never sends its YouTube session cookies there.
  static bool cookiesBelongOn(Uri uri) {
    try {
      final host = uri.host.toLowerCase();
      if (host == 'googlevideo.com' || host.endsWith('.googlevideo.com')) {
        return false;
      }
      if (host.endsWith('.c.youtube.com')) return false;
      if (uri.path.contains('/videoplayback')) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Adapts concurrent chunk count to measured throughput and total size.
  static int optimalChunkCount(int totalBytes, {double throughputMbps = 10.0}) {
    if (totalBytes < minChunkThreshold * 2) return 1;

    int targetChunks;
    if (throughputMbps < 2.0) {
      targetChunks = 2;
    } else if (throughputMbps >= 15.0 && totalBytes >= 8 * 1024 * 1024) {
      targetChunks = 8;
    } else {
      targetChunks = 4;
    }

    while (
        targetChunks > 1 && (totalBytes / targetChunks) < minChunkThreshold) {
      targetChunks ~/= 2;
    }

    return targetChunks.clamp(1, 8);
  }
}
