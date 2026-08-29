// lib/features/auth/presentation/ytm_web_login_sheet.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';

class YtmWebLoginSheet extends StatefulWidget {
  static const String googleSignInUrl =
      'https://accounts.google.com/ServiceLogin?service=youtube&passive=true&continue=https%3A%2F%2Fmusic.youtube.com%2F&hl=en';

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
  double _progress = 0.0;
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

  static const String mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Mobile Safari/537.36';
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

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

    final isYtm = widget.isBrowseMode ||
        _currentUrl.contains('music.youtube.com') ||
        (_currentUrl.contains('youtube.com') &&
            !_currentUrl.contains('accounts.youtube.com'));
    final initialUa = isYtm ? desktopUserAgent : mobileUserAgent;

    _settings = InAppWebViewSettings(
      userAgent: initialUa,
      useHybridComposition: false,
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
      await accountService.clearSessionWebViewCookies();
      await accountService.logout();
      await InAppWebViewController.clearAllCache();
      _isLoggedIn = false;
      _detectedCookies = null;
      _hadSuccessfulYtLoad = false;
      _mismatchAutoNavCount = 0;
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

  Future<void> _navigateTo(String url) async {
    _pollIntervalSeconds = 2;
    _scheduleNextAuthPoll();
    final isYtm = url.contains('music.youtube.com') ||
        (url.contains('youtube.com') && !url.contains('accounts.youtube.com'));
    final targetUa = isYtm ? desktopUserAgent : mobileUserAgent;
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
                                icon:
                                    const Icon(Icons.refresh_rounded, size: 20),
                                tooltip: 'Refresh page',
                                onPressed: () => _webViewController?.reload(),
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

                  if (_isLoading || _progress < 1.0)
                    LinearProgressIndicator(
                      value: _isLoading ? null : _progress,
                      backgroundColor: p.surfaceContainer,
                      color: p.accent,
                      minHeight: 2.5,
                    ),
                  const Divider(height: 1),

                  // WebView Body
                  Expanded(
                    child: ClipRRect(
                      child: InAppWebView(
                        initialUrlRequest: URLRequest(
                          url: WebUri(_currentUrl),
                        ),
                        initialSettings: _settings,
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
                          final urlStr = url?.toString() ?? '';
                          final isYtm = urlStr.contains('music.youtube.com') ||
                              (urlStr.contains('youtube.com') &&
                                  !urlStr.contains('accounts.youtube.com') &&
                                  !_isAuthInProgressUrl(urlStr));
                          final targetUa =
                              isYtm ? desktopUserAgent : mobileUserAgent;
                          try {
                            await controller.setSettings(
                              settings:
                                  InAppWebViewSettings(userAgent: targetUa),
                            );
                          } catch (_) {}
                        },
                        onProgressChanged: (controller, progress) {
                          if (mounted) {
                            setState(() => _progress = progress / 100);
                          }
                        },
                        onLoadStop: (controller, url) async {
                          if (mounted) setState(() => _isLoading = false);
                          await _updateNavState();
                          final urlStr = url?.toString() ?? '';

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

                          final host = Uri.tryParse(urlStr)?.host ?? '';
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
}
