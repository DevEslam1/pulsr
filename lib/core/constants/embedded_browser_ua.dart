// lib/core/constants/embedded_browser_ua.dart
//
// Single source of truth for the User-Agent strings and anti-fingerprint JS
// used by the embedded sign-in / YouTube Music WebView.
//
// KEEP BUMPED: Google cross-references the UA version string against its list
// of current real browser releases. Stale versions are an additional signal
// that the request comes from an embedded WebView.
//
// Last bumped: 2026-09-05 — Firefox 136.0 (latest stable) / Chrome 138.0.7204.93 / Safari 18.5

class EmbeddedBrowserUa {
  EmbeddedBrowserUa._();

  /// Firefox 136.0 Mobile User-Agent on Android (latest stable release).
  static const String firefoxMobile =
      'Mozilla/5.0 (Android 15; Mobile; rv:136.0) Gecko/136.0 Firefox/136.0';

  /// Firefox 136.0 Desktop User-Agent (Windows 10/11 x64, latest stable release).
  static const String firefoxDesktop =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0';

  /// Safari 18.5 Mobile User-Agent on iOS.
  static const String safariMobile =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';

  /// Safari 18.5 Desktop User-Agent (macOS Sequoia 15.5).
  static const String safariDesktop =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15';

  /// Chrome 138 Desktop User-Agent (Windows 11).
  static const String chromeDesktop =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.7204.93 Safari/537.36';

  /// Chrome 138 Mobile User-Agent on Android — no wv/Version-4.0 tokens.
  static const String chromeMobile =
      'Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.7204.93 Mobile Safari/537.36';

  /// Default mobile sign-in UA: Authentic Chrome Mobile on Android.
  /// Matches the underlying Chromium WebView engine and avoids BotGuard Gecko/Blink mismatches.
  static const String mobile = chromeMobile;

  /// Default desktop browsing UA: Firefox Desktop on Windows.
  static const String desktop = firefoxDesktop;

  /// JavaScript injected at AT_DOCUMENT_START to normalize browser environment.
  ///
  /// Hides all signals that reveal an Android WebView context and emulates authentic
  /// browser environment matching the spoofed User-Agent:
  ///   • webdriver suppression & automation artifacts cleanup
  ///   • Authentic userAgentData / UA Client Hints matching the spoofed browser
  ///   • Firefox environment emulation (strips window.chrome, userAgentData, sets vendor/productSub/oscpu/buildID)
  ///   • Standard navigator.plugins / mimeTypes for desktop browsers
  ///   • navigator.languages and connection normalization
  ///   • WebGL emulator renderer masking (masks SwiftShader / llvmpipe on emulators)
  ///   • DOM-level detection for Google block pages
  ///
  /// All overrides use configurable:true so DevTools / page scripts
  /// that inspect the descriptor won't throw.
  static const String antiFingerprint = r'''
(function () {
  'use strict';

  // CRITICAL: Do NOT tamper with native prototypes on Google or YouTube authentication domains.
  // Google BotGuard actively tests Function.prototype.toString on Intl, WebGL, and Navigator APIs.
  // Any non-native wrapper immediately trips Google's "This browser or app may not be secure" interstitial.
  try {
    var host = (window.location && window.location.hostname) || '';
    if (host.indexOf('google.com') !== -1 ||
        host.indexOf('youtube.com') !== -1 ||
        host.indexOf('gstatic.com') !== -1) {
      return;
    }
  } catch (e) {}

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
  try {
    Object.defineProperty(navigator, 'webdriver', {
      get: function () { return false; },
      configurable: true,
      enumerable: true
    });
  } catch (e) {}

  // ── 2. Clean automation / bot instrumentation traces ───────────────────────
  try {
    var automationKeys = [
      '__webdriver_evaluate',
      '__selenium_evaluate',
      '__webdriver_script_function',
      '__webdriver_script_func',
      '__webdriver_script_fn',
      '__fxdriver_evaluate',
      '__driver_unwrapped',
      '__webdriver_unwrapped',
      '__driver_evaluate',
      '__selenium_unwrapped',
      '__fxdriver_unwrapped',
      'calledSelenium',
      '_Selenium_IDE_Recorder',
      '_selenium',
      'callSelenium',
      '_WEBDRIVER_ELEM_CACHE',
      'driver-evaluate',
      'domAutomation',
      'domAutomationController'
    ];
    automationKeys.forEach(function (k) {
      try { delete window[k]; } catch (ex) {}
      try { delete document[k]; } catch (ex) {}
    });
    for (var wk in window) {
      if (wk.indexOf('cdc_') === 0 || wk.indexOf('$cdc_') === 0) {
        try { delete window[wk]; } catch (ex) {}
      }
    }
    for (var dk in document) {
      if (dk.indexOf('cdc_') === 0 || dk.indexOf('$cdc_') === 0) {
        try { delete document[dk]; } catch (ex) {}
      }
    }
  } catch (e) {}

  // ── 3. Detect active spoofed UA type ──────────────────────────────────────
  var ua = (navigator.userAgent || '');
  var isSafari = ua.indexOf('Safari') !== -1 && ua.indexOf('Chrome') === -1;
  var isFirefox = ua.indexOf('Firefox') !== -1;
  var isChrome = !isSafari && !isFirefox;
  var isMobile = ua.indexOf('Mobile') !== -1 || ua.indexOf('Android') !== -1 || ua.indexOf('iPhone') !== -1;

  // ── 4. Handle navigator.userAgentData & browser-specific stubs ─────────────
  if (isFirefox) {
    // Firefox strictly does not implement UA Client Hints (navigator.userAgentData)
    try {
      delete Navigator.prototype.userAgentData;
    } catch (e) {}
    try {
      delete navigator.userAgentData;
    } catch (e) {}
    if ('userAgentData' in navigator) {
      try {
        Object.defineProperty(navigator, 'userAgentData', {
          get: function () { return undefined; },
          configurable: true,
          enumerable: false
        });
      } catch (e) {}
    }
    if (typeof Navigator !== 'undefined' && Navigator.prototype) {
      try {
        Object.defineProperty(Navigator.prototype, 'userAgentData', {
          get: function () { return undefined; },
          configurable: true,
          enumerable: false
        });
      } catch (e) {}
    }

    // Firefox does not have window.chrome
    try {
      delete window.chrome;
    } catch (e) {}
    try {
      delete Object.getPrototypeOf(window).chrome;
    } catch (e) {}
    if ('chrome' in window) {
      try {
        Object.defineProperty(window, 'chrome', {
          value: undefined,
          writable: true,
          configurable: true,
          enumerable: false
        });
      } catch (e) {}
    }

    // Standard Firefox navigator attributes
    def(navigator, 'vendor', '');
    def(navigator, 'product', 'Gecko');
    def(navigator, 'productSub', '20100101');
    def(navigator, 'buildID', '20181001000000');
    def(navigator, 'platform', isMobile ? 'Linux armv8l' : 'Win32');
    def(navigator, 'oscpu', isMobile ? 'Linux armv8l' : 'Windows NT 10.0; Win64; x64');
    def(navigator, 'appVersion', isMobile ? '5.0 (Android 15)' : '5.0 (Windows)');
    def(navigator, 'maxTouchPoints', isMobile ? 5 : 0);
    def(navigator, 'doNotTrack', 'unspecified');

    // External search provider object stub for Firefox
    if (!window.external || typeof window.external.AddSearchProvider === 'undefined') {
      try {
        window.external = window.external || {};
        window.external.AddSearchProvider = function () {};
        window.external.IsSearchProviderInstalled = function () {};
      } catch (e) {}
    }

    // Standard PDF plugins for desktop Firefox
    if (!isMobile) {
      try {
        var ffPlugins = (function () {
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
          get: function () { return ffPlugins; },
          configurable: true,
          enumerable: true,
        });
        Object.defineProperty(navigator, 'mimeTypes', {
          get: function () {
            return [{
              type: 'application/pdf',
              suffixes: 'pdf',
              description: '',
              enabledPlugin: ffPlugins[0],
            }];
          },
          configurable: true,
          enumerable: true,
        });
      } catch (e) {}
    } else {
      try {
        var emptyPlugins = [];
        emptyPlugins.namedItem = function () { return null; };
        emptyPlugins.item = function () { return null; };
        emptyPlugins.refresh = function () {};
        emptyPlugins.length = 0;
        Object.defineProperty(navigator, 'plugins', {
          get: function () { return emptyPlugins; },
          configurable: true,
          enumerable: true,
        });
      } catch (e) {}
    }
  } else if (isSafari) {
    try {
      delete Navigator.prototype.userAgentData;
    } catch (e) {}
    try {
      delete navigator.userAgentData;
    } catch (e) {}
    try {
      Object.defineProperty(navigator, 'userAgentData', {
        get: function () { return undefined; },
        configurable: true,
        enumerable: false
      });
    } catch (e) {}
    if (typeof Navigator !== 'undefined' && Navigator.prototype) {
      try {
        Object.defineProperty(Navigator.prototype, 'userAgentData', {
          get: function () { return undefined; },
          configurable: true,
          enumerable: false
        });
      } catch (e) {}
    }
    try { delete window.chrome; } catch (e) {}
    try { delete Object.getPrototypeOf(window).chrome; } catch (e) {}
    def(navigator, 'vendor', 'Apple Computer, Inc.');
    def(navigator, 'platform', isMobile ? 'iPhone' : 'MacIntel');
    def(navigator, 'maxTouchPoints', isMobile ? 5 : 0);
  } else if (isChrome) {
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
      if (typeof Navigator !== 'undefined' && Navigator.prototype) {
        Object.defineProperty(Navigator.prototype, 'userAgentData', {
          get: function () { return uadStub; },
          configurable: true,
          enumerable: true
        });
      }
    } catch (e) {}

    try {
      Object.defineProperty(navigator, 'userAgentData', {
        get: function () { return uadStub; },
        configurable: true,
        enumerable: true
      });
    } catch (e) {}

    def(navigator, 'vendor', 'Google Inc.');
    def(navigator, 'platform', isMobile ? 'Linux armv8l' : 'Win32');
    def(navigator, 'maxTouchPoints', isMobile ? 5 : 0);

    // Ensure window.chrome stub is present for Chrome
    if (!window.chrome || typeof window.chrome.runtime === 'undefined') {
      try {
        Object.defineProperty(window.chrome || {}, 'webview', {
          value: undefined,
          configurable: true,
          writable: true,
        });
      } catch (e) {}
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
    } else {
      try {
        if (window.chrome.webview) {
          delete window.chrome.webview;
        }
      } catch (e) {}
    }

    try {
      var chromePlugins = (function () {
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
        get: function () { return chromePlugins; },
        configurable: true,
        enumerable: true,
      });
      Object.defineProperty(navigator, 'mimeTypes', {
        get: function () {
          return [{
            type: 'application/pdf',
            suffixes: 'pdf',
            description: '',
            enabledPlugin: chromePlugins[0],
          }];
        },
        configurable: true,
        enumerable: true,
      });
    } catch (e) {}
  }

  // ── 5. navigator.languages & language ────────────────────────────────────
  try {
    Object.defineProperty(navigator, 'languages', {
      get: function () { return ['en-US', 'en']; },
      configurable: true,
      enumerable: true,
    });
    Object.defineProperty(navigator, 'language', {
      get: function () { return 'en-US'; },
      configurable: true,
      enumerable: true,
    });
  } catch (e) {}

  // ── 5.1 Geo & Timezone normalization (Egypt Region) ────────────────────────
  try {
    if (typeof Intl !== 'undefined' && Intl.DateTimeFormat && Intl.DateTimeFormat.prototype.resolvedOptions) {
      var origResolved = Intl.DateTimeFormat.prototype.resolvedOptions;
      Intl.DateTimeFormat.prototype.resolvedOptions = function () {
        var res = origResolved.apply(this, arguments);
        res.timeZone = 'Africa/Cairo';
        return res;
      };
    }
  } catch (e) {}
  try {
    if (typeof navigator !== 'undefined' && navigator.geolocation) {
      var fakePos = {
        coords: {
          latitude: 30.0444,
          longitude: 31.2357,
          accuracy: 10,
          altitude: null,
          altitudeAccuracy: null,
          heading: null,
          speed: null
        },
        timestamp: Date.now()
      };
      navigator.geolocation.getCurrentPosition = function (success) {
        if (success) success(fakePos);
      };
      navigator.geolocation.watchPosition = function (success) {
        if (success) success(fakePos);
        return 1;
      };
    }
  } catch (e) {}

  // ── 6. Mask emulator / headless WebGL renderer ────────────────────────────
  try {
    var patchWebGL = function (proto) {
      if (!proto || !proto.getParameter) return;
      var origGetParam = proto.getParameter;
      proto.getParameter = function (param) {
        // UNMASKED_VENDOR_WEBGL = 0x9245
        if (param === 37445) {
          var origV = origGetParam.apply(this, arguments);
          if (origV && (origV.indexOf('Google') !== -1 || origV.indexOf('Mesa') !== -1)) {
            return isMobile ? 'Qualcomm' : 'Google Inc. (NVIDIA)';
          }
          return origV;
        }
        // UNMASKED_RENDERER_WEBGL = 0x9246
        if (param === 37446) {
          var origR = origGetParam.apply(this, arguments);
          if (origR && (origR.indexOf('SwiftShader') !== -1 || origR.indexOf('llvmpipe') !== -1 || origR.indexOf('Emulator') !== -1)) {
            return isMobile
              ? 'Adreno (TM) 750'
              : 'ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 Direct3D11 vs_5_0 ps_5_0, D3D11)';
          }
          return origR;
        }
        return origGetParam.apply(this, arguments);
      };
    };
    if (typeof WebGLRenderingContext !== 'undefined') patchWebGL(WebGLRenderingContext.prototype);
    if (typeof WebGL2RenderingContext !== 'undefined') patchWebGL(WebGL2RenderingContext.prototype);
  } catch (e) {}

  // ── 7. navigator.permissions.query notification stub ──────────────────────
  try {
    if (navigator.permissions && navigator.permissions.query) {
      var origQuery = navigator.permissions.query.bind(navigator.permissions);
      navigator.permissions.query = function (params) {
        if (params && params.name === 'notifications') {
          return Promise.resolve({
            state: (typeof Notification !== 'undefined' && Notification.permission === 'granted') ? 'granted' : 'prompt',
            onchange: null
          });
        }
        return origQuery(params);
      };
    }
  } catch (e) {}

  // ── 8. navigator.connection ───────────────────────────────────────────────
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

  // ── 9. DOM block detector flag ───────────────────────────────────────────
  try {
    window.__googleBlockDetected = false;
    var checkBlock = function () {
      try {
        var bodyText = (document.body && (document.body.innerText || document.body.textContent)) || '';
        if (bodyText.length > 0) {
          var lower = bodyText.toLowerCase();
          // Never trigger block detection on 2FA / Phone approval / challenge screens
          if (lower.indexOf("2-step") !== -1 ||
              lower.indexOf("check your phone") !== -1 ||
              lower.indexOf("tap yes") !== -1 ||
              lower.indexOf("google sent a notification") !== -1 ||
              lower.indexOf("verification code") !== -1 ||
              lower.indexOf("security key") !== -1 ||
              lower.indexOf("authenticator") !== -1 ||
              lower.indexOf("enter the code") !== -1) {
            window.__googleBlockDetected = false;
            return;
          }
          // Only true block pages (strict matching):
          if (lower.indexOf("this browser or app may not be secure") !== -1 ||
              (lower.indexOf("couldn't sign you in") !== -1 &&
               (lower.indexOf("try using a different browser") !== -1 ||
                lower.indexOf("browser or app may not be secure") !== -1))) {
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
