// lib/features/remote_sources/remote_stream_pump.dart
//
// P0-1 "remote sources": the part of the stream bridge that moves bytes.
//
// The server above it decides *what* to answer (routing, range, status); this
// class answers it: serve a cached file window, pump a provider stream while
// teeing it into the cache, or send a small text error. Keeping the two apart
// means the routing table and the I/O loop can be read independently.
import 'dart:convert';
import 'dart:io';

import '../../core/utils/error_logger.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import 'remote_byte_range.dart';
import 'remote_cache_sink.dart';
import 'remote_cache_store.dart';

/// Writes stream responses to an [HttpResponse].
class RemoteStreamPump {
  /// Creates a pump over an optional [cache] and a read window size.
  const RemoteStreamPump({
    required this.cache,
    this.maxChunkBytes = 128 * 1024,
  });

  /// Cache used to warm and read files; `null` disables caching.
  final RemoteCacheStore? cache;

  /// Size of the read window used when serving a cached file.
  final int maxChunkBytes;

  /// Starts a cache write for a full download, or returns `null` when caching
  /// is disabled or unavailable.
  ///
  /// [etag]/[modifiedAt] are the validators the provider reported for the
  /// file; they are stored with the entry so a later [RemoteCacheStore.lookup]
  /// can tell whether the bytes on disk still describe the server's file.
  Future<RemoteCacheSink?> startCacheWrite(
    String sourceId,
    String path, {
    String? etag,
    DateTime? modifiedAt,
    bool pin = false,
  }) async {
    final store = cache;
    if (store == null) return null;
    try {
      return await store.beginWrite(
        sourceId,
        path,
        pin: pin,
        etag: etag,
        modifiedAt: modifiedAt,
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Remote cache write could not start',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      return null;
    }
  }

  /// Sends [range] (or the whole file) from [file].
  Future<void> sendFile(
    HttpResponse response,
    File file,
    RemoteByteRange? range,
  ) async {
    final start = range?.start ?? 0;
    final end = range?.end ?? (await file.length()) - 1;
    RandomAccessFile? handle;
    var clientAborted = false;
    try {
      handle = await file.open();
      await handle.setPosition(start);
      var remaining = end - start + 1;
      while (remaining > 0) {
        final want = remaining < maxChunkBytes ? remaining : maxChunkBytes;
        final chunk = await handle.read(want);
        if (chunk.isEmpty) break;
        response.add(chunk);
        remaining -= chunk.length;
        try {
          await response.flush();
        } on IOException catch (e) {
          clientAborted = true;
          ErrorLogger.log(
            'Stream client aborted cached playback: $e',
            category: 'RemoteSources',
          );
          await destroy(response);
          return;
        }
      }
    } on FileSystemException catch (e, st) {
      ErrorLogger.log(
        'Cached file could not be served',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      await destroy(response);
      return;
    } finally {
      await handle?.close();
    }
    if (clientAborted) return;
    try {
      await response.close();
    } on IOException catch (e) {
      ErrorLogger.log(
        'Stream client disconnected while finishing cached response: $e',
        category: 'RemoteSources',
      );
      await destroy(response);
    }
  }

  /// Pumps `provider.openRead` into [response], teeing into [sink] when given.
  ///
  /// Returns `false` when the connection had to be dropped because the failure
  /// happened after the first byte was sent or when fewer than
  /// [expectedLength] bytes arrived (never committing truncated bytes to cache).
  /// A provider failure before any byte hits the wire rethrows so the caller
  /// can still answer with a proper status code.
  Future<bool> sendFromProvider(
    HttpResponse response,
    RemoteFsProvider provider,
    String path, {
    int start = 0,
    int? end,
    RemoteCacheSink? sink,
    int? expectedLength,
  }) async {
    var wrote = false;
    var bytesRead = 0;
    try {
      await for (final chunk
          in provider.openRead(path, start: start, end: end)) {
        bytesRead += chunk.length;
        sink?.add(chunk);
        try {
          response.add(chunk);
          wrote = true;
          await response.flush();
        } on IOException catch (e) {
          ErrorLogger.log(
            'Stream client aborted remote playback: $e',
            category: 'RemoteSources',
          );
          await abortSink(sink);
          await destroy(response);
          return false;
        }
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Remote stream aborted while reading from the provider',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': provider.source.authority},
      );
      await abortSink(sink);
      if (!wrote) {
        // No byte reached the wire, so the response can still carry a proper
        // status and message instead of looking like a truncated download.
        rethrow;
      }
      await destroy(response);
      return false;
    }
    if (expectedLength != null && bytesRead != expectedLength) {
      ErrorLogger.log(
        'Remote stream ended early ($bytesRead of $expectedLength bytes); '
        'discarding cache write',
        category: 'RemoteSources',
        meta: {'authority': provider.source.authority},
      );
      await abortSink(sink);
      await destroy(response);
      return false;
    }
    final file = await sink?.commit();
    if (file == null) {
      await abortSink(sink);
    }
    try {
      await response.close();
    } on IOException catch (e) {
      ErrorLogger.log(
        'Stream client disconnected while finishing remote response: $e',
        category: 'RemoteSources',
      );
      await destroy(response);
      return false;
    }
    return true;
  }

  /// Sends a short text error, resetting any staged length/range headers.
  Future<void> sendText(
    HttpResponse response,
    int status,
    String message,
  ) async {
    try {
      // A 200/206 header block may already be staged but not flushed; reset the
      // length and range so the error body is framed as a plain chunked reply.
      response.headers.removeAll(HttpHeaders.contentRangeHeader);
      response.contentLength = -1;
      response.headers.contentType = ContentType.text;
      response.statusCode = status;
      response.write(message);
      await response.close();
    } on IOException catch (e, st) {
      ErrorLogger.log(
        'Could not send a stream error response',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    } on StateError catch (e, st) {
      ErrorLogger.log(
        'Stream error response was already committed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
  }

  /// Drops a connection whose body can no longer be completed.
  Future<void> destroy(HttpResponse response) async {
    try {
      final socket = await response.detachSocket(writeHeaders: false);
      socket.destroy();
      return;
    } catch (_) {
      // Headers were already flushed, so detachSocket() throws StateError.
      // Signal an error into the IOSink and close so dart:io aborts the
      // chunked stream instead of leaving the socket open forever.
    }
    try {
      response.addError(const HttpException('Stream aborted'));
      await response.close();
    } on HttpException {
      // Expected: closing an errored IOSink rethrows the injected abort error
      // after terminating the HTTP stream cleanly.
    } catch (e, st) {
      ErrorLogger.log(
        'Could not drop a failed stream connection',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
  }

  /// Aborts a cache write that will not be completed.
  Future<void> abortSink(RemoteCacheSink? sink) async {
    if (sink == null) return;
    try {
      await sink.abort();
    } catch (e, st) {
      ErrorLogger.log(
        'Remote cache sink did not abort cleanly',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
  }

  /// Encodes a provider path for a URL segment.
  static String encodePath(String path) =>
      base64UrlEncode(utf8.encode(path)).replaceAll('=', '');
}
