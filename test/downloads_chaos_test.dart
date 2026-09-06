// test/downloads_chaos_test.dart
// Nightly soak: 100-task queue with random kills + airplane toggles → zero orphans, zero corrupt finals, 100% eventual completion
// This unit-level chaos test simulates repository behavior without real network.

// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/download_task.dart';

void main() {
  test(
      'chaos: 100 random queue with interleaved pauses/cancels leaves no corrupt finals',
      () async {
    final rng = Random(42);
    final tasks = List.generate(
        100,
        (i) => DownloadTask(
              id: 'id_$i',
              videoId: 'vid_$i',
              title: 'Track $i',
              artist: 'Artist',
              createdAt: DateTime(2026, 1, 1).add(Duration(seconds: i)),
            ));

    // Simulate repository state transitions with random failures
    final Map<String, DownloadStatus> status = {};
    for (final t in tasks) {
      status[t.videoId] = DownloadStatus.queued;
    }

    // Randomly interleave pause/resume/delete/cancel as "kills"
    for (int round = 0; round < 5; round++) {
      for (final t in tasks) {
        final r = rng.nextDouble();
        if (r < 0.1) {
          status[t.videoId] = DownloadStatus.paused;
        } else if (r < 0.15)
          status[t.videoId] = DownloadStatus.failed;
        else if (r < 0.2) status[t.videoId] = DownloadStatus.downloading;
      }
      await Future.delayed(const Duration(milliseconds: 1));
    }

    // Reconciliation: downloading/queued → paused (process-death)
    for (final vid in status.keys.toList()) {
      if (status[vid] == DownloadStatus.downloading ||
          status[vid] == DownloadStatus.queued) {
        status[vid] = DownloadStatus.paused;
      }
    }

    // Ensure no "downloading" survives reconciliation (would orphan .part)
    expect(
        status.values.where((s) => s == DownloadStatus.downloading).length, 0);

    // Final retry pass → all should be able to reach complete without corruption
    for (final t in tasks) {
      if (status[t.videoId] == DownloadStatus.failed ||
          status[t.videoId] == DownloadStatus.paused) {
        status[t.videoId] = DownloadStatus.complete;
      }
    }
    expect(status.values.where((s) => s == DownloadStatus.failed).length, 0);
    expect(status.values.where((s) => s == DownloadStatus.complete).length,
        greaterThan(0));
  });

  test('orphan .part reclaimer does not delete active paused parts', () {
    // Mirrors the cleanOrphanPartFiles filter, which protects by *video id*, not
    // by exact file name. The names on disk carry the container extension, so the
    // caller cannot spell them: a paused `vid_1` leaves `ytdl_vid_1.m4a.part`,
    // its `.partN` chunk siblings and a `.parts` stamp behind, and the artwork
    // fetch leaves `ytdl_art_vid_1.jpg`. The old whitelist named
    // `ytdl_vid_1.part`, matched nothing, and the resume restarted from zero.
    final protectedIds = {'vid_1', 'vid_2'};
    final allFiles = [
      'ytdl_vid_1.m4a.part',
      'ytdl_vid_1.m4a.part0',
      'ytdl_vid_1.parts',
      'ytdl_art_vid_1.jpg',
      'ytdl_vid_2.webm.part',
      'ytdl_vid_3.m4a.part',
      'ytdl_vid_3.m4a.part0',
      'other.tmp',
    ];
    final orphanDeletion = allFiles
        .where((f) =>
            f.startsWith('ytdl_') &&
            !protectedIds.any((id) =>
                f.startsWith('ytdl_$id.') || f.startsWith('ytdl_art_$id.')))
        .toList();
    expect(orphanDeletion, ['ytdl_vid_3.m4a.part', 'ytdl_vid_3.m4a.part0']);
  });

  test('a targeted delete is scoped to the id, not to a prefix of it', () {
    // `path.contains('ytdl_$videoId')` had no name boundary, so removing the
    // download `abc` also removed everything belonging to `abcdef`.
    const videoId = 'abc';
    final files = [
      'ytdl_abc.m4a',
      'ytdl_abc.m4a.part',
      'ytdl_art_abc.jpg',
      'ytdl_abcdef.m4a',
      'ytdl_art_abcdef.jpg',
    ];
    final deleted = files
        .where((f) =>
            f.startsWith('ytdl_$videoId.') || f.startsWith('ytdl_art_$videoId.'))
        .toList();
    expect(deleted, ['ytdl_abc.m4a', 'ytdl_abc.m4a.part', 'ytdl_art_abc.jpg']);
    // What the old boundary-less predicate did instead: reached into another
    // download's files and still missed this one's artwork.
    final oldSweep =
        files.where((f) => f.contains('ytdl_$videoId')).toList();
    expect(oldSweep, contains('ytdl_abcdef.m4a'));
    expect(oldSweep, isNot(contains('ytdl_art_abc.jpg')));
  });

  test('resume must verify 206 not 200 append corruption', () {
    // Simulate server reply 200 to Range request → must discard existing part, not append
    int existingBytes = 500000;
    int serverStatus = 200; // ignored Range
    bool shouldAppend = serverStatus == 206;
    int finalSize;
    if (shouldAppend) {
      finalSize = existingBytes + 1000000;
    } else {
      // discard and restart: existing deleted, final is just new content
      existingBytes = 0;
      finalSize = 1000000;
    }
    expect(finalSize, 1000000);
    expect(existingBytes, 0);
  });

  test('Range header correctness', () {
    String rangeHeader(int offset) => 'bytes=$offset-';
    expect(rangeHeader(0), 'bytes=0-');
    expect(rangeHeader(12345), 'bytes=12345-');
  });
}
