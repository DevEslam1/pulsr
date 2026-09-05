// lib/features/auth/presentation/ytm_web_login_sheet.dart
import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../core/constants/embedded_browser_ua.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../utils/google_login_recovery.dart';

import '../../../core/utils/error_logger.dart';
class YtmWebLoginSheet extends StatefulWidget {
  // Use the modern Google accounts sign-in flow (v3 identifier endpoint).
  // The older ServiceLogin URL is more aggressively fingerprinted for
  // embedded browsers — the v3 path goes through the same risk checks but
  // is substantially less likely to show the "This browser may not be secure"
  // interstitial for WebView UAs that pass the other signal checks.
  static const String googleSignInUrl =
      'https://accounts.google.com/v3/signin/identifier?continue=https%3A%2F%2Fmusic.youtube.com%2F&service=youtube&hl=en&flowName=GlifWebSignIn&flowEntry=ServiceLogin';

  final String? initialUrl;
  final String? title;
  final bool isBrowseMode;

  const YtmWebLoginSheet({
    super.key,
    this.initialUrl,
    this.title,
    this.isBrowseMode = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    String? initialUrl,
    String? title,
    bool isBrowseMode = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => YtmWebLoginSheet(
        initialUrl: initialUrl,
        title: title,
        isBrowseMode: isBrowseMode,
      ),
    );
  }

  @override
  State<YtmWebLoginSheet> createState() => _YtmWebLoginSheetState();
}

class _YtmWebLoginSheetState extends State<YtmWebLoginSheet> {
  InAppWebViewController? _webViewController;
  InAppWebViewSettings? _settings;
  bool _isLoading = true;

  // F-17: WebView progress ticks arrive many times per page load; they feed
  // this notifier and rebuild only the small progress bar, not the whole
  // ~1000-line sheet.
  final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0.0);

  bool _isLoggedIn = false;
  String? _detectedCookies;
  bool _showHint = false;
  Timer? _hintTimer;
  Timer? _authPollTimer;
  bool _hadSuccessfulYtLoad = false;

  static const String googleSignInUrl = YtmWebLoginSheet.googleSignInUrl;

  static bool _isCookieMismatchUrl(String u) => RegExp(
        r'CookieMismatch|/sorry|speedbump',
        caseSensitive: false,
      ).hasMatch(u);

  static bool _isAuthInProgressUrl(String u) => RegExp(
        r'accounts\.google\.com/(v3/)?signin|accounts\.google\.com/ServiceLogin|/checkpoint/|/challenge/|challenge|consent\.google',
        caseSensitive: false,
      ).hasMatch(u);

  bool _canGoBack = false;
  bool _canGoForward = false;
  late String _currentUrl;
  // Debounce timer: prevents rapid CookieMismatch events from triggering
  // multiple navigations to music.youtube.com.
  Timer? _cookieMismatchDebounce;

  /// Collapses overlapping login checks (2s poll + onLoadStop +
  /// onUpdateVisitedHistory) so cookies are harvested exactly once.
  Future<bool>? _loginCheckInFlight;

  /// Auto-navigation attempts past Google's CookieMismatch interstitial.
  /// Capped: when third-party cookie state is broken, Google bounces the
  /// reload straight back to CookieMismatch forever.
  int _mismatchAutoNavCount = 0;

  // --- Google "This browser or app may not be secure" block recovery ---
  // UAs live in EmbeddedBrowserUa (single source; keep bumped — see file).
  // Chrome Desktop is the default: its TLS fingerprint matches the Chromium
  // WebView engine, giving the most consistent signal to Google's risk check.
  static String get mobileUserAgent => EmbeddedBrowserUa.chromeMobile;
  static String get desktopUserAgent => EmbeddedBrowserUa.chromeDesktop;

  static const String _ytmBrowseGuardJs = r'''
(function () {
  'use strict';
  try {
    var isPlayUrl = function(url) {
      if (!url) return false;
      var s = String(url).toLowerCase();
      return s.indexOf('play.google.com') !== -1 ||
             s.indexOf('market://') !== -1 ||
             s.indexOf('intent://') !== -1;
    };

    // Override location assign/replace to suppress Google Play redirection
    var origAssign = window.location.assign;
    window.location.assign = function(url) {
      if (isPlayUrl(url)) {
        return;
      }
      return origAssign.apply(this, arguments);
    };

    var origReplace = window.location.replace;
    window.location.replace = function(url) {
      if (isPlayUrl(url)) {
        return;
      }
      return origReplace.apply(this, arguments);
    };

    // Emulate desktop screen metrics so YouTube Music desktop player renders
    if (window.screen && (window.screen.width < 1024 || window.screen.availWidth < 1024)) {
      try {
        Object.defineProperty(window.screen, 'width', { get: function() { return 1366; }, configurable: true });
        Object.defineProperty(window.screen, 'availWidth', { get: function() { return 1366; }, configurable: true });
        Object.defineProperty(window.screen, 'height', { get: function() { return 768; }, configurable: true });
        Object.defineProperty(window.screen, 'availHeight', { get: function() { return 728; }, configurable: true });
      } catch (e) {}
    }

    // Intercept clicks on links pointing to Google Play
    document.addEventListener('click', function(e) {
      var target = e.target;
      while (target && target !== document) {
        if (target.tagName === 'A' && target.href && isPlayUrl(target.href)) {
          e.preventDefault();
          e.stopPropagation();
          return false;
        }
        target = target.parentElement;
      }
    }, true);

    // Set Egypt region preference cookie on .youtube.com
    try {
      document.cookie = "PREF=f1=50000000&gl=EG&hl=en; domain=.youtube.com; path=/";
    } catch(e) {}

    // Hook ytcfg to enforce Egypt region and disable unavailable state
    try {
      var patchData = function(data) {
        if (!data || typeof data !== 'object') return data;
        data.GL = 'EG';
        data.HL = 'en';
        data.IS_UNAVAILABLE = false;
        data.IS_UNAVAILABLE_IN_REGION = false;
        data.UNAVAILABLE_IN_REGION = false;
        if (data.INNERTUBE_CONTEXT && data.INNERTUBE_CONTEXT.client) {
          data.INNERTUBE_CONTEXT.client.gl = 'EG';
          data.INNERTUBE_CONTEXT.client.hl = 'en';
        }
        return data;
      };

      var origYtcfg = window.ytcfg;
      if (origYtcfg) {
        if (origYtcfg.d) {
          var origD = origYtcfg.d;
          origYtcfg.d = function() {
            return patchData(origD.apply(this, arguments));
          };
        }
        if (origYtcfg.set) {
          var origSet = origYtcfg.set;
          origYtcfg.set = function(k, v) {
            if (typeof k === 'object') patchData(k);
            return origSet.apply(this, arguments);
          };
        }
      }
    } catch(e) {}
  } catch (e) {}
})();
''';

  static const String _ytmViewportEnforceJs = r'''
(function () {
  'use strict';
  try {
    // Hide mobile app promotional banners and overlays
    var style = document.createElement('style');
    style.textContent = `
      ytmusic-app-promo,
      .ytmusic-app-promo,
      #app-promo,
      [class*="app-promo"],
      ytmusic-banner-promo-renderer,
      ytmusic-mobile-topbar-renderer {
        display: none !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);

    // Ensure desktop viewport width on phones so YouTube Music renders full desktop player
    var meta = document.querySelector('meta[name="viewport"]');
    if (meta) {
      meta.setAttribute('content', 'width=1024, initial-scale=0.85, maximum-scale=3.0, user-scalable=yes');
    }
  } catch (e) {}
})();
''';

  /// Returns the [UserScript] list to inject into the WebView.
  ///
  /// The script deletes navigator.userAgentData (Chromium-only, absent in
  /// Safari) and aligns platform/vendor so Google's sign-in cannot fingerprint
  /// the embedded WebView even after the UA string has been spoofed.
  /// Also injects browse guard & viewport scripts to ensure the full YouTube
  /// Music web player renders instead of Google Play redirects.
  static UnmodifiableListView<UserScript> get _antiFingerPrintScripts =>
      UnmodifiableListView([
        UserScript(
          source: EmbeddedBrowserUa.antiFingerprint,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(
          source: _ytmBrowseGuardJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(
          source: _ytmViewportEnforceJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        ),
      ]);

  static const List<String> _blockPhrases = [
    "couldn't sign you in",
    'this browser or app may not be secure',
  ];

  final GoogleBlockRecovery _blockRecovery =
      GoogleBlockRecovery(initialIdentity: BrowserIdentity.chromeDesktop);

  /// Non-null while the automatic recovery ladder is running (drives the
  /// inline status banner); prevents re-entry so the ladder never loops.
  String? _blockStatus;

  /// True after the 2 automatic retries were exhausted → recovery card.
  bool _blockExhausted = false;

  /// Identity override chosen by the ladder or the recovery card. Null =
  /// use the default isYtm URL-based selection.
  BrowserIdentity? _uaIdentityOverride;

  /// Throttle for the block-page JS text scan (once per 2.5 s per page).
  DateTime _lastBlockScanAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Suppresses block re-detection for 8 s after each recovery step so the
  /// new page has time to fully load before we scan again. Without this,
  /// the poll fires while the reloaded page is still the block page and
  /// triggers another recovery step immediately, looping forever.
  DateTime _blockCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  String _uaFor(BrowserIdentity identity) {
    switch (identity) {
      case BrowserIdentity.chromeDesktop:
        return EmbeddedBrowserUa.chromeDesktop;
      case BrowserIdentity.safariMobile:
        return EmbeddedBrowserUa.safariMobile;
      case BrowserIdentity.desktop:
        return EmbeddedBrowserUa.desktop;
      case BrowserIdentity.mobile:
        return EmbeddedBrowserUa.mobile;
    }
  }

  bool _isGeoBlocked = false;

  /// Ensures that any YouTube Music URL carries explicit gl=EG&hl=en parameters.
  static String _withGeoParams(String url) {
    if (!url.contains('music.youtube.com')) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.queryParameters.containsKey('gl')) return url;
    final newParams = Map<String, String>.from(uri.queryParameters);
    newParams['gl'] = 'EG';
    newParams['hl'] = 'en';
    return uri.replace(queryParameters: newParams).toString();
  }

  Future<bool> _scanPageForGeoBlock(InAppWebViewController controller) async {
    try {
      final raw = await controller.evaluateJavascript(source: '''
(() => {
  try {
    var text = (document.body && (document.body.innerText || document.body.textContent)) || '';
    var lower = text.toLowerCase();
    return lower.includes('not available in your area') ||
           lower.includes('not available in your country') ||
           lower.includes("isn't available in your country") ||
           lower.includes("isn't available in your region") ||
           lower.includes('not available in your region') ||
           lower.includes('غير متوفر في منطقتك') ||
           lower.includes('غير متاح في منطقتك');
  } catch (e) { return false; }
})()''');
      return raw == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _forceEgRegionReload() async {
    if (mounted) setState(() => _isGeoBlocked = false);
    try {
      final cookieManager = CookieManager.instance();
      await cookieManager.setCookie(
        url: WebUri('https://music.youtube.com'),
        name: 'PREF',
        value: 'f1=50000000&gl=EG&hl=en',
        domain: '.youtube.com',
        path: '/',
      );
    } catch (_) {}
    await _navigateTo('https://music.youtube.com/?gl=EG&hl=en');
  }

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl != null
        ? _withGeoParams(widget.initialUrl!)
        : (widget.isBrowseMode
            ? 'https://music.youtube.com/?gl=EG&hl=en'
            : googleSignInUrl);

    // Pre-seed Egypt region preference cookie for YouTube domains
    try {
      final cookieManager = CookieManager.instance();
      cookieManager.setCookie(
        url: WebUri('https://music.youtube.com'),
        name: 'PREF',
        value: 'f1=50000000&gl=EG&hl=en',
        domain: '.youtube.com',
        path: '/',
      );
    } catch (_) {}

    final accountService = getIt<YtmAccountService>();
    if (accountService.isLoggedIn) {
      accountService.validateSession().then((ok) {
        if (!mounted) return;
        setState(() => _isLoggedIn = ok);
        if (!ok) {
          _clearCookiesAndReset(); // start the re-login with a CLEAN jar (fixes B6)
        }
      });
    }

    final isYtm =
        widget.isBrowseMode || _currentUrl.contains('music.youtube.com');
    final initialUa = _uaIdentityOverride != null
        ? _uaFor(_uaIdentityOverride!)
        : (isYtm ? desktopUserAgent : mobileUserAgent);

    _settings = InAppWebViewSettings(
      userAgent: initialUa,
      preferredContentMode: isYtm
          ? UserPreferredContentMode.DESKTOP
          : UserPreferredContentMode.RECOMMENDED,
      useHybridComposition: true,
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      supportMultipleWindows: true,
      mediaPlaybackRequiresUserGesture: false,
      isInspectable: kDebugMode,
      transparentBackground: false,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      cacheEnabled: true,
      databaseEnabled: true,
      domStorageEnabled: true,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,
      allowFileAccess: true,
      allowContentAccess: true,
      useWideViewPort: true,
      loadWithOverviewMode: true,
      supportZoom: true,
      builtInZoomControls: true,
      displayZoomControls: false,
      allowsInlineMediaPlayback: true,
      useShouldOverrideUrlLoading: true,
      // Empty set suppresses the X-Requested-With header that Android WebView
      // normally injects with the app's package name (com.pulsr.music).
      // Google uses this header to detect embedded WebViews and block sign-in.
      requestedWithHeaderOriginAllowList: <String>{},
      // Disable hardware acceleration override to avoid rendering fingerprint differences
      disableDefaultErrorPage: false,
    );

    _hintTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_isLoggedIn && !widget.isBrowseMode) {
        setState(() => _showHint = true);
      }
    });

    _pollIntervalSeconds = 2;
    _scheduleNextAuthPoll();
  }

  int _pollIntervalSeconds = 2;

  void _scheduleNextAuthPoll() {
    _authPollTimer?.cancel();
    if (!mounted || _isLoggedIn) return;

    _authPollTimer = Timer(Duration(seconds: _pollIntervalSeconds), () async {
      if (!mounted || _isLoggedIn) return;
      if (_webViewController != null && !_isLoading) {
        final loggedIn = await _checkIfLoggedIn();
        if (loggedIn) return;

        // Check for Google block during polling (detects SPA client-side rejections after tapping Next)
        if (!widget.isBrowseMode && !_blockExhausted && _blockStatus == null) {
          // Skip block scan during post-recovery cooldown to prevent re-detection
          // of the same block page before the new page has finished loading.
          final inCooldown = DateTime.now().isBefore(_blockCooldownUntil);
          final isBlocked = (!inCooldown && _shouldScanForBlockPage())
              ? await _scanPageForBlockText(_webViewController!)
              : false;
          if (isBlocked) {
            _handleGoogleBlock();
            return;
          }
        }
      }
      if (_pollIntervalSeconds < 3) {
        _pollIntervalSeconds = 3;
      } else if (_pollIntervalSeconds < 5) {
        _pollIntervalSeconds = 5;
      } else if (_pollIntervalSeconds < 8) {
        _pollIntervalSeconds = 8;
      } else {
        _pollIntervalSeconds = 10;
      }
      _scheduleNextAuthPoll();
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _authPollTimer?.cancel();
    _cookieMismatchDebounce?.cancel();
    _progressNotifier.dispose();
    super.dispose();
  }

  Future<void> _updateNavState() async {
    if (_webViewController == null) return;
    try {
      final back = await _webViewController!.canGoBack();
      final forward = await _webViewController!.canGoForward();
      final url = await _webViewController!.getUrl();
      if (mounted) {
        setState(() {
          _canGoBack = back;
          _canGoForward = forward;
          if (url != null) {
            _currentUrl = url.toString();
          }
        });
      }
    } catch (e, st) {
      ErrorLogger.log('_updateNavState failed', error: e, stackTrace: st, category: 'YtmWebLoginSheet');
    }
  }

  /// Called by the CookieMismatch page detection. Google's cross-domain OAuth cookie
  /// sync redirect or mismatched state. Debounce navigation to music.youtube.com.
  void _handleCookieMismatch() {
    // Hard cap on automatic bounces: when Google's third-party cookie state
    // is broken it redirects every reload straight back to CookieMismatch.
    const maxMismatchNav = 3;
    if (_mismatchAutoNavCount >= maxMismatchNav) {
      debugPrint('[YtmWebLogin] CookieMismatch auto-navigation cap reached; '
          'treating as Google block for recovery.');
      _handleGoogleBlock();
      return;
    }

    _cookieMismatchDebounce?.cancel();
    _cookieMismatchDebounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _mismatchAutoNavCount++;
      final target =
          widget.isBrowseMode ? 'https://music.youtube.com' : googleSignInUrl;
      debugPrint('[YtmWebLogin] Navigating past CookieMismatch '
          '(attempt $_mismatchAutoNavCount/3) → $target');
      _navigateTo(target);
    });
  }

  /// Manual action triggered ONLY by the clear-cache button in the toolbar.
  /// Wipes all WebView cookies and cache, resets the YTM session, and reloads.
  Future<void> _clearCookiesAndReset() async {
    try {
      final accountService = getIt<YtmAccountService>();
      // Scoped wipe: only YouTube/Google sign-in cookies, never the whole
      // device WebView cookie jar.
      await _clearWebViewCookiesAndCache();
      await accountService.logout();
      _isLoggedIn = false;
      _detectedCookies = null;
      _hadSuccessfulYtLoad = false;
      _mismatchAutoNavCount = 0;
      // Manual "start over" also dismisses the block recovery card.
      if (mounted && (_blockExhausted || _blockStatus != null)) {
        setState(() {
          _blockExhausted = false;
          _blockStatus = null;
        });
      }
      final target =
          widget.isBrowseMode ? 'https://music.youtube.com' : googleSignInUrl;
      unawaited(_navigateTo(target));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Cookies and cache cleared. Reloading YouTube Music...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[YtmWebLogin] Failed to clear cookies: $e');
    }
  }

  /// Shared cookie+cache wipe used by the toolbar button and the block
  /// recovery ladder. Clears the scoped session cookies and the WebView cache
  /// only — no session flags or navigation.
  Future<void> _clearWebViewCookiesAndCache() async {
    try {
      final accountService = getIt<YtmAccountService>();
      await accountService.clearSessionWebViewCookies();
      await InAppWebViewController.clearAllCache();
    } catch (e) {
      debugPrint('[YtmWebLogin] Failed to clear WebView cookies/cache: $e');
    }
  }

  // ---------- Google block detection & recovery ladder ----------

  /// URL-level block signals: the dedicated `signin/blocked` path, or the
  /// ServiceLogin / signin pages carrying an explicit error parameter.
  bool _matchesBlockedUrl(Uri? uri) {
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    if (path.contains('signin/blocked')) return true;
    final hasErrorParam = uri.queryParameters.containsKey('error') ||
        uri.queryParameters.containsKey('errorCode');
    if (hasErrorParam &&
        (path.contains('servicelogin') || path.contains('signin'))) {
      return true;
    }
    return false;
  }

  bool _shouldScanForBlockPage() {
    final now = DateTime.now();
    if (now.difference(_lastBlockScanAt) <
        const Duration(milliseconds: 2500)) {
      return false;
    }
    _lastBlockScanAt = now;
    return true;
  }

  /// Lightweight throttled JS evaluation: looks for Google's block-page
  /// phrases in the document title/body text (first 4 KB, lowercased).
  Future<bool> _scanPageForBlockText(InAppWebViewController controller) async {
    try {
      final currentUrl =
          (await controller.getUrl())?.toString().toLowerCase() ?? '';
      if (currentUrl.contains('/challenge/') ||
          currentUrl.contains('signin/challenge') ||
          currentUrl.contains('/checkpoint/')) {
        return false;
      }

      final raw = await controller.evaluateJavascript(source: '''
(() => {
  try {
    var t = (document.title || '');
    var b = '';
    try { b = (document.body && (document.body.innerText || document.body.textContent)) || ''; } catch (e) {}
    var full = (t + '|' + b).slice(0, 8000).toLowerCase();

    // 2-Step Verification / phone prompt is active authentication, NOT a block
    if (full.includes('2-step') ||
        full.includes('check your phone') ||
        full.includes('tap yes') ||
        full.includes('google sent a notification') ||
        full.includes('verification code') ||
        full.includes('security key') ||
        full.includes('authenticator') ||
        full.includes('enter the code')) {
      window.__googleBlockDetected = false;
      return '';
    }

    if (window.__googleBlockDetected) return "couldn't sign you in";
    return full;
  } catch (e) { return ''; }
})()''');
      final text = raw?.toString().toLowerCase() ?? '';
      if (text.isEmpty) return false;
      if (text.contains('2-step') ||
          text.contains('check your phone') ||
          text.contains('tap yes') ||
          text.contains('google sent a notification') ||
          text.contains('verification code') ||
          text.contains('security key') ||
          text.contains('authenticator') ||
          text.contains('enter the code')) {
        return false;
      }
      for (final phrase in _blockPhrases) {
        if (text.contains(phrase)) return true;
      }
    } catch (e, st) {
      ErrorLogger.log('_scanPageForBlockText failed', error: e, stackTrace: st, category: 'YtmWebLoginSheet');
    }
    return false;
  }

  /// Entry point of the automatic recovery ladder (max 2 retries, then the
  /// manual recovery card — never loops).
  void _handleGoogleBlock() {
    if (!mounted || widget.isBrowseMode) return;
    // Already recovering, or exhausted → stop; the card handles it manually.
    if (_blockStatus != null || _blockExhausted) return;

    final step = _blockRecovery.onBlocked();
    if (step == null) {
      debugPrint('[YtmWebLogin] Google block: retries exhausted.');
      setState(() {
        _blockExhausted = true;
        _blockStatus = null;
      });
      return;
    }
    debugPrint('[YtmWebLogin] Google block detected → ladder attempt '
        '${_blockRecovery.attempt}/${_blockRecovery.maxAttempts} '
        '→ identity ${step.nextIdentity.name}');
    setState(() {
      _blockStatus =
          'Google blocked the embedded browser — retrying with different browser identity (${_blockRecovery.attempt}/${_blockRecovery.maxAttempts})…';
    });
    unawaited(_runBlockRecoveryStep(step));
  }

  Future<void> _runBlockRecoveryStep(BlockRecoveryStep step) async {
    try {
      // 1. Clear cookies + cache, 2. switch browser identity, 3. reload.
      await _clearWebViewCookiesAndCache();
      _uaIdentityOverride = step.nextIdentity;
      try {
        await _webViewController?.setSettings(
          settings: InAppWebViewSettings(
              userAgent: _uaFor(step.nextIdentity)),
        );
      } catch (e, st) {
        ErrorLogger.log('_runBlockRecoveryStep failed', error: e, stackTrace: st, category: 'YtmWebLoginSheet');
      }
      final target =
          widget.isBrowseMode ? 'https://music.youtube.com' : googleSignInUrl;
      await _webViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(target)));
      // Set cooldown AFTER the load is initiated so the poll doesn't
      // re-scan the still-loading block page.
      _blockCooldownUntil = DateTime.now().add(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[YtmWebLogin] Block recovery step failed: $e');
    } finally {
      if (mounted) setState(() => _blockStatus = null);
    }
  }

  /// Recovery card "Retry": manual full ladder — reset attempts, clean
  /// session, default identity selection, reload.
  Future<void> _manualRetryFromBlock() async {
    _blockRecovery.reset();
    _uaIdentityOverride = null;
    _hadSuccessfulYtLoad = false;
    _mismatchAutoNavCount = 0;
    if (mounted) {
      setState(() {
        _blockExhausted = false;
        _blockStatus = 'Retrying sign-in with a clean session…';
      });
    }
    await _clearWebViewCookiesAndCache();
    await _navigateTo(
        widget.isBrowseMode ? 'https://music.youtube.com' : googleSignInUrl);
    if (mounted) setState(() => _blockStatus = null);
  }

  /// Recovery card identity toggle: switch UA mode and reload in place.
  Future<void> _switchIdentityManually(BrowserIdentity identity) async {
    _uaIdentityOverride = identity;
    if (mounted) {
      setState(() {
        _blockExhausted = false;
        _blockStatus =
            'Reloading with ${identity.name} browser identity…';
      });
    }
    await _navigateTo(
        widget.isBrowseMode ? 'https://music.youtube.com' : googleSignInUrl);
    if (mounted) setState(() => _blockStatus = null);
  }

  Future<void> _navigateTo(String url) async {
    final effectiveUrl = _withGeoParams(url);
    _pollIntervalSeconds = 2;
    _scheduleNextAuthPoll();
    final isYtm =
        widget.isBrowseMode || effectiveUrl.contains('music.youtube.com');
    final targetUa = _uaIdentityOverride != null
        ? _uaFor(_uaIdentityOverride!)
        : (isYtm ? desktopUserAgent : mobileUserAgent);
    try {
      await _webViewController?.setSettings(
        settings: InAppWebViewSettings(
          userAgent: targetUa,
          preferredContentMode: isYtm
              ? UserPreferredContentMode.DESKTOP
              : UserPreferredContentMode.RECOMMENDED,
        ),
      );
    } catch (e, st) {
      ErrorLogger.log('_navigateTo failed', error: e, stackTrace: st, category: 'YtmWebLoginSheet');
    }
    final loadUrlFuture = _webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(effectiveUrl)));
    if (loadUrlFuture != null) unawaited(loadUrlFuture);
  }

  Future<bool> _checkIfLoggedIn([String? url]) {
    if (_isLoggedIn) return Future<bool>.value(true);
    return _loginCheckInFlight ??=
        _detectLoginState(url).whenComplete(() => _loginCheckInFlight = null);
  }

  Future<bool> _detectLoginState([String? url]) async {
    if (_isLoggedIn) return true;

    String? currentUrl = url;
    try {
      final webUri = await _webViewController?.getUrl();
      currentUrl ??= webUri?.toString();
    } catch (e, st) {
      ErrorLogger.log('_detectLoginState failed', error: e, stackTrace: st, category: 'YtmWebLoginSheet');
    }

    if (currentUrl != null) {
      if (currentUrl.startsWith('chrome-error://') ||
          currentUrl.startsWith('about:') ||
          _isCookieMismatchUrl(currentUrl) ||
          _isAuthInProgressUrl(currentUrl)) {
        return false;
      }
    }

    if (!_hadSuccessfulYtLoad) {
      return false; // never trust a jar we injected ourselves
    }

    final accountService = getIt<YtmAccountService>();

    // 1. Try InAppWebView CookieManager (deduplicated by name; rotated values win)
    try {
      final cookieManager = CookieManager.instance();
      final domains = [
        'https://google.com',
        'https://accounts.google.com',
        'https://myaccount.google.com',
        'https://accounts.youtube.com',
        'https://youtube.com',
        'https://www.youtube.com',
        'https://music.youtube.com',
      ];
      final Map<String, String> jar = {};
      for (final domain in domains) {
        final cookies = await cookieManager.getCookies(url: WebUri(domain));
        for (final c in cookies) {
          jar[c.name] = c.value as String? ?? '';
        }
      }
      final combinedCookies =
          jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
      if (combinedCookies.isNotEmpty &&
          YtmAccountService.looksLikeSignedInCookies(combinedCookies)) {
        if (!_isLoggedIn) {
          _isLoggedIn = true;
          _detectedCookies = combinedCookies;
          await accountService.saveSession(combinedCookies);
          if (mounted) {
            setState(() {});
            // Navigate to music.youtube.com to complete the OAuth redirect
            // and ensure music.youtube.com domain cookies are also set.
            unawaited(_navigateTo('https://music.youtube.com'));
          }
        }
        return true;
      }
    } catch (e, st) {
      ErrorLogger.log('_detectLoginState failed', error: e, stackTrace: st, category: 'YtmWebLoginSheet');
    }

    // 2. Try native platform cookie manager
    final cookies = await accountService.getNativeCookiesFromDomains();
    if (cookies != null &&
        cookies.isNotEmpty &&
        YtmAccountService.looksLikeSignedInCookies(cookies)) {
      if (!_isLoggedIn) {
        _isLoggedIn = true;
        _detectedCookies = cookies;
        await accountService.saveSession(cookies);
        if (mounted) {
          setState(() {});
          unawaited(_navigateTo('https://music.youtube.com'));
        }
      }
      return true;
    }

    // 3. Fallback: JS document.cookie
    if (currentUrl != null &&
        !currentUrl.startsWith('chrome-error://') &&
        !currentUrl.startsWith('about:') &&
        !_isCookieMismatchUrl(currentUrl) &&
        !_isAuthInProgressUrl(currentUrl)) {
      try {
        final rawCookie = await _webViewController?.evaluateJavascript(
          source:
              '(() => { try { return document.cookie || ""; } catch (e) { return ""; } })()',
        );
        String cookieStr = rawCookie?.toString() ?? '';
        if (cookieStr.startsWith('"') && cookieStr.endsWith('"')) {
          cookieStr = cookieStr.substring(1, cookieStr.length - 1);
        }
        if (cookieStr.isNotEmpty &&
            YtmAccountService.looksLikeSignedInCookies(cookieStr)) {
          if (!_isLoggedIn) {
            _isLoggedIn = true;
            _detectedCookies = cookieStr;
            await accountService.saveSession(cookieStr);
            if (mounted) {
              setState(() {});
              unawaited(_navigateTo('https://music.youtube.com'));
            }
          }
          return true;
        }
      } catch (e, st) {
        ErrorLogger.log('toString failed', error: e, stackTrace: st, category: 'YtmWebLoginSheet');
      }
    }

    return false;
  }

  Future<void> _forceSaveAndFinish() async {
    final accountService = getIt<YtmAccountService>();
    var cookies = _detectedCookies;

    // 1. Try InAppWebView CookieManager (deduplicated by name)
    if (cookies == null || cookies.isEmpty) {
      try {
        final cookieManager = CookieManager.instance();
        final domains = [
          'https://google.com',
          'https://accounts.google.com',
          'https://myaccount.google.com',
          'https://accounts.youtube.com',
          'https://youtube.com',
          'https://www.youtube.com',
          'https://music.youtube.com',
        ];
        final Map<String, String> jar = {};
        for (final domain in domains) {
          final domainCookies =
              await cookieManager.getCookies(url: WebUri(domain));
          for (final c in domainCookies) {
            jar[c.name] = c.value as String? ?? '';
          }
        }
        if (jar.isNotEmpty) {
          cookies = jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
        }
      } catch (e, st) {
        ErrorLogger.log('_forceSaveAndFinish failed', error: e, stackTrace: st, category: 'YtmWebLoginSheet');
      }
    }

    // 2. Try native platform cookies
    if (cookies == null || cookies.isEmpty) {
      cookies = await accountService.getNativeCookiesFromDomains();
    }

    // 3. Try JS document.cookie
    if (cookies == null || cookies.isEmpty) {
      try {
        final rawCookie = await _webViewController?.evaluateJavascript(
          source:
              '(() => { try { return document.cookie || ""; } catch (e) { return ""; } })()',
        );
        String cookieStr = rawCookie?.toString() ?? '';
        if (cookieStr.startsWith('"') && cookieStr.endsWith('"')) {
          cookieStr = cookieStr.substring(1, cookieStr.length - 1);
        }
        if (cookieStr.isNotEmpty) {
          cookies = cookieStr;
        }
      } catch (e, st) {
        ErrorLogger.log('toString failed', error: e, stackTrace: st, category: 'YtmWebLoginSheet');
      }
    }

    if (cookies != null &&
        cookies.isNotEmpty &&
        YtmAccountService.looksLikeSignedInCookies(cookies)) {
      await accountService.saveSession(cookies);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
      return;
    }

    if (_isLoggedIn && accountService.isLoggedIn) {
      final valid = await accountService.validateSession();
      if (valid) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
        return;
      }
    }

    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Please complete sign in on YouTube Music first.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final media = MediaQuery.of(context);
    final topPadding = media.padding.top;
    final bottomInset = media.viewInsets.bottom;
    final totalHeight = media.size.height;
    final isBrowse = widget.isBrowseMode;

    // Expand height cleanly down to the bottom of the screen with proper status bar clearance
    final safeTop = topPadding > 0 ? topPadding : 24.0;
    final targetHeight = (totalHeight - safeTop - (isBrowse ? 8 : 16))
        .clamp(300.0, totalHeight);

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Adaptive.isTablet(context) ? 680 : double.infinity,
          maxHeight: targetHeight,
        ),
        child: AnimatedPadding(
          padding: EdgeInsets.only(bottom: bottomInset),
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: targetHeight,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: p.hairline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: true,
              bottom: true,
              child: Column(
                children: [
                  // Top Drag Handle & Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: p.textTertiary.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (isBrowse) ...[
                          // BROWSER TOOLBAR
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    size: 18),
                                tooltip: 'Back',
                                onPressed: _canGoBack
                                    ? () async {
                                        await _webViewController?.goBack();
                                        await _updateNavState();
                                      }
                                    : null,
                              ),
                              IconButton(
                                icon: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 18),
                                tooltip: 'Forward',
                                onPressed: _canGoForward
                                    ? () async {
                                        await _webViewController?.goForward();
                                        await _updateNavState();
                                      }
                                    : null,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: p.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: p.hairline),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.lock_rounded,
                                          size: 13, color: p.accent),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _currentUrl.replaceFirst(
                                              'https://', ''),
                                          style: TextStyle(
                                            color: p.textSecondary,
                                            fontSize: 12,
                                            fontFamily: 'monospace',
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon:
                                    const Icon(Icons.refresh_rounded, size: 20),
                                tooltip: 'Refresh',
                                onPressed: () => _webViewController?.reload(),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                tooltip: 'Close',
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                          // Quick Navigation Chips
                          SizedBox(
                            height: 36,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              children: [
                                _navChip(
                                  label: 'Home',
                                  icon: Icons.home_rounded,
                                  url: 'https://music.youtube.com/?gl=EG&hl=en',
                                  p: p,
                                ),
                                const SizedBox(width: 6),
                                _navChip(
                                  label: 'Explore',
                                  icon: Icons.explore_rounded,
                                  url: 'https://music.youtube.com/explore?gl=EG&hl=en',
                                  p: p,
                                ),
                                const SizedBox(width: 6),
                                _navChip(
                                  label: 'Library',
                                  icon: Icons.library_music_rounded,
                                  url: 'https://music.youtube.com/library?gl=EG&hl=en',
                                  p: p,
                                ),
                                const SizedBox(width: 6),
                                _navChip(
                                  label: 'Liked Music',
                                  icon: Icons.favorite_rounded,
                                  url:
                                      'https://music.youtube.com/playlist?list=LM&gl=EG&hl=en',
                                  p: p,
                                ),
                                const SizedBox(width: 6),
                                _navChip(
                                  label: 'New Releases',
                                  icon: Icons.fiber_new_rounded,
                                  url: 'https://music.youtube.com/new_releases?gl=EG&hl=en',
                                  p: p,
                                ),
                                const SizedBox(width: 6),
                                _navChip(
                                  label: 'History',
                                  icon: Icons.history_rounded,
                                  url: 'https://music.youtube.com/history?gl=EG&hl=en',
                                  p: p,
                                ),
                                const SizedBox(width: 6),
                                _navChip(
                                  label: 'YouTube Web',
                                  icon: Icons.video_library_rounded,
                                  url: 'https://www.youtube.com',
                                  p: p,
                                ),
                                const SizedBox(width: 6),
                                _navChip(
                                  label: 'Egypt Mode',
                                  icon: Icons.public_rounded,
                                  url: 'https://music.youtube.com/?gl=EG&hl=en',
                                  p: p,
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // LOGIN HEADER
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                _isLoggedIn
                                    ? Icons.check_circle_rounded
                                    : Icons.cloud_sync_rounded,
                                color:
                                    _isLoggedIn ? p.success : Colors.redAccent,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _isLoggedIn
                                          ? 'Logged In Successfully'
                                          : 'Sign in to YouTube Music',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.textPrimary,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      _isLoggedIn
                                          ? 'Account connected! Tap "Done" to finish.'
                                          : 'Connect account to sync Liked Music automatically',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _isLoggedIn
                                            ? p.success
                                            : p.textSecondary,
                                        fontSize: 11,
                                        fontWeight: _isLoggedIn
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Action Controls
                              if (_isLoggedIn) ...[
                                FilledButton.icon(
                                  onPressed: _forceSaveAndFinish,
                                  icon: const Icon(
                                    Icons.check_rounded,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Done',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: p.success,
                                    elevation: 2,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                FilledButton(
                                  onPressed: _forceSaveAndFinish,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: p.surfaceContainerHigh,
                                    foregroundColor: p.textPrimary,
                                    elevation: 0,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(color: p.hairline),
                                    ),
                                  ),
                                  child: Text(
                                    'Done',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                IconButton(
                                  icon: const Icon(Icons.refresh_rounded, size: 18),
                                  tooltip: 'Refresh page',
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _webViewController?.reload(),
                                ),
                                const SizedBox(width: 2),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                                  tooltip: 'More options',
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(),
                                  onSelected: (action) {
                                    switch (action) {
                                      case 'ytm_web':
                                        _navigateTo('https://music.youtube.com');
                                        break;
                                      case 'manual_cookies':
                                        _showManualCookieDialog(context);
                                        break;
                                      case 'clear_cache':
                                        _clearCookiesAndReset();
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'ytm_web',
                                      child: Row(
                                        children: [
                                          Icon(Icons.music_note_rounded,
                                              size: 18, color: p.textSecondary),
                                          const SizedBox(width: 8),
                                          const Text('Open YouTube Music Web'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'manual_cookies',
                                      child: Row(
                                        children: [
                                          Icon(Icons.vpn_key_rounded,
                                              size: 18, color: p.textSecondary),
                                          const SizedBox(width: 8),
                                          const Text('Import Cookies Manually'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'clear_cache',
                                      child: Row(
                                        children: [
                                          Icon(Icons.cleaning_services_rounded,
                                              size: 18, color: p.textSecondary),
                                          const SizedBox(width: 8),
                                          const Text('Clear Cache & Reset'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(width: 2),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                tooltip: 'Close',
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(),
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (!isBrowse && _isLoggedIn)
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: p.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: p.success.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              size: 18, color: p.success),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Login detected! Tap the green "Done" button to complete setup.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: p.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (!isBrowse && _showHint)
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 18, color: Colors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Make sure you sign into the correct Google account. Tap "Done" once logged in.',
                              style:
                                  TextStyle(fontSize: 12, color: p.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Inline status banner during the block recovery ladder.
                  if (!isBrowse && _blockStatus != null)
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: p.accent.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: p.accent),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _blockStatus!,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: p.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Geo-block alert banner with one-tap bypass & YouTube fallback
                  if (_isGeoBlocked)
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.public_off_rounded,
                                  color: Colors.amber, size: 17),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'YouTube Music is restricted in your region',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: p.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your network IP is outside YouTube Music Web support. Force Egypt mode or switch to YouTube Web (never geo-blocked).',
                            style: TextStyle(
                                fontSize: 11, color: p.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              FilledButton.icon(
                                onPressed: _forceEgRegionReload,
                                icon: const Text('🇪🇬',
                                    style: TextStyle(fontSize: 12)),
                                label: const Text('Force Egypt Mode',
                                    style: TextStyle(fontSize: 11)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: p.accent,
                                  foregroundColor: p.onAccent,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _navigateTo('https://www.youtube.com'),
                                icon: const Icon(Icons.video_library_rounded,
                                    size: 13),
                                label: const Text('Open YouTube Web',
                                    style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  if (_isLoading || _progressNotifier.value < 1.0)
                    ValueListenableBuilder<double>(
                      valueListenable: _progressNotifier,
                      builder: (context, progress, _) {
                        if (!_isLoading && progress >= 1.0) {
                          return const SizedBox.shrink();
                        }
                        return LinearProgressIndicator(
                          value: _isLoading ? null : progress,
                          backgroundColor: p.surfaceContainer,
                          color: p.accent,
                          minHeight: 2.5,
                        );
                      },
                    ),
                  const Divider(height: 1),

                  // WebView Body — replaced by the recovery card once the
                  // automatic retries against Google's block page are spent.
                  Expanded(
                    child: (!isBrowse && _blockExhausted)
                        ? _buildBlockRecoveryCard(p)
                        : ClipRRect(
                      child: InAppWebView(
                        initialUrlRequest: URLRequest(
                          url: WebUri(_currentUrl),
                        ),
                        initialSettings: _settings,
                        initialUserScripts: _antiFingerPrintScripts,
                        gestureRecognizers: const <Factory<
                            OneSequenceGestureRecognizer>>{
                          Factory<OneSequenceGestureRecognizer>(
                            EagerGestureRecognizer.new,
                          ),
                        },
                        onWebViewCreated: (controller) {
                          _webViewController = controller;
                        },
                        onCreateWindow: (controller, createWindowAction) async {
                          final url = createWindowAction.request.url;
                          if (url != null) {
                            final urlStr = url.toString().toLowerCase();
                            if (urlStr.startsWith('market://') ||
                                urlStr.startsWith('intent://') ||
                                urlStr.contains('play.google.com')) {
                              return false;
                            }
                            await controller.loadUrl(
                                urlRequest: URLRequest(url: url));
                          }
                          return true;
                        },
                        shouldOverrideUrlLoading:
                            (controller, navigationAction) async {
                          final uri = navigationAction.request.url;
                          if (uri == null) return NavigationActionPolicy.ALLOW;
                          final urlStr = uri.toString();
                          final urlLower = urlStr.toLowerCase();

                          // Prevent Google Play Store / market / intent deep links from opening
                          if (urlLower.startsWith('market://') ||
                              urlLower.startsWith('intent://') ||
                              urlLower.contains('play.google.com') ||
                              (urlLower.contains('google.com/url') &&
                                  urlLower.contains('play.google.com'))) {
                            if (!widget.isBrowseMode && !urlLower.contains('music')) {
                              unawaited(_navigateTo(googleSignInUrl));
                            } else {
                              unawaited(_navigateTo('https://music.youtube.com'));
                            }
                            return NavigationActionPolicy.CANCEL;
                          }

                          if (!urlStr.startsWith('http://') &&
                              !urlStr.startsWith('https://') &&
                              !urlStr.startsWith('about:')) {
                            return NavigationActionPolicy.CANCEL;
                          }
                          return NavigationActionPolicy.ALLOW;
                        },
                        onLoadStart: (controller, url) async {
                          if (mounted) setState(() => _isLoading = true);
                          final urlStr = url?.toString() ?? '';
                          final urlLower = urlStr.toLowerCase();

                          // Fail-safe: if WebView started navigating to Google Play, stop and bounce to YTM
                          if (urlLower.contains('play.google.com') ||
                              urlLower.startsWith('market://') ||
                              urlLower.startsWith('intent://')) {
                            debugPrint(
                                '[YtmWebLogin] onLoadStart caught Google Play link, returning to music.youtube.com');
                            unawaited(controller.stopLoading());
                            final fallback = widget.isBrowseMode
                                ? 'https://music.youtube.com'
                                : googleSignInUrl;
                            unawaited(_navigateTo(fallback));
                            return;
                          }

                          final isYtm = widget.isBrowseMode ||
                              urlLower.contains('music.youtube.com');
                          final targetUa = _uaIdentityOverride != null
                              ? _uaFor(_uaIdentityOverride!)
                              : (isYtm ? desktopUserAgent : mobileUserAgent);
                          try {
                            await controller.setSettings(
                              settings: InAppWebViewSettings(
                                userAgent: targetUa,
                                preferredContentMode: isYtm
                                    ? UserPreferredContentMode.DESKTOP
                                    : UserPreferredContentMode.RECOMMENDED,
                              ),
                            );
                          } catch (e, st) {
                            ErrorLogger.log('startsWith failed', error: e, stackTrace: st, category: 'YtmWebLoginSheet');
                          }
                        },
                        onProgressChanged: (controller, progress) {
                          // F-17: no setState — progress ticks only rebuild
                          // the ValueListenableBuilder bar above.
                          _progressNotifier.value = progress / 100;
                        },
                        onLoadStop: (controller, url) async {
                          if (mounted) setState(() => _isLoading = false);
                          await _updateNavState();
                          final urlStr = url?.toString() ?? '';
                          final urlLower = urlStr.toLowerCase();

                          // Fail-safe: if loaded page landed on Google Play, bounce back to YouTube Music
                          if (urlLower.contains('play.google.com')) {
                            debugPrint(
                                '[YtmWebLogin] onLoadStop landed on play.google.com, bouncing to music.youtube.com');
                            final fallback = widget.isBrowseMode
                                ? 'https://music.youtube.com'
                                : googleSignInUrl;
                            unawaited(_navigateTo(fallback));
                            return;
                          }

                          final parsedUrl = Uri.tryParse(urlStr);
                          final host = parsedUrl?.host ?? '';

                          // Check for Geo-block ("not available in your area" / "not available in your country")
                          if (urlLower.contains('music.youtube.com')) {
                            final isGeoBlocked =
                                await _scanPageForGeoBlock(controller);
                            if (mounted && _isGeoBlocked != isGeoBlocked) {
                              setState(() => _isGeoBlocked = isGeoBlocked);
                            }
                          } else {
                            if (mounted && _isGeoBlocked) {
                              setState(() => _isGeoBlocked = false);
                            }
                          }

                          // --- Google block detection ("This browser or app
                          // may not be secure") ---
                          if (host == 'accounts.google.com' ||
                              host == 'accounts.youtube.com') {
                            final blockedByUrl = _matchesBlockedUrl(parsedUrl);
                            final blockedByText = blockedByUrl
                                ? false
                                : (_shouldScanForBlockPage()
                                    ? await _scanPageForBlockText(controller)
                                    : false);
                            if (blockedByUrl || blockedByText) {
                              _handleGoogleBlock();
                              return;
                            }
                          }

                          // Only bounce if Google navigated to an actual CookieMismatch or block error page.
                          if (_isCookieMismatchUrl(urlStr)) {
                            if (_isLoggedIn) {
                              _isLoggedIn = false;
                              _detectedCookies = null;
                              if (mounted) setState(() {});
                            }
                            _handleCookieMismatch();
                            return;
                          }

                          // Do not capture on Google Sign-In or EU consent screens before the user finishes
                          if (_isAuthInProgressUrl(urlStr) ||
                              host == 'consent.youtube.com' ||
                              host == 'consent.google.com' ||
                              host.startsWith('consent.')) {
                            return;
                          }

                          if (host.endsWith('youtube.com') ||
                              host == 'youtu.be') {
                            _hadSuccessfulYtLoad = true;
                            _pollIntervalSeconds = 2;
                            _scheduleNextAuthPoll();
                          }
                          _mismatchAutoNavCount = 0;
                          await _checkIfLoggedIn(urlStr);
                        },
                        onReceivedError: (controller, request, error) {
                          debugPrint(
                              '[YtmWebLogin] Web resource error: ${error.type} - ${error.description}');
                          if (mounted) setState(() => _isLoading = false);
                        },
                        onUpdateVisitedHistory:
                            (controller, url, isReload) async {
                          await _updateNavState();
                          final urlStr = url?.toString() ?? '';
                          if (urlStr.isNotEmpty &&
                              !_isCookieMismatchUrl(urlStr) &&
                              !_isAuthInProgressUrl(urlStr)) {
                            await _checkIfLoggedIn(urlStr);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shown in place of the WebView once both automatic retries against
  /// Google's embedded-browser block were exhausted.
  Widget _buildBlockRecoveryCard(PulsrPalette p) {
    final currentIdentity = _uaIdentityOverride ?? BrowserIdentity.mobile;
    // Cycle to the next identity in the ladder order
    const ladder = [
      BrowserIdentity.chromeDesktop,
      BrowserIdentity.mobile,
      BrowserIdentity.safariMobile,
      BrowserIdentity.desktop,
    ];
    final currentIdx = ladder.indexOf(currentIdentity);
    final otherIdentity = ladder[(currentIdx + 1) % ladder.length];

    String identityLabel(BrowserIdentity id) {
      switch (id) {
        case BrowserIdentity.chromeDesktop: return 'Chrome Desktop';
        case BrowserIdentity.mobile: return 'Firefox Mobile';
        case BrowserIdentity.safariMobile: return 'Safari Mobile';
        case BrowserIdentity.desktop: return 'Firefox Desktop';
      }
    }

    IconData identityIcon(BrowserIdentity id) {
      switch (id) {
        case BrowserIdentity.chromeDesktop: return Icons.desktop_windows_rounded;
        case BrowserIdentity.mobile: return Icons.smartphone_rounded;
        case BrowserIdentity.safariMobile: return Icons.phone_iphone_rounded;
        case BrowserIdentity.desktop: return Icons.laptop_windows_rounded;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.error.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.gpp_bad_rounded, color: p.error, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Google is blocking this sign-in",
                        style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "Google blocks sign-in inside embedded browsers for some "
                  "accounts, and the automatic retries (clearing cookies and "
                  "switching the browser identity) didn't get past it.\n\n"
                  "Pulsr captures your YouTube Music session from this "
                  "embedded browser's cookies, so the sign-in has to happen "
                  "here — signing in inside the app is required for the "
                  "connection to be detected.",
                  style: TextStyle(
                      color: p.textSecondary, fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current identity: ${identityLabel(currentIdentity)}',
                  style: TextStyle(
                      color: p.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _manualRetryFromBlock,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry',
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _switchIdentityManually(otherIdentity),
            icon: Icon(identityIcon(otherIdentity), size: 18),
            label: Text(
                'Try ${identityLabel(otherIdentity)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.hairline),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _blockExhausted = false);
              _navigateTo('https://music.youtube.com');
            },
            icon: const Icon(Icons.music_note_rounded, size: 18),
            label: const Text('Open YouTube Music web directly',
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.hairline),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showManualCookieDialog(context),
            icon: const Icon(Icons.vpn_key_rounded, size: 18),
            label: const Text('Import Cookies / Token Manually',
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.hairline),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tip: if Google continues to block in-app sign-in on this device, paste your cookies from your browser using the button above.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _navChip({
    required String label,
    required IconData icon,
    required String url,
    required PulsrPalette p,
  }) {
    final isCurrent = _currentUrl == url || _currentUrl.startsWith('$url?');

    return InkWell(
      onTap: () => _navigateTo(url),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isCurrent ? p.accentContainer : p.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrent ? p.accent : p.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isCurrent ? p.accent : p.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isCurrent ? p.accent : p.textPrimary,
                fontSize: 11,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showManualCookieDialog(BuildContext context) async {
    final p = context.palette;
    final textController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: p.surface,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.vpn_key_rounded, color: p.accent, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Import Cookies Manually',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'If Google blocks embedded browser login on this device, you can paste your raw cookie string (e.g. from browser DevTools on desktop) or cURL cookie header directly:',
                  style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textController,
                  maxLines: 4,
                  style: TextStyle(color: p.textPrimary, fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'SAPISID=...; __Secure-3PSID=...; SID=...',
                    hintStyle: TextStyle(color: p.textTertiary, fontSize: 11),
                    filled: true,
                    fillColor: p.surfaceContainer,
                    errorText: errorText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: p.onAccent,
              ),
              onPressed: () async {
                final input = textController.text.trim();
                if (input.isEmpty) {
                  setDialogState(() => errorText = 'Please enter cookie text');
                  return;
                }
                final accountService = getIt<YtmAccountService>();
                String cookieStr = input;
                if (cookieStr.toLowerCase().contains('cookie:')) {
                  final idx = cookieStr.toLowerCase().indexOf('cookie:');
                  cookieStr = cookieStr.substring(idx + 7).trim();
                }
                await accountService.saveSession(cookieStr);
                final valid = await accountService.validateSession();
                if (valid) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    setState(() {
                      _isLoggedIn = true;
                      _detectedCookies = cookieStr;
                    });
                    Navigator.of(context).pop(true);
                  }
                } else {
                  setDialogState(() => errorText = 'Invalid or expired cookies (must include SAPISID and PSID)');
                }
              },
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
