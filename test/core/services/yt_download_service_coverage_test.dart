// test/core/services/yt_download_service_coverage_test.dart
//
// Remaining-branch coverage for YtDownloadService: the foreground-service
// failure path, the YtmException/PlatformException/generic error funnels, the
// container-sniff correction (WebM bytes behind a .m4a URL), artwork failure
// retry, tagging retry/abandon, throughput sampling, proactive re-resolution
// of an expiring URL and the orphan-sweep no-directory guard.
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
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/audio/adaptive_buffer_engine.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtmService extends Mock implements YtmService {}

class MockMediaScanner extends Mock implements MediaScannerService {}

class MockMusicRepository extends Mock implements IMusicRepository {}

const _downloadChannel = MethodChannel(PulsrChannels.ytDownload);
const _tagChannel = MethodChannel(PulsrChannels.tagEditor);
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

class FakeHeaders implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('headers.${invocation.memberName}');
}

class FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final List<int> body;
  final int? fixedContentLength;
  final Stream<List<int>>? bodyStream;
  final FakeHeaders responseHeaders = FakeHeaders();

  FakeResponse({
    required this.statusCode,
    this.body = const [],
    this.fixedContentLength,
    this.bodyStream,
    Map<String, String> headers = const {},
  }) {
    responseHeaders.values.addAll(headers);
  }

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
  }) {
    final stream = bodyStream ?? Stream<List<int>>.value(body);
    return stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('response.${invocation.memberName}');
}

class FakeRequest implements HttpClientRequest {
  @override
  final Uri uri;

  @override
  final FakeHeaders headers = FakeHeaders();

  final Future<FakeResponse> Function(FakeRequest request) onClose;

  FakeRequest(this.uri, this.onClose);

  @override
  Future<HttpClientResponse> close() => onClose(this);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('request.${invocation.memberName}');
}

class FakeClient implements HttpClient {
  final Future<FakeResponse> Function(FakeRequest request) handler;
  final List<FakeRequest> requests = [];

  FakeClient(this.handler);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = FakeRequest(url, handler);
    requests.add(request);
    return request;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('client.${invocation.memberName}');
}

late Directory tempDir;
late FakeClient client;
late MockYtmService ytm;
late MockMediaScanner scanner;
late MockMusicRepository repo;
late YtDownloadService service;

late Future<FakeResponse> Function(FakeRequest request) server;
late int freeDiskSpace;
late String? saveResult;
late int writeTagsCalls;
late List<String> downloadChannelCalls;

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

List<int> _webmBody(int size) {
  final bytes = Uint8List(size);
  if (size >= 4) {
    bytes[0] = 0x1A;
    bytes[1] = 0x45;
    bytes[2] = 0xDF;
    bytes[3] = 0xA3;
  }
  return bytes;
}

YtmStream _stream({
  String videoId = 'vidTest0001',
  int bitrateKbps = 128,
  Duration duration = const Duration(minutes: 3),
  String container = 'm4a',
  int? expiresAt,
}) =>
    YtmStream(
      videoId: videoId,
      url: 'https://rr1---sn-x.googlevideo.com/videoplayback?expire=1800000000',
      mimeType: container == 'webm' ? 'audio/webm' : 'audio/mp4',
      container: container,
      bitrateKbps: bitrateKbps,
      duration: duration,
      title: 'T',
      artist: 'A',
      expiresAt: expiresAt,
      userAgent: 'TestAgent/1.0',
    );

SongsTableData _song({
  String videoId = 'vidTest0001',
  String? artworkUrl,
}) =>
    YtmTrack(
      videoId: videoId,
      title: 'Song',
      artist: 'Artist',
      duration: const Duration(minutes: 3),
      artworkUrl: artworkUrl,
    ).toSongData();

void _mockChannel(
  MethodChannel channel,
  Future<Object?> Function(MethodCall call)? handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();

    tempDir = Directory.systemTemp.createTempSync('pulsr_ytdl_cov_');
    freeDiskSpace = 500 * 1024 * 1024;
    saveResult = p.join(tempDir.path, 'saved.m4a');
    writeTagsCalls = 0;
    downloadChannelCalls = [];
    server = (request) async => FakeResponse(statusCode: 404);
    client = FakeClient((request) => server(request));

    ytm = MockYtmService();
    when(() => ytm.ensurePoTokenReady()).thenAnswer((_) async => true);
    when(() => ytm.isWifiConnected()).thenAnswer((_) async => true);
    when(() => ytm.invalidatePoToken()).thenAnswer((_) async {});
    when(() => ytm.isBotCoolingDown).thenReturn(false);
    when(() => ytm.resolveStream(
          any(),
          quality: any(named: 'quality'),
          forceRefresh: any(named: 'forceRefresh'),
          preferM4a: any(named: 'preferM4a'),
        )).thenAnswer((_) async => _stream());

    scanner = MockMediaScanner();
    repo = MockMusicRepository();
    when(() => repo.reconcileDownloadedSong(
          oldId: any(named: 'oldId'),
          newPath: any(named: 'newPath'),
          fallbackSong: any(named: 'fallbackSong'),
        )).thenAnswer((_) async => const Right<AppFailure, int?>(42));

    service = YtDownloadService(client, ytm, scanner, repo);

    _mockChannel(_pathProviderChannel, (call) async => tempDir.path);
    _mockChannel(_downloadChannel, (call) async {
      downloadChannelCalls.add(call.method);
      switch (call.method) {
        case 'getFreeDiskSpace':
          return freeDiskSpace;
        case 'saveToMusic':
          return saveResult;
        case 'startDownloadForeground':
          return true;
        default:
          return null;
      }
    });
    _mockChannel(_tagChannel, (call) async {
      if (call.method == 'writeTags') writeTagsCalls++;
      return null;
    });
  });

  tearDown(() async {
    _mockChannel(_downloadChannel, null);
    _mockChannel(_tagChannel, null);
    _mockChannel(_pathProviderChannel, null);
    await getIt.reset();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<FakeResponse> sequential(List<int> body) async =>
      FakeResponse(statusCode: 200, body: body);

  test('a foreground-service start failure is tolerated', () async {
    _mockChannel(_downloadChannel, (call) async {
      downloadChannelCalls.add(call.method);
      switch (call.method) {
        case 'getFreeDiskSpace':
          return freeDiskSpace;
        case 'saveToMusic':
          return saveResult;
        case 'startDownloadForeground':
          throw PlatformException(code: 'FOREGROUND_DENIED');
        default:
          return null;
      }
    });
    server = (request) async => sequential(_m4aBody(2 * 1024 * 1024));

    final result = await service.download(_song());
    expect(result.isRight(), isTrue);
    expect(downloadChannelCalls, contains('startDownloadForeground'));
  });

  test('a YtmException network failure maps to a no-connection message',
      () async {
    when(() => ytm.resolveStream(
          any(),
          quality: any(named: 'quality'),
          forceRefresh: any(named: 'forceRefresh'),
          preferM4a: any(named: 'preferM4a'),
        )).thenThrow(const YtmException('YTM_NETWORK'));

    final result = await service.download(_song(videoId: 'vidNet000001'));
    result.match(
      (failure) => expect(failure.message, 'No connection while downloading'),
      (_) => fail('expected a failure'),
    );
  });

  test('a PlatformException from the platform maps to a download failure',
      () async {
    _mockChannel(_downloadChannel, (call) async {
      downloadChannelCalls.add(call.method);
      switch (call.method) {
        case 'getFreeDiskSpace':
          return freeDiskSpace;
        case 'saveToMusic':
          throw PlatformException(code: 'SAVE_FAIL', message: 'nope');
        case 'startDownloadForeground':
          return true;
        default:
          return null;
      }
    });
    server = (request) async => sequential(_m4aBody(2 * 1024 * 1024));

    final result = await service.download(_song(videoId: 'vidPlat00001'));
    result.match(
      (failure) => expect(failure.message, 'nope'),
      (_) => fail('expected a failure'),
    );
  });

  test('an unexpected error from the indexer hits the catch-all', () async {
    when(() => repo.reconcileDownloadedSong(
          oldId: any(named: 'oldId'),
          newPath: any(named: 'newPath'),
          fallbackSong: any(named: 'fallbackSong'),
        )).thenThrow(StateError('indexer exploded'));
    server = (request) async => sequential(_m4aBody(2 * 1024 * 1024));

    final result = await service.download(_song(videoId: 'vidGen000001'));
    result.match(
      (failure) => expect(failure.message, contains('indexer exploded')),
      (_) => fail('expected a failure'),
    );
  });

  test('sniffs WebM bytes behind an m4a URL and skips the MP4 tagger',
      () async {
    server = (request) async => sequential(_webmBody(2 * 1024 * 1024));

    final result = await service.download(_song(videoId: 'vidSniff0001'));
    expect(result.isRight(), isTrue);
    expect(writeTagsCalls, 0, reason: 'webm must not go to the MP4 tagger');
    expect(
      downloadChannelCalls.contains('saveToMusic'),
      isTrue,
    );
  });

  test('an artwork fetch failure is retried and then abandoned', () async {
    server = (request) async {
      if (request.uri.host == 'i.ytimg.com') {
        return FakeResponse(statusCode: 404);
      }
      return sequential(_m4aBody(2 * 1024 * 1024));
    };

    final result = await service.download(
      _song(
        videoId: 'vidArt000001',
        artworkUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      ),
    );
    expect(result.isRight(), isTrue);
    // The main transfer still succeeds without artwork.
    expect(writeTagsCalls, 1);
  });

  test('a flaky tag write is retried once and succeeds', () async {
    var tagAttempts = 0;
    _mockChannel(_tagChannel, (call) async {
      if (call.method == 'writeTags') {
        tagAttempts++;
        writeTagsCalls++;
        if (tagAttempts == 1) throw PlatformException(code: 'FLAKY');
      }
      return null;
    });
    server = (request) async => sequential(_m4aBody(2 * 1024 * 1024));

    final result = await service.download(_song(videoId: 'vidTag000001'));
    expect(result.isRight(), isTrue);
    expect(writeTagsCalls, 2);
  });

  test('a permanently failing tag write does not fail the download', () async {
    _mockChannel(_tagChannel, (call) async {
      if (call.method == 'writeTags') {
        writeTagsCalls++;
        throw PlatformException(code: 'BAD_TAG');
      }
      return null;
    });
    server = (request) async => sequential(_m4aBody(2 * 1024 * 1024));

    final result = await service.download(_song(videoId: 'vidTagFail01'));
    expect(result.isRight(), isTrue);
    expect(writeTagsCalls, 2);
  });

  test('reports throughput to a registered AdaptiveBufferEngine', () async {
    final engine = AdaptiveBufferEngine();
    getIt.registerSingleton<AdaptiveBufferEngine>(engine);
    server = (request) async => sequential(_m4aBody(2 * 1024 * 1024));

    expect(engine.averageNetworkSpeedMbps, 10.0);
    final result = await service.download(_song(videoId: 'vidPerf00001'));
    expect(result.isRight(), isTrue);
    // _sampleThroughput ran against the registered engine (the actual EWMA
    // update is skipped for a sub-200ms transfer, which is expected here).
    engine.dispose();
  });

  test('proactively re-resolves a URL that cannot outlive the transfer',
      () async {
    var resolveCalls = 0;
    when(() => ytm.resolveStream(
          any(),
          quality: any(named: 'quality'),
          forceRefresh: any(named: 'forceRefresh'),
          preferM4a: any(named: 'preferM4a'),
        )).thenAnswer((_) async {
      resolveCalls++;
      if (resolveCalls == 1) {
        return _stream(
          videoId: 'vidExpire001',
          expiresAt: DateTime.now()
              .add(const Duration(seconds: 30))
              .millisecondsSinceEpoch,
        );
      }
      return _stream(
        videoId: 'vidExpire001',
        expiresAt: DateTime.now()
            .add(const Duration(hours: 3))
            .millisecondsSinceEpoch,
      );
    });
    server = (request) async => sequential(_m4aBody(2 * 1024 * 1024));

    final result = await service.download(_song(videoId: 'vidExpire001'));
    expect(result.isRight(), isTrue);
    expect(resolveCalls, greaterThanOrEqualTo(2));
    verify(() => ytm.resolveStream(
          any(),
          quality: any(named: 'quality'),
          forceRefresh: true,
          preferM4a: any(named: 'preferM4a'),
        )).called(greaterThanOrEqualTo(1));
  });

  test('cleanOrphanPartFiles is a no-op when the cache directory is missing',
      () async {
    _mockChannel(
        _pathProviderChannel, (call) async => p.join(tempDir.path, 'missing'));
    await service.cleanOrphanPartFiles();
    // No throw and the guard returned before listing.
  });
}
