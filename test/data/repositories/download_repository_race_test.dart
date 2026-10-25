// test/data/repositories/download_repository_race_test.dart
import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/download_repository_impl.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtDownloadService extends Mock implements YtDownloadService {}

/// Delays every SELECT so the completion branch's DB read stays in flight long
/// enough for a delete to land inside the window deterministically.
class _SlowSelectInterceptor extends QueryInterceptor {
  _SlowSelectInterceptor(this.delay);

  final Duration delay;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await Future<void>.delayed(delay);
    return executor.runSelect(statement, args);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockYtDownloadService service;
  late AppDatabase db;
  late DownloadRepositoryImpl repo;

  setUpAll(() {
    registerFallbackValue(const SongsTableData(
      id: -42,
      title: 'Fallback',
      artist: 'Fallback',
      album: '',
      path: 'ytmusic://fallbackVid1',
      source: SongSource.youtube,
      remoteId: 'fallbackVid1',
      durationMs: 1000,
      isFavorite: false,
      playCount: 0,
      lastPositionMs: 0,
      isMissing: false,
      isDownloaded: false,
    ));
    registerFallbackValue(<String>{});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = MockYtDownloadService();
    when(() => service.setMaxConcurrentDownloads(any())).thenReturn(null);
    when(() => service.downloadPolicyBlock()).thenAnswer((_) async => null);
    when(() => service.markPaused(any())).thenReturn(null);
    when(() => service.clearPaused(any())).thenReturn(null);
    when(() => service.cancel(any())).thenReturn(null);
    when(() => service.deleteArtifactsFor(any())).thenAnswer((_) async {});
    when(() => service.cleanOrphanPartFiles(
            protectedVideoIds: any(named: 'protectedVideoIds')))
        .thenAnswer((_) async {});
    when(() => service.getDownloadedPath(any())).thenReturn(null);
    db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(
        _SlowSelectInterceptor(const Duration(milliseconds: 120))));
    repo = DownloadRepositoryImpl(service, db);
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  DownloadTask task(String videoId) => DownloadTask(
        id: videoId,
        videoId: videoId,
        title: 'Song $videoId',
        artist: 'Artist',
        createdAt: DateTime(2026, 1, 1),
      );

  group('delete vs completion race', () {
    test('a delete during the completion DB read is not undone', () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: const Value(7),
              title: 'Done',
              path: 'Z:/pulsr/does-not-exist/race.m4a',
            ),
          );

      final download = Completer<Result<int>>();
      when(() => service.download(any(),
              bypassInternalQueue: any(named: 'bypassInternalQueue'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) => download.future);

      expect((await repo.queueDownload(task('abcdefghijk'))).isRight(), isTrue);

      final deleteFuture = repo.deleteDownload('abcdefghijk');
      download.complete(const Right(7));
      await deleteFuture;
      // Let the delayed completion read and any reconcile settle.
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(await repo.getAllDownloads(), isEmpty,
          reason: 'the completed task must stay deleted');
    });

    test('a progress tick after delete does not resurrect the task', () async {
      void Function(YtDownloadProgress)? onProgress;
      final download = Completer<Result<int>>();
      when(() => service.download(any(),
          bypassInternalQueue: any(named: 'bypassInternalQueue'),
          onProgress: any(named: 'onProgress'))).thenAnswer((invocation) {
        onProgress = invocation.namedArguments[const Symbol('onProgress')]
            as void Function(YtDownloadProgress)?;
        return download.future;
      });

      await repo.queueDownload(task('abcdefghijk'));
      final deleteFuture = repo.deleteDownload('abcdefghijk');
      download.complete(const Left(DownloadFailure('Video unavailable')));
      await deleteFuture;

      onProgress
          ?.call(const YtDownloadProgress(YtDownloadStage.downloading, 0.5));
      await Future<void>.delayed(Duration.zero);

      expect(await repo.getAllDownloads(), isEmpty,
          reason: 'late progress must not resurrect a deleted task');
    });
  });

  group('stale failure/speed/eta text', () {
    test('completion clears error, speed and eta', () async {
      when(() => service.download(any(),
          bypassInternalQueue: any(named: 'bypassInternalQueue'),
          onProgress: any(named: 'onProgress'))).thenAnswer((invocation) async {
        final onProgress = invocation.namedArguments[const Symbol('onProgress')]
            as void Function(YtDownloadProgress)?;
        onProgress?.call(const YtDownloadProgress(
            YtDownloadStage.downloading, 0.5, 128.0, 42));
        return const Right(3);
      });

      await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final t = (await repo.getAllDownloads()).single;
      expect(t.status, DownloadStatus.complete);
      expect(t.progress, 1.0);
      expect(t.error, isNull);
      expect(t.speedKbps, isNull);
      expect(t.etaSeconds, isNull);
    });

    test('failure clears stale speed and eta', () async {
      when(() => service.download(any(),
          bypassInternalQueue: any(named: 'bypassInternalQueue'),
          onProgress: any(named: 'onProgress'))).thenAnswer((invocation) async {
        final onProgress = invocation.namedArguments[const Symbol('onProgress')]
            as void Function(YtDownloadProgress)?;
        onProgress?.call(const YtDownloadProgress(
            YtDownloadStage.downloading, 0.5, 99.0, 12));
        return const Left(DownloadFailure('Video unavailable'));
      });

      await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final t = (await repo.getAllDownloads()).single;
      expect(t.status, DownloadStatus.failed);
      expect(t.error, 'Video unavailable');
      expect(t.speedKbps, isNull);
      expect(t.etaSeconds, isNull);
    });

    test('retry clears the previous failure, speed and eta', () async {
      var calls = 0;
      final pending = Completer<Result<int>>();
      when(() => service.download(any(),
          bypassInternalQueue: any(named: 'bypassInternalQueue'),
          onProgress: any(named: 'onProgress'))).thenAnswer((invocation) {
        calls++;
        if (calls == 1) {
          final onProgress =
              invocation.namedArguments[const Symbol('onProgress')] as void
                  Function(YtDownloadProgress)?;
          onProgress?.call(const YtDownloadProgress(
              YtDownloadStage.downloading, 0.5, 77.0, 9));
          return Future.value(const Left(DownloadFailure('Video unavailable')));
        }
        return pending.future;
      });

      await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect((await repo.getAllDownloads()).single.error, 'Video unavailable');

      final retry = await repo.retryDownload('abcdefghijk');
      expect(retry.isRight(), isTrue);

      final t = (await repo.getAllDownloads()).single;
      expect(t.status, DownloadStatus.downloading);
      expect(t.error, isNull);
      expect(t.speedKbps, isNull);
      expect(t.etaSeconds, isNull);

      pending.complete(const Left(DownloadFailure('Video unavailable')));
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('DownloadTask.copyWith clear flags', () {
    test('clearError/clearSpeedKbps/clearEtaSeconds reset the fields', () {
      final t = DownloadTask(
        id: 'abcdefghijk',
        videoId: 'abcdefghijk',
        title: 'Song',
        artist: 'Artist',
        error: 'boom',
        speedKbps: 128.0,
        etaSeconds: 42,
        createdAt: DateTime(2026, 1, 1),
      );

      final cleared = t.copyWith(
        clearError: true,
        clearSpeedKbps: true,
        clearEtaSeconds: true,
      );
      expect(cleared.error, isNull);
      expect(cleared.speedKbps, isNull);
      expect(cleared.etaSeconds, isNull);

      final kept = t.copyWith(status: DownloadStatus.queued);
      expect(kept.error, 'boom');
      expect(kept.speedKbps, 128.0);
      expect(kept.etaSeconds, 42);
    });
  });
}
