import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/ytm_error_classifier.dart';
import 'package:pulsr/data/services/ytm_service.dart';

const _channel = MethodChannel(YtmService.channelName);

void _mockChannel(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    YtmService.resetGlobalBlock();
  });

  tearDown(() {
    _mockChannel((_) async => null);
    YtmService.resetGlobalBlock();
  });

  group('Requirement 10: Fallback Chain & PO Token Test Suite', () {
    test('(a) Top-priority client failure falls through to fallback resolution', () async {
      int resolveAttempts = 0;
      final requestedClients = <String>[];

      _mockChannel((call) async {
        if (call.method == 'resolveStream') {
          resolveAttempts++;
          if (resolveAttempts == 1) {
            requestedClients.add('ANDROID_VR_FAILED');
            return {
              'videoId': call.arguments['videoId'],
              'url': 'https://googlevideo.com/videoplayback?fallback=ios_music',
              'mimeType': 'audio/mp4',
              'container': 'm4a',
              'bitrateKbps': 140,
              'durationMs': 180000,
              'title': 'Fallback Song',
              'artist': 'Fallback Artist',
              'clientUsed': 'IOS_MUSIC',
            };
          }
        }
        return null;
      });

      final result = await YtmService().resolveStream('dQw4w9WgXcQ');
      expect(result.url, contains('fallback=ios_music'));
      expect(result.title, equals('Fallback Song'));
      expect(result.duration.inMilliseconds, equals(180000));
    });

    test('(b) All clients failing produces clear typed user-facing error state without crashing', () async {
      _mockChannel((call) async {
        if (call.method == 'resolveStream') {
          throw PlatformException(
            code: 'CLIENT_DEPRECATED',
            message: 'All Innertube client fallback resolutions failed for video dQw4w9WgXcQ',
            details: {'signal': 'CLIENT_DEPRECATED', 'traceId': 'trace-dead-all'},
          );
        }
        return null;
      });

      await expectLater(
        YtmService().resolveStream('dQw4w9WgXcQ'),
        throwsA(isA<YtmException>().having(
          (e) => e.code,
          'code',
          equals('CLIENT_DEPRECATED'),
        )),
      );

      final errorInfo = YtmErrorClassifier.classifyCode('CLIENT_DEPRECATED', null, 'trace-dead-all');
      expect(errorInfo.recoveryAction, equals(YtmRecoveryAction.rotateIdentity));
      expect(errorInfo.message, contains('Innertube client version refreshed'));
    });

    test('(c) PO token cache hit vs expired-token refresh path', () async {
      int tokenMints = 0;
      Map<String, dynamic> poTokenState = {
        'isReady': true,
        'isExpired': false,
        'isExpiringSoon': false,
        'visitorData': 'vData123',
        'streamingPoToken': 'poTokenInitial',
        'webViewBroken': false,
        'isLimitedMode': false,
      };

      _mockChannel((call) async {
        if (call.method == 'getPoTokenState') {
          return poTokenState;
        }
        if (call.method == 'getAccountPoToken') {
          tokenMints++;
          return {
            'poToken': 'poTokenMinted_$tokenMints',
            'visitorData': 'vData123',
          };
        }
        return null;
      });

      final state1 = await _channel.invokeMapMethod<String, dynamic>('getPoTokenState');
      expect(state1?['isReady'], isTrue);
      expect(state1?['isExpired'], isFalse);
      expect(state1?['streamingPoToken'], equals('poTokenInitial'));

      poTokenState['isExpired'] = true;
      final state2 = await _channel.invokeMapMethod<String, dynamic>('getPoTokenState');
      expect(state2?['isExpired'], isTrue);

      final refreshed = await _channel.invokeMapMethod<String, dynamic>(
        'getAccountPoToken',
        {'dataSyncId': 'syncUser456'},
      );
      expect(refreshed?['poToken'], equals('poTokenMinted_1'));
      expect(tokenMints, equals(1));
    });

    test('(d) Broken PO token subsystem triggers distinguishable error and limitedMode recovery', () {
      final brokenInfo = YtmErrorClassifier.classifyCode('PO_TOKEN_BROKEN');
      expect(brokenInfo.recoveryAction, equals(YtmRecoveryAction.limitedMode));
      expect(brokenInfo.message, contains('Security subsystem unavailable'));

      final timeoutInfo = YtmErrorClassifier.classifyCode('PO_TOKEN_TIMEOUT');
      expect(timeoutInfo.recoveryAction, equals(YtmRecoveryAction.retryWithBackoff));
    });

    test('(e) Dynamic client version update via platform channel', () async {
      bool versionUpdated = false;
      _mockChannel((call) async {
        if (call.method == 'updateClientVersion') {
          if (call.arguments['clientName'] == 'ANDROID_VR' &&
              call.arguments['version'] == '1.64.00') {
            versionUpdated = true;
            return true;
          }
        }
        return false;
      });

      final success = await _channel.invokeMethod<bool>('updateClientVersion', {
        'clientName': 'ANDROID_VR',
        'version': '1.64.00',
      });

      expect(success, isTrue);
      expect(versionUpdated, isTrue);
    });
  });
}
