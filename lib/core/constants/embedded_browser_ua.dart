// lib/core/constants/embedded_browser_ua.dart
//
// Single source of truth for the User-Agent strings and anti-fingerprint JS
// used by the embedded sign-in / YouTube Music WebView.
//
// KEEP BUMPED: Google cross-references the UA version string against its list
// of current real browser releases. Stale versions are an additional signal
// that the request comes from an embedded WebView.
//
// Last bumped: 2026-09-01 — Chrome 138.0.7204.93 / Safari 18.5

class EmbeddedBrowserUa {
  EmbeddedBrowserUa._();

  /// Safari 18.5 Mobile User-Agent on iOS (current stable as of Sept 2026).
  static const String safariMobile =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';

  /// Safari 18.5 Desktop User-Agent (macOS Sequoia 15.5).
  static const String safariDesktop =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15';

  /// Chrome 138 Desktop User-Agent (Windows 11) — current stable as of Sept 2026.
  static const String chromeDesktop =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.7204.93 Safari/537.36';

  /// Chrome 138 Mobile User-Agent on Android — no wv/Version-4.0 tokens.
  static const String chromeMobile =
      'Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.7204.93 Mobile Safari/537.36';

  /// Default mobile sign-in UA: Chrome Mobile on Android — no wv/Version-4.0 tokens.
  static const String mobile = chromeMobile;

  /// Default desktop browsing UA: Chrome Desktop (full YouTube Music web experience).
  static const String desktop = chromeDesktop;

  /// JavaScript injected at AT_DOCUMENT_START to normalize browser environment.
  ///
  /// Hides all signals that reveal an Android WebView context:
  ///   • webdriver suppression
  ///   • Authentic userAgentData / UA Client Hints matching the spoofed browser
  ///   • Standard navigator.plugins / mimeTypes for Chrome
  ///   • navigator.languages and connection normalization
  ///   • Consistent navigator.vendor and navigator.platform
  ///   • DOM-level detection for Google block pages
  ///
  /// All overrides use configurable:true so DevTools / page scripts
  /// that inspect the descriptor won't throw.
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
    if (typeof Navigator !== 'undefined' && Navigator.prototype) {
      Object.defineProperty(Navigator.prototype, 'webdriver', {
        get: function () { return false; },
        configurable: true,
        enumerable: true
      });
    }
  } catch (e) {}

  // ── 2. Detect active spoofed UA type ──────────────────────────────────────
  var ua = (navigator.userAgent || '');
  var isSafari = ua.indexOf('Safari') !== -1 && ua.indexOf('Chrome') === -1;
  var isFirefox = ua.indexOf('Firefox') !== -1;
  var isChrome = !isSafari && !isFirefox;
  var isMobile = ua.indexOf('Mobile') !== -1 || ua.indexOf('Android') !== -1 || ua.indexOf('iPhone') !== -1;

  // ── 3. Handle navigator.userAgentData (UA Client Hints) & browser stubs ───
  if (isChrome) {
    var chromeMatch = ua.match(/Chrome\/(\d+)/);
    var chromeMajor = chromeMatch ? chromeMatch[1] : '138';

    var brandList = [
      { brand: 'Chromium',      version: chromeMajor },
      { brand: 'Google Chrome', version: chromeMajor },
      { brand: 'Not=A?Brand',   version: '24'        }
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
          uaFullVersion:   chromeMajor + '.0.7204.93',
          fullVersionList: brandList.map(function (b) {
            return { brand: b.brand, version: b.version + '.0.7204.93' };
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

    // Ensure window.chrome stub is present for Chrome
    if (!window.chrome || typeof window.chrome.runtime === 'undefined') {
      try {
        Object.defineProperty(window, 'chrome', {
          value: {
            app: {
              isInstalled: false,
              InstallState: { DISABLED: 'disabled', INSTALLED: 'installed', NOT_INSTALLED: 'not_installed' },
              RunningState: { CANNOT_RUN: 'cannot_run', READY_TO_RUN: 'ready_to_run', RUNNING: 'running' },
            },
            runtime: {
              connect: function () {},
              sendMessage: function () {},
            },
            csi: function () {},
            loadTimes: function () { return null; },
          },
          configurable: true,
          writable: true,
          enumerable: true,
        });
      } catch (e) {}
    }
  } else if (isSafari) {
    try {
      Object.defineProperty(navigator, 'userAgentData', {
        get: function () { return undefined; },
        configurable: true,
        enumerable: false
      });
    } catch (e) {}
    try { delete window.chrome; } catch (e) {}
    def(navigator, 'vendor', 'Apple Computer, Inc.');
    def(navigator, 'platform', isMobile ? 'iPhone' : 'MacIntel');
    def(navigator, 'maxTouchPoints', isMobile ? 5 : 0);
  } else if (isFirefox) {
    try {
      Object.defineProperty(navigator, 'userAgentData', {
        get: function () { return undefined; },
        configurable: true,
        enumerable: false
      });
    } catch (e) {}
    try { delete window.chrome; } catch (e) {}
    def(navigator, 'vendor', '');
    def(navigator, 'platform', isMobile ? 'Linux armv8l' : 'Win32');
    def(navigator, 'oscpu', isMobile ? 'Linux armv8l' : 'Windows NT 10.0; Win64; x64');
  }

  // ── 4. navigator.plugins — 5 standard PDF plugins for Chrome ─────────────
  if (isChrome) {
    try {
      var fakePlugins = (function () {
        var names = [
          'PDF Viewer',
          'Chrome PDF Viewer',
          'Chromium PDF Viewer',
          'Microsoft Edge PDF Viewer',
          'WebKit built-in PDF',
        ];
        var mimeType = { type: 'application/pdf', suffixes: 'pdf', description: '' };
        var plugins = [];
        for (var i = 0; i < names.length; i++) {
          var p = {
            name: names[i],
            description: '',
            filename: 'internal-pdf-viewer',
            length: 1,
            0: mimeType,
            namedItem: function () { return null; },
            item: function (n) { return n === 0 ? mimeType : null; },
          };
          plugins.push(p);
        }
        plugins.namedItem = function (n) {
          for (var j = 0; j < plugins.length; j++) {
            if (plugins[j].name === n) return plugins[j];
          }
          return null;
        };
        plugins.item = function (n) { return plugins[n] || null; };
        plugins.refresh = function () {};
        plugins.length = names.length;
        return plugins;
      })();
      Object.defineProperty(navigator, 'plugins', {
        get: function () { return fakePlugins; },
        configurable: true,
        enumerable: true,
      });
      Object.defineProperty(navigator, 'mimeTypes', {
        get: function () {
          return [{
            type: 'application/pdf',
            suffixes: 'pdf',
            description: '',
            enabledPlugin: fakePlugins[0],
          }];
        },
        configurable: true,
        enumerable: true,
      });
    } catch (e) {}
  }

  // ── 5. navigator.languages ───────────────────────────────────────────────
  try {
    Object.defineProperty(navigator, 'languages', {
      get: function () { return ['en-US', 'en']; },
      configurable: true,
      enumerable: true,
    });
  } catch (e) {}

  // ── 6. navigator.connection ───────────────────────────────────────────────
  try {
    var conn = navigator.connection ||
               navigator.mozConnection ||
               navigator.webkitConnection;
    if (conn) {
      var overrides = { effectiveType: '4g', type: 'wifi', downlink: 10, rtt: 50 };
      for (var key in overrides) {
        if (Object.prototype.hasOwnProperty.call(overrides, key)) {
          try {
            var val = overrides[key];
            Object.defineProperty(conn, key, {
              get: (function (v) { return function () { return v; }; })(val),
              configurable: true,
              enumerable: true,
            });
          } catch (ex) {}
        }
      }
    }
  } catch (e) {}

  // ── 7. DOM block detector flag ───────────────────────────────────────────
  try {
    window.__googleBlockDetected = false;
    var checkBlock = function () {
      try {
        var bodyText = (document.body && (document.body.innerText || document.body.textContent)) || '';
        if (bodyText.length > 0) {
          var lower = bodyText.toLowerCase();
          if (lower.indexOf("couldn't sign you in") !== -1 ||
              lower.indexOf("this browser or app may not be secure") !== -1) {
            window.__googleBlockDetected = true;
          }
        }
      } catch (err) {}
    };
    if (typeof MutationObserver !== 'undefined') {
      var observer = new MutationObserver(checkBlock);
      if (document.documentElement) {
        observer.observe(document.documentElement, { childList: true, subtree: true });
      } else {
        document.addEventListener('DOMContentLoaded', function () {
          observer.observe(document.documentElement, { childList: true, subtree: true });
        });
      }
    }
  } catch (e) {}

})();
''';
}
