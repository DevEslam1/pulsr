// test/data/repositories/download_repository_more_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
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

class FakeSongsTableData extends Fake implements SongsTableData {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const downloadChannel = MethodChannel(PulsrChannels.ytDownload);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MockYtDownloadService service;
  late AppDatabase? db;
  late DownloadRepositoryImpl repo;

  setUpAll(() {
    registerFallbackValue(<String>{});
    registerFallbackValue(FakeSongsTableData());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(downloadChannel, (call) async {
      if (call.method == 'getFreeDiskSpace') return 100 * 1024 * 1024;
      return null;
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
    db = null;
    repo = DownloadRepositoryImpl(service);
  });

  tearDown(() async {
    await repo.dispose();
    await db?.close();
    messenger.setMockMethodCallHandler(downloadChannel, null);
  });

  DownloadTask task(String videoId,
          {DownloadStatus status = DownloadStatus.queued,
          String? filePath,
          int? fileSize,
          int? localSongId}) =>
      DownloadTask(
        id: videoId,
        videoId: videoId,
        title: 'Song $videoId',
        artist: 'Artist',
        status: status,
        filePath: filePath,
        fileSize: fileSize,
        localSongId: localSongId,
        createdAt: DateTime(2026, 1, 1),
      );

  Future<void> seed(List<DownloadTask> tasks) async {
    SharedPreferences.setMockInitialValues({
      'pulsr_download_tasks_v2': jsonEncode(tasks.map((t) => t.toJson()).toList()),
    });
    await repo.reconcileOnBoot();
  }

  Future<void> sendNative(String method, Object? args) async {
    await messenger.handlePlatformMessage(
      PulsrChannels.ytDownload,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  group('native download callbacks', () {
    test('onDownloadPaused pauses a known task and syncs the notification',
        () async {
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) => Completer<Result<int>>().future);
      await seed([task('abcdefghijk')]);

      await sendNative('onDownloadPaused', {'videoId': 'abcdefghijk'});

      final tasks = await repo.getAllDownloads();
      expect(tasks.single.status, DownloadStatus.paused);
      verify(() => service.markPaused('abcdefghijk')).called(1);
    });

    test('onDownloadResumed requeues a paused task', () async {
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const Right(3));
      await seed([task('abcdefghijk', status: DownloadStatus.paused)]);

      await sendNative('onDownloadResumed', {'videoId': 'abcdefghijk'});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      verify(() => service.clearPaused('abcdefghijk')).called(1);
    });

    test('onDownloadCancelled deletes a task', () async {
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) => Completer<Result<int>>().future);
      await seed([task('abcdefghijk')]);

      await sendNative('onDownloadCancelled', {'videoId': 'abcdefghijk'});

      expect(await repo.getAllDownloads(), isEmpty);
      verify(() => service.clearPaused('abcdefghijk')).called(1);
    });

    test('ignores callbacks with empty or non-map arguments', () async {
      await sendNative('onDownloadPaused', {'videoId': ''});
      await sendNative('onDownloadPaused', 'not-a-map');
      await sendNative('onDownloadPaused', null);
      await sendNative('somethingElse', {'videoId': 'abcdefghijk'});
    });

    test('onDownloadServiceDegraded is logged without side effects', () async {
      await sendNative('onDownloadServiceDegraded', {'stage': 'doze'});
      await sendNative('onDownloadServiceDegraded', null);
    });
  });

  group('queueDownload storage preflight', () {
    test('proceeds when free space is unknown (zero)', () async {
      messenger.setMockMethodCallHandler(downloadChannel, (call) async {
        if (call.method == 'getFreeDiskSpace') return 0;
        return null;
      });
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const Right(1));

      final res = await repo.queueDownload(task('abcdefghijk'));
      expect(res.isRight(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      verify(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .called(1);
    });

    test('proceeds when the disk-space channel throws', () async {
      messenger.setMockMethodCallHandler(downloadChannel, (call) async {
        if (call.method == 'getFreeDiskSpace') {
          throw PlatformException(code: 'NO_CHANNEL');
        }
        return null;
      });
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const Right(1));

      expect((await repo.queueDownload(task('abcdefghijk'))).isRight(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      verify(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .called(1);
    });

    test('dedupes a task that is actively downloading', () async {
      final completer = Completer<Result<int>>();
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) => completer.future);

      final first = await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final second = await repo.queueDownload(task('abcdefghijk'));

      expect(first.isRight(), isTrue);
      expect(second.isRight(), isTrue);
      verify(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .called(1);
      completer.complete(const Left(DownloadFailure('done')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });

    test('a complete task with no file path is re-downloaded', () async {
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const Right(1));
      await seed([task('abcdefghijk', status: DownloadStatus.complete)]);

      await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      verify(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .called(1);
    });
  });

  group('retry / delete', () {
    test('retryDownload turns a failed task back into a transfer', () async {
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const Right(7));
      await seed([task('abcdefghijk', status: DownloadStatus.failed)]);

      final res = await repo.retryDownload('abcdefghijk');
      expect(res.isRight(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final done = (await repo.getAllDownloads()).single;
      expect(done.status, DownloadStatus.complete);
    });

    test('deleteDownload cancels an in-flight transfer', () async {
      final completer = Completer<Result<int>>();
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) => completer.future);

      await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final del = repo.deleteDownload('abcdefghijk');
      completer.complete(const Left(DownloadFailure('cancel')));
      final res = await del;

      expect(res.isRight(), isTrue);
      expect(await repo.getAllDownloads(), isEmpty);
      verify(() => service.cancel('abcdefghijk')).called(1);
    });
  });

  group('reconcileOnBoot metadata', () {
    test('resolves file metadata from the local song row', () async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db!.into(db!.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(42),
            title: 'Downloaded',
            path: '/music/dl.m4a',
            fileSize: const Value(5000),
          ));
      repo = DownloadRepositoryImpl(service, db);

      await seed([
        task('abcdefghijk',
            status: DownloadStatus.complete, localSongId: 42),
      ]);

      final restored = (await repo.getAllDownloads()).single;
      expect(restored.filePath, '/music/dl.m4a');
      expect(restored.fileSize, 5000);
    });

    test('derives the size from disk when the row has none', () async {
      final temp = Directory.systemTemp.createTempSync('dl_boot_size');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}${Platform.pathSeparator}dl.m4a')
        ..writeAsStringSync('12345678');

      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db!.into(db!.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(43),
            title: 'Downloaded',
            path: file.path,
          ));
      repo = DownloadRepositoryImpl(service, db);

      await seed([
        task('abcdefghijk',
            status: DownloadStatus.complete, localSongId: 43),
      ]);

      final restored = (await repo.getAllDownloads()).single;
      expect(restored.fileSize, 8);
    });

    test('restores queued and tagging tasks as paused', () async {
      await seed([
        task('queuedtask1'),
        task('taggingtask', status: DownloadStatus.tagging),
        task('failedtask', status: DownloadStatus.failed),
      ]);

      final byId = {for (final t in await repo.getAllDownloads()) t.videoId: t};
      expect(byId['queuedtask1']!.status, DownloadStatus.paused);
      expect(byId['taggingtask']!.status, DownloadStatus.paused);
      expect(byId['failedtask']!.status, DownloadStatus.failed);
    });
  });

  group('storage stats', () {
    test('falls back to the local song row size', () async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DownloadRepositoryImpl(service, db);
      when(() => service.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const Right(42));

      await repo.queueDownload(task('abcdefghijk'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // No path is recorded for the completed task, so the size can only come
      // from the library row once it appears.
      final completed = (await repo.getAllDownloads()).single;
      expect(completed.status, DownloadStatus.complete);
      expect(completed.localSongId, 42);

      await db!.into(db!.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(42),
            title: 'Downloaded',
            path: '/music/not-on-disk.m4a',
            fileSize: const Value(4096),
          ));

      final stats = (await repo.getStorageStats()).getOrElse(
          (_) => throw StateError('failed'));
      expect(stats.usedBytes, 4096);
      expect(stats.downloadedSongsCount, 1);
    });

    test('measures an existing file when the recorded size is missing',
        () async {
      final temp = Directory.systemTemp.createTempSync('dl_stats_more');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}${Platform.pathSeparator}stat.m4a')
        ..writeAsStringSync('0123456789');

      await seed([
        task('abcdefghijk', status: DownloadStatus.complete, filePath: file.path),
      ]);
      // reconcileOnBoot keeps fileSize null because there is no localSongId.

      final stats = (await repo.getStorageStats()).getOrElse(
          (_) => throw StateError('failed'));
      expect(stats.usedBytes, 10);
      final stored = (await repo.getAllDownloads()).single;
      expect(stored.fileSize, 10);
    });

    test('a total of zero is normalised to one byte', () async {
      messenger.setMockMethodCallHandler(downloadChannel, (call) async {
        if (call.method == 'getFreeDiskSpace') return 0;
        return null;
      });
      final stats = (await repo.getStorageStats()).getOrElse(
          (_) => throw StateError('failed'));
      expect(stats.totalBytes, 1);
      expect(stats.usedPercentage, 0.0);
    });

    test('a failing disk-space channel still yields stats', () async {
      messenger.setMockMethodCallHandler(downloadChannel, (call) async {
        if (call.method == 'getFreeDiskSpace') {
          throw PlatformException(code: 'NO_CHANNEL');
        }
        return null;
      });
      final res = await repo.getStorageStats();
      expect(res.isRight(), isTrue);
    });
  });

  test('dispose is idempotent and flushes state', () async {
    await repo.dispose();
    await repo.dispose();
  });
}
