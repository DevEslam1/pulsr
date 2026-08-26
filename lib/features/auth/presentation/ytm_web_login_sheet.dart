// lib/features/auth/presentation/ytm_web_login_sheet.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';

class YtmWebLoginSheet extends StatefulWidget {
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

  bool _canGoBack = false;
  bool _canGoForward = false;
  late String _currentUrl;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl ?? 'https://music.youtube.com';

    final accountService = getIt<YtmAccountService>();
    if (accountService.isLoggedIn) {
      _isLoggedIn = true;
    }

    // Use Desktop Chrome User-Agent for both Android and desktop platforms.
    // Google Accounts on mobile User-Agents attempts to invoke Android Play Services /
    // OS Account Manager intents, which fail inside WebViews with "CookieMismatch".
    // A desktop User-Agent ensures pure web cookie authentication.
    const userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

    _settings = InAppWebViewSettings(
      userAgent: userAgent,
      applicationNameForUserAgent: '',
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      supportMultipleWindows: false,
      mediaPlaybackRequiresUserGesture: false,
      isInspectable: kDebugMode,
      transparentBackground: true,
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
    );

    _hintTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_isLoggedIn && !widget.isBrowseMode) {
        setState(() => _showHint = true);
      }
    });

    // Periodic poll to detect login completion as soon as session cookies are available
    _authPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && !_isLoggedIn) {
        _checkIfLoggedIn();
      }
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _authPollTimer?.cancel();
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

  Future<void> _clearCookiesAndReset() async {
    try {
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();
      await InAppWebViewController.clearAllCache();
      final accountService = getIt<YtmAccountService>();
      await accountService.logout();
      _navigateTo('https://music.youtube.com');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cookies and cache cleared. Reloading YouTube Music...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[YtmWebLogin] Failed to clear cookies: $e');
    }
  }

  void _navigateTo(String url) {
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  Future<bool> _checkIfLoggedIn([String? url]) async {
    if (_isLoggedIn) return true;

    String? currentUrl = url;
    try {
      final webUri = await _webViewController?.getUrl();
      currentUrl ??= webUri?.toString();
    } catch (_) {}

    if (currentUrl != null) {
      if (currentUrl.startsWith('chrome-error://') ||
          currentUrl.startsWith('about:') ||
          currentUrl.contains('accounts.google.com') ||
          currentUrl.contains('ServiceLogin') ||
          currentUrl.contains('signin/v2')) {
        return false;
      }
    }

    final accountService = getIt<YtmAccountService>();

    // 1. Try InAppWebView CookieManager
    try {
      final cookieManager = CookieManager.instance();
      final domains = [
        'https://music.youtube.com',
        'https://youtube.com',
        'https://accounts.google.com',
      ];
      final List<String> cookieParts = [];
      for (final domain in domains) {
        final cookies = await cookieManager.getCookies(url: WebUri(domain));
        for (final c in cookies) {
          final pair = '${c.name}=${c.value}';
          if (!cookieParts.contains(pair)) {
            cookieParts.add(pair);
          }
        }
      }
      if (cookieParts.isNotEmpty) {
        final combinedCookies = cookieParts.join('; ');
        final hasSecure3Psid = combinedCookies.contains('__Secure-3PSID');
        final hasSecure1Psid = combinedCookies.contains('__Secure-1PSID');
        final hasSapisid = combinedCookies.contains('SAPISID');

        if (hasSapisid && (hasSecure3Psid || hasSecure1Psid)) {
          if (!_isLoggedIn) {
            _isLoggedIn = true;
            _detectedCookies = combinedCookies;
            await accountService.saveSession(combinedCookies);
            if (mounted) {
              setState(() {});
            }
          }
          return true;
        }
      }
    } catch (_) {}

    // 2. Try native platform cookie manager
    final cookies = await accountService.getNativeCookiesFromDomains();
    if (cookies != null && cookies.isNotEmpty) {
      final hasSecure3Psid = cookies.contains('__Secure-3PSID');
      final hasSecure1Psid = cookies.contains('__Secure-1PSID');
      final hasSapisid = cookies.contains('SAPISID');

      if (hasSapisid && (hasSecure3Psid || hasSecure1Psid)) {
        if (!_isLoggedIn) {
          _isLoggedIn = true;
          _detectedCookies = cookies;
          await accountService.saveSession(cookies);
          if (mounted) {
            setState(() {});
          }
        }
        return true;
      }
    }

    // 3. Fallback: JS document.cookie
    if (currentUrl != null &&
        !currentUrl.startsWith('chrome-error://') &&
        !currentUrl.startsWith('about:')) {
      try {
        final rawCookie = await _webViewController?.evaluateJavascript(
          source: '(() => { try { return document.cookie || ""; } catch (e) { return ""; } })()',
        );
        String cookieStr = rawCookie?.toString() ?? '';
        if (cookieStr.startsWith('"') && cookieStr.endsWith('"')) {
          cookieStr = cookieStr.substring(1, cookieStr.length - 1);
        }
        if (cookieStr.contains('SAPISID') &&
            (cookieStr.contains('__Secure-3PSID') ||
                cookieStr.contains('__Secure-1PSID') ||
                cookieStr.contains('SSID'))) {
          if (!_isLoggedIn) {
            _isLoggedIn = true;
            _detectedCookies = cookieStr;
            await accountService.saveSession(cookieStr);
            if (mounted) {
              setState(() {});
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

    // 1. Try InAppWebView CookieManager
    if (cookies == null || cookies.isEmpty) {
      try {
        final cookieManager = CookieManager.instance();
        final domains = [
          'https://music.youtube.com',
          'https://youtube.com',
          'https://accounts.google.com',
        ];
        final List<String> cookieParts = [];
        for (final domain in domains) {
          final domainCookies = await cookieManager.getCookies(url: WebUri(domain));
          for (final c in domainCookies) {
            final pair = '${c.name}=${c.value}';
            if (!cookieParts.contains(pair)) {
              cookieParts.add(pair);
            }
          }
        }
        if (cookieParts.isNotEmpty) {
          cookies = cookieParts.join('; ');
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
          source: '(() => { try { return document.cookie || ""; } catch (e) { return ""; } })()',
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

    if (cookies != null && cookies.isNotEmpty) {
      await accountService.saveSession(cookies);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
      return;
    }

    if (_isLoggedIn || accountService.isLoggedIn) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
      return;
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
    final size = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isBrowse = widget.isBrowseMode;

    return Center(
      child: ConstrainedBox(
        constraints: Adaptive.sheetConstraints(context),
        child: AnimatedPadding(
          padding: EdgeInsets.only(bottom: bottomInset),
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: size.height * (isBrowse ? 0.92 : 0.88),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: AppRadii.bottomSheetRadius,
              border: Border.all(color: p.hairline),
            ),
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
                              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                              tooltip: 'Back',
                              onPressed: _canGoBack
                                  ? () async {
                                      await _webViewController?.goBack();
                                      await _updateNavState();
                                    }
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
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
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: p.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: p.hairline),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.lock_rounded, size: 13, color: p.accent),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _currentUrl.replaceFirst('https://', ''),
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
                              icon: const Icon(Icons.refresh_rounded, size: 20),
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
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                                url: 'https://music.youtube.com/playlist?list=LM',
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
                              color: _isLoggedIn ? p.success : Colors.redAccent,
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
                                      color: _isLoggedIn ? p.success : p.textSecondary,
                                      fontSize: 11.5,
                                      fontWeight: _isLoggedIn ? FontWeight.w600 : FontWeight.normal,
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
                                foregroundColor:
                                    _isLoggedIn ? Colors.white : p.textPrimary,
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
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              tooltip: 'Refresh page',
                              onPressed: () => _webViewController?.reload(),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.cleaning_services_rounded, size: 20),
                              tooltip: 'Clear cache & reset cookies',
                              onPressed: _clearCookiesAndReset,
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(context).pop(false),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                if (!isBrowse && _isLoggedIn)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: p.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: p.success.withValues(alpha: 0.4)),
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
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 18, color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Make sure you sign into the correct Google account. Tap "Done" once logged in.',
                            style: TextStyle(fontSize: 12, color: p.textPrimary),
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
                      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
                        Factory<OneSequenceGestureRecognizer>(
                          EagerGestureRecognizer.new,
                        ),
                      },
                      onWebViewCreated: (controller) {
                        _webViewController = controller;
                      },
                      onLoadStart: (controller, url) {
                        if (mounted) setState(() => _isLoading = true);
                      },
                      onProgressChanged: (controller, progress) {
                        if (mounted) setState(() => _progress = progress / 100);
                      },
                      onLoadStop: (controller, url) async {
                        if (mounted) setState(() => _isLoading = false);
                        await _updateNavState();
                        final urlStr = url?.toString() ?? '';
                        if (urlStr.contains('CookieMismatch')) {
                          debugPrint(
                              '[YtmWebLogin] Detected CookieMismatch page from Google, resetting cookies and cache...');
                          await _clearCookiesAndReset();
                          return;
                        }
                        await _checkIfLoggedIn(url?.toString());
                      },
                      onReceivedError: (controller, request, error) {
                        debugPrint(
                            '[YtmWebLogin] Web resource error: ${error.type} - ${error.description}');
                        if (mounted) setState(() => _isLoading = false);
                      },
                      onUpdateVisitedHistory: (controller, url, isReload) async {
                        await _updateNavState();
                        if (url != null) {
                          await _checkIfLoggedIn(url.toString());
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
