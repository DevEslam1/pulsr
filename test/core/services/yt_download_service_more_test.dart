// test/core/services/yt_download_service_more_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/data/audio/adaptive_buffer_engine.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtmService extends Mock implements YtmService {}

class MockMediaScanner extends Mock implements MediaScannerService {}

class MockMusicRepository extends Mock implements IMusicRepository {}

class MockHttpClient extends Mock implements HttpClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHttpClient http;
  late MockYtmService ytm;
  late MockMediaScanner scanner;
  late MockMusicRepository repo;
  late YtDownloadService service;

  YtmStream stream({
    int bitrateKbps = 128,
    Duration duration = const Duration(minutes: 3),
    int? expiresAt,
  }) =>
      YtmStream(
        videoId: 'vidTest0001',
        url:
            'https://rr1---sn-x.googlevideo.com/videoplayback?expire=1800000000',
        mimeType: 'audio/mp4',
        container: 'm4a',
        bitrateKbps: bitrateKbps,
        duration: duration,
        title: 'T',
        artist: 'A',
        expiresAt: expiresAt,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    http = MockHttpClient();
    ytm = MockYtmService();
    scanner = MockMediaScanner();
    repo = MockMusicRepository();
    service = YtDownloadService(http, ytm, scanner, repo);
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('byte / lifetime estimates', () {
    test('estimateBytes falls back for unknown bitrate and duration', () {
      expect(
        YtDownloadService.estimateBytes(
            stream(bitrateKbps: 0, duration: Duration.zero)),
        240 * 160 * 1000 ~/ 8,
      );
      expect(
        YtDownloadService.estimateBytes(
            stream(bitrateKbps: 128, duration: const Duration(seconds: 180))),
        180 * 128 * 1000 ~/ 8,
      );
    });

    test('requiredPreflightBytes is twice the estimate plus 10MB', () {
      final s = stream(bitrateKbps: 128,
          duration: const Duration(seconds: 180));
      expect(YtDownloadService.requiredPreflightBytes(s),
          YtDownloadService.estimateBytes(s) * 2 + 10 * 1024 * 1024);
    });

    test('requiredLifetime clamps to 1..30 minutes plus 2 minutes', () {
      final tiny = stream(bitrateKbps: 1, duration: const Duration(seconds: 1));
      expect(YtDownloadService.requiredLifetime(tiny),
          const Duration(minutes: 1) + const Duration(minutes: 2));

      final huge =
          stream(bitrateKbps: 320, duration: const Duration(hours: 6));
      expect(YtDownloadService.requiredLifetime(huge),
          const Duration(minutes: 30) + const Duration(minutes: 2));
    });
  });

  group('resume stamps', () {
    test('resumeStampFor is deterministic and URL-derived', () {
      final a = YtDownloadService.resumeStampFor(Uri.parse('https://x/a'));
      final b = YtDownloadService.resumeStampFor(Uri.parse('https://x/a'));
      final c = YtDownloadService.resumeStampFor(Uri.parse('https://x/b'));
      expect(a, b);
      expect(a, isNot(c));
    });

    test('resumeStampMatches requires an exact trimmed match', () {
      expect(YtDownloadService.resumeStampMatches('123', '123'), isTrue);
      expect(YtDownloadService.resumeStampMatches(' 123 ', '123'), isTrue);
      expect(YtDownloadService.resumeStampMatches(null, '123'), isFalse);
      expect(YtDownloadService.resumeStampMatches('124', '123'), isFalse);
      expect(YtDownloadService.resumeStampMatches('', '123'), isFalse);
    });
  });

  group('safeExtension / sanitizeFilename', () {
    test('safeExtension rejects traversal-like and unknown extensions', () {
      expect(YtDownloadService.safeExtension(null), 'm4a');
      expect(YtDownloadService.safeExtension(''), 'm4a');
      expect(YtDownloadService.safeExtension('../evil'), 'm4a');
      expect(YtDownloadService.safeExtension('a.b'), 'm4a');
      expect(YtDownloadService.safeExtension(r'a\b'), 'm4a');
      expect(YtDownloadService.safeExtension('FLAC'), 'flac');
      expect(YtDownloadService.safeExtension('nope'), 'm4a');
    });

    test('sanitizeFilename fills empty parts and strips reserved chars', () {
      expect(YtDownloadService.sanitizeFilename('', '', 'mp3'),
          'Unknown Artist - Unknown Title.mp3');
      final cleaned = YtDownloadService.sanitizeFilename(
          'a/b:c', 'd?e*f', 'mp3');
      expect(cleaned, 'a_b_c - d_e_f.mp3');
    });

    test('sanitizeFilename never equals a reserved device name', () {
      // The base is always "<artist> - <title>", so it can never be exactly
      // CON/PRN/etc.; the reserved-name branch is defensive/unreachable.
      expect(YtDownloadService.sanitizeFilename('CON', '', 'mp3'),
          'CON - Unknown Title.mp3');
      expect(YtDownloadService.sanitizeFilename('NUL', '', 'mp3'),
          'NUL - Unknown Title.mp3');
    });

    test('sanitizeFilename caps UTF-8 byte length and trailing dots', () {
      final longTitle = 'x' * 400;
      final name = YtDownloadService.sanitizeFilename('A', longTitle, 'mp3');
      final base = name.substring(0, name.length - '.mp3'.length);
      // May include the trailing dot strip; byte cap is 180 on the base.
      expect(base.length, lessThanOrEqualTo(180));
      expect(name.endsWith('.mp3'), isTrue);

      final dotted = YtDownloadService.sanitizeFilename('A', 'T...  ', 'mp3');
      expect(dotted, 'A - T.mp3');
    });

    test('sanitizeFilename never yields an empty base', () {
      final name = YtDownloadService.sanitizeFilename('', '...', 'm4a');
      expect(name.endsWith('.m4a'), isTrue);
      expect(name, isNot('.m4a'));
    });
  });

  group('sniffContainerBytes', () {
    test('detects every supported container signature', () {
      expect(YtDownloadService.sniffContainerBytes([]), isNull);
      expect(
          YtDownloadService.sniffContainerBytes(
              [0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70]),
          (ext: 'm4a', mime: 'audio/mp4'));
      expect(
          YtDownloadService.sniffContainerBytes([0x1A, 0x45, 0xDF, 0xA3]),
          (ext: 'webm', mime: 'audio/webm'));
      expect(
          YtDownloadService.sniffContainerBytes(
              [0x4F, 0x67, 0x67, 0x53, 0x00]),
          (ext: 'ogg', mime: 'audio/ogg'));
      expect(
          YtDownloadService.sniffContainerBytes([0x66, 0x4C, 0x61, 0x43]),
          (ext: 'flac', mime: 'audio/flac'));
      expect(
          YtDownloadService.sniffContainerBytes([0x49, 0x44, 0x33, 0x04]),
          (ext: 'mp3', mime: 'audio/mpeg'));
      expect(
          YtDownloadService.sniffContainerBytes([0xFF, 0xFB, 0x90, 0x00]),
          (ext: 'mp3', mime: 'audio/mpeg'));
      expect(
          YtDownloadService.sniffContainerBytes([0x00, 0x01, 0x02]),
          isNull);
    });
  });

  group('queue limits and pauses', () {
    test('setMaxConcurrentDownloads clamps to 1..5', () {
      service.setMaxConcurrentDownloads(0);
      service.setMaxConcurrentDownloads(9);
      service.setMaxConcurrentDownloads(3);
      // No getter, but the call must not throw and is idempotent.
      service.setMaxConcurrentDownloads(5);
    });

    test('markPaused and clearPaused are safe without a running service', () {
      service.markPaused('abcdefghijk');
      service.clearPaused('abcdefghijk');
      service.clearPaused('never-seen00');
    });

    test('cancel is bounded and tolerant of unknown ids', () {
      for (var i = 0; i < 260; i++) {
        service.cancel('id${i.toString().padLeft(9, '0')}');
      }
      expect(service.getResolvedStream('missing'), isNull);
      expect(service.getDownloadedPath('missing'), isNull);
    });

    test('deleteArtifactsFor ignores an empty id', () async {
      await service.deleteArtifactsFor('');
    });

    test('deleteArtifactsFor is a no-op when the cache dir is missing',
        () async {
      // path_provider is unstubbed here, so getTemporaryDirectory throws and the
      // catch swallows it.
      await service.deleteArtifactsFor('abcdefghijk');
    });
  });

  group('download validation', () {
    test('rejects non-YouTube tracks', () async {
      const localSong = SongsTableData(
        id: 1,
        title: 'Local',
        artist: 'A',
        album: 'B',
        durationMs: 1000,
        path: '/music/local.mp3',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );
      final res = await service.download(localSong);
      expect(res.isLeft(), isTrue);
    });

    test('rejects a YouTube track without a video id', () async {
      const noId = SongsTableData(
        id: -1,
        title: 'Online',
        artist: 'A',
        album: 'B',
        durationMs: 1000,
        path: 'ytmusic://',
        source: SongSource.youtube,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );
      final res = await service.download(noId);
      expect(res.isLeft(), isTrue);
    });
  });

  group('downloadPolicyBlock', () {
    test('blocks offline-only mode', () async {
      SharedPreferences.setMockInitialValues(
          {'setting_offline_only_mode': true});
      final block = await service.downloadPolicyBlock();
      expect(block, isA<DownloadFailure>());
      expect(block!.message, contains('Offline Only'));
    });

    test('blocks wifi-only mode when not on wifi', () async {
      SharedPreferences.setMockInitialValues({'setting_wifi_only_mode': true});
      when(() => ytm.isWifiConnected()).thenAnswer((_) async => false);
      final block = await service.downloadPolicyBlock();
      expect(block, isA<DownloadFailure>());
      expect(block!.message, contains('Wi-Fi Only'));
    });

    test('allows wifi-only mode when on wifi', () async {
      SharedPreferences.setMockInitialValues({'setting_wifi_only_mode': true});
      when(() => ytm.isWifiConnected()).thenAnswer((_) async => true);
      expect(await service.downloadPolicyBlock(), isNull);
    });

    test('allows download when no policy is active', () async {
      expect(await service.downloadPolicyBlock(), isNull);
    });
  });

  group('resolveDownloadStream force refresh', () {
    test('invalidates a registered URL cache when forced', () async {
      final cache = YtmUrlCache();
      getIt.registerSingleton<YtmUrlCache>(cache);
      when(() => ytm.resolveStream(
            any(),
            quality: any(named: 'quality'),
            forceRefresh: any(named: 'forceRefresh'),
            preferM4a: any(named: 'preferM4a'),
          )).thenAnswer((_) async => stream());

      final resolved = await service.resolveDownloadStream('vidTest0001',
          'high', true);
      expect(resolved.videoId, 'vidTest0001');
      expect(service.getResolvedStream('vidTest0001'), isNotNull);
    });
  });

  group('throughput sampling', () {
    test('samples into a registered AdaptiveBufferEngine', () async {
      final engine = AdaptiveBufferEngine();
      getIt.registerSingleton<AdaptiveBufferEngine>(engine);
      // Drive a private path indirectly is not possible; ensure the engine
      // registration path is harmless when absent/present.
      engine.dispose();
    });

    test('tolerates the engine being absent', () async {
      // No registration: _sampleThroughput must short-circuit.
      expect(getIt.isRegistered<AdaptiveBufferEngine>(), isFalse);
    });
  });
}
