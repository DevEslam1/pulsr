// lib/data/repositories/download_repository_execution.dart
//
// Split out of download_repository_impl.dart: single-task download execution,
// retry backoff, progress mapping, auto-pause on policy/connectivity loss,
// and completion reconciliation into the local library row.
part of 'download_repository_impl.dart';

extension DownloadRepositoryExecution on DownloadRepositoryImpl {
  Future<void> _executeTask(DownloadTask task) async {
    final videoId = task.videoId;
    final completer = Completer<void>();
    _activeCompleters[videoId] = completer;
    _updateTask(task.copyWith(status: DownloadStatus.downloading));

    try {
      // No upfront resolve: YtDownloadService.download() resolves internally
      // and caches the stream (getResolvedStream). Resolving here first
      // doubled resolve QPS and tripped 429/bot cooldowns after a few tracks,
      // after which every queued track failed fast and the batch "stopped".
      final synthTrack = YtmTrack(
        videoId: videoId,
        title: task.title,
        artist: task.artist,
        duration: Duration(milliseconds: task.durationMs ?? 0),
        artworkUrl: task.artworkUrl,
      );
      // `sourceSongId` is the row the user actually tapped; using it (instead
      // of relying on the synthetic id being identical) makes the completed
      // row replace the right queue/library entry. Album and duration are
      // persisted with the task so a resumed download still tags and looks up
      // lyrics with the real metadata.
      final songRow = synthTrack.toSongData().copyWith(
            id: task.sourceSongId ?? synthTrack.songId,
            album: task.album ?? '',
          );

      // A per-track quality survives restarts in the persisted task; hand it to
      // the service's admission path, which consumes it only when it creates a
      // new job (so a dedupe chain cannot swallow it).
      final quality = task.quality;

      Either<AppFailure, int>? result;
      // One initial attempt + up to 2 transient retries with backoff.
      for (var attempt = 0; attempt < 3; attempt++) {
        if (_pausedVideoIds.contains(videoId) || !_tasks.containsKey(videoId)) {
          break;
        }
        if (attempt > 0) {
          // Exponential backoff with ~20% jitter: ~2s, ~4s.
          final backoffMs = (2000 << (attempt - 1)) +
              DownloadRepositoryImpl._random.nextInt(400);
          await Future.delayed(Duration(milliseconds: backoffMs));
          if (_pausedVideoIds.contains(videoId) ||
              !_tasks.containsKey(videoId)) {
            break;
          }
          final current = _tasks[videoId];
          if (current == null) break;
          _updateTask(current.copyWith(
            status: DownloadStatus.downloading,
            clearError: true,
            clearSpeedKbps: true,
            clearEtaSeconds: true,
          ));
        }
        // Re-arm the picker override for every attempt: the transfer consumes
        // it when it creates a job, so a repository-level retry (a fresh job)
        // would otherwise fall back to the global download quality.
        if (quality != null) {
          _ytDownloadService.setPendingDownloadQuality(videoId, quality);
        }
        result = await _ytDownloadService.download(
          songRow,
          bypassInternalQueue: true,
          onProgress: (p) {
            if (_pausedVideoIds.contains(videoId)) return;
            // A deleted task must not be resurrected by a late progress tick.
            final progressTask = _tasks[videoId];
            if (progressTask == null) return;
            // `canceled` is a request, not transfer progress. Mapping it to
            // `downloading` used to flip a task that was already saving (or
            // paused) back to an active-looking row.
            if (p.stage == YtDownloadStage.canceled) return;

            final mappedStatus = switch (p.stage) {
              YtDownloadStage.queued => DownloadStatus.queued,
              YtDownloadStage.resolving ||
              YtDownloadStage.downloading =>
                DownloadStatus.downloading,
              YtDownloadStage.tagging ||
              YtDownloadStage.saving ||
              YtDownloadStage.indexing =>
                DownloadStatus.tagging,
              YtDownloadStage.done => DownloadStatus.tagging,
              YtDownloadStage.canceled => progressTask.status,
            };

            _updateTask(progressTask.copyWith(
              status: mappedStatus,
              progress: p.fraction ?? progressTask.progress,
              speedKbps: p.speedKbps,
              etaSeconds: p.etaSeconds,
            ));
          },
        );
        final failure = result.getLeft().toNullable();
        if (failure == null) break; // success
        // The transfer itself already retried with backoff. A connectivity
        // failure that outlived that belongs to the network-change listener:
        // retrying here only delays parking it, while the partial is safe.
        final info =
            YtmErrorClassifier.classify(failure.error ?? failure.message);
        if (info.signal == YtmBlockSignal.networkUnavailable &&
            !await ConnectivityGuard.hasConnection()) {
          // Genuinely offline: more waiting cannot help. A network failure
          // while the device is online may be a transient DNS/route blip, so
          // that one still gets the normal retry budget.
          break;
        }
        if (!DownloadRepositoryImpl._isTransientFailure(failure)) {
          break; // permanent: don't burn retries
        }
      }
      result ??= const Left(DownloadFailure('Download cancelled'));
      // A successful result means tagging/saving/indexing already completed in
      // the service, regardless of what the user did in the meantime.
      final completedId = result.getRight().toNullable();

      if (_pausedVideoIds.contains(videoId) && completedId == null) {
        _activeVideoIds.remove(videoId);
        _activeCompleters.remove(videoId);
        if (!completer.isCompleted) completer.complete();
        _processQueue();
        return;
      }
      if (completedId != null && _pausedVideoIds.contains(videoId)) {
        // Pause lost the race against the save/index tail. Marking the task
        // paused here would make the next resume fetch a second copy of a file
        // that is already in the library.
        _pausedVideoIds.remove(videoId);
        _ytDownloadService.clearPaused(videoId);
        _notifyNativePaused(videoId, false);
      }

      // If the task was deleted while downloading, don't resurrect it. When the
      // service still finished the save+index (delete landed mid-tagging), the
      // library row and file it just produced must be removed too, otherwise
      // they linger untracked until a full scan.
      if (!_tasks.containsKey(videoId)) {
        if (completedId != null) {
          try {
            await _libraryMaintenance.removeDownloadedArtifacts(
              localSongId: completedId,
              contentUri: _ytDownloadService.getDownloadedContentUri(videoId),
            );
            _ytDownloadService.forgetDownloadedPath(videoId);
          } catch (e, st) {
            ErrorLogger.log('Failed cleaning download deleted mid-save',
                error: e, stackTrace: st, category: 'Download');
          }
        }
        _activeVideoIds.remove(videoId);
        _activeCompleters.remove(videoId);
        if (!completer.isCompleted) completer.complete();
        _processQueue();
        return;
      }

      // Await the completion branch: a discarded future let `finally` free the
      // slot and deleters run between the DB read and `_updateTask(complete)`,
      // resurrecting a task the user had already removed.
      await result.fold(
        (failure) async {
          // Classify via YtmErrorClassifier for localized message, but repository keeps raw for UI to map
          final current = _tasks[videoId];
          if (current == null) return;
          if (_pausedVideoIds.contains(videoId) ||
              current.status == DownloadStatus.paused) {
            return;
          }
          // A transfer refused by the Wi-Fi/offline policy is not a broken
          // download: park it as paused (and mark it policy-owned) so the next
          // network-path change resumes it, instead of showing a permanent
          // failure the user must retry by hand.
          AppFailure? policyBlock;
          try {
            policyBlock = await _ytDownloadService.downloadPolicyBlock();
          } catch (_) {
            policyBlock = null;
          }
          if (policyBlock != null) {
            _parkAutoPaused(videoId, current, error: policyBlock.message);
            return;
          }
          final info =
              YtmErrorClassifier.classify(failure.error ?? failure.message);
          if (info.signal == YtmBlockSignal.networkUnavailable &&
              !await ConnectivityGuard.hasConnection()) {
            // Connectivity loss is temporary even when it outlives the retry
            // budget. Parking as auto-paused keeps the partial and lets the
            // network-change listener resume it; a failed row would require a
            // manual retry for something the device already knows how to fix.
            _parkAutoPaused(videoId, current, error: failure.message);
            return;
          }
          _updateTask(current.copyWith(
            status: DownloadStatus.failed,
            error: failure.message,
            clearSpeedKbps: true,
            clearEtaSeconds: true,
          ));
          _ytDownloadService.releaseForeground(videoId);
        },
        (newId) async {
          _cachedStorageStats =
              null; // Invalidate storage stats cache on completion
          final current = _tasks[videoId];
          if (current == null) return;
          String? resolvedPath =
              current.filePath ?? _ytDownloadService.getDownloadedPath(videoId);
          int? resolvedSize = current.fileSize;
          String? resolvedFormat = current.format;
          int? resolvedBitrate = current.bitrate;
          var resolvedTitle = current.title;
          var resolvedArtist = current.artist;
          var resolvedAlbum = current.album;
          var resolvedDuration = current.durationMs;

          final db = _effectiveDb;
          if (db != null) {
            try {
              final song = await (db.select(db.songsTable)
                    ..where((t) => t.id.equals(newId)))
                  .getSingleOrNull();
              if (song != null) {
                resolvedPath = song.path;
                resolvedSize = song.fileSize;
                resolvedBitrate = song.bitrateKbps ?? resolvedBitrate;
                // The reconciled row is authoritative: the download service
                // may have repaired "Unknown Artist" from the resolved
                // stream, and the task tile must show the same metadata.
                if (MetadataPlaceholders.isRealTitle(song.title)) {
                  resolvedTitle = song.title;
                }
                if (MetadataPlaceholders.isRealArtist(song.artist)) {
                  resolvedArtist = song.artist;
                }
                if (MetadataPlaceholders.isRealAlbum(song.album)) {
                  resolvedAlbum = song.album;
                }
                if (song.durationMs > 0) resolvedDuration = song.durationMs;
                if ((resolvedSize == null || resolvedSize <= 0)) {
                  // Stat off the platform thread; this completes on the
                  // download's own isolate, never the UI thread.
                  final f = File(resolvedPath);
                  if (await f.exists()) resolvedSize = await f.length();
                }
              }
            } catch (e, st) {
              ErrorLogger.log('Failed reading completed song row',
                  error: e, stackTrace: st, category: 'Download');
            }
          }

          if (resolvedFormat == null && resolvedPath != null) {
            final ext =
                p.extension(resolvedPath).replaceFirst('.', '').toLowerCase();
            if (ext.isNotEmpty) resolvedFormat = ext;
          }
          if (resolvedSize == null && resolvedPath != null) {
            try {
              final f = File(resolvedPath);
              if (await f.exists()) resolvedSize = await f.length();
            } catch (e, st) {
              ErrorLogger.log('Failed checking resolved download file length',
                  error: e, stackTrace: st, category: 'Download');
            }
          }

          // Re-read after the async DB read: a delete may have landed meanwhile.
          final latest = _tasks[videoId];
          if (latest == null) return;
          _updateTask(latest.copyWith(
            status: DownloadStatus.complete,
            progress: 1.0,
            clearError: true,
            clearSpeedKbps: true,
            clearEtaSeconds: true,
            localSongId: newId,
            filePath: resolvedPath,
            fileSize: resolvedSize,
            format: resolvedFormat,
            bitrate: resolvedBitrate,
            title: resolvedTitle,
            artist: resolvedArtist,
            album: resolvedAlbum,
            durationMs: resolvedDuration,
            contentUri: _ytDownloadService.getDownloadedContentUri(videoId),
          ));
          // Guarantees the native job is dropped even if the service's own
          // terminal publish was skipped (foreground start still in flight).
          _ytDownloadService.releaseForeground(videoId);
          // Reconcile just this task: a full sweep of every completed download
          // after each completion re-stat'ed the entire history on every track.
          final completed = _tasks[videoId];
          if (completed != null) {
            unawaited(_reconcileCompletedTask(completed));
          }
        },
      );
    } catch (e) {
      if (_tasks.containsKey(videoId)) {
        final current = _tasks[videoId] ?? task;
        _updateTask(current.copyWith(
          status: DownloadStatus.failed,
          error: e.toString(),
          clearSpeedKbps: true,
          clearEtaSeconds: true,
        ));
        _ytDownloadService.releaseForeground(videoId);
      }
    } finally {
      _pausingVideoIds.remove(videoId);
      _activeVideoIds.remove(videoId);
      _activeCompleters.remove(videoId);
      if (!completer.isCompleted) completer.complete();
      _processQueue();
    }
  }
}
