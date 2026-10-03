part of 'ytm_web_login_sheet.dart';

bool _shouldScanForBlockText(String currentUrl) {
  if (currentUrl.isEmpty) return false;
  if (currentUrl.contains('/challenge/') ||
      currentUrl.contains('signin/challenge') ||
      currentUrl.contains('/checkpoint/')) {
    return false;
  }
  return currentUrl.contains('accounts.google.com') ||
      currentUrl.contains('music.youtube.com') ||
      currentUrl.contains('youtube.com');
}

extension _YtmBlockRecoveryCard on _YtmWebLoginSheetState {
  // ---------- Google block detection & recovery ladder ----------

  String _uaFor(BrowserIdentity identity) {
    switch (identity) {
      case BrowserIdentity.chromeDesktop:
        return EmbeddedBrowserUa.chromeDesktop;
      case BrowserIdentity.safariMobile:
        return EmbeddedBrowserUa.safariMobile;
      case BrowserIdentity.desktop:
        return EmbeddedBrowserUa.desktop;
      case BrowserIdentity.mobile:
        // The "mobile" identity is the runtime-derived, coherent one — use the
        // resolved WebView UA rather than the stale packaged constant.
        return _resolvedUserAgent;
    }
  }

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
    if (_blockCooldownStopwatch.isRunning &&
        _blockCooldownStopwatch.elapsed < const Duration(seconds: 8)) {
      return false;
    }
    if (_lastBlockScanStopwatch.elapsed < const Duration(milliseconds: 2500)) {
      return false;
    }
    _lastBlockScanStopwatch.reset();
    return true;
  }

  /// Lightweight throttled JS evaluation: looks for Google's block-page
  /// phrases in the document title/body text (first 4 KB, lowercased).
  Future<bool> _scanPageForBlockText(InAppWebViewController controller) async {
    if (_disposed) return false;
    try {
      final currentUrl =
          (await controller.getUrl())?.toString().toLowerCase() ?? '';
      if (!_shouldScanForBlockText(currentUrl)) {
        return false;
      }

      final raw = await controller.evaluateJavascript(source: '''
(() => {
  try {
    var t = (document.title || '');
    var b = '';
    try { b = (document.body && (document.body.innerText || document.body.textContent)) || ''; } catch (e) {}
    var full = (t + '|' + b).slice(0, 8000).toLowerCase();

    // 2-Step Verification / CAPTCHA challenge is active authentication, NOT a block
    if (full.includes('2-step') ||
        full.includes('check your phone') ||
        full.includes('tap yes') ||
        full.includes('google sent a notification') ||
        full.includes('verification code') ||
        full.includes('security key') ||
        full.includes('authenticator') ||
        full.includes('enter the code') ||
        full.includes('type the text') ||
        full.includes('captcha')) {
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
          text.contains('enter the code') ||
          text.contains('type the text') ||
          text.contains('captcha')) {
        return false;
      }
      for (final phrase in _YtmWebLoginSheetState._blockPhrases) {
        if (text.contains(phrase)) return true;
      }
    } catch (e, st) {
      _handleWebViewError('_scanPageForBlockText failed', e, st);
    }
    return false;
  }

  /// Entry point when Google blocks the embedded browser.
  /// Shows the manual recovery card directly so the user is in control and
  /// never trapped in an automatic reload/wipe loop.
  void _handleGoogleBlock() {
    if (!mounted || widget.isBrowseMode) return;
    // Already recovering or showing recovery options.
    if (_blockStatus != null || _blockExhausted) return;

    debugPrint(
        '[YtmWebLogin] Google block detected — presenting recovery options.');
    _setStateSafe(() {
      _blockExhausted = true;
      _blockStatus = null;
    });
  }

  /// Pushes a user-agent (and optionally a content mode) onto the live WebView
  /// without discarding everything else it was configured with.
  ///
  /// `setSettings` replaces the whole settings object, so handing it a freshly
  /// constructed `InAppWebViewSettings(userAgent: …)` reset every other field to
  /// its default. That silently undid the configuration this sheet depends on to
  /// look like a real browser to Google — `requestedWithHeaderOriginAllowList`
  /// (the empty set that suppresses `X-Requested-With: com.pulsr.music`, the
  /// header Google uses to spot an embedded WebView and refuse sign-in),
  /// `thirdPartyCookiesEnabled`/`sharedCookiesEnabled` (without which the login
  /// never lands in the jar we read), `domStorageEnabled`, and
  /// `useShouldOverrideUrlLoading` (which the OAuth redirect chain runs through).
  /// So the block-recovery path, whose entire job is to look *less* like a bot,
  /// was making the next attempt look more like one.
  Future<void> _applyWebViewIdentity(
    InAppWebViewController? controller, {
    required String userAgent,
    UserPreferredContentMode? contentMode,
  }) async {
    final base = _settings?.copy() ??
        YtmWebLoginSheet.buildDefaultSettings(userAgent: userAgent);
    base.userAgent = userAgent;
    if (contentMode != null) base.preferredContentMode = contentMode;
    // Keep the field in step with the WebView, so the next call copies from what
    // is actually installed rather than from the initial value.
    _settings = base;
    await controller?.setSettings(settings: base);
  }

  /// Recovery card "Retry": manual full ladder — reset attempts, clean
  /// session, default identity selection, reload.
  Future<void> _manualRetryFromBlock() async {
    _blockRecovery.reset();
    _uaIdentityOverride = null;
    _hadSuccessfulYtLoad = false;
    _mismatchAutoNavCount = 0;
    if (mounted) {
      _setStateSafe(() {
        _blockExhausted = false;
        _blockStatus = 'Retrying sign-in with a clean session…';
      });
    }
    await _clearWebViewCookiesAndCache();
    await _applyWebViewIdentity(
      _webViewController,
      userAgent: mobileUserAgent,
      contentMode: UserPreferredContentMode.MOBILE,
    );
    _blockCooldownStopwatch
      ..reset()
      ..start();
    await _navigateTo(widget.isBrowseMode
        ? 'https://music.youtube.com'
        : _YtmWebLoginSheetState.googleSignInUrl);
    if (mounted && !_disposed) _setStateSafe(() => _blockStatus = null);
  }

  /// Recovery card identity toggle: switch UA mode and reload in place.
  Future<void> _switchIdentityManually(BrowserIdentity identity) async {
    _uaIdentityOverride = identity;
    final isDesktop = identity == BrowserIdentity.desktop ||
        identity == BrowserIdentity.chromeDesktop;
    if (mounted && !_disposed) {
      _setStateSafe(() {
        _blockExhausted = false;
        _blockStatus = 'Reloading with ${identity.name} browser identity…';
      });
    }
    await _clearWebViewCookiesAndCache();
    await _applyWebViewIdentity(
      _webViewController,
      userAgent: _uaFor(identity),
      contentMode: isDesktop
          ? UserPreferredContentMode.DESKTOP
          : UserPreferredContentMode.MOBILE,
    );
    _blockCooldownStopwatch
      ..reset()
      ..start();
    await _navigateTo(widget.isBrowseMode
        ? 'https://music.youtube.com'
        : _YtmWebLoginSheetState.googleSignInUrl);
    if (mounted && !_disposed) _setStateSafe(() => _blockStatus = null);
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
        case BrowserIdentity.chromeDesktop:
          return 'Chrome Desktop';
        case BrowserIdentity.mobile:
          return 'Chrome Mobile';
        case BrowserIdentity.safariMobile:
          return 'Safari Mobile';
        case BrowserIdentity.desktop:
          return 'Firefox Desktop';
      }
    }

    IconData identityIcon(BrowserIdentity id) {
      switch (id) {
        case BrowserIdentity.chromeDesktop:
          return Icons.desktop_windows_rounded;
        case BrowserIdentity.mobile:
          return Icons.smartphone_rounded;
        case BrowserIdentity.safariMobile:
          return Icons.phone_iphone_rounded;
        case BrowserIdentity.desktop:
          return Icons.laptop_windows_rounded;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s20, vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: p.error.withValues(alpha: 0.08),
              borderRadius: AppRadii.r14All,
              border: Border.all(color: p.error.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.gpp_bad_rounded, color: p.error, size: 22),
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(
                      child: Text(
                        context.l10n.browseGoogleBlocking,
                        style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.callout,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s10),
                Text(
                  context.l10n.browseGoogleBlockingBody,
                  style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.label,
                      height: 1.4),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${context.l10n.browseCurrentIdentity}: ${identityLabel(currentIdentity)}',
                  style: TextStyle(
                      color: p.textTertiary,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s14),
          FilledButton.icon(
            onPressed: () async {
              final ok = await YtmOAuthLoginSheet.show(context);
              if (ok == true && mounted) Navigator.of(context).pop(true);
            },
            icon: const Icon(Icons.tv_rounded, size: 18),
            label: Text(context.l10n.googleTvSignIn,
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FilledButton.icon(
            onPressed: _manualRetryFromBlock,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(context.l10n.retry,
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: p.surfaceContainerHigh,
              foregroundColor: p.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: () => _switchIdentityManually(otherIdentity),
            icon: Icon(identityIcon(otherIdentity), size: 18),
            label: Text(context.l10n.tryIdentity(identityLabel(otherIdentity)),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.hairline),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: () {
              _setStateSafe(() => _blockExhausted = false);
              _navigateTo('https://music.youtube.com');
            },
            icon: const Icon(Icons.music_note_rounded, size: 18),
            label: Text(context.l10n.openYtmWebDirect,
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.hairline),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: () => _showManualCookieDialog(context),
            icon: const Icon(Icons.vpn_key_rounded, size: 18),
            label: Text(context.l10n.importCookiesToken,
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.hairline),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
            ),
          ),
          const SizedBox(height: AppSpacing.s10),
          Text(
            context.l10n.googleBlockTip,
            textAlign: TextAlign.center,
            style:
                TextStyle(color: p.textTertiary, fontSize: AppFontSize.caption),
          ),
        ],
      ),
    );
  }
}
