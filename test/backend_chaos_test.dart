// test/backend_chaos_test.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/services/xdm_backend_service.dart';
import 'package:pulsr/data/services/ytm_service.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';
import 'package:pulsr/domain/models/rate_limit_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHttpClient extends Mock implements http.Client {}
class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHttpClient mockClient;
  late MockSecureStorage mockSecureStorage;
  late XdmBackendService backendService;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.ytdlpBackendEnabled: true,
      PrefsKeys.extractorEngine: 'remote',
    });
    YtmRateLimiter.debugReset();
    mockClient = MockHttpClient();
    mockSecureStorage = MockSecureStorage();
    when(() => mockSecureStorage.read(key: any(named: 'key')))
        .thenAnswer((_) async => 'mock-token');

    backendService = XdmBackendService.withClient(
      mockClient,
      secureStorage: mockSecureStorage,
    );
  });

  group('RateLimitPolicy Domain Tests', () {
    test('native and backend pacing policies calculate clamped exponential backoff with jitter', () {
      const policy = RateLimitPolicy.nativePacing;
      expect(policy.maxTokens, 8);
      expect(policy.refillRate, 4.0);

      final b1 = policy.calculateBackoff(consecutiveFailures: 1, retryAfterSeconds: null);
      expect(b1.inSeconds, greaterThanOrEqualTo(2));
      expect(b1.inSeconds, lessThanOrEqualTo(4));

      final bHonored = policy.calculateBackoff(consecutiveFailures: 1, retryAfterSeconds: 45);
      expect(bHonored.inSeconds, 30); // Clamped to maxBackoffSeconds (30s)
    });
  });

  group('Backend Chaos & Resilience Tests (Phase 1.A)', () {
    test('429 burst trips rate limiter and honors Retry-After header', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                jsonEncode({'error_code': 'RATE_LIMITED', 'message': 'Rate limit hit'}),
                429,
                headers: {'retry-after': '12'},
              ));

      await expectLater(
        () => backendService.resolveStream('test-video-id'),
        throwsA(isA<YtmException>().having((e) => e.code, 'code', 'RATE_LIMITED')),
      );

      expect(YtmRateLimiter.shared.isBackendCoolingDown, isTrue);
      expect(YtmRateLimiter.shared.backendCooldownRemaining.inSeconds, greaterThanOrEqualTo(8));
    });

    test('503 burst trips circuit breaker after 3 consecutive failures', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('Service Unavailable', 503));

      expect(backendService.circuitState, BackendCircuitState.closed);
      expect(backendService.isCircuitOpen, isFalse);

      // Attempt 1
      await backendService.checkHealth(force: true);
      expect(backendService.consecutiveInfraFailures, 1);
      expect(backendService.circuitState, BackendCircuitState.closed);

      // Attempt 2
      await backendService.checkHealth(force: true);
      expect(backendService.consecutiveInfraFailures, 2);
      expect(backendService.circuitState, BackendCircuitState.closed);

      // Attempt 3: Circuit opens
      await backendService.checkHealth(force: true);
      expect(backendService.consecutiveInfraFailures, 3);
      expect(backendService.circuitState, BackendCircuitState.open);
      expect(backendService.isCircuitOpen, isTrue);

      // Subsequent resolveStream is blocked immediately by circuit breaker
      final stream = await backendService.resolveStream('test-video-id');
      expect(stream, isNull);
    });

    test('timeout burst records infra failures and trips circuit breaker', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenThrow(TimeoutException('Request timed out'));

      await backendService.checkHealth(force: true);
      await backendService.checkHealth(force: true);
      await backendService.checkHealth(force: true);

      expect(backendService.isCircuitOpen, isTrue);
    });

    test('malformed JSON response is handled safely without unhandled crashes', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('<<<INVALID JSON>>>', 200));

      final stream = await backendService.resolveStream('test-video-id');
      expect(stream, isNull);
    });

    test('empty response body is handled gracefully', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('', 200));

      final stream = await backendService.resolveStream('test-video-id');
      expect(stream, isNull);
    });

    test('health endpoint uses configured custom backend URL', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.ytdlpBackendUrl: 'https://custom-backend.example.com/',
        PrefsKeys.ytdlpBackendEnabled: true,
      });

      Uri? capturedUri;
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((inv) async {
        capturedUri = inv.positionalArguments.first as Uri;
        return http.Response(
            jsonEncode({
              'status': 'ok',
              'backend_version': '2.5.0',
              'ytdlp_version': '2026.01.01',
              'proxy_pool_size': 12,
            }),
            200);
      });

      final health = await backendService.checkHealth(force: true);
      expect(health.ok, isTrue);
      expect(capturedUri?.host, 'custom-backend.example.com');
      expect(capturedUri?.path, '/health');
      expect(capturedUri?.queryParameters['strict'], 'true');
    });

    test('backend disabled setting immediately bypasses remote resolution', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.ytdlpBackendEnabled: false,
      });

      final stream = await backendService.resolveStream('test-video-id');
      expect(stream, isNull);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });
  });
}

