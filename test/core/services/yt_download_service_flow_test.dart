// test/core/services/yt_download_service_flow_test.dart
//
// End-to-end (no network) coverage of YtDownloadService.download():
// validation gates, the network policy block, the sequential and parallel
// transfer paths, resume with and without Range support, cancellation,
// pre-flight storage refusal, MediaStore/reconcile failures and the artifact
// sweeps. The transport is a hand-rolled HttpClient fake, so everything below
// is deterministic and file-system local.
import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
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
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
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

// ---------------------------------------------------------------------------
// Minimal HttpClient fake. dart:io's HttpClient is an abstract interface, and
// the service only ever touches openUrl/getUrl, close, headers and a streaming
// response body, so a noSuchMethod-backed implementation stays tiny.
// ---------------------------------------------------------------------------

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
    return stream.listen(
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

// ---------------------------------------------------------------------------

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
late Map<Object?, Object?>? lastWriteTagsArgs;
late List<String> downloadChannelCalls;
late List<Map<Object?, Object?>> progressNotifications;

List<int> _m4aBody(int size) {
  final bytes = Uint8List(size);
  if (size >= 12) {
    bytes[4] = 0x66; // f
    bytes[5] = 0x74; // t
    bytes[6] = 0x79; // y
    bytes[7] = 0x70; // p
    bytes[8] = 0x4D; // M
    bytes[9] = 0x34; // 4
    bytes[10] = 0x41; // A
    bytes[11] = 0x20; // space
  }
  return bytes;
}

YtmStream _stream({
  String videoId = 'vidTest0001',
  int bitrateKbps = 128,
  Duration duration = const Duration(minutes: 3),
  String container = 'm4a',
  String? cookies,
  String userAgent = 'TestAgent/1.0',
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
      cookies: cookies,
      userAgent: userAgent,
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

String _stageName(YtDownloadProgress progress) => progress.stage.name;

Future<void> _waitFor(bool Function() predicate) async {
  for (var i = 0; i < 400; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('condition not reached');
}

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

    tempDir = Directory.systemTemp.createTempSync('pulsr_ytdl_test_');
    freeDiskSpace = 500 * 1024 * 1024;
    saveResult = p.join(tempDir.path, 'saved.m4a');
    writeTagsCalls = 0;
    lastWriteTagsArgs = null;
    downloadChannelCalls = [];
    progressNotifications = [];
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
        case 'updateDownloadProgress':
          progressNotifications
              .add((call.arguments as Map).cast<Object?, Object?>());
          return null;
        default:
          return null;
      }
    });
    _mockChannel(_tagChannel, (call) async {
      if (call.method == 'writeTags') {
        writeTagsCalls++;
        lastWriteTagsArgs = (call.arguments as Map).cast<Object?, Object?>();
      }
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

  Future<FakeResponse> sequential(List<int> body) async {
    return FakeResponse(statusCode: 200, body: body);
  }

  group('download input validation', () {
    test('rejects rows that are not YouTube tracks', () async {
      final song = _song().copyWith(source: SongSource.local);
      final result = await service.download(song);
      result.match(
        (failure) => expect(
          failure,
          const DownloadFailure('Only YouTube tracks can be downloaded'),
        ),
        (_) => fail('expected a failure'),
      );
    });

    test('rejects a track with no video id', () async {
      final song = _song().copyWith(remoteId: const Value(null));
      final result = await service.download(song);
      result.match(
        (failure) => expect(
          failure,
          const DownloadFailure('Track has no video id'),
        ),
        (_) => fail('expected a failure'),
      );
    });
  });

  group('downloadPolicyBlock', () {
    test('blocks when Offline Only Mode is on', () async {
      SharedPreferences.setMockInitialValues(
          {'setting_offline_only_mode': true});
      final failure = await service.downloadPolicyBlock();
      expect(failure, isA<DownloadFailure>());
      expect(failure!.message, contains('Offline Only Mode'));
    });

    test('blocks Wi-Fi Only Mode without Wi-Fi', () async {
      SharedPreferences.setMockInitialValues({'setting_wifi_only_mode': true});
      when(() => ytm.isWifiConnected()).thenAnswer((_) async => false);
      final failure = await service.downloadPolicyBlock();
      expect(failure!.message, contains('Wi-Fi Only Mode'));
    });

    test('allows Wi-Fi Only Mode once Wi-Fi is confirmed', () async {
      SharedPreferences.setMockInitialValues({'setting_wifi_only_mode': true});
      expect(await service.downloadPolicyBlock(), isNull);
    });

    test('allows downloads by default', () async {
      expect(await service.downloadPolicyBlock(), isNull);
    });
  });

  group('sequential download', () {
    test('completes the full pipeline and reports every stage', () async {
      server = (request) async => sequential(_m4aBody(2 * 1024 * 1024));
      final song = _song();
      final stages = <String>[];

      final result = await service.download(
        song,
        onProgress: (progress) => stages.add(_stageName(progress)),
      );

      result.match((failure) => fail('unexpected failure: $failure'),
          (newId) => expect(newId, 42));
      expect(
          stages,
          containsAllInOrder([
            'queued',
            'resolving',
            'downloading',
            'tagging',
            'saving',
            'indexing',
            'done',
          ]));
      expect(service.getDownloadedPath(song.remoteId!), saveResult);
      expect(service.getResolvedStream(song.remoteId!), isNotNull);
      expect(writeTagsCalls, 1);
      verify(() => repo.reconcileDownloadedSong(
            oldId: song.id,
            newPath: saveResult!,
            fallbackSong: any(named: 'fallbackSong'),
          )).called(1);
      expect(
        downloadChannelCalls,
        containsAll(['getFreeDiskSpace', 'saveToMusic']),
      );
      await _waitFor(
          () => downloadChannelCalls.contains('stopDownloadForeground'));
      expect(progressNotifications, isNotEmpty);
    });

    test('embeds downloaded artwork and withholds cookies from googlevideo',
        () async {
      final jpg = Uint8List.fromList(List<int>.filled(2048, 0x41));
      server = (request) async {
        if (request.uri.host == 'i.ytimg.com') {
          return FakeResponse(statusCode: 200, body: jpg);
        }
        return sequential(_m4aBody(2 * 1024 * 1024));
      };
      when(() => ytm.resolveStream(
            any(),
            quality: any(named: 'quality'),
            forceRefresh: any(named: 'forceRefresh'),
            preferM4a: any(named: 'preferM4a'),
          )).thenAnswer((_) async => _stream(cookies: 'SAPISID=session'));

      final song = _song(
        artworkUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
      final result = await service.download(song);

      expect(result.isRight(), isTrue);
      expect(writeTagsCalls, 1);
      expect(lastWriteTagsArgs!['artworkPath'], isNotNull);

      final audioRequest = client.requests
          .firstWhere((r) => r.uri.host.endsWith('googlevideo.com'));
      expect(audioRequest.headers.values.containsKey('cookie'), isFalse,
          reason: 'the session must never travel to the CDN');
      expect(
        client.requests.where((r) => r.uri.host == 'i.ytimg.com'),
        isNotEmpty,
        reason: 'the high-res cover must be fetched in parallel',
      );
    });

    test('refuses when free disk space is below the safety floor', () async {
      freeDiskSpace = 1024;
      server = (request) async => sequential(_m4aBody(2 * 1024 * 1024));

      final result = await service.download(_song());

      result.match(
        (failure) =>
            expect(failure.message, 'Insufficient storage space for download'),
        (_) => fail('expected a failure'),
      );
      expect(client.requests, isEmpty,
          reason: 'the transfer must never start on a full disk');
    });

    test('reports a body shorter than half the estimate as incomplete',
        () async {
      server = (request) async => sequential(_m4aBody(3000));

      final result = await service.download(_song());

      result.match(
        (failure) => expect(failure.message, startsWith('Download incomplete')),
        (_) => fail('expected a failure'),
      );
      expect(writeTagsCalls, 0);
    });

    test('fails when MediaStore returns no path', () async {
      server = (request) async => sequential(_m4aBody(2 * 1024 * 1024));
      saveResult = null;

      final result = await service.download(_song());

      result.match(
        (failure) =>
            expect(failure.message, 'MediaStore did not return a path'),
        (_) => fail('expected a failure'),
      );
    });

    test('fails when reconcile finds no surviving library row', () async {
      server = (request) async => sequential(_m4aBody(2 * 1024 * 1024));
      when(() => repo.reconcileDownloadedSong(
            oldId: any(named: 'oldId'),
            newPath: any(named: 'newPath'),
            fallbackSong: any(named: 'fallbackSong'),
          )).thenAnswer((_) async => const Right<AppFailure, int?>(null));

      final result = await service.download(_song());

      result.match(
        (failure) => expect(
          failure.message,
          'Downloaded file was not found in the library',
        ),
        (_) => fail('expected a failure'),
      );
    });

    test('propagates a reconcile failure unchanged', () async {
      server = (request) async => sequential(_m4aBody(2 * 1024 * 1024));
      when(() => repo.reconcileDownloadedSong(
                oldId: any(named: 'oldId'),
                newPath: any(named: 'newPath'),
                fallbackSong: any(named: 'fallbackSong'),
              ))
          .thenAnswer((_) async =>
              const Left<AppFailure, int?>(DownloadFailure('database is sad')));

      final result = await service.download(_song());

      result.match(
        (failure) => expect(failure.message, 'database is sad'),
        (_) => fail('expected a failure'),
      );
    });
  });

  group('resume', () {
    test('appends a 206 response to a stamped .part', () async {
      const videoId = 'vidResume001';
      final stream = _stream(
          videoId: videoId,
          duration: const Duration(seconds: 1),
          bitrateKbps: 64);
      when(() => ytm.resolveStream(
            any(),
            quality: any(named: 'quality'),
            forceRefresh: any(named: 'forceRefresh'),
            preferM4a: any(named: 'preferM4a'),
          )).thenAnswer((_) async => stream);

      final dest = File(p.join(tempDir.path, 'ytdl_$videoId.m4a'));
      File('${dest.path}.part').writeAsBytesSync(_m4aBody(70000));
      File('${dest.path}.part.stamp').writeAsStringSync(
          YtDownloadService.resumeStampFor(Uri.parse(stream.url)));

      final rest = _m4aBody(70000);
      server = (request) async {
        final range = request.headers.values['range'];
        if (range == null) {
          return sequential(_m4aBody(140000));
        }
        if (range == 'bytes=70000-') {
          return FakeResponse(
            statusCode: 206,
            body: rest,
            headers: {'content-range': 'bytes 70000-139999/140000'},
          );
        }
        return FakeResponse(
          statusCode: 200,
          body: _m4aBody(140000),
          fixedContentLength: 140000,
        );
      };

      final result = await service.download(_song(videoId: videoId));

      expect(result.isRight(), isTrue);
      final ranged = client.requests
          .where((r) => r.headers.values['range'] == 'bytes=70000-');
      expect(ranged, hasLength(1));
    });

    test('restarts from scratch when the server ignores Range', () async {
      const videoId = 'vidRestart01';
      final stream = _stream(
          videoId: videoId,
          duration: const Duration(seconds: 1),
          bitrateKbps: 64);
      when(() => ytm.resolveStream(
            any(),
            quality: any(named: 'quality'),
            forceRefresh: any(named: 'forceRefresh'),
            preferM4a: any(named: 'preferM4a'),
          )).thenAnswer((_) async => stream);

      final dest = File(p.join(tempDir.path, 'ytdl_$videoId.m4a'));
      File('${dest.path}.part').writeAsBytesSync(_m4aBody(70000));
      File('${dest.path}.part.stamp').writeAsStringSync(
          YtDownloadService.resumeStampFor(Uri.parse(stream.url)));

      final fullBody = _m4aBody(140000);
      server = (request) async {
        final range = request.headers.values['range'];
        if (range != null && range != 'bytes=0-0') {
          // A 200 answer to a ranged request: Range was ignored.
          return FakeResponse(
            statusCode: 200,
            body: fullBody,
            fixedContentLength: fullBody.length,
          );
        }
        if (range == 'bytes=0-0') {
          return FakeResponse(
            statusCode: 200,
            body: const [0],
            fixedContentLength: fullBody.length,
          );
        }
        return FakeResponse(
          statusCode: 200,
          body: fullBody,
          fixedContentLength: fullBody.length,
        );
      };

      final result = await service.download(_song(videoId: videoId));

      expect(result.isRight(), isTrue);
      final bodyRequests = client.requests
          .where((r) =>
              r.uri.path.contains('videoplayback') &&
              r.headers.values['range'] != 'bytes=0-0')
          .toList();
      // Explicitly: one ignored-range request and one clean restart.
      expect(bodyRequests.where((r) => r.headers.values.containsKey('range')),
          hasLength(1));
      expect(bodyRequests.where((r) => !r.headers.values.containsKey('range')),
          hasLength(1));
    });

    test('discards a .part whose stamp belongs to another URL', () async {
      const videoId = 'vidStampOld1';
      final stream = _stream(
          videoId: videoId,
          duration: const Duration(seconds: 1),
          bitrateKbps: 64);
      when(() => ytm.resolveStream(
            any(),
            quality: any(named: 'quality'),
            forceRefresh: any(named: 'forceRefresh'),
            preferM4a: any(named: 'preferM4a'),
          )).thenAnswer((_) async => stream);

      final dest = File(p.join(tempDir.path, 'ytdl_$videoId.m4a'));
      File('${dest.path}.part').writeAsBytesSync(_m4aBody(70000));
      File('${dest.path}.part.stamp').writeAsStringSync('12345');

      final fullBody = _m4aBody(140000);
      server = (request) async {
        if (request.headers.values['range'] == 'bytes=0-0') {
          return FakeResponse(
            statusCode: 200,
            body: const [0],
            fixedContentLength: fullBody.length,
          );
        }
        return FakeResponse(
          statusCode: 200,
          body: fullBody,
          fixedContentLength: fullBody.length,
        );
      };

      final result = await service.download(_song(videoId: videoId));

      expect(result.isRight(), isTrue);
      expect(
        client.requests.where((r) =>
            r.headers.values.containsKey('range') &&
            r.headers.values['range'] != 'bytes=0-0'),
        isEmpty,
        reason: 'a stale part must not be resumed',
      );
    });
  });

  group('parallel download', () {
    test('splits into four chunks and merges them', () async {
      const total = 3000000;
      final bytes = _m4aBody(total);
      server = (request) async {
        final range = request.headers.values['range'];
        if (range == null) {
          return FakeResponse(
            statusCode: 206,
            body: bytes,
            headers: {'accept-ranges': 'bytes'},
          );
        }
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
        final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
        final start = int.parse(match.group(1)!);
        final end = int.parse(match.group(2)!);
        return FakeResponse(
          statusCode: 206,
          body: bytes.sublist(start, end + 1),
          headers: {'content-range': 'bytes $start-$end/$total'},
        );
      };

      final result = await service.download(_song());

      expect(result.isRight(), isTrue);
      final chunkRequests = client.requests
          .where((r) =>
              r.headers.values.containsKey('range') &&
              r.headers.values['range'] != 'bytes=0-0')
          .toList();
      expect(chunkRequests, hasLength(4));
      expect(progressNotifications, isNotEmpty);
      expect(writeTagsCalls, 1);
    });

    test('falls back to one sequential request when Range is ignored mid-way',
        () async {
      const total = 3000000;
      final bytes = _m4aBody(total);
      server = (request) async {
        final range = request.headers.values['range'];
        if (range == null) {
          return FakeResponse(
            statusCode: 200,
            body: bytes,
            fixedContentLength: total,
          );
        }
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
        // The whole body for every ranged chunk: Range is ignored.
        return FakeResponse(
          statusCode: 200,
          body: bytes,
          fixedContentLength: total,
        );
      };

      final result = await service.download(_song());

      expect(result.isRight(), isTrue);
      final sequentialRequests = client.requests
          .where((r) => !r.headers.values.containsKey('range'))
          .toList();
      expect(sequentialRequests, hasLength(1));
    });
  });

  group('cancellation', () {
    test('a cancel during the transfer yields a canceled failure', () async {
      final controller = StreamController<List<int>>();
      server = (request) async {
        if (request.headers.values['range'] == 'bytes=0-0') {
          return FakeResponse(
            statusCode: 200,
            body: const [0],
            fixedContentLength: 2 * 1024 * 1024,
          );
        }
        return FakeResponse(
          statusCode: 200,
          bodyStream: controller.stream,
        );
      };

      final song = _song(videoId: 'vidCancel001');
      final stages = <String>[];
      final resultFuture = service.download(
        song,
        onProgress: (progress) => stages.add(_stageName(progress)),
      );
      await _waitFor(() => client.requests.length >= 2);
      service.cancel(song.remoteId!);
      controller.add(_m4aBody(2048));
      final result = await resultFuture;

      result.match(
        (failure) => expect(
          failure.message.toLowerCase(),
          contains('canceled'),
        ),
        (_) => fail('expected a failure'),
      );
      expect(stages, contains('canceled'));
      await controller.close();
    });

    test('a queued duplicate is canceled without consuming a slot', () async {
      service.setMaxConcurrentDownloads(1);
      final controller = StreamController<List<int>>();
      server = (request) async {
        if (request.headers.values['range'] == 'bytes=0-0') {
          return FakeResponse(
            statusCode: 200,
            body: const [0],
            fixedContentLength: 2 * 1024 * 1024,
          );
        }
        return FakeResponse(
          statusCode: 200,
          bodyStream: controller.stream,
        );
      };

      final first = service.download(_song(videoId: 'vidQueue0001'));
      await _waitFor(() => client.requests.length >= 2);

      final secondStages = <String>[];
      final second = service.download(
        _song(videoId: 'vidQueue0002'),
        onProgress: (progress) => secondStages.add(_stageName(progress)),
      );
      await _waitFor(() => secondStages.contains('queued'));
      service.cancel('vidQueue0002');

      controller.add(_m4aBody(2 * 1024 * 1024));
      await controller.close();

      final results = await Future.wait([first, second]);
      expect(results[0].isRight(), isTrue);
      results[1].match(
        (failure) => expect(failure.message, 'Download canceled'),
        (_) => fail('expected a failure'),
      );
    });
  });

  group('bot block', () {
    test('a 403 probe surfaces the classified bot-block failure', () async {
      server = (request) async => FakeResponse(statusCode: 403);
      when(() => ytm.resolveStream(
                any(),
                quality: any(named: 'quality'),
                forceRefresh: any(named: 'forceRefresh'),
                preferM4a: any(named: 'preferM4a'),
              ))
          .thenAnswer((_) async =>
              _stream(duration: const Duration(seconds: 1), bitrateKbps: 64));

      final result = await service.download(_song());

      result.match(
        (failure) => expect(failure.message.toLowerCase(), contains('verif')),
        (_) => fail('expected a failure'),
      );
      verify(() => ytm.resolveStream(
            any(),
            quality: any(named: 'quality'),
            forceRefresh: any(named: 'forceRefresh'),
            preferM4a: any(named: 'preferM4a'),
          )).called(5);
      verify(() => ytm.invalidatePoToken()).called(greaterThanOrEqualTo(1));
    });
  });

  group('resolveDownloadStream', () {
    test('caches the resolved stream and bounds the map at 128 ids', () async {
      when(() => ytm.resolveStream(
            any(),
            quality: any(named: 'quality'),
            forceRefresh: any(named: 'forceRefresh'),
            preferM4a: any(named: 'preferM4a'),
          )).thenAnswer((invocation) async {
        final id = invocation.positionalArguments[0] as String;
        return _stream(videoId: id);
      });

      for (var i = 0; i < 130; i++) {
        await service.resolveDownloadStream('bound$i'.padRight(11, 'x'));
      }

      expect(service.getResolvedStream('bound0xxxxx'), isNull,
          reason: 'the oldest entry must be evicted');
      expect(service.getResolvedStream('bound129xxx'), isNotNull);
    });

    test('forceRefresh invalidates the URL cache first', () async {
      final cache = YtmUrlCache.withClock(FakeClock(DateTime(2026)));
      getIt.registerSingleton<YtmUrlCache>(cache);
      cache.putStream(_stream(), quality: 'high');
      expect(cache.get('vidTest0001'), isNotNull);

      await service.resolveDownloadStream('vidTest0001', 'high', true);

      expect(cache.get('vidTest0001'), isNull);
      verify(() => ytm.resolveStream(
            'vidTest0001',
            quality: 'high',
            forceRefresh: true,
            preferM4a: true,
          )).called(1);
    });
  });

  group('artifact sweeps', () {
    test('deleteArtifactsFor removes only this id\'s files', () async {
      void touch(String name) =>
          File(p.join(tempDir.path, name)).writeAsStringSync('x');

      touch('ytdl_abc.m4a');
      touch('ytdl_abc.m4a.part');
      touch('ytdl_abc.m4a.part0');
      touch('ytdl_abc.parts');
      touch('ytdl_art_abc.jpg');
      touch('ytdl_abcd.m4a');
      touch('ytdl_art_abcd.jpg');

      await service.deleteArtifactsFor('abc');

      expect(File(p.join(tempDir.path, 'ytdl_abc.m4a')).existsSync(), isFalse);
      expect(File(p.join(tempDir.path, 'ytdl_abc.m4a.part')).existsSync(),
          isFalse);
      expect(File(p.join(tempDir.path, 'ytdl_abc.m4a.part0')).existsSync(),
          isFalse);
      expect(
          File(p.join(tempDir.path, 'ytdl_abc.parts')).existsSync(), isFalse);
      expect(
          File(p.join(tempDir.path, 'ytdl_art_abc.jpg')).existsSync(), isFalse);
      expect(File(p.join(tempDir.path, 'ytdl_abcd.m4a')).existsSync(), isTrue);
      expect(
          File(p.join(tempDir.path, 'ytdl_art_abcd.jpg')).existsSync(), isTrue);
    });

    test('deleteArtifactsFor ignores an empty id and a live download',
        () async {
      await service.deleteArtifactsFor('');
      // A live download owns its partial: start one, then try to delete.
      final controller = StreamController<List<int>>();
      server = (request) async {
        if (request.headers.values['range'] == 'bytes=0-0') {
          return FakeResponse(
            statusCode: 200,
            body: const [0],
            fixedContentLength: 2 * 1024 * 1024,
          );
        }
        return FakeResponse(statusCode: 200, bodyStream: controller.stream);
      };
      final song = _song(videoId: 'vidLive0001');
      final resultFuture = service.download(song);
      await _waitFor(() => client.requests.length >= 2);
      final partial = File(p.join(tempDir.path, 'ytdl_vidLive0001.m4a.part'));
      partial.writeAsStringSync('x');
      await service.deleteArtifactsFor('vidLive0001');
      expect(partial.existsSync(), isTrue);

      service.cancel('vidLive0001');
      controller.add(_m4aBody(1024));
      await resultFuture;
      await controller.close();
    });

    test('cleanOrphanPartFiles keeps young, busy and active files', () async {
      void touch(String name, {bool old = false}) {
        final file = File(p.join(tempDir.path, name))..writeAsStringSync('x');
        if (old) {
          file.setLastModifiedSync(
              DateTime.now().subtract(const Duration(minutes: 20)));
        }
      }

      touch('ytdl_old1.m4a.part', old: true);
      touch('ytdl_new1.m4a.part');
      touch('ytdl_busy1.m4a.part', old: true);
      touch('ytdl_active1.m4a.part', old: true);
      touch('other_old.tmp', old: true);

      await service.cleanOrphanPartFiles(
        activePartNames: {'ytdl_active1.m4a.part'},
        protectedVideoIds: {'busy1'},
      );

      expect(File(p.join(tempDir.path, 'ytdl_old1.m4a.part')).existsSync(),
          isFalse);
      expect(File(p.join(tempDir.path, 'ytdl_new1.m4a.part')).existsSync(),
          isTrue);
      expect(File(p.join(tempDir.path, 'ytdl_busy1.m4a.part')).existsSync(),
          isTrue);
      expect(File(p.join(tempDir.path, 'ytdl_active1.m4a.part')).existsSync(),
          isTrue);
      expect(File(p.join(tempDir.path, 'other_old.tmp')).existsSync(), isTrue);
    });
  });

  group('paused markers', () {
    test('markPaused/clearPaused round-trip without throwing', () {
      service.markPaused('vidPaused01');
      service.clearPaused('vidPaused01');
      service.setMaxConcurrentDownloads(0);
      service.setMaxConcurrentDownloads(99);
      expect(service.getDownloadedPath('missing'), isNull);
      expect(service.getResolvedStream('missing'), isNull);
    });
  });

  group('duplicate downloads', () {
    test('a second request for the same video chains onto the first', () async {
      final controller = StreamController<List<int>>();
      server = (request) async {
        if (request.headers.values['range'] == 'bytes=0-0') {
          return FakeResponse(
            statusCode: 200,
            body: const [0],
            fixedContentLength: 2 * 1024 * 1024,
          );
        }
        return FakeResponse(statusCode: 200, bodyStream: controller.stream);
      };

      final song = _song(videoId: 'vidDup00001');
      final first = service.download(song);
      await _waitFor(() => client.requests.length >= 2);
      final second = service.download(song);

      controller.add(_m4aBody(2 * 1024 * 1024));
      await controller.close();

      final results = await Future.wait([first, second]);
      expect(results[0].isRight(), isTrue);
      expect(results[1].isRight(), isTrue);
      expect(writeTagsCalls, 1,
          reason: 'the duplicate must not run its own transfer');
    });
  });
}
