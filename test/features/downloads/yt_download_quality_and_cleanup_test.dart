// Covers the per-download quality override on YtDownloadService.download()
// (picker value reaches the stream request; the persisted download-quality
// setting is preferred over streaming) and the _RangeIgnored artifact sweep.
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
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/ytm_audio_quality.dart';
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
  final FakeHeaders responseHeaders = FakeHeaders();

  FakeResponse({
    required this.statusCode,
    this.body = const [],
    this.fixedContentLength,
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
    return Stream<List<int>>.value(body).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeClient client;
  late MockYtmService ytm;
  late YtDownloadService service;
  late Future<FakeResponse> Function(FakeRequest request) server;

  List<int> m4aBody(int size) {
    final bytes = Uint8List(size);
    if (size >= 12) {
      bytes[4] = 0x66; // f
      bytes[5] = 0x74; // t
      bytes[6] = 0x79; // y
      bytes[7] = 0x70; // p
    }
    return bytes;
  }

  YtmStream streamFor(String videoId) => YtmStream(
        videoId: videoId,
        url:
            'https://rr1---sn-x.googlevideo.com/videoplayback?expire=1800000000',
        mimeType: 'audio/mp4',
        container: 'm4a',
        bitrateKbps: 128,
        // Zero duration: the download-integrity heuristic skips its
        // duration-derived size check, so a tiny body can complete.
        duration: Duration.zero,
        title: 'T',
        artist: 'A',
        userAgent: 'TestAgent/1.0',
      );

  SongsTableData songFor(String videoId) => YtmTrack(
        videoId: videoId,
        title: 'Song',
        artist: 'Artist',
        duration: Duration.zero,
      ).toSongData();

  void mockChannel(
    MethodChannel channel,
    Future<Object?> Function(MethodCall call)? handler,
  ) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();

    tempDir = Directory.systemTemp.createTempSync('pulsr_ytdl_quality_');
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
              title: any(named: 'title'),
              artist: any(named: 'artist'),
            ))
        .thenAnswer((invocation) async =>
            streamFor(invocation.positionalArguments[0] as String));

    final scanner = MockMediaScanner();
    final repo = MockMusicRepository();
    when(() => repo.reconcileDownloadedSong(
          oldId: any(named: 'oldId'),
          newPath: any(named: 'newPath'),
          fallbackSong: any(named: 'fallbackSong'),
        )).thenAnswer((_) async => const Right<AppFailure, int?>(42));

    service = YtDownloadService(client, ytm, scanner, repo);

    mockChannel(_pathProviderChannel, (call) async => tempDir.path);
    mockChannel(_downloadChannel, (call) async {
      switch (call.method) {
        case 'getFreeDiskSpace':
          return 500 * 1024 * 1024;
        case 'saveToMusic':
          return p.join(tempDir.path, 'saved.m4a');
        case 'startDownloadForeground':
          return true;
        default:
          return null;
      }
    });
    mockChannel(_tagChannel, (call) async => null);
  });

  tearDown(() async {
    mockChannel(_downloadChannel, null);
    mockChannel(_tagChannel, null);
    mockChannel(_pathProviderChannel, null);
    await getIt.reset();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('resolveDownloadQuality', () {
    test('override wins, then download setting, then streaming, then high', () {
      expect(
        YtDownloadService.resolveDownloadQuality(
          override: YtmAudioQuality.low,
          downloadQuality: 'high',
          streamingQuality: 'medium',
        ),
        'low',
      );
      expect(
        YtDownloadService.resolveDownloadQuality(
          downloadQuality: 'medium',
          streamingQuality: 'low',
        ),
        'medium',
      );
      expect(
        YtDownloadService.resolveDownloadQuality(streamingQuality: 'low'),
        'low',
      );
      expect(YtDownloadService.resolveDownloadQuality(), 'high');
      expect(
        YtDownloadService.resolveDownloadQuality(
          downloadQuality: '  ',
          streamingQuality: '',
        ),
        'high',
      );
    });
  });

  group('per-download quality', () {
    test('a pending picker override reaches the stream request', () async {
      server =
          (request) async => FakeResponse(statusCode: 200, body: m4aBody(2048));
      const videoId = 'vidQuality01';
      service.setPendingDownloadQuality(videoId, YtmAudioQuality.low);

      final result = await service.download(songFor(videoId));

      result.match(
        (failure) => fail('download failed: ${failure.message}'),
        (_) {},
      );
      verify(() => ytm.resolveStream(
            videoId,
            quality: 'low',
            forceRefresh: any(named: 'forceRefresh'),
            preferM4a: any(named: 'preferM4a'),
            title: any(named: 'title'),
            artist: any(named: 'artist'),
          )).called(1);
    });

    test('the persisted download quality beats the streaming quality',
        () async {
      SharedPreferences.setMockInitialValues({
        'setting_download_quality': 'medium',
        'setting_streaming_quality': 'low',
      });
      server =
          (request) async => FakeResponse(statusCode: 200, body: m4aBody(2048));
      const videoId = 'vidQuality02';

      final result = await service.download(songFor(videoId));

      final failure = result.getLeft().toNullable();
      expect(failure, isNull, reason: failure?.message);
      verify(() => ytm.resolveStream(
            videoId,
            quality: 'medium',
            forceRefresh: any(named: 'forceRefresh'),
            preferM4a: any(named: 'preferM4a'),
            title: any(named: 'title'),
            artist: any(named: 'artist'),
          )).called(1);
    });
  });

  group('_RangeIgnored cleanup', () {
    test('no .partN or .parts scratch survives the sequential retry', () async {
      const videoId = 'vidRangeIgn01';
      const total = 3000000;
      final bytes = m4aBody(total);
      server = (request) async {
        final range = request.headers.values['range'];
        if (range == 'bytes=0-0') {
          return FakeResponse(
            statusCode: 206,
            body: const [0],
            fixedContentLength: 1,
            headers: {
              'content-range': 'bytes 0-0/$total',
              'accept-ranges': 'bytes',
            },
          );
        }
        // Any ranged chunk answered with the whole body: Range is ignored.
        return FakeResponse(
          statusCode: 200,
          body: bytes,
          fixedContentLength: total,
        );
      };

      final result = await service.download(songFor(videoId));

      expect(result.isRight(), isTrue);
      final leftovers = tempDir
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .where((name) =>
              name.startsWith('ytdl_$videoId') &&
              (name.endsWith('.parts') ||
                  name.endsWith('.part') ||
                  RegExp(r'\.part\d$').hasMatch(name)))
          .toList();
      expect(leftovers, isEmpty,
          reason: 'Range-ignored chunk scratch must not be left behind');
    });
  });
}
