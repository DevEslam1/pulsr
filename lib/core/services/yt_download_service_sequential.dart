// lib/core/services/yt_download_service_sequential.dart
//
// Split out of yt_download_service.dart: the single-request sequential
// transfer path with resumable `.part` + `.part.stamp` verification, 416/200
// Range fallback, periodic sink backpressure, and atomic commit.
part of 'yt_download_service.dart';

extension YtDownloadServiceSequential on YtDownloadService {
  Future<_TransferOutcome> _downloadSequential(
    Uri uri,
    File dest,
    _QueuedDownload task,
    void Function(YtDownloadProgress)? onProgress, {
    String? userAgent,
    String? cookies,
    int? expectedBytes,
    String? container,
    bool allowResume = true,
    int retryCount = 0, // FIX-A01: Add retryCount parameter (max 1)
  }) async {
    final stopwatch = Stopwatch()..start();
    final partFile = File('${dest.path}.part');
    // F6: a `.part` is only resumable against the same body that wrote it. The
    // stamp identifies container + expected size rather than the URL, so a
    // re-resolved (freshly signed) URL for the same body resumes, while a
    // quality/format change does not.
    final stampFile = File('${dest.path}.part.stamp');
    final resumeStamp = YtDownloadTransferMath.resumeStampFor(
        container: container ?? 'bin',
        expectedBytes: expectedBytes,
        videoId: task.song.remoteId);
    int resumeOffset = 0;
    try {
      if (await partFile.exists()) {
        resumeOffset = allowResume ? await partFile.length() : 0;
        var stampMatches = false;
        try {
          if (await stampFile.exists()) {
            stampMatches = YtDownloadService.resumeStampMatches(
                await stampFile.readAsString(), resumeStamp);
          }
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
        if (resumeOffset > 0 && !stampMatches) {
          // Written for a different body, or by a build without the stamp:
          // nothing in it is known to line up, so start over.
          try {
            await partFile.delete();
          } catch (_) {
            // Best-effort: failure intentionally ignored on this non-critical path.
          }
          resumeOffset = 0;
        }
        // Keep resume only if meaningful (>64k) to avoid overhead for tiny partials
        if (resumeOffset < 64 * 1024) {
          try {
            await partFile.delete();
          } catch (_) {
            // Best-effort: failure intentionally ignored on this non-critical path.
          }
          resumeOffset = 0;
        }
      }
      try {
        await stampFile.writeAsString(resumeStamp, flush: true);
      } catch (_) {
        // Best-effort: failure intentionally ignored on this non-critical path.
      }
    } catch (_) {
      resumeOffset = 0;
    }

    final request = await _http
        .openUrl('GET', uri)
        .timeout(YtDownloadService._stallTimeout);
    _trackRequest(task.runId, request);
    try {
      if (resumeOffset > 0) {
        YtDownloadTransferPolicy.applyHeaders(request, userAgent,
            cookies: cookies, range: 'bytes=$resumeOffset-');
      } else {
        YtDownloadTransferPolicy.applyHeaders(request, userAgent,
            cookies: cookies);
      }
      final response =
          await request.close().timeout(YtDownloadService._stallTimeout);

      // 429 / Retry-After aware backoff + jitter integration
      if (response.statusCode == 429) {
        final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
        final retrySec = int.tryParse(retryAfter ?? '');
        // Drain body before throwing so connection reused
        await YtDownloadHttpSupport.drainSmall(response);
        throw YtmException('YTM_429',
            'HTTP 429 Too Many Requests${retrySec != null ? ' Retry-After: $retrySec' : ''}');
      }
      if (response.statusCode == HttpStatus.forbidden ||
          response.statusCode == HttpStatus.unauthorized) {
        await YtDownloadHttpSupport.drainSmall(response);
        throw YtmException('YTM_STREAM_EXPIRED',
            'HTTP ${response.statusCode} on stream request');
      }

      // The server says the resume offset is past the end of the body (the
      // partial belongs to a different/larger body). Retrying the same range
      // five times could never succeed; drop the partial and start clean.
      if (resumeOffset > 0 &&
          response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        await YtDownloadHttpSupport.drainSmall(response);
        try {
          await partFile.delete();
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
        try {
          if (await stampFile.exists()) await stampFile.delete();
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
        if (retryCount >= 1) {
          throw const DownloadFailure('Server rejected the resume range');
        }
        return await _downloadSequential(uri, dest, task, onProgress,
            userAgent: userAgent,
            cookies: cookies,
            expectedBytes: expectedBytes,
            container: container,
            allowResume: false,
            retryCount: retryCount + 1);
      }

      // Resume correctness: if we sent Range, server MUST reply 206. A 200 means it ignored Range
      // → appending would corrupt file. Abort body and discard stale part + stamp.
      if (resumeOffset > 0) {
        if (response.statusCode == HttpStatus.ok) {
          await YtDownloadHttpSupport.abortBody(response);
          try {
            await partFile.delete();
          } catch (_) {
            // Best-effort: failure intentionally ignored on this non-critical path.
          }
          try {
            if (await stampFile.exists()) await stampFile.delete();
          } catch (_) {
            // Best-effort: failure intentionally ignored on this non-critical path.
          }
          // FIX-A01: On second occurrence, throw DownloadFailure('Server does not support resume')
          if (retryCount >= 1) {
            throw const DownloadFailure('Server does not support resume');
          }
          // Retry from scratch with incremented retryCount
          return await _downloadSequential(uri, dest, task, onProgress,
              userAgent: userAgent,
              cookies: cookies,
              expectedBytes: expectedBytes,
              container: container,
              allowResume: false,
              retryCount: retryCount + 1); // FIX-A01
        }
        if (response.statusCode != HttpStatus.partialContent) {
          await YtDownloadHttpSupport.drainSmall(response);
          throw DownloadFailure('HTTP ${response.statusCode} on resume');
        }
      } else {
        if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.partialContent) {
          await YtDownloadHttpSupport.drainSmall(response);
          throw DownloadFailure(
              'HTTP ${response.statusCode} on stream request');
        }
      }

      // Determine total expected size for atomic commit verification
      final total = response.contentLength; // remaining bytes
      // If resumed, total via Content-Range: bytes start-end/total
      final contentRange =
          response.headers.value(HttpHeaders.contentRangeHeader);
      int? expectedFinalSize;
      if (contentRange != null && contentRange.contains('/')) {
        expectedFinalSize = int.tryParse(contentRange.split('/').last);
      } else if (total > 0) {
        expectedFinalSize = resumeOffset + total;
      }
      // Fallback: if server gave contentLength as full size even for 206, handle
      if (resumeOffset > 0 && total > 0 && expectedFinalSize == null) {
        expectedFinalSize = resumeOffset + total;
      }

      final sink = resumeOffset > 0
          ? partFile.openWrite(mode: FileMode.append)
          : partFile.openWrite();
      var received = resumeOffset;
      var unflushedBytes = 0;
      const flushThresholdBytes = 512 * 1024;
      var lastEmitTime = 0;
      final baseReceived = resumeOffset;

      try {
        // Per-event watchdog, same as the chunked path: a stalled edge node used
        // to hold the transfer open indefinitely with the progress bar frozen.
        await for (final chunk
            in response.timeout(YtDownloadService._stallTimeout)) {
          if (task.isCanceled) {
            throw const DownloadFailure('Download canceled');
          }
          await _assertTransferPolicy();
          received += chunk.length;
          sink.add(chunk);
          unflushedBytes += chunk.length;
          if (unflushedBytes >= flushThresholdBytes) {
            unflushedBytes = 0;
            await sink.flush();
          }
          if (onProgress != null) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final effectiveTotal = expectedFinalSize ?? total;
            final fraction = effectiveTotal > 0
                ? (received / effectiveTotal).clamp(0.0, 1.0).toDouble()
                : null;
            if (now - lastEmitTime > 80 ||
                (effectiveTotal > 0 && received >= effectiveTotal)) {
              lastEmitTime = now;
              final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
              final speedKbps = elapsedSeconds > 0
                  ? ((received - baseReceived) / elapsedSeconds) / 1024.0
                  : 0.0;
              final remainingBytes =
                  effectiveTotal > 0 ? effectiveTotal - received : 0;
              final etaSeconds = (speedKbps > 0 && remainingBytes > 0)
                  ? (remainingBytes / (speedKbps * 1024.0)).round()
                  : null;

              onProgress(YtDownloadProgress(
                YtDownloadStage.downloading,
                fraction,
                speedKbps,
                etaSeconds,
              ));
            }
          }
        }
        await sink.flush();
        _sampleThroughput(received - baseReceived, stopwatch.elapsed);
      } on FileSystemException catch (e) {
        YtDownloadHttpSupport.throwStorageOrOriginal(e);
      } finally {
        try {
          await sink.close();
        } on FileSystemException catch (e) {
          YtDownloadHttpSupport.throwStorageOrOriginal(e);
        }
      }

      if (task.isCanceled) {
        // Keep .part for resume if partially downloaded; don't delete on cancel (pause semantics)
        throw const DownloadFailure('Download canceled');
      }

      // Atomic commit: verify size == expected, fsync, then rename
      if (await partFile.exists()) {
        final finalSize = await partFile.length();

        if (expectedFinalSize != null && expectedFinalSize > 0) {
          if (finalSize < expectedFinalSize) {
            // Keep the part: every byte in it is valid and the next attempt
            // resumes from here. The old check only fired when `total > 0`, so a
            // server that sent no length at all had its truncated body renamed
            // over `dest` and committed as a complete download.
            throw DownloadFailure(
                'Incomplete download: $finalSize/$expectedFinalSize bytes');
          }
          if (finalSize > expectedFinalSize) {
            // More bytes than the body holds: a resumed request was answered from
            // offset 0 and a second copy got appended. Nothing here is salvageable
            // and keeping it would only resume from a worse offset.
            await partFile.delete().catchError((_) => partFile);
            throw DownloadFailure(
                'Oversized download: $finalSize/$expectedFinalSize bytes');
          }
        } else if (expectedBytes != null &&
            expectedBytes > 0 &&
            finalSize < expectedBytes ~/ 2) {
          // Unknown-length body (`contentLength == -1` and no Content-Range): the
          // duration-derived estimate is the only bar available, and committing a
          // half-sized file as complete is worse than retrying.
          throw DownloadFailure(
              'Suspiciously small download: ${finalSize ~/ 1024}KB of ~${expectedBytes ~/ 1024}KB');
        }

        if (finalSize < 1024) {
          await partFile.delete().catchError((_) => partFile);
          throw const DownloadFailure('Downloaded file too small — corrupt');
        }
        // fsync before rename for durability (atomic commit)
        try {
          final raf = await partFile.open(mode: FileMode.append);
          await raf.flush();
          await raf.close();
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
        if (await dest.exists()) {
          await dest.delete();
        }
        await partFile.rename(dest.path);
        try {
          if (await stampFile.exists()) {
            await stampFile.delete();
          }
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
      }
      return _TransferOutcome(
        verifiedHttpBytes: expectedFinalSize,
        hasVerifiedHttpLength:
            expectedFinalSize != null && expectedFinalSize > 0,
      );
    } finally {
      _untrackRequest(task.runId, request);
    }
  }
}
