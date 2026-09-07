// test/core/services/engine3_resolution_strategy_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/ytm_error_classifier.dart';
import 'package:pulsr/core/services/xdm_backend_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHttpClient mockClient;
  late XdmBackendService xdmService;
  late YtmService ytmService;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.ytdlpBackendEnabled: true,
      PrefsKeys.ytdlpBackendUrl: 'https://test-backend.app',
      PrefsKeys.ytdlpBackendToken: 'test-token',
      PrefsKeys.syncCookiesToBackend: false,
    });

    mockClient = MockHttpClient();
    xdmService = XdmBackendService.withClient(mockClient);

    if (getIt.isRegistered<XdmBackendService>()) {
      getIt.unregister<XdmBackendService>();
    }
    getIt.registerSingleton<XdmBackendService>(xdmService);

    ytmService = YtmService();
    YtmRateLimiter.debugReset();
  });

  tearDown(() {
    if (getIt.isRegistered<XdmBackendService>()) {
      getIt.unregister<XdmBackendService>();
    }
    ytmService.dispose();
  });

  group('Engine 3 Resolution Strategy & Resilience Matrix', () {
    test(
        'INT-1: App resolves stream via Native when backend is unreachable/down',
        () async {
      // Backend is down (503 / exception)
      when(() => mockClient.get(
            any(),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => http.Response('Backend unavailable', 503));

      // Native MethodChannel mock responds with valid stream
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.ytm),
        (MethodCall methodCall) async {
          if (methodCall.method == 'resolveStream') {
            return {
              'videoId': 'test_video_123',
              'url': 'https://googlevideo.com/native_stream',
              'mimeType': 'audio/mp4',
              'container': 'm4a',
              'bitrateKbps': 140,
              'durationMs': 200000,
              'title': 'Native Track',
              'artist': 'Native Artist',
            };
          }
          return null;
        },
      );

      final stream = await ytmService.resolveStream('test_video_123');
      expect(stream, isNotNull);
      expect(stream.url, 'https://googlevideo.com/native_stream');
      expect(stream.title, 'Native Track');

      // Clear mock
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel(PulsrChannels.ytm), null);
    });

    test('INT-2: No backend fallback — native failure surfaces directly',
        () async {
      // Native MethodChannel throws extraction failure
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.ytm),
        (MethodCall methodCall) async {
          if (methodCall.method == 'resolveStream') {
            throw PlatformException(
                code: 'YTM_400', message: 'Client deprecated');
          }
          return null;
        },
      );

      // Remote backend decommissioned: must not be called, native error
      // surfaces directly instead of falling back.
      await expectLater(
        ytmService.resolveStream('fallback_vid'),
        throwsA(isA<YtmException>()),
      );
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel(PulsrChannels.ytm), null);
    });

    test(
        'INT-3: Error code classification maps backend error codes to block signals',
        () {
      final botInfo = YtmErrorClassifier.classifyCode('BOT_CHECK');
      expect(botInfo.signal, YtmBlockSignal.botChallenge);
      expect(
          botInfo.recoveryAction, YtmRecoveryAction.invalidatePoTokenAndRetry);

      final rateInfo = YtmErrorClassifier.classifyCode('RATE_LIMITED');
      expect(rateInfo.signal, YtmBlockSignal.rateLimited);
      expect(rateInfo.recoveryAction, YtmRecoveryAction.retryWithBackoff);

      final geoInfo = YtmErrorClassifier.classifyCode('GEO_BLOCKED');
      expect(geoInfo.signal, YtmBlockSignal.geoBlocked);
      expect(geoInfo.recoveryAction, YtmRecoveryAction.skipToNextTrack);

      final goneInfo = YtmErrorClassifier.classifyCode('CONTENT_GONE');
      expect(goneInfo.signal, YtmBlockSignal.videoGone);
      expect(goneInfo.recoveryAction, YtmRecoveryAction.skipToNextTrack);

      final timeoutInfo = YtmErrorClassifier.classifyCode('RESOLVE_TIMEOUT');
      expect(timeoutInfo.recoveryAction, YtmRecoveryAction.retryWithBackoff);
    });

    test('INT-4: Backend disabled — resolveStream never sends cookies',
        () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.ytdlpBackendEnabled: true,
        PrefsKeys.ytdlpBackendUrl: 'https://test-backend.app',
        PrefsKeys.syncCookiesToBackend: false,
      });

      final result = await xdmService.resolveStream('vid_test',
          cookies: 'sensitive_cookie=value');
      expect(result, isNull);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('INT-5: YtmStream correctly reports isExpiringSoon and isExpired', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final validStream = YtmStream(
        videoId: 'vid1',
        url: 'https://example.com/1',
        mimeType: 'audio/mp4',
        container: 'm4a',
        bitrateKbps: 128,
        duration: Duration.zero,
        title: 'Title',
        artist: 'Artist',
        expiresAt: now + const Duration(hours: 4).inMilliseconds,
      );
      expect(validStream.isExpired, isFalse);
      expect(validStream.isExpiringSoon(), isFalse);

      final expiringSoonStream = YtmStream(
        videoId: 'vid2',
        url: 'https://example.com/2',
        mimeType: 'audio/mp4',
        container: 'm4a',
        bitrateKbps: 128,
        duration: Duration.zero,
        title: 'Title',
        artist: 'Artist',
        expiresAt: now + const Duration(minutes: 2).inMilliseconds,
      );
      expect(expiringSoonStream.isExpired, isFalse);
      expect(expiringSoonStream.isExpiringSoon(), isTrue);

      final expiredStream = YtmStream(
        videoId: 'vid3',
        url: 'https://example.com/3',
        mimeType: 'audio/mp4',
        container: 'm4a',
        bitrateKbps: 128,
        duration: Duration.zero,
        title: 'Title',
        artist: 'Artist',
        expiresAt: now - 1000,
      );
      expect(expiredStream.isExpired, isTrue);
      expect(expiredStream.isExpiringSoon(), isTrue);
    });
  });
}
