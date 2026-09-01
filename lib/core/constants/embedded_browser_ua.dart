// lib/core/constants/embedded_browser_ua.dart
//
// Single source of truth for the User-Agent strings and anti-fingerprint JS
// used by the embedded sign-in / YouTube Music WebView.
//
// KEEP BUMPED: Google cross-references the UA version string against its list
// of current real browser releases. Stale versions are an additional signal
// that the request comes from an embedded WebView.

class EmbeddedBrowserUa {
  EmbeddedBrowserUa._();

  /// Safari 18.3 Mobile User-Agent on iOS (Clean WebKit signature matching Android WebView engine without Gecko/V8 contradictions).
  static const String safariMobile =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1';

  /// Safari 18.3 Desktop User-Agent (macOS)
  static const String safariDesktop =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15';

  /// Chrome 137 Desktop User-Agent (Windows 11) — standard, highly compatible desktop browser
  static const String chromeDesktop =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.7151.119 Safari/537.36';

  /// Chrome 137 Mobile User-Agent on Android — no wv/Version-4.0 tokens.
  static const String chromeMobile =
      'Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.7151.119 Mobile Safari/537.36';

  /// Default mobile sign-in UA: Safari Mobile (WebKit signature without Android WebView leaks)
  static const String mobile = safariMobile;

  /// Default desktop browsing UA: Chrome Desktop (full YouTube Music web experience)
  static const String desktop = chromeDesktop;

  /// JavaScript injected at AT_DOCUMENT_START to normalize browser environment.
  ///
  /// Suppresses the signals Google uses to detect an embedded WebView:
  ///   1. navigator.webdriver (automation flag)
  ///   2. navigator.userAgentData / Client Hints — Android WebView leaks
  ///      {brand:"Android WebView"} here even with a spoofed UA string.
  ///   3. Missing window.chrome / inconsistent navigator.vendor & platform.
  static const String antiFingerprint = r'''
(function () {
  'use strict';

  function def(obj, prop, value) {
    try {
      Object.defineProperty(obj, prop, {
        get: function () { return value; },
        configurable: true,
        enumerable: true
      });
    } catch (e) {}
  }

  // ── 1. Suppress webdriver flag ─────────────────────────────────────────────
  try {
    Object.defineProperty(navigator, 'webdriver', {
      get: function () { return false; },
      configurable: true,
      enumerable: true
    });
  } catch (e) {}

  // ── 2. Detect spoofed UA type ──────────────────────────────────────────────
  var ua        = (navigator.userAgent || '');
  var isSafari  = ua.indexOf('Safari') !== -1 && ua.indexOf('Chrome') === -1;
  var isChrome  = ua.indexOf('Chrome') !== -1;
  var isMobile  = ua.indexOf('Mobile') !== -1 || ua.indexOf('iPhone') !== -1 || ua.indexOf('Android') !== -1;

  // ── 3. Suppress / replace navigator.userAgentData (UA Client Hints) ────────
  if (isSafari) {
    // Real Safari has no userAgentData and no window.chrome
    try {
      Object.defineProperty(navigator, 'userAgentData', {
        get: function () { return undefined; },
        configurable: true,
        enumerable: false
      });
    } catch (e) {}
    try {
      delete window.chrome;
    } catch (e) {}
    def(navigator, 'vendor', 'Apple Computer, Inc.');
    def(navigator, 'platform', isMobile ? 'iPhone' : 'MacIntel');
    def(navigator, 'maxTouchPoints', isMobile ? 5 : 0);
  } else if (isChrome) {
    // Build a self-consistent stub that matches the spoofed Chrome version.
    var chromeMatch = ua.match(/Chrome\/(\d+)/);
    var chromeMajor = chromeMatch ? chromeMatch[1] : '137';

    var brandList = [
      { brand: 'Google Chrome', version: chromeMajor },
      { brand: 'Chromium',      version: chromeMajor },
      { brand: 'Not=A?Brand',   version: '99'        }
    ];
    var platform = isMobile ? 'Android' : 'Windows';

    var uadStub = {
      brands:   brandList,
      mobile:   isMobile,
      platform: platform,
      getHighEntropyValues: function (hints) {
        var all = {
          brands:          brandList,
          mobile:          isMobile,
          platform:        platform,
          platformVersion: isMobile ? '15.0.0' : '15.0.0',
          architecture:    isMobile ? 'arm' : 'x86',
          bitness:         '64',
          model:           isMobile ? 'Pixel 9 Pro' : '',
          uaFullVersion:   chromeMajor + '.0.7151.119',
          fullVersionList: brandList.map(function (b) {
            return { brand: b.brand, version: b.version + '.0.7151.119' };
          })
        };
        var result = {};
        if (hints && hints.forEach) {
          hints.forEach(function (h) {
            if (Object.prototype.hasOwnProperty.call(all, h)) result[h] = all[h];
          });
        } else {
          result = all;
        }
        return Promise.resolve(result);
      },
      toJSON: function () {
        return { brands: brandList, mobile: isMobile, platform: platform };
      }
    };

    try {
      Object.defineProperty(navigator, 'userAgentData', {
        get: function () { return uadStub; },
        configurable: true,
        enumerable: true
      });
    } catch (e) {}

    def(navigator, 'vendor', 'Google Inc.');
    def(navigator, 'platform', isMobile ? 'Linux armv8l' : 'Win32');

    // Ensure window.chrome stub is properly initialized
    if (!window.chrome) {
      try {
        Object.defineProperty(window, 'chrome', {
          value: {
            app:       { isInstalled: false },
            csi:       function () {},
            loadTimes: function () {},
            runtime:   {}
          },
          configurable: true,
          enumerable:   true,
          writable:     true
        });
      } catch (e) {}
    }
  }
})();
''';
}
