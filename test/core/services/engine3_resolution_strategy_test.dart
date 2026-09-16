// test/core/services/engine3_resolution_strategy_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/errors/ytm_error_classifier.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHttpClient mockClient;
  late YtmService ytmService;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    mockClient = MockHttpClient();
    ytmService = YtmService();
    YtmRateLimiter.debugReset();
  });

  tearDown(() {
    ytmService.dispose();
  });

  group('Engine 3 Resolution Strategy & Resilience Matrix (on-device only)', () {
    test('INT-1: App resolves the stream via the native extractor', () async {
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

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel(PulsrChannels.ytm), null);
    });

    test('INT-2: native failure surfaces directly with no HTTP fallback',
        () async {
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

      await expectLater(
        ytmService.resolveStream('fallback_vid'),
        throwsA(isA<YtmException>()),
      );
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel(PulsrChannels.ytm), null);
    });

    test('INT-3: error code classification maps codes to block signals', () {
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

    test('INT-4: YtmStream correctly reports isExpiringSoon and isExpired', () {
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
