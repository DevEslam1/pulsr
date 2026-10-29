// lib/core/services/yt_download_http_support.dart
import 'dart:io';

import '../errors/failures.dart';

/// Small response/IO helpers shared by the download transfer paths.
class YtDownloadHttpSupport {
  /// Reads the tiny body of a probe/error response so its socket can be
  /// reused. Bounded: a body that stops arriving must not hold the probe.
  static Future<void> drainSmall(HttpClientResponse response) async {
    try {
      await response.drain<void>().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort: the request that follows opens its own connection.
    }
  }

  /// Drops a response whose body we deliberately do not want (a whole-file
  /// 200 answer to a ranged probe) without paying for downloading it.
  static Future<void> abortBody(HttpClientResponse response) async {
    try {
      final socket = await response.detachSocket();
      socket.destroy();
    } catch (_) {
      await drainSmall(response);
    }
  }

  /// Maps a disk-full [FileSystemException] (including one surfaced by
  /// `flush`/`close`, which write-side catches often miss) to the typed
  /// failure the retry scheduler understands.
  static Never throwStorageOrOriginal(FileSystemException error) {
    final message = error.message.toLowerCase();
    if (message.contains('no space') ||
        message.contains('enospc') ||
        error.osError?.errorCode == 28) {
      throw const StorageFailure('Storage full while writing download');
    }
    throw error;
  }
}
