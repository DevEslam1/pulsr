// test/core/constants/embedded_browser_ua_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/embedded_browser_ua.dart';

void main() {
  group('EmbeddedBrowserUa constants', () {
    test('expose browser-family markers', () {
      expect(EmbeddedBrowserUa.firefoxMobile, contains('Firefox/154.0'));
      expect(EmbeddedBrowserUa.firefoxMobile, contains('Android 15'));
      expect(EmbeddedBrowserUa.firefoxDesktop, contains('Firefox/154.0'));
      expect(EmbeddedBrowserUa.safariMobile, contains('Version/18.6'));
      expect(EmbeddedBrowserUa.safariMobile, contains('iPhone'));
      expect(EmbeddedBrowserUa.safariDesktop, contains('Version/18.6'));
      expect(EmbeddedBrowserUa.chromeDesktop, contains('Chrome/153.0.8010.36'));
      expect(EmbeddedBrowserUa.chromeMobile, contains('Chrome/153.0.8010.36'));
      expect(EmbeddedBrowserUa.chromeMobile, isNot(contains('wv')));
    });

    test('aliases pick the expected defaults', () {
      expect(EmbeddedBrowserUa.mobile, EmbeddedBrowserUa.chromeMobile);
      expect(EmbeddedBrowserUa.desktop, EmbeddedBrowserUa.firefoxDesktop);
    });

    test('antiFingerprint JS guards Google auth hosts', () {
      expect(EmbeddedBrowserUa.antiFingerprint, contains('google.com'));
      expect(EmbeddedBrowserUa.antiFingerprint, contains('__googleBlockDetected'));
      expect(EmbeddedBrowserUa.antiFingerprint, contains('webdriver'));
    });
  });

  group('normalizeAndroidWebViewUa', () {
    test('falls back to chromeMobile for empty or blank input', () {
      expect(EmbeddedBrowserUa.normalizeAndroidWebViewUa(''),
          EmbeddedBrowserUa.chromeMobile);
      expect(EmbeddedBrowserUa.normalizeAndroidWebViewUa('   '),
          EmbeddedBrowserUa.chromeMobile);
    });

    test('falls back when no Chrome engine token is present', () {
      expect(
        EmbeddedBrowserUa.normalizeAndroidWebViewUa(
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36'),
        EmbeddedBrowserUa.chromeMobile,
      );
    });

    test('strips WebView (wv) and legacy Version tokens, keeps engine version',
        () {
      final normalized = EmbeddedBrowserUa.normalizeAndroidWebViewUa(
        'Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro Build/AP4A; wv) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
        'Chrome/153.0.8010.36 Mobile Safari/537.36',
      );
      expect(normalized, contains('Chrome/153.0.8010.36'));
      expect(normalized, isNot(contains('wv')));
      expect(normalized, isNot(contains('Version/4.0')));
      expect(normalized, contains('Pixel 9 Pro Build/AP4A'));
    });

    test('collapses repeated whitespace', () {
      final normalized =
          EmbeddedBrowserUa.normalizeAndroidWebViewUa('  a   Chrome/1.2  b  ');
      expect(normalized, 'a Chrome/1.2 b');
    });
  });
}
