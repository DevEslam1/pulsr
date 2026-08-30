// lib/core/constants/embedded_browser_ua.dart
//
// Single source of truth for the User-Agent strings and anti-fingerprint JS
// used by the embedded sign-in / YouTube Music WebView.
//
// Google OAuth blocks Android WebView via two mechanisms:
//   1. The X-Requested-With header (suppressed via requestedWithHeaderOriginAllowList: {}).
//   2. navigator.userAgentData (the User-Agent Client Hints API) — present in
//      Chromium/Android WebView but NOT in Safari. Google reads it at sign-in
//      to detect embedded browsers even when the UA string claims to be Safari.
//
// The [antiFingerprint] script is injected at AT_DOCUMENT_START and deletes
// navigator.userAgentData plus aligns platform/vendor with the spoofed Safari UA.
class EmbeddedBrowserUa {
  EmbeddedBrowserUa._();

  /// iOS 18.5 Safari Mobile User-Agent (updated 2025)
  static const String mobile =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';

  /// macOS 15.5 Safari Desktop User-Agent (updated 2025)
  static const String desktop =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15';

  /// JavaScript injected at AT_DOCUMENT_START.
  ///
  /// Removes the Chromium-only [navigator.userAgentData] property and aligns
  /// other navigator fingerprint fields with genuine Safari behaviour so that
  /// Google's sign-in page cannot distinguish the WebView from a real Safari.
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

  // ── 1. Delete navigator.userAgentData ───────────────────────────────────────
  // Chrome/Android WebView exposes this; Safari does not. Google uses its
  // presence to detect embedded browsers even when the UA string is spoofed.
  try {
    Object.defineProperty(navigator, 'userAgentData', {
      get: function () { return undefined; },
      configurable: true,
      enumerable: false
    });
  } catch (e) {}

  // ── 2. Align platform / vendor ──────────────────────────────────────────────
  var ua = (navigator.userAgent || '');
  var isIphone = ua.indexOf('iPhone') !== -1;
  tryDefine(navigator, 'platform', isIphone ? 'iPhone' : 'MacIntel');
  tryDefine(navigator, 'vendor', 'Apple Computer, Inc.');

  // ── 3. Remove WebView-specific extension APIs that Safari never ships ────────
  try { delete window.chrome; } catch (e) {}

  // ── 4. Suppress the High-Entropy Client-Hints permission ────────────────────
  // navigator.userAgentData.getHighEntropyValues() is a giveaway; it won't
  // exist once we've deleted userAgentData above, but belt-and-suspenders.
  try {
    var nav = window.navigator;
    if (nav && nav.userAgentData && nav.userAgentData.getHighEntropyValues) {
      nav.userAgentData.getHighEntropyValues = function () {
        return Promise.resolve({});
      };
    }
  } catch (e) {}
})();
''';
}
