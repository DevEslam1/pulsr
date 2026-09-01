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
        r'accounts\.google\.com|ServiceLogin|signin|/checkpoint/|consent\.',
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
  static String get mobileUserAgent => EmbeddedBrowserUa.mobile;
  static String get desktopUserAgent => EmbeddedBrowserUa.desktop;

  /// Returns the [UserScript] list to inject at AT_DOCUMENT_START.
  ///
  /// The script deletes navigator.userAgentData (Chromium-only, absent in
  /// Safari) and aligns platform/vendor so Google's sign-in cannot fingerprint
  /// the embedded WebView even after the UA string has been spoofed.
  static UnmodifiableListView<UserScript> get _antiFingerPrintScripts =>
      UnmodifiableListView([
        UserScript(
          source: EmbeddedBrowserUa.antiFingerprint,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]);

  static const List<String> _blockPhrases = [
    "couldn't sign you in",
    'this browser or app may not be secure',
  ];

  final GoogleBlockRecovery _blockRecovery = GoogleBlockRecovery();

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

  String _uaFor(BrowserIdentity identity) => identity == BrowserIdentity.desktop
      ? EmbeddedBrowserUa.desktop
      : EmbeddedBrowserUa.mobile;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl ??
        (widget.isBrowseMode ? 'https://music.youtube.com' : googleSignInUrl);

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

    final initialUa = _uaIdentityOverride != null
        ? _uaFor(_uaIdentityOverride!)
        : (widget.isBrowseMode ? desktopUserAgent : mobileUserAgent);

    _settings = InAppWebViewSettings(
      userAgent: initialUa,
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
    } catch (_) {}
  }

  /// Called by the CookieMismatch page detection. Google's cross-domain OAuth cookie
  /// sync redirect or mismatched state. Debounce navigation to music.youtube.com.
  void _handleCookieMismatch() {
    // Hard cap on automatic bounces: when Google's third-party cookie state
    // is broken it redirects every reload straight back to CookieMismatch.
    if (_mismatchAutoNavCount >= 3) {
      debugPrint('[YtmWebLogin] CookieMismatch auto-navigation cap reached; '
          'stopping and resetting cookies.');
      _clearCookiesAndReset();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
                'Google cookie mismatch detected. Resetting cookies — please sign in again.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
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
      final raw = await controller.evaluateJavascript(source: '''
(() => {
  try {
    var t = (document.title || '');
    var b = '';
    try { b = (document.body && document.body.innerText) || ''; } catch (e) {}
    return (t + '|' + b).slice(0, 4000).toLowerCase();
  } catch (e) { return ''; }
})()''');
      final text = raw?.toString().toLowerCase() ?? '';
      for (final phrase in _blockPhrases) {
        if (text.contains(phrase)) return true;
      }
    } catch (_) {}
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
      } catch (_) {}
      final target =
          widget.isBrowseMode ? 'https://music.youtube.com' : googleSignInUrl;
      await _webViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(target)));
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
    _pollIntervalSeconds = 2;
    _scheduleNextAuthPoll();
    final targetUa = _uaIdentityOverride != null
        ? _uaFor(_uaIdentityOverride!)
        : (widget.isBrowseMode ? desktopUserAgent : mobileUserAgent);
    try {
      await _webViewController?.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUa),
      );
    } catch (_) {}
    final loadUrlFuture = _webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)));
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
    } catch (_) {}

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
    } catch (_) {}

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
      } catch (_) {}
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
      } catch (_) {}
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
      } catch (_) {}
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

    // Expand height cleanly down to the bottom of the screen
    final targetHeight = (totalHeight - topPadding - (isBrowse ? 8 : 16))
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
              top: false,
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
                                  url: 'https://music.youtube.com',
                                  p: p,
                                ),
                                const SizedBox(width: 6),
                                _navChip(
                                  label: 'Explore / Charts',
                                  icon: Icons.explore_rounded,
                                  url: 'https://music.youtube.com/explore',
                                  p: p,
                                ),
                                const SizedBox(width: 6),
                                _navChip(
                                  label: 'Library',
                                  icon: Icons.library_music_rounded,
                                  url: 'https://music.youtube.com/library',
                                  p: p,
                                ),
                                const SizedBox(width: 6),
                                _navChip(
                                  label: 'Liked Music',
                                  icon: Icons.favorite_rounded,
                                  url:
                                      'https://music.youtube.com/playlist?list=LM',
                                  p: p,
                                ),
                                const SizedBox(width: 6),
                                _navChip(
                                  label: 'New Releases',
                                  icon: Icons.fiber_new_rounded,
                                  url: 'https://music.youtube.com/new_releases',
                                  p: p,
                                ),
                                const SizedBox(width: 6),
                                _navChip(
                                  label: 'History',
                                  icon: Icons.history_rounded,
                                  url: 'https://music.youtube.com/history',
                                  p: p,
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // LOGIN HEADER
                          Row(
                            children: [
                              Icon(
                                _isLoggedIn
                                    ? Icons.check_circle_rounded
                                    : Icons.cloud_sync_rounded,
                                color:
                                    _isLoggedIn ? p.success : Colors.redAccent,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isLoggedIn
                                          ? 'Logged In Successfully'
                                          : 'Sign in to YouTube Music',
                                      style: TextStyle(
                                        color: p.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      _isLoggedIn
                                          ? 'Account connected! Tap "Done" to finish.'
                                          : 'Connects your account to sync your Liked Music automatically',
                                      style: TextStyle(
                                        color: _isLoggedIn
                                            ? p.success
                                            : p.textSecondary,
                                        fontSize: 11.5,
                                        fontWeight: _isLoggedIn
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Done Button
                              FilledButton(
                                onPressed: _forceSaveAndFinish,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _isLoggedIn
                                      ? p.success
                                      : p.surfaceContainerHigh,
                                  foregroundColor: _isLoggedIn
                                      ? Colors.white
                                      : p.textPrimary,
                                  elevation: _isLoggedIn ? 3 : 0,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: _isLoggedIn
                                        ? BorderSide.none
                                        : BorderSide(color: p.hairline),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isLoggedIn) ...[
                                      const Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      'Done',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _isLoggedIn
                                            ? Colors.white
                                            : p.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(
                                    Icons.music_note_rounded,
                                    size: 20),
                                tooltip: 'Open YouTube Music web',
                                onPressed: () => _navigateTo('https://music.youtube.com'),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon:
                                    const Icon(Icons.refresh_rounded, size: 20),
                                tooltip: 'Refresh page',
                                onPressed: () => _webViewController?.reload(),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(
                                    Icons.vpn_key_rounded,
                                    size: 20),
                                tooltip: 'Import cookies manually',
                                onPressed: () => _showManualCookieDialog(context),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(
                                    Icons.cleaning_services_rounded,
                                    size: 20),
                                tooltip: 'Clear cache & reset cookies',
                                onPressed: _clearCookiesAndReset,
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                tooltip: 'Close',
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
                            final urlStr = url.toString();
                            if (urlStr.startsWith('market://') ||
                                urlStr.startsWith('intent://') ||
                                urlStr.contains('play.google.com/store/apps/details')) {
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

                          // Prevent Google Play Store / market / intent deep links from opening
                          if (urlStr.startsWith('market://') ||
                              urlStr.startsWith('intent://') ||
                              urlStr.contains('play.google.com/store/apps/details') ||
                              (urlStr.contains('google.com/url') &&
                                  urlStr.contains('play.google.com'))) {
                            if (!widget.isBrowseMode) {
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
                          final targetUa = _uaIdentityOverride != null
                              ? _uaFor(_uaIdentityOverride!)
                              : (widget.isBrowseMode ? desktopUserAgent : mobileUserAgent);
                          try {
                            await controller.setSettings(
                              settings:
                                  InAppWebViewSettings(userAgent: targetUa),
                            );
                          } catch (_) {}
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
                          final parsedUrl = Uri.tryParse(urlStr);
                          final host = parsedUrl?.host ?? '';

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
    final currentIdentity = _uaIdentityOverride ?? BrowserIdentity.desktop;
    final otherIdentity = currentIdentity == BrowserIdentity.desktop
        ? BrowserIdentity.mobile
        : BrowserIdentity.desktop;
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
                  'Current browser identity: ${currentIdentity.name} Safari',
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
            icon: Icon(
                otherIdentity == BrowserIdentity.mobile
                    ? Icons.smartphone_rounded
                    : Icons.desktop_windows_rounded,
                size: 18),
            label: Text(
                otherIdentity == BrowserIdentity.mobile
                    ? 'Use Mobile browser identity'
                    : 'Use Desktop browser identity',
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
