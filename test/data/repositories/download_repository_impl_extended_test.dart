// test/data/repositories/download_repository_impl_extended_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/download_repository_impl.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtDownloadService extends Mock implements YtDownloadService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const downloadChannel = MethodChannel(PulsrChannels.ytDownload);

  late MockYtDownloadService service;
  late DownloadRepositoryImpl repo;
  final List<MethodCall> channelCalls = [];

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
    channelCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(downloadChannel, (call) async {
      channelCalls.add(call);
      switch (call.method) {
        case 'getFreeDiskSpace':
          return 100 * 1024 * 1024;
        default:
          return null;
      }
    });

    service = MockYtDownloadService();
    when(() => service.setMaxConcurrentDownloads(any())).thenReturn(null);
    when(() => service.downloadPolicyBlock()).thenAnswer((_) async => null);
    when(() => service.markPaused(any())).thenReturn(null);
    when(() => service.clearPaused(any())).thenReturn(null);
    when(() => service.cancel(any())).thenReturn(null);
    when(() => service.deleteArtifactsFor(any())).thenAnswer((_) async {});
    when(() => service.cleanOrphanPartFiles(
        protectedVideoIds: any(named: 'protectedVideoIds'))).thenAnswer(
        (_) async {});
    when(() => service.getDownloadedPath(any())).thenReturn(null);
    repo = DownloadRepositoryImpl(service);
  });

  tearDown(() async {
    await repo.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(downloadChannel, null);
  });

  DownloadTask task(String videoId, {String? title}) => DownloadTask(
        id: videoId,
        videoId: videoId,
        title: title ?? 'Song $videoId',
        artist: 'Artist',
        createdAt: DateTime(2026, 1, 1),
      );

  group('pause / resume / retry / delete', () {
    test('pauseDownload on an unknown task returns a failure', () async {
      final res = await repo.pauseDownload('missing00000');
      expect(res.isLeft(), isTrue);
    });

    test('resumeDownload on an unknown task returns a failure', () async {
      final res = await repo.resumeDownload('missing00000');
      expect(res.isLeft(), isTrue);
    });

    test('retryDownload on an unknown task returns a failure', () async {
      final res = await repo.retryDownload('missing00000');
      expect(res.isLeft(), isTrue);
    });

    test('pauseDownload marks the native pause and updates status', () async {
      SharedPreferences.setMockInitialValues({
        'pulsr_download_tasks_v2': jsonEncode([
          task('abcdefghijk').toJson(),
        ]),
      });
      await repo.reconcileOnBoot();

      final res = await repo.pauseDownload('abcdefghijk');
      expect(res.isRight(), isTrue);
      verify(() => service.markPaused('abcdefghijk')).called(1);
      final tasks = await repo.getAllDownloads();
      expect(tasks.single.status, DownloadStatus.paused);
      expect(
          channelCalls
              .where((c) => c.method == 'setDownloadPaused')
              .map((c) => c.arguments['paused']),
          contains(true));
    });

    test('deleteDownload removes the task and clears its artifacts',
        () async {
      final temp = Directory.systemTemp.createTempSync('dl_delete');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}${Platform.pathSeparator}done.m4a')
        ..writeAsStringSync('audio');

      SharedPreferences.setMockInitialValues({
        'pulsr_download_tasks_v2': jsonEncode([
          task('abcdefghijk').copyWith(
              status: DownloadStatus.complete, filePath: file.path).toJson(),
        ]),
      });
      when(() => service.getDownloadedPath(any())).thenReturn(file.path);
      await repo.reconcileOnBoot();

      final res = await repo.deleteDownload('abcdefghijk');
      expect(res.isRight(), isTrue);
      verify(() => service.deleteArtifactsFor('abcdefghijk')).called(1);
      verify(() => service.clearPaused('abcdefghijk')).called(1);
      expect(file.existsSync(), isFalse);
      expect(await repo.getAllDownloads(), isEmpty);
    });
  });

  group('queueDownload edge cases', () {
    test('storage preflight rejects when free space is too low', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(downloadChannel, (call) async {
        if (call.method == 'getFreeDiskSpace') return 1024;
        return null;
      });

      final res = await repo.queueDownload(task('abcdefghijk'));
      expect(res.isLeft(), isTrue);
      expect(res.getLeft().toNullable(), isA<StorageFailure>());
      verifyNever(
          () => service.download(any(), onProgress: any(named: 'onProgress')));
    });

    test('re-queues a complete task only after its file disappears', () async {
      final temp = Directory.systemTemp.createTempSync('dl_complete');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}${Platform.pathSeparator}done.m4a')
        ..writeAsStringSync('audio');
      when(() => service.getDownloadedPath(any())).thenReturn(file.path);
      var downloadCalls = 0;
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async {
        downloadCalls++;
        return const Right(77);
      });

      await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final first = await repo.getAllDownloads();
      expect(first.single.status, DownloadStatus.complete);

      // File still present: dedupes without a second transfer.
      final again = await repo.queueDownload(task('abcdefghijk'));
      expect(again.isRight(), isTrue);
      expect(downloadCalls, 1);

      // File removed: allows a re-download.
      file.deleteSync();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await file.exists(), isFalse);
      await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(downloadCalls, 2);
    });
  });

  group('progress stage mapping', () {
    test('broadcasts every stage mapping', () async {
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((invocation) async {
        final onProgress = invocation.namedArguments[const Symbol('onProgress')]
            as void Function(YtDownloadProgress)?;
        onProgress?.call(const YtDownloadProgress(YtDownloadStage.queued));
        onProgress?.call(const YtDownloadProgress(YtDownloadStage.resolving));
        onProgress
            ?.call(const YtDownloadProgress(YtDownloadStage.downloading, 0.3));
        onProgress?.call(const YtDownloadProgress(YtDownloadStage.saving));
        onProgress?.call(const YtDownloadProgress(YtDownloadStage.indexing));
        onProgress?.call(const YtDownloadProgress(YtDownloadStage.done));
        onProgress?.call(const YtDownloadProgress(YtDownloadStage.canceled));
        return const Right(9);
      });

      final events = <DownloadTask>[];
      final sub = repo.observeDownloads().listen(events.add);
      await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(events.any((t) => t.status == DownloadStatus.queued), isTrue);
      expect(events.any((t) => t.status == DownloadStatus.tagging), isTrue);
      expect(events.any((t) => t.status == DownloadStatus.complete), isTrue);
      await sub.cancel();
    });

    test('retries a transient failure then succeeds', () async {
      var calls = 0;
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          return const Left(DownloadFailure('HTTP 429 Rate limited'));
        }
        return const Right(11);
      });

      await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(calls, 2);
      final tasks = await repo.getAllDownloads();
      expect(tasks.single.status, DownloadStatus.complete);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a permanent failure stops retrying', () async {
      var calls = 0;
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async {
        calls++;
        return const Left(DownloadFailure('Video unavailable'));
      });

      await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, 1);
      final tasks = await repo.getAllDownloads();
      expect(tasks.single.status, DownloadStatus.failed);
    });
  });

  group('storage stats', () {
    test('caches results within the TTL', () async {
      final first = await repo.getStorageStats();
      expect(first.isRight(), isTrue);
      final second = await repo.getStorageStats();
      expect(second.isRight(), isTrue);
      expect(
          channelCalls.where((c) => c.method == 'getFreeDiskSpace').length, 1);
    });

    test('aggregates completed file sizes', () async {
      final temp = Directory.systemTemp.createTempSync('dl_stats');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}${Platform.pathSeparator}stat.m4a')
        ..writeAsStringSync('0123456789');
      when(() => service.getDownloadedPath(any())).thenReturn(file.path);
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const Right(5));

      await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final stats = (await repo.getStorageStats()).getOrElse(
          (_) => throw StateError('failed'));
      expect(stats.downloadedSongsCount, 1);
      expect(stats.usedBytes, 10);
      expect(stats.freeBytes, 100 * 1024 * 1024);
    });
  });

  group('reconcileOnBoot', () {
    test('restores queued tasks as paused and keeps complete ones with files',
        () async {
      final temp = Directory.systemTemp.createTempSync('dl_boot');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}${Platform.pathSeparator}keep.m4a')
        ..writeAsStringSync('audio');

      SharedPreferences.setMockInitialValues({
        'pulsr_download_tasks_v2': jsonEncode([
          task('queuedtask1').toJson(),
          task('completetask').copyWith(
              status: DownloadStatus.complete, filePath: file.path).toJson(),
          task('failedtask')
              .copyWith(status: DownloadStatus.failed)
              .toJson(),
        ]),
      });

      await repo.reconcileOnBoot();
      final tasks = await repo.getAllDownloads();
      expect(tasks.length, 3);
      expect(
          tasks.firstWhere((t) => t.videoId == 'queuedtask1').status,
          DownloadStatus.paused);
      expect(
          tasks.firstWhere((t) => t.videoId == 'completetask').status,
          DownloadStatus.complete);
      expect(
          tasks.firstWhere((t) => t.videoId == 'failedtask').status,
          DownloadStatus.failed);
      verify(() => service.cleanOrphanPartFiles(
          protectedVideoIds: any(named: 'protectedVideoIds'))).called(1);
    });

    test('marks a complete task as failed when the file is gone', () async {
      SharedPreferences.setMockInitialValues({
        'pulsr_download_tasks_v2': jsonEncode([
          task('gonetask').copyWith(
              status: DownloadStatus.complete,
              filePath: '/definitely/not/here.m4a').toJson(),
        ]),
      });
      await repo.reconcileOnBoot();
      final tasks = await repo.getAllDownloads();
      expect(tasks.single.status, DownloadStatus.failed);
      expect(tasks.single.error, 'File deleted');
    });

    test('ignores empty stored json and recovers from corrupt json', () async {
      SharedPreferences.setMockInitialValues({
        'pulsr_download_tasks_v2': '',
      });
      await repo.reconcileOnBoot();
      expect(await repo.getAllDownloads(), isEmpty);

      SharedPreferences.setMockInitialValues({
        'pulsr_download_tasks_v2': 'not-json',
      });
      final second = DownloadRepositoryImpl(service);
      await second.reconcileOnBoot();
      expect(await second.getAllDownloads(), isEmpty);
      await second.dispose();
    });
  });
}
