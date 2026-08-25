// lib/features/auth/presentation/ytm_web_login_sheet.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/theme/aura_theme.dart';

class YtmWebLoginSheet extends StatefulWidget {
  const YtmWebLoginSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const YtmWebLoginSheet(),
    );
  }

  @override
  State<YtmWebLoginSheet> createState() => _YtmWebLoginSheetState();
}

class _YtmWebLoginSheetState extends State<YtmWebLoginSheet> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _progress = 0.0;
  bool _isLoggedIn = false;
  String? _detectedCookies;
  bool _showHint = false;
  Timer? _hintTimer;
  Timer? _authPollTimer;

  @override
  void initState() {
    super.initState();
    final accountService = getIt<YtmAccountService>();
    if (accountService.isLoggedIn) {
      _isLoggedIn = true;
    }

    final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final userAgent = isApple
        ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'
        : 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Mobile Safari/537.36';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
          onPageStarted: (url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) async {
            if (mounted) setState(() => _isLoading = false);
            await _checkIfLoggedIn(url);
          },
          onWebResourceError: (error) {
            debugPrint('[YtmWebLogin] Web resource error: ${error.errorCode} - ${error.description}');
            if (mounted) setState(() => _isLoading = false);
          },
          onUrlChange: (change) async {
            if (change.url != null) {
              await _checkIfLoggedIn(change.url);
            }
          },
        ),
      );

    _hintTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_isLoggedIn) {
        setState(() => _showHint = true);
      }
    });

    // Periodic poll to detect login completion as soon as session cookies are available
    _authPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && !_isLoggedIn) {
        _checkIfLoggedIn();
      }
    });

    _initWebView();
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _authPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _initWebView() async {
    final accountService = getIt<YtmAccountService>();
    if (accountService.isLoggedIn && mounted) {
      setState(() => _isLoggedIn = true);
    }
    await _controller.loadRequest(
      Uri.parse('https://music.youtube.com'),
    );
  }

  Future<bool> _checkIfLoggedIn([String? url]) async {
    if (_isLoggedIn) return true;

    String? currentUrl = url;
    try {
      currentUrl ??= await _controller.currentUrl();
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

    // Fallback: JS document.cookie (safely wrapped in IIFE try-catch)
    if (currentUrl != null &&
        !currentUrl.startsWith('chrome-error://') &&
        !currentUrl.startsWith('about:')) {
      try {
        final rawCookie = await _controller.runJavaScriptReturningResult(
          '(() => { try { return document.cookie || ""; } catch (e) { return ""; } })()',
        );
        String cookieStr = rawCookie.toString();
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

    if (cookies == null || cookies.isEmpty) {
      cookies = await accountService.getNativeCookiesFromDomains();
    }

    if (cookies == null || cookies.isEmpty) {
      try {
        final rawCookie = await _controller.runJavaScriptReturningResult(
          '(() => { try { return document.cookie || ""; } catch (e) { return ""; } })()',
        );
        String cookieStr = rawCookie.toString();
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

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 150),
      child: Container(
        height: size.height * 0.88,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: p.hairline),
        ),
        child: Column(
          children: [
            // Drag handle & Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                  const SizedBox(height: 10),
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
                      // Done Button - Turns green when user login is detected
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
                        onPressed: () {
                          _controller.reload();
                        },
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
              ),
            ),
            if (_isLoggedIn)
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
            else if (_showHint)
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
                child: WebViewWidget(
                  controller: _controller,
                  gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
                    Factory<OneSequenceGestureRecognizer>(
                      EagerGestureRecognizer.new,
                    ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
