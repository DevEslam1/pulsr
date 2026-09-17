import 'dart:async';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });

  late MockYtDownloadService service;
  late DownloadRepositoryImpl repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = MockYtDownloadService();
    when(() => service.setMaxConcurrentDownloads(any())).thenReturn(null);
    when(() => service.downloadPolicyBlock())
        .thenAnswer((_) async => null);
    repo = DownloadRepositoryImpl(service);
  });

  tearDown(() => repo.dispose());

  DownloadTask task(String videoId, {String? title}) => DownloadTask(
        id: videoId,
        videoId: videoId,
        title: title ?? 'Song $videoId',
        artist: 'Artist',
        createdAt: DateTime(2026, 1, 1),
      );

  test('rejects a malformed video id', () async {
    final result = await repo.queueDownload(task('short'));
    expect(result.isLeft(), isTrue);
    verifyNever(() => service.download(any(), onProgress: any(named: 'onProgress')));
  });

  test('dedupes a task that is already queued', () async {
    final completer = Completer<Result<int>>();
    when(() => service.download(any(), onProgress: any(named: 'onProgress')))
        .thenAnswer((_) => completer.future);

    final first = await repo.queueDownload(task('abcdefghijk'));
    final second = await repo.queueDownload(task('abcdefghijk'));

    expect(first.isRight(), isTrue);
    expect(second.isRight(), isTrue);
    expect(first.getOrElse((_) => ''), second.getOrElse((_) => ''));
    verify(() => service.download(any(), onProgress: any(named: 'onProgress')))
        .called(1);
    completer.complete(const Left(DownloadFailure('done')));
    await Future.delayed(Duration.zero);
  });

  test('refuses to queue when the network policy blocks downloads', () async {
    when(() => service.downloadPolicyBlock()).thenAnswer(
        (_) async => const DownloadFailure('Wi-Fi Only Mode is active.'));

    final result = await repo.queueDownload(task('abcdefghijk'));

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable()?.message, contains('Wi-Fi'));
    verifyNever(
        () => service.download(any(), onProgress: any(named: 'onProgress')));
  });

  test('honours maxConcurrent from DownloadSettings', () async {
    SharedPreferences.setMockInitialValues(
        {'setting_download_max_concurrent': 2});
    final completers = <Completer<Result<int>>>[];
    when(() => service.download(any(), onProgress: any(named: 'onProgress')))
        .thenAnswer((_) {
      final c = Completer<Result<int>>();
      completers.add(c);
      return c.future;
    });

    await repo.queueDownload(task('aaaaaaaaaaa'));
    await repo.queueDownload(task('bbbbbbbbbbb'));
    await repo.queueDownload(task('ccccccccccc'));
    await repo.queueDownload(task('ddddddddddd'));

    // Only two transfers may be in flight; the rest wait in the queue.
    expect(completers.length, 2);
    verify(() => service.setMaxConcurrentDownloads(2)).called(greaterThan(0));

    completers.first.complete(const Right(1));
    await Future.delayed(Duration.zero);
    await Future.delayed(Duration.zero);
    expect(completers.length, 3);

    for (final c in completers) {
      if (!c.isCompleted) c.complete(const Left(DownloadFailure('done')));
    }
  });

  test('maps tagging stage and records the reconciled local id', () async {
    when(() => service.download(any(), onProgress: any(named: 'onProgress')))
        .thenAnswer((invocation) async {
      final onProgress = invocation.namedArguments[const Symbol('onProgress')]
          as void Function(YtDownloadProgress)?;
      onProgress?.call(
          const YtDownloadProgress(YtDownloadStage.downloading, 0.4));
      onProgress?.call(const YtDownloadProgress(YtDownloadStage.tagging));
      return const Right(501);
    });

    final events = <DownloadTask>[];
    final sub = repo.observeDownloads().listen(events.add);

    await repo.queueDownload(task('abcdefghijk'));
    await Future.delayed(const Duration(milliseconds: 20));

    expect(events.any((t) => t.status == DownloadStatus.tagging), isTrue);
    final last = events.lastWhere((t) => t.status == DownloadStatus.complete,
        orElse: () => throw StateError('no completion emitted'));
    expect(last.localSongId, 501);
    expect(last.sourceSongId, isNull); // caller did not provide one

    await sub.cancel();
  });

  test('persists tasks across a reload of the preference store', () async {
    when(() => service.download(any(), onProgress: any(named: 'onProgress')))
        .thenAnswer((invocation) async {
      final onProgress = invocation.namedArguments[const Symbol('onProgress')]
          as void Function(YtDownloadProgress)?;
      onProgress?.call(const YtDownloadProgress(YtDownloadStage.downloading, 1));
      return const Right(9);
    });

    await repo.queueDownload(task('abcdefghijk'));
    // Terminal states flush immediately; give the microtask a beat.
    await Future.delayed(const Duration(milliseconds: 50));

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pulsr_download_tasks_v2');
    expect(raw, isNotNull);
    expect(raw, contains('abcdefghijk'));
    expect(raw, contains('"status":"complete"'));
  });
}
