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

  /// Default mobile sign-in UA: Safari Mobile (WebKit signature without Android WebView leaks).
  static const String mobile = safariMobile;

  /// Default desktop browsing UA: Chrome Desktop (full YouTube Music web experience).
  static const String desktop = chromeDesktop;

  /// JavaScript injected at AT_DOCUMENT_START to normalize browser environment.
  ///
  /// Hides all signals that reveal an Android WebView context:
  ///   • webdriver / userAgentData flags on Navigator.prototype
  ///   • Empty navigator.plugins (WebView has none; Chrome has 5)
  ///   • navigator.languages (WebView returns [] or ['en-US'])
  ///   • Missing window.chrome runtime object (absent in WebView)
  ///   • navigator.connection.type leaking "cellular" or "unknown"
  ///
  /// All overrides use configurable:true so DevTools / page scripts
  /// that inspect the descriptor won't throw.
  static const String antiFingerprint = r'''
(function () {
  'use strict';

  // ── 1. Navigator.prototype flags ────────────────────────────────────────
  try {
    if (typeof Navigator !== 'undefined' && Navigator.prototype) {
      Object.defineProperty(Navigator.prototype, 'webdriver', {
        get: function () { return false; },
        configurable: true,
        enumerable: true
      });
      Object.defineProperty(Navigator.prototype, 'userAgentData', {
        get: function () { return undefined; },
        configurable: true,
        enumerable: false
      });
    }
  } catch (e) {}

  // ── 2. navigator.plugins — Chrome has 5 default PDF plugins; WebView has 0 ─
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

  // ── 3. navigator.languages — WebView often returns [] or just ['en-US'] ─
  try {
    Object.defineProperty(navigator, 'languages', {
      get: function () { return ['en-US', 'en']; },
      configurable: true,
      enumerable: true,
    });
  } catch (e) {}

  // ── 4. window.chrome — absent in WebView, present in Chrome ─────────────
  try {
    if (!window.chrome || typeof window.chrome.runtime === 'undefined') {
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
    }
  } catch (e) {}

  // ── 5. navigator.connection — hide "cellular" / "unknown" transport ──────
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

})();
''';
}
