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
  bool _isSuccessHandled = false;
  bool _showHint = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final userAgent = isApple
        ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'
        : 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36';

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
            await _checkForAuthSuccess(url);
          },
        ),
      );

    _hintTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_isSuccessHandled) {
        setState(() => _showHint = true);
      }
    });

    _initWebView();
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  Future<void> _initWebView() async {
    try {
      await WebViewCookieManager().clearCookies();
      await _controller.clearCache();
    } catch (_) {}
    await _controller.loadRequest(
      Uri.parse('https://music.youtube.com'),
    );
  }

  Future<void> _checkForAuthSuccess(String url) async {
    if (_isSuccessHandled) return;

    final isOnYtm = url.contains('music.youtube.com') &&
        !url.contains('ServiceLogin') &&
        !url.contains('accounts.google.com') &&
        !url.contains('signin');
    if (!isOnYtm) return;

    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted || _isSuccessHandled) return;

    final accountService = getIt<YtmAccountService>();
    final cookies = await accountService.getNativeCookiesFromDomains();

    if (cookies != null && cookies.isNotEmpty) {
      final hasSecure3Psid = cookies.contains('__Secure-3PSID');
      final hasSecure1Psid = cookies.contains('__Secure-1PSID');
      final hasSapisid = cookies.contains('SAPISID');

      if (hasSapisid && (hasSecure3Psid || hasSecure1Psid)) {
        _isSuccessHandled = true;
        await accountService.saveSession(cookies);
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
        return;
      }
    }

    // Fallback: JS document.cookie
    try {
      final rawCookie = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      String cookieStr = rawCookie.toString();
      if (cookieStr.startsWith('"') && cookieStr.endsWith('"')) {
        cookieStr = cookieStr.substring(1, cookieStr.length - 1);
      }
      if (cookieStr.contains('SAPISID')) {
        _isSuccessHandled = true;
        await accountService.saveSession(cookieStr);
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (_) {}
  }

  Future<void> _forceSaveAndFinish() async {
    final accountService = getIt<YtmAccountService>();
    var nativeCookies = await accountService.getNativeCookiesFromDomains();
    if (nativeCookies == null || nativeCookies.isEmpty) {
      try {
        final rawCookie = await _controller.runJavaScriptReturningResult(
          'document.cookie',
        );
        String cookieStr = rawCookie.toString();
        if (cookieStr.startsWith('"') && cookieStr.endsWith('"')) {
          cookieStr = cookieStr.substring(1, cookieStr.length - 1);
        }
        if (cookieStr.isNotEmpty) {
          nativeCookies = cookieStr;
        }
      } catch (_) {}
    }

    if (nativeCookies != null && nativeCookies.isNotEmpty) {
      await accountService.saveSession(nativeCookies);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } else {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(false);
      }
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
                      const Icon(Icons.cloud_sync_rounded,
                          color: Colors.redAccent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sign in to YouTube Music',
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Connects your account to sync your Liked Music automatically',
                              style: TextStyle(
                                  color: p.textSecondary, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: _forceSaveAndFinish,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: const Text('Done', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_showHint)
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
                    const Icon(Icons.info_outline_rounded, size: 18, color: Colors.amber),
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
