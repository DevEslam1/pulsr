// test/core/services/yt_download_regression_fixes_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/yt_download_artifact_store.dart';
import 'package:pulsr/core/services/yt_download_file_naming.dart';
import 'package:pulsr/core/services/yt_download_foreground_controller.dart';
import 'package:pulsr/core/services/yt_download_http_support.dart';
import 'package:pulsr/core/services/yt_download_pause_registry.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/core/services/yt_download_transfer_math.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockYtmService extends Mock implements YtmService {}

class _MockMediaScanner extends Mock implements MediaScannerService {}

class _MockMusicRepo extends Mock implements IMusicRepository {}

const _downloadChannel = MethodChannel(PulsrChannels.ytDownload);
const _tagChannel = MethodChannel(PulsrChannels.tagEditor);
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

class _FakeHeaders implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse({
    required this.statusCode,
    this.body = const [],
    this.fixedContentLength,
    this.bodyStream,
    Map<String, String> headers = const {},
  }) {
    responseHeaders.values.addAll(headers);
  }

  @override
  final int statusCode;
  final List<int> body;
  final int? fixedContentLength;
  final Stream<List<int>>? bodyStream;
  final _FakeHeaders responseHeaders = _FakeHeaders();

  @override
  int get contentLength => fixedContentLength ?? body.length;

  @override
  HttpHeaders get headers => responseHeaders;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      (bodyStream ?? Stream<List<int>>.value(body)).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.uri, this._onClose);

  @override
  final Uri uri;
  @override
  final _FakeHeaders headers = _FakeHeaders();
  final Future<_FakeResponse> Function(_FakeRequest) _onClose;
  bool aborted = false;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborted = true;
  }

  @override
  Future<HttpClientResponse> close() => _onClose(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeClient implements HttpClient {
  _FakeClient(this.handler);

  final Future<_FakeResponse> Function(_FakeRequest) handler;
  final List<_FakeRequest> requests = [];

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final req = _FakeRequest(url, handler);
    requests.add(req);
    return req;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<int> _m4aBody(int size) {
  final bytes = Uint8List(size);
  if (size >= 12) {
    bytes[4] = 0x66;
    bytes[5] = 0x74;
    bytes[6] = 0x79;
    bytes[7] = 0x70;
    bytes[8] = 0x4D;
    bytes[9] = 0x34;
    bytes[10] = 0x41;
    bytes[11] = 0x20;
  }
  return bytes;
}

SongsTableData _song({
  String videoId = 'vidReg00001',
  String? artworkUrl,
}) =>
    YtmTrack(
      videoId: videoId,
      title: 'Reg Track',
      artist: 'Reg Artist',
      duration: const Duration(minutes: 1),
      artworkUrl: artworkUrl,
    ).toSongData();

YtmStream _stream({String videoId = 'vidReg00001'}) => YtmStream(
      videoId: videoId,
      url: 'https://rr1---sn.googlevideo.com/videoplayback?expire=1900000000',
      mimeType: 'audio/mp4',
      container: 'm4a',
      bitrateKbps: 128,
      duration: const Duration(minutes: 1),
      title: 'Reg Track',
      artist: 'Reg Artist',
      userAgent: 'TestAgent/1.0',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_downloadChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_tagChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await getIt.reset();
  });

  group('C-05 Foreground lifecycle & releaseDownloadJob', () {
    test('release invokes releaseDownloadJob without progress: 100', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_downloadChannel, (call) async {
        calls.add(call);
        return true;
      });

      final controller = YtDownloadForegroundController();
      controller.start('vid1', 'Track');
      controller.release('vid1');
      await Future<void>.delayed(Duration.zero);

      final releaseCall =
          calls.firstWhere((c) => c.method == 'releaseDownloadJob');
      expect((releaseCall.arguments as Map)['videoId'], 'vid1');
      expect(
        calls.where((c) =>
            c.method == 'updateDownloadProgress' &&
            (c.arguments as Map)['progress'] == 100),
        isEmpty,
      );
    });

    test('queued download canceled before slot runs never starts foreground',
        () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = Directory.systemTemp.createTempSync('ytdl_c05_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final fgCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathChannel, (_) async => tempDir.path);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_downloadChannel, (call) async {
        fgCalls.add(call.method);
        if (call.method == 'getFreeDiskSpace') return 500 * 1024 * 1024;
        if (call.method == 'saveToMusic') {
          return p.join(tempDir.path, 'out.m4a');
        }
        return true;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_tagChannel, (_) async => true);

      final blockFirst = StreamController<List<int>>();
      final client = _FakeClient((req) async {
        if (req.headers.values['range'] == 'bytes=0-0') {
          return _FakeResponse(statusCode: 200, fixedContentLength: 2048);
        }
        return _FakeResponse(
          statusCode: 200,
          fixedContentLength: 2048,
          bodyStream: blockFirst.stream,
        );
      });
      final ytm = _MockYtmService();
      when(() => ytm.ensurePoTokenReady()).thenAnswer((_) async => true);
      when(() => ytm.isWifiConnected()).thenAnswer((_) async => true);
      when(() => ytm.isBotCoolingDown).thenReturn(false);
      when(() => ytm.resolveStream(
            any(),
            quality: any(named: 'quality'),
            forceRefresh: any(named: 'forceRefresh'),
            preferM4a: any(named: 'preferM4a'),
            title: any(named: 'title'),
            artist: any(named: 'artist'),
          )).thenAnswer((inv) async =>
          _stream(videoId: inv.positionalArguments.first as String));
      final repo = _MockMusicRepo();
      when(() => repo.reconcileDownloadedSong(
            oldId: any(named: 'oldId'),
            newPath: any(named: 'newPath'),
            fallbackSong: any(named: 'fallbackSong'),
          )).thenAnswer((_) async => const Right<AppFailure, int?>(1));

      final service =
          YtDownloadService(client, ytm, _MockMediaScanner(), repo);
      addTearDown(service.dispose);
      service.setMaxConcurrentDownloads(1);

      final firstStarted = Completer<void>();
      final first = service.download(
        _song(videoId: 'vidBusy0001'),
        onProgress: (prog) {
          if (prog.stage == YtDownloadStage.downloading &&
              !firstStarted.isCompleted) {
            firstStarted.complete();
          }
        },
      );
      await firstStarted.future;
      fgCalls.clear();

      // Queue second while slot is occupied, wait until it is officially queued,
      // then cancel before it ever starts executing.
      final secondQueued = Completer<void>();
      final second = service.download(
        _song(videoId: 'vidQueue002'),
        onProgress: (prog) {
          if (prog.stage == YtDownloadStage.queued && !secondQueued.isCompleted) {
            secondQueued.complete();
          }
        },
      );
      await secondQueued.future;
      service.cancel('vidQueue002');
      expect(await second, isA<Left<AppFailure, int>>());
      expect(fgCalls.contains('startDownloadForeground'), isFalse);

      blockFirst.add(_m4aBody(2048));
      await blockFirst.close();
      expect((await first).isRight(), isTrue);
    });
  });

  group('C-06 Per-run generation & artwork isolation', () {
    test('winding-down artwork from canceled run A never deletes run B art',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('ytdl_c06_art_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final delayedArtCompleter = Completer<String?>();
      final runAArt = File(p.join(tempDir.path, 'ytdl_art_vid_1.jpg'))
        ..writeAsBytesSync([1, 2, 3]);
      final runBArt = File(p.join(tempDir.path, 'ytdl_art_vid_2.jpg'))
        ..writeAsBytesSync([4, 5, 6]);

      var currentGeneration = 1;
      final cleanupA = YtDownloadArtifactStore.cleanupScratch(
        artworkFuture: delayedArtCompleter.future,
        wasCanceled: true,
        isCurrentRun: () => currentGeneration == 1,
      );

      // Simulate retry run B taking over before run A's artworkFuture resolves.
      currentGeneration = 2;
      delayedArtCompleter.complete(runBArt.path);
      await cleanupA;

      expect(runBArt.existsSync(), isTrue);
      expect(runAArt.existsSync(), isTrue);
    });
  });

  group('H-12 Naming, Sniffing, ENOSPC, 416, & Pause Registry', () {
    test('sniffContainerBytes distinguishes ADTS AAC from MP3', () {
      final aac = YtDownloadFileNaming.sniffContainerBytes(
          const [0xFF, 0xF1, 0x50, 0x80]);
      final mp3 = YtDownloadFileNaming.sniffContainerBytes(
          const [0xFF, 0xFB, 0x90, 0x00]);
      expect(aac?.ext, 'aac');
      expect(aac?.mime, 'audio/aac');
      expect(mp3?.ext, 'mp3');
      expect(mp3?.mime, 'audio/mpeg');
    });

    test('sanitizeFilename trims UTF-8 without breaking ZWJ emoji clusters',
        () {
      const emoji = '\u{1F469}\u{200D}\u{1F52C}'; // scientist ZWJ cluster
      final longTitle = List.filled(40, emoji).join();
      final name =
          YtDownloadFileNaming.sanitizeFilename('Artist', longTitle, 'm4a');
      expect(name.endsWith('.m4a'), isTrue);
      final stem = name.substring(0, name.length - 4);
      expect(
        stem.runes.any((r) => r >= 0xD800 && r <= 0xDFFF),
        isFalse,
      );
      expect(stem.length, lessThan(longTitle.length));
    });

    test('Windows ENOSPC errno 112 and 39 map to StorageFailure', () {
      expect(
        () => YtDownloadHttpSupport.throwStorageOrOriginal(
          const FileSystemException(
              'Write failed', '/a', OSError('Disk full', 112)),
        ),
        throwsA(isA<StorageFailure>()),
      );
      expect(
        () => YtDownloadHttpSupport.throwStorageOrOriginal(
          const FileSystemException('Write failed', '/a', OSError('Error', 39)),
        ),
        throwsA(isA<StorageFailure>()),
      );
    });

    test('416 on resume deletes stale .part & stamp and falls back cleanly',
        () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = Directory.systemTemp.createTempSync('ytdl_416_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathChannel, (_) async => tempDir.path);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_downloadChannel, (call) async {
        if (call.method == 'getFreeDiskSpace') return 500 * 1024 * 1024;
        if (call.method == 'saveToMusic') {
          return p.join(tempDir.path, 'saved.m4a');
        }
        return true;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_tagChannel, (_) async => true);

      // Pre-seed matching-stamp >64KB .part to force a resume Range request.
      final part = File(p.join(tempDir.path, 'ytdl_vidReg00001.m4a.part'))
        ..writeAsBytesSync(Uint8List(80 * 1024));
      final stamp = YtDownloadTransferMath.resumeStampFor(
        container: 'm4a',
        expectedBytes: 960000,
        videoId: 'vidReg00001',
      );
      File('${part.path}.stamp').writeAsStringSync(stamp);

      var sequentialCalls = 0;
      final client = _FakeClient((req) async {
        if (req.headers.values['range'] == 'bytes=0-0') {
          return _FakeResponse(statusCode: 200, fixedContentLength: 200 * 1024);
        }
        sequentialCalls++;
        if (req.headers.values['range'] != null) {
          return _FakeResponse(statusCode: 416);
        }
        return _FakeResponse(statusCode: 200, body: _m4aBody(200 * 1024));
      });

      final ytm = _MockYtmService();
      when(() => ytm.ensurePoTokenReady()).thenAnswer((_) async => true);
      when(() => ytm.isWifiConnected()).thenAnswer((_) async => true);
      when(() => ytm.isBotCoolingDown).thenReturn(false);
      when(() => ytm.resolveStream(
            any(),
            quality: any(named: 'quality'),
            forceRefresh: any(named: 'forceRefresh'),
            preferM4a: any(named: 'preferM4a'),
            title: any(named: 'title'),
            artist: any(named: 'artist'),
          )).thenAnswer((_) async => _stream());
      final repo = _MockMusicRepo();
      when(() => repo.reconcileDownloadedSong(
            oldId: any(named: 'oldId'),
            newPath: any(named: 'newPath'),
            fallbackSong: any(named: 'fallbackSong'),
          )).thenAnswer((_) async => const Right<AppFailure, int?>(9));

      final service =
          YtDownloadService(client, ytm, _MockMediaScanner(), repo);
      addTearDown(service.dispose);
      final res = await service.download(_song());
      expect(res.isRight(), isTrue);
      expect(sequentialCalls, 2);
      expect(File('${part.path}.stamp').existsSync(), isFalse);
    });

    test('cleanOrphanPartFiles respects YtDownloadPauseRegistry', () async {
      final tempDir = Directory.systemTemp.createTempSync('ytdl_pause_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathChannel, (_) async => tempDir.path);

      final pausedPart = File(p.join(tempDir.path, 'ytdl_vidPause1.m4a.part'))
        ..writeAsBytesSync([1, 2, 3]);
      final oldStamp = DateTime.now().subtract(const Duration(minutes: 20));
      pausedPart.setLastModifiedSync(oldStamp);

      final client = _FakeClient((_) async => _FakeResponse(statusCode: 404));
      final service = YtDownloadService(
          client, _MockYtmService(), _MockMediaScanner(), _MockMusicRepo());
      addTearDown(service.dispose);
      service.markPaused('vidPause1');
      await service.cleanOrphanPartFiles();
      expect(pausedPart.existsSync(), isTrue);

      final registry = YtDownloadPauseRegistry();
      registry.mark('v1');
      expect(registry.isNotEmpty, isTrue);
      registry.dispose();
    });
  });
}
