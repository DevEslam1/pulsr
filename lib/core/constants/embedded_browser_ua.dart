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

  /// Firefox 140 Mobile User-Agent on Android (Highly resilient against Google
  /// OAuth blocks — Gecko engine has no userAgentData / Client Hints API so
  /// there is nothing extra to suppress.)
  static const String firefoxMobile =
      'Mozilla/5.0 (Android 15; Mobile; rv:140.0) Gecko/140.0 Firefox/140.0';

  /// Firefox 140 Desktop User-Agent (Windows 11)
  static const String firefoxDesktop =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0';

  /// Chrome 137 Mobile User-Agent on Android — no wv/Version-4.0 tokens.
  static const String chromeMobile =
      'Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.7151.119 Mobile Safari/537.36';

  /// Chrome 137 Desktop User-Agent (Windows 11)
  static const String chromeDesktop =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.7151.119 Safari/537.36';

  /// Default mobile sign-in UA: Firefox Mobile (Gecko has no userAgentData so nothing leaks)
  static const String mobile = firefoxMobile;

  /// Default desktop browsing UA: Chrome Desktop (full YouTube Music web experience)
  static const String desktop = chromeDesktop;

  /// JavaScript injected at AT_DOCUMENT_START to normalize browser environment.
  ///
  /// Suppresses the three signals Google uses to detect an embedded WebView:
  ///   1. navigator.webdriver (automation flag)
  ///   2. navigator.userAgentData / Client Hints — Android WebView leaks
  ///      {brand:"Android WebView"} here even with a spoofed UA string.
  ///      For Firefox UAs we hide the property entirely (real Firefox has none).
  ///      For Chrome UAs we replace it with a self-consistent stub.
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
  var ua       = (navigator.userAgent || '');
  var isFirefox = ua.indexOf('Firefox') !== -1;
  var isChrome  = !isFirefox && ua.indexOf('Chrome') !== -1;
  var isMobile  = ua.indexOf('Mobile') !== -1 || ua.indexOf('Android') !== -1;

  // ── 3. Suppress / replace navigator.userAgentData (UA Client Hints) ────────
  //
  // Android WebView exposes userAgentData.brands = [{brand:"Android WebView",…}]
  // and getHighEntropyValues() reveals the real platform — even when the UA
  // string is spoofed. This is the PRIMARY Google WebView detection vector.
  if (isFirefox) {
    // Real Firefox has no userAgentData — hide the property entirely.
    try {
      Object.defineProperty(navigator, 'userAgentData', {
        get: function () { return undefined; },
        configurable: true,
        enumerable: false
      });
    } catch (e) {}
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
          platformVersion: '15.0.0',
          architecture:    isMobile ? 'arm' : 'x86',
          bitness:         '64',
          model:           isMobile ? 'Pixel 9 Pro' : '',
          uaFullVersion:   chromeMajor + '.0.0.0',
          fullVersionList: brandList.map(function (b) {
            return { brand: b.brand, version: b.version + '.0.0.0' };
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
  }

  // ── 4. Normalise other navigator properties ───────────────────────────────
  if (isFirefox) {
    def(navigator, 'vendor', '');
    def(navigator, 'platform', isMobile ? 'Linux armv8l' : 'Win32');
    def(navigator, 'oscpu',    isMobile ? 'Linux armv8l' : 'Windows NT 10.0; Win64; x64');
  } else {
    def(navigator, 'vendor',   'Google Inc.');
    def(navigator, 'platform', isMobile ? 'Linux armv8l' : 'Win32');

    // ── 5. Inject window.chrome stub (absent in some Android WebView builds) ─
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
