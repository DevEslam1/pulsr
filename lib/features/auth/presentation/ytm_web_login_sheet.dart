// lib/features/auth/presentation/ytm_web_login_sheet.dart
import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/motion/pulsr_motion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../core/constants/embedded_browser_ua.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../utils/google_login_recovery.dart';
import 'ytm_oauth_login_sheet.dart';

import '../../../core/utils/error_logger.dart';
import '../../../core/utils/ytm_locale.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

part 'ytm_web_login_shell.dart';
part 'ytm_login_form_view.dart';
part 'ytm_browse_toolbar.dart';
part 'ytm_cookie_recovery_view.dart';
part 'ytm_geo_block_banner.dart';
part 'ytm_block_recovery_card.dart';

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

  static bool _isShowing = false;

  static Future<bool?> show(
    BuildContext context, {
    String? initialUrl,
    String? title,
    bool isBrowseMode = false,
  }) async {
    if (_isShowing) return null;
    _isShowing = true;
    try {
      return await PulsrSheetHelper.showPulsrSheet<bool>(
        context: context,
        enableDrag: false,
        wrapWithContainer: false,
        builder: (_) => YtmWebLoginSheet(
          initialUrl: initialUrl,
          title: title,
          isBrowseMode: isBrowseMode,
        ),
      );
    } finally {
      _isShowing = false;
    }
  }

  /// Generates hardened [InAppWebViewSettings] ensuring strict sandboxing:
  /// no local file access, no universal access from file URLs, no content provider access,
  /// no mixed content, and suppressed X-Requested-With package headers.
  static InAppWebViewSettings buildDefaultSettings({String? userAgent}) {
    return InAppWebViewSettings(
      userAgent: userAgent ?? EmbeddedBrowserUa.mobile,
      preferredContentMode: UserPreferredContentMode.MOBILE,
      useHybridComposition: true,
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: true,
      mediaPlaybackRequiresUserGesture: false,
      isInspectable: kDebugMode,
      transparentBackground: false,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
      cacheEnabled: true,
      databaseEnabled: true,
      domStorageEnabled: true,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,
      allowFileAccess: false,
      allowContentAccess: false,
      allowFileAccessFromFileURLs: false,
      allowUniversalAccessFromFileURLs: false,
      geolocationEnabled: false,
      useWideViewPort: true,
      loadWithOverviewMode: true,
      supportZoom: true,
      builtInZoomControls: false,
      displayZoomControls: false,
      allowsInlineMediaPlayback: true,
      useShouldOverrideUrlLoading: true,
      requestedWithHeaderOriginAllowList: <String>{},
      disableDefaultErrorPage: false,
    );
  }

  /// Evaluates whether a navigation action to [uri] is permitted under Pulsr's webview sandbox.
  /// Blocks non-HTTPS schemes (especially javascript:, file:, data:, market:, intent:) and untrusted domains.
  static NavigationActionPolicy evaluateNavigation(Uri? uri) {
    if (uri == null) return NavigationActionPolicy.ALLOW;
    final urlStr = uri.toString().toLowerCase();

    // Block all script execution or local file access schemes
    if (urlStr.startsWith('javascript:') ||
        urlStr.startsWith('file:') ||
        urlStr.startsWith('data:') ||
        urlStr.startsWith('blob:') ||
        uri.scheme == 'javascript' ||
        uri.scheme == 'file' ||
        uri.scheme == 'data' ||
        uri.scheme == 'blob') {
      return NavigationActionPolicy.CANCEL;
    }

    // Block app market and intent schemes
    if (urlStr.startsWith('market://') ||
        urlStr.startsWith('intent://') ||
        urlStr.contains('play.google.com') ||
        (urlStr.contains('google.com/url') &&
            urlStr.contains('play.google.com'))) {
      return NavigationActionPolicy.CANCEL;
    }

    // Enforce trusted Google/YouTube endpoints
    if (!_YtmWebLoginSheetState._isTrustedGoogleNavigation(uri)) {
      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.ALLOW;
  }

  @override
  State<YtmWebLoginSheet> createState() => _YtmWebLoginSheetState();
}

enum _AuthPollState { idle, polling, cooldown, dead, done }

class _YtmWebLoginSheetState extends State<YtmWebLoginSheet> {
  InAppWebViewController? _webViewController;
  InAppWebViewSettings? _settings;
  bool _isLoading = true;

  /// The UA actually pushed onto the live WebView. On Android it is derived
  /// from the device's real System WebView (see [_resolveUserAgent]) so the UA
  /// string and the engine-reported Client Hints cannot disagree; elsewhere it
  /// falls back to the packaged constant.
  String _resolvedUserAgent = EmbeddedBrowserUa.mobile;

  /// Set once the native WebView behind [_webViewController] has been torn down.
  bool _webViewGone = false;
  _AuthPollState _pollState = _AuthPollState.idle;
  int _deadHandleHits = 0;
  static const int _maxDeadHandleHits = 3;

  /// Identity of the native WebView instance currently mounted. Bumped by
  /// [_restartWebView] so Flutter builds a *new* platform view (and therefore
  /// a new native WebView) instead of reusing a dead handle.
  int _webViewInstance = 0;

  bool _disposed = false;

  /// Whether [error] means the native WebView is gone rather than that the call
  /// itself failed. Nothing is recoverable from it, and it is not worth a crash
  /// report — it is the expected shape of "you are holding a dead handle".
  bool _isWebViewGoneError(Object error) =>
      error is MissingPluginException ||
      (error is PlatformException && error.code == 'invalid_instance_id');

  /// Funnels a caught WebView error: drops the dead-handle case (recording it so
  /// callers stop retrying) and crash-reports everything else as before.
  void _handleWebViewError(String context, Object error, StackTrace stack) {
    if (_isWebViewGoneError(error)) {
      _pollState = _AuthPollState.dead;
      _deadHandleHits++;
      if (!_webViewGone) {
        _webViewGone = true;
        _webViewController = null;
        _cancelAllTimers();
        debugPrint(
            '[YtmWebLogin] native WebView is gone ($context, hits: $_deadHandleHits) — pausing auth poll');
        if (mounted) setState(() {});
      }
      return;
    }
    ErrorLogger.log(context,
        error: error, stackTrace: stack, category: 'YtmWebLoginSheet');
  }

  /// setState that tolerates a callback landing after the sheet is gone.
  /// WebView callbacks are async and a page load can outlive a fast dismiss;
  /// without this guard those late callbacks threw "setState() called after
  /// dispose()".
  void _setStateSafe(VoidCallback fn) {
    if (!mounted || _disposed) return;
    setState(fn);
  }

  final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0.0);

  bool _isLoggedIn = false;
  bool _finishing = false;
  String? _detectedCookies;
  bool _showHint = false;
  Timer? _hintTimer;
  Timer? _authPollTimer;
  bool _hadSuccessfulYtLoad = false;

  static const String googleSignInUrl = YtmWebLoginSheet.googleSignInUrl;

  static bool _isCookieMismatchUrl(String u) {
    if (RegExp(
      r'CookieMismatch|/sorry|speedbump',
      caseSensitive: false,
    ).hasMatch(u)) {
      return true;
    }
    final uri = Uri.tryParse(u);
    if (uri == null) return false;
    final hasCookieError = uri.queryParameters.containsKey('cookie_mismatch') ||
        uri.queryParameters['error'] == 'cookie_mismatch' ||
        (uri.queryParameters['flowName'] == 'GlifWebSignIn' &&
            uri.queryParameters.containsKey('cookie_mismatch'));
    return hasCookieError ||
        uri.path.contains('cookiemismatch') ||
        uri.path.contains('cookie_mismatch');
  }

  static bool _isAuthInProgressUrl(String u) => RegExp(
        r'accounts\.google\.com/(v3/)?signin|accounts\.google\.com/ServiceLogin|/checkpoint/|/challenge/|challenge|consent\.google',
        caseSensitive: false,
      ).hasMatch(u);

  static bool _isTrustedGoogleNavigation(Uri uri) {
    if (uri.scheme == 'about') return true;
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'google.com' ||
        host.endsWith('.google.com') ||
        host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtu.be' ||
        host.endsWith('.youtu.be') ||
        host == 'googleusercontent.com' ||
        host.endsWith('.googleusercontent.com') ||
        host == 'gstatic.com' ||
        host.endsWith('.gstatic.com') ||
        host == 'googleapis.com' ||
        host.endsWith('.googleapis.com');
  }

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
  // On Android the default identity is derived from the real System WebView at
  // runtime so the UA string matches the engine's Client Hints exactly.
  String get mobileUserAgent => _resolvedUserAgent;

  static const String _ytmBrowseGuardJs = r'''
(function () {
  'use strict';
  try {
    var host = (window.location && window.location.hostname) || '';
    // Only run browse guard on YouTube / YouTube Music.
    // NEVER tamper with window.location on accounts.google.com or google.com!
    if (host.indexOf('youtube.com') === -1) {
      return;
    }

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
      document.cookie = "PREF=${YtmLocale.prefCookieValue()}; domain=.youtube.com; path=/";
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
    var host = (window.location && window.location.hostname) || '';
    // Only enforce viewport & promo hiding on YouTube Music.
    // NEVER alter styles or viewport on Google Sign-In (accounts.google.com).
    if (host.indexOf('music.youtube.com') === -1) {
      return;
    }

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

    // Enforce mobile responsive viewport for natural phone layout
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'viewport';
      (document.head || document.documentElement).appendChild(meta);
    }
    meta.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes');
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
  static final UnmodifiableListView<UserScript> _antiFingerPrintScripts =
      UnmodifiableListView<UserScript>([
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

  /// Phrases that are, on their own, proof of Google's embedded-browser block.
  static const List<String> _blockPhrases = [
    'this browser or app may not be secure',
  ];

  /// `Couldn't sign you in` is Google's generic failure heading, so it also
  /// appears on ordinary errors ("Something went wrong"). It only counts as
  /// the browser block when one of these companions is present — the same
  /// pairing the injected detector in [EmbeddedBrowserUa.antiFingerprint]
  /// requires.
  static const String _blockHeading = "couldn't sign you in";
  static const List<String> _blockHeadingCompanions = [
    'try using a different browser',
    'browser or app may not be secure',
  ];

  final GoogleBlockRecovery _blockRecovery =
      GoogleBlockRecovery(initialIdentity: BrowserIdentity.mobile);

  /// Non-null while the automatic recovery ladder is running (drives the
  /// inline status banner); prevents re-entry so the ladder never loops.
  String? _blockStatus;

  /// True after the 2 automatic retries were exhausted → recovery card.
  bool _blockExhausted = false;

  /// Identity override chosen by the ladder or the recovery card. Null =
  /// follow the automatic ladder.
  BrowserIdentity? _uaIdentityOverride;

  final Stopwatch _lastBlockScanStopwatch = Stopwatch()..start();

  /// Suppresses block re-detection for 8 s after each recovery step so the
  /// new page has time to fully load before we scan again. Without this,
  /// the poll fires while the reloaded page is still the block page and
  /// triggers another recovery step immediately, looping forever.
  final Stopwatch _blockCooldownStopwatch = Stopwatch();

  bool _isGeoBlocked = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl != null
        ? _withGeoParams(widget.initialUrl!)
        : (widget.isBrowseMode ? YtmLocale.homeUrl() : googleSignInUrl);

    // Pre-seed Egypt region preference cookie for YouTube domains
    unawaited(() async {
      try {
        final cookieManager = CookieManager.instance();
        await cookieManager.setCookie(
          url: WebUri('https://music.youtube.com'),
          name: 'PREF',
          value: YtmLocale.prefCookieValue(),
          domain: '.youtube.com',
          path: '/',
        );
      } catch (_) {}
    }());

    final accountService = getIt<YtmAccountService>();
    if (accountService.isLoggedIn) {
      // Only a definite `invalid` may tear the jar down. `validateSession()`
      // flattens the three-way verdict into a bool, so a timeout, a captive
      // portal or an IP-level 403 read as "signed out": the sheet dropped to the
      // sign-in prompt and `_clearCookiesAndReset()` wiped a session that was
      // perfectly good, forcing a real re-login over something transient.
      accountService.validateSessionDetailed().then((verdict) {
        if (!mounted) return;
        setState(
            () => _isLoggedIn = verdict != SessionValidationResult.invalid);
        if (verdict == SessionValidationResult.invalid) {
          _clearCookiesAndReset(); // start the re-login with a CLEAN jar (fixes B6)
        }
      });
    }

    unawaited(_bootstrapSettings().catchError((error, stackTrace) {
      if (!mounted) return;
      ErrorLogger.log('Failed to bootstrap WebView settings',
          error: error, stackTrace: stackTrace, category: 'YtmWebLoginSheet');
      if (mounted) {
        setState(() {
          _settings = YtmWebLoginSheet.buildDefaultSettings(
              userAgent: EmbeddedBrowserUa.mobile);
        });
        _scheduleNextAuthPoll();
      }
    }));
  }

  /// Resolves the coherent runtime identity, then builds the WebView settings.
  ///
  /// Kept out of [initState] because the real Android System WebView UA is only
  /// available asynchronously. The WebView is not built until this completes
  /// (see the `_settings == null` gate in [build]), so the very first navigation
  /// — the sign-in page — already carries the coherent UA.
  Future<void> _bootstrapSettings() async {
    try {
      _resolvedUserAgent = await _resolveUserAgent();
      if (!mounted) return;

      final initialUa = _uaIdentityOverride != null
          ? _uaFor(_uaIdentityOverride!)
          : _resolvedUserAgent;

      _settings = YtmWebLoginSheet.buildDefaultSettings(userAgent: initialUa);

      _hintTimer = Timer(const Duration(seconds: 30), () {
        if (_disposed ||
            !mounted ||
            _webViewGone ||
            _isLoggedIn ||
            widget.isBrowseMode) {
          return;
        }
        setState(() => _showHint = true);
      });

      _pollIntervalSeconds = 2;
      if (!widget.isBrowseMode) _scheduleNextAuthPoll();
      if (mounted) setState(() {});
    } catch (e, st) {
      ErrorLogger.log(
          'Failed to bootstrap WebView settings in _bootstrapSettings',
          error: e,
          stackTrace: st,
          category: 'YtmWebLoginSheet');
      if (!mounted) return;
      setState(() {
        _settings = YtmWebLoginSheet.buildDefaultSettings(
            userAgent: EmbeddedBrowserUa.mobile);
      });
      if (!widget.isBrowseMode) _scheduleNextAuthPoll();
    }
  }

  /// Derives a coherent Chrome-on-Android UA from the device's real System
  /// WebView.
  ///
  /// The old code hardcoded a browser version, so the UA string inevitably
  /// drifted from the installed engine and disagreed with the engine's
  /// `navigator.userAgentData` / Client Hints — one of the strongest
  /// embedded-WebView signals Google screens for. Deriving the string from the
  /// live engine keeps the two in lock-step. Non-Android (desktop) keeps the
  /// packaged constant.
  Future<String> _resolveUserAgent() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return EmbeddedBrowserUa.mobile;
    }
    try {
      final raw = await InAppWebViewController.getDefaultUserAgent()
          .timeout(const Duration(seconds: 4));
      final normalized = EmbeddedBrowserUa.normalizeAndroidWebViewUa(raw);
      debugPrint('[YtmWebLogin] Runtime WebView UA: $normalized');
      return normalized;
    } catch (e) {
      debugPrint(
          '[YtmWebLogin] getDefaultUserAgent failed, using fallback: $e');
      return EmbeddedBrowserUa.mobile;
    }
  }

  int _pollIntervalSeconds = 2;
  int _authPollAttempts = 0;
  static const int _maxPollAttempts = 120;
  // FIX-H10: Generation counter to discard stale poll executions
  int _pollGeneration = 0;

  void _scheduleNextAuthPoll() {
    _authPollTimer?.cancel();
    // Browse mode has nothing to save automatically: the user is reading a web
    // page, and the poll's cookie harvest would only add background work (and a
    // home-page bounce) on top of the page's own traffic.
    if (_disposed ||
        !mounted ||
        widget.isBrowseMode ||
        _isLoggedIn ||
        _webViewGone ||
        _pollState == _AuthPollState.dead ||
        _pollState == _AuthPollState.done) {
      return;
    }
    if (_authPollAttempts >= _maxPollAttempts) {
      debugPrint('[YtmWebLogin] Max poll attempts reached, stopping.');
      _pollState = _AuthPollState.idle;
      return;
    }
    _authPollAttempts++;
    _pollState = _AuthPollState.polling;
    final generation = ++_pollGeneration;

    _authPollTimer = Timer(Duration(seconds: _pollIntervalSeconds), () async {
      if (_disposed) return;
      if (!mounted ||
          _isLoggedIn ||
          _webViewGone ||
          generation != _pollGeneration ||
          _pollState == _AuthPollState.dead) {
        return;
      }
      if (_webViewController != null && !_isLoading) {
        final loggedIn = await _checkIfLoggedIn();
        if (_disposed || !mounted || generation != _pollGeneration) return;
        if (loggedIn) {
          _pollState = _AuthPollState.done;
          return;
        }
        if (_disposed ||
            _webViewGone ||
            _webViewController == null ||
            generation != _pollGeneration) {
          _pollState = _AuthPollState.dead;
          return;
        }

        // Check for Google block during polling (detects SPA client-side rejections after tapping Next)
        if (!widget.isBrowseMode && !_blockExhausted && _blockStatus == null) {
          final inCooldown = _blockCooldownStopwatch.isRunning &&
              _blockCooldownStopwatch.elapsed < const Duration(seconds: 8);
          if (inCooldown) {
            _pollState = _AuthPollState.cooldown;
          }
          final isBlocked = (!inCooldown && _shouldScanForBlockPage())
              ? await _scanPageForBlockText(_webViewController!)
              : false;
          if (_disposed || !mounted || generation != _pollGeneration) return;
          if (isBlocked) {
            _handleGoogleBlock();
            return;
          }
        }
      }
      if (_disposed || !mounted) return;
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

  void _cancelAllTimers() {
    _hintTimer?.cancel();
    _hintTimer = null;
    _authPollTimer?.cancel();
    _authPollTimer = null;
    _cookieMismatchDebounce?.cancel();
    _cookieMismatchDebounce = null;
  }

  @override
  void dispose() {
    _cancelAllTimers();
    _disposed = true;
    _webViewGone = true;
    _blockCooldownStopwatch.stop();
    _lastBlockScanStopwatch.stop();
    _progressNotifier.dispose();
    _webViewController = null;
    super.dispose();
  }

  Future<void> _updateNavState() async {
    // Capture the controller: it is nulled out by _handleWebViewError and by
    // dispose() while these calls are awaiting, and the previous `!` then threw
    // a Null-check TypeError that was crash-reported as if it were a bug.
    final controller = _webViewController;
    if (_disposed || controller == null) return;
    try {
      final back = await controller.canGoBack();
      final forward = await controller.canGoForward();
      final url = await controller.getUrl();
      if (mounted && !_disposed) {
        setState(() {
          _canGoBack = back;
          _canGoForward = forward;
          if (url != null) {
            _currentUrl = url.toString();
          }
        });
      }
    } catch (e, st) {
      _handleWebViewError('_updateNavState failed', e, st);
    }
  }

  Future<void> _navigateTo(String url) async {
    final effectiveUrl = _withGeoParams(url);
    // Record the destination before touching the platform view. If the native
    // handle is already gone, the WebView is rebuilt from _currentUrl — and it
    // must land on the page we were asked to open, not replay the block page
    // that killed the previous instance.
    _currentUrl = effectiveUrl;
    _pollIntervalSeconds = 2;
    _authPollAttempts = 0;
    _pollState = _AuthPollState.idle;

    final targetUa = _uaIdentityOverride != null
        ? _uaFor(_uaIdentityOverride!)
        : mobileUserAgent;
    final isDesktop = _uaIdentityOverride == BrowserIdentity.desktop ||
        _uaIdentityOverride == BrowserIdentity.chromeDesktop;
    final contentMode = isDesktop
        ? UserPreferredContentMode.DESKTOP
        : UserPreferredContentMode.MOBILE;

    if (_webViewController == null || _webViewGone) {
      // No live handle to drive. Update the settings the replacement starts
      // with, then force a fresh native instance at _currentUrl.
      _settings = _settingsWithIdentity(
        _settings,
        userAgent: targetUa,
        contentMode: contentMode,
      );
      _restartWebView();
      return;
    }

    _scheduleNextAuthPoll();
    try {
      await _applyWebViewIdentity(
        _webViewController,
        userAgent: targetUa,
        contentMode: contentMode,
      );
    } catch (e, st) {
      _handleWebViewError('_navigateTo setSettings failed', e, st);
    }
    if (_webViewController == null || _webViewGone) {
      _restartWebView();
      return;
    }
    final loadUrlFuture = _webViewController!
        .loadUrl(urlRequest: URLRequest(url: WebUri(effectiveUrl)));
    // `loadUrl` on a dead handle throws asynchronously; unawaited, that became an
    // unhandled rejection rather than reaching _handleWebViewError.
    unawaited(loadUrlFuture.catchError((Object e, StackTrace st) =>
        _handleWebViewError('_navigateTo loadUrl failed', e, st)));
  }

  /// Rebuilds the native WebView after its handle died.
  ///
  /// Bumping [_webViewInstance] changes the widget key, so the framework tears
  /// down the old element and creates a new native view; simply clearing
  /// [_webViewGone] would keep the dead platform handle. The new view starts
  /// at [_currentUrl] with the identity already stored in [_settings].
  void _restartWebView() {
    _webViewGone = false;
    _webViewController = null;
    _deadHandleHits = 0;
    _pollState = _AuthPollState.idle;
    _pollIntervalSeconds = 2;
    _authPollAttempts = 0;
    // A brand-new view has no history yet. Leaving the old flags behind made
    // PopScope swallow the first back press (it tried to pop history that no
    // longer exists).
    _canGoBack = false;
    _canGoForward = false;
    _setStateSafe(() => _webViewInstance++);
    if (!widget.isBrowseMode) _scheduleNextAuthPoll();
  }

  /// Toolbar refresh that survives a native handle dying under it.
  Future<void> _reloadPage() async {
    final controller = _webViewController;
    if (controller == null || _webViewGone) {
      _navigateTo(_currentUrl);
      return;
    }
    try {
      await controller.reload();
    } catch (e, st) {
      _handleWebViewError('reload failed', e, st);
    }
  }

  Future<void> _goBack() async {
    final controller = _webViewController;
    if (controller == null || _webViewGone) return;
    try {
      await controller.goBack();
      await _updateNavState();
    } catch (e, st) {
      _handleWebViewError('goBack failed', e, st);
    }
  }

  Future<void> _goForward() async {
    final controller = _webViewController;
    if (controller == null || _webViewGone) return;
    try {
      await controller.goForward();
      await _updateNavState();
    } catch (e, st) {
      _handleWebViewError('goForward failed', e, st);
    }
  }

  Future<bool> _checkIfLoggedIn([String? url]) {
    if (_disposed || _isLoggedIn) return Future<bool>.value(true);
    return _loginCheckInFlight ??= () async {
      try {
        if (_disposed) return false;
        return await _detectLoginState(url);
      } catch (e, st) {
        ErrorLogger.log('Login check failed',
            error: e, stackTrace: st, category: 'YtmWebLogin');
        return false;
      } finally {
        _loginCheckInFlight = null;
      }
    }();
  }

  Future<bool> _detectLoginState([String? url]) async {
    if (_disposed || _isLoggedIn) return true;

    String? currentUrl = url;
    try {
      final webUri = await _webViewController?.getUrl();
      currentUrl ??= webUri?.toString();
    } catch (e, st) {
      _handleWebViewError('_detectLoginState getUrl failed', e, st);
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
      // This jar spans accounts.google.com and music.youtube.com and is keyed by
      // name only, so the Google account-management cookies land in it too.
      // Scope them out before anything treats this as the YouTube session.
      final combinedCookies = YtmAccountService.scopeCookiesForYouTube(
          jar.entries.map((e) => '${e.key}=${e.value}').join('; '));
      if (combinedCookies.isNotEmpty &&
          YtmAccountService.looksLikeSignedInCookies(combinedCookies)) {
        if (!_isLoggedIn) {
          _isLoggedIn = true;
          _detectedCookies = combinedCookies;
          await accountService.saveSession(combinedCookies);
          if (mounted && !_disposed) {
            setState(() {});
            // Navigate to music.youtube.com to complete the OAuth redirect
            // and ensure music.youtube.com domain cookies are also set. In
            // browse mode the user is already on YouTube: bouncing would
            // throw them off the page they are reading.
            if (!widget.isBrowseMode) {
              unawaited(_navigateTo('https://music.youtube.com'));
            }
          }
        }
        return true;
      }
    } catch (e, st) {
      // Not routed through _handleWebViewError: CookieManager is a static plugin
      // channel that outlives any one webview, so a failure here says nothing
      // about whether _webViewController is still alive.
      ErrorLogger.log('_detectLoginState cookie read failed',
          error: e, stackTrace: st, category: 'YtmWebLoginSheet');
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
        if (mounted && !_disposed) {
          setState(() {});
          if (!widget.isBrowseMode) {
            unawaited(_navigateTo('https://music.youtube.com'));
          }
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
            if (mounted && !_disposed) {
              setState(() {});
              if (!widget.isBrowseMode) {
                unawaited(_navigateTo('https://music.youtube.com'));
              }
            }
          }
          return true;
        }
      } catch (e, st) {
        ErrorLogger.log('toString failed',
            error: e, stackTrace: st, category: 'YtmWebLoginSheet');
      }
    }

    return false;
  }

  Future<void> _forceSaveAndFinish() async {
    if (_finishing) return;
    _finishing = true;
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
          // Same cross-host jar as in _detectLoginState: keep only what a
          // browser would actually send to a YouTube host.
          cookies = YtmAccountService.scopeCookiesForYouTube(
              jar.entries.map((e) => '${e.key}=${e.value}').join('; '));
        }
      } catch (e, st) {
        ErrorLogger.log('_forceSaveAndFinish failed',
            error: e, stackTrace: st, category: 'YtmWebLoginSheet');
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
        ErrorLogger.log('toString failed',
            error: e, stackTrace: st, category: 'YtmWebLoginSheet');
      }
    }

    if (cookies != null &&
        cookies.isNotEmpty &&
        YtmAccountService.looksLikeSignedInCookies(cookies)) {
      // saveSession refuses a jar without session cookies; trusting it blindly
      // closed the sheet on a session that was never stored.
      final saved = await accountService.saveSession(cookies);
      if (saved) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        } else {
          _finishing = false;
        }
        return;
      }
    }

    if (_isLoggedIn && accountService.isLoggedIn) {
      final valid = await accountService.validateSession();
      if (valid) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        } else {
          // Hosted as a page rather than a route: there is nothing to pop, but
          // the sheet must not latch `_finishing` and kill the Done button.
          _finishing = false;
        }
        return;
      }
    }

    _finishing = false;
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10n.completeSignInFirst),
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
    // `clamp(300, totalHeight)` throws when the viewport is shorter than 300 px
    // (a resized desktop window, a small split-screen pane): clamp requires
    // min <= max. Cap at the viewport and let the sheet shrink with it.
    final availableHeight = totalHeight - safeTop - (isBrowse ? 8 : 16);
    final targetHeight = availableHeight.clamp(0.0, totalHeight);

    return PopScope(
      // Back must unwind WebView history before it dismisses the sheet — both
      // in the in-app browser and while walking back through Google's sign-in
      // pages. Otherwise Android's back gesture closes the whole flow on the
      // first press, losing the half-finished login.
      canPop: _blockExhausted ||
          _webViewGone ||
          _deadHandleHits >= _YtmWebLoginSheetState._maxDeadHandleHits ||
          !_canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_goBack());
      },
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Adaptive.isTablet(context) ? 680 : double.infinity,
            maxHeight: targetHeight,
          ),
          child: AnimatedPadding(
            padding: EdgeInsets.only(bottom: bottomInset),
            duration: context.motionMs(150),
            child: Container(
              height: targetHeight,
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadii.r24)),
                border: Border.all(color: p.hairline),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.scrimAt(0.35),
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
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          AppSpacing.md,
                          AppSpacing.s10,
                          AppSpacing.md,
                          AppSpacing.s6),
                      child: Column(
                        children: [
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: p.textTertiary.withValues(alpha: 0.3),
                                borderRadius: AppRadii.r2All,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          if (isBrowse) ...[
                            // BROWSER TOOLBAR
                            ..._buildBrowseToolbar(p),
                          ] else ...[
                            _buildLoginHeader(p),
                          ],
                        ],
                      ),
                    ),

                    if (!isBrowse && _isLoggedIn)
                      _buildLoggedInBanner(p)
                    else if (!isBrowse && _showHint)
                      _buildHintBanner(p),

                    // Inline status banner during the block recovery ladder.
                    if (!isBrowse && _blockStatus != null)
                      _buildBlockStatusBanner(p),

                    // Geo-block alert banner with one-tap bypass & YouTube fallback
                    if (_isGeoBlocked) _buildGeoBlockBanner(p),

                    if (_isLoading || _progressNotifier.value < 1.0)
                      _buildLoadingBar(p),
                    const Divider(height: 1),

                    // WebView Body — replaced by the recovery card once the
                    // automatic retries against Google's block page are spent.
                    Expanded(
                      child: _buildWebViewBody(p, isBrowse),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
