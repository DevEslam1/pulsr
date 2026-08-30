// lib/core/constants/embedded_browser_ua.dart
//
// Single source of truth for the User-Agent strings and anti-fingerprint JS
// used by the embedded sign-in / YouTube Music WebView.

class EmbeddedBrowserUa {
  EmbeddedBrowserUa._();

  /// Firefox 135 Mobile User-Agent on Android (Highly resilient against Google OAuth blocks)
  static const String firefoxMobile =
      'Mozilla/5.0 (Android 14; Mobile; rv:135.0) Gecko/135.0 Firefox/135.0';

  /// Firefox 135 Desktop User-Agent (Windows 11)
  static const String firefoxDesktop =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:135.0) Gecko/20100101 Firefox/135.0';

  /// Chrome 133 Mobile User-Agent on Android (Clean without wv/Version-4.0 tokens)
  static const String chromeMobile =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.6943.122 Mobile Safari/537.36';

  /// Chrome 133 Desktop User-Agent (Windows 11)
  static const String chromeDesktop =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.6943.122 Safari/537.36';

  /// Default mobile sign-in UA: Firefox Mobile (most resilient against Google OAuth WebView block)
  static const String mobile = firefoxMobile;

  /// Default desktop browsing UA: Chrome Desktop (full YouTube Music web experience)
  static const String desktop = chromeDesktop;

  /// JavaScript injected at AT_DOCUMENT_START to normalize browser environment.
  static const String antiFingerprint = r'''
(function () {
  'use strict';
  function tryDefine(obj, prop, value) {
    try {
      Object.defineProperty(obj, prop, {
        get: function () { return value; },
        configurable: true,
        enumerable: true
      });
    } catch (e) {}
  }

  // ── 1. Normalize webdriver ──────────────────────────────────────────────────
  try {
    Object.defineProperty(navigator, 'webdriver', {
      get: function () { return false; },
      configurable: true,
      enumerable: true
    });
  } catch (e) {}

  var ua = (navigator.userAgent || '');
  var isFirefox = ua.indexOf('Firefox') !== -1;
  var isMobile = ua.indexOf('Mobile') !== -1 || ua.indexOf('Android') !== -1;

  if (isFirefox) {
    // Firefox environment emulation
    try {
      Object.defineProperty(navigator, 'userAgentData', {
        get: function () { return undefined; },
        configurable: true,
        enumerable: false
      });
    } catch (e) {}
    tryDefine(navigator, 'vendor', '');
    tryDefine(navigator, 'platform', isMobile ? 'Linux armv8l' : 'Win32');
    tryDefine(navigator, 'oscpu', isMobile ? 'Linux armv8l' : 'Windows NT 10.0; Win64; x64');
  } else {
    // Chromium / Chrome environment normalization
    tryDefine(navigator, 'vendor', 'Google Inc.');
    tryDefine(navigator, 'platform', isMobile ? 'Linux armv8l' : 'Win32');
    if (!window.chrome) {
      window.chrome = {
        app: { isInstalled: false },
        csi: function () {},
        loadTimes: function () {},
        runtime: {}
      };
    }
  }
})();
''';
}
