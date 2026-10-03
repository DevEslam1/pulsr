part of 'ytm_web_login_sheet.dart';

extension _YtmCookieRecoveryView on _YtmWebLoginSheetState {
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
    if (_disposed || !mounted) return;
    _cookieMismatchDebounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _disposed || _webViewGone) return;
      _mismatchAutoNavCount++;
      final target = widget.isBrowseMode
          ? 'https://music.youtube.com'
          : _YtmWebLoginSheetState.googleSignInUrl;
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
        _setStateSafe(() {
          _blockExhausted = false;
          _blockStatus = null;
        });
      }
      final target = widget.isBrowseMode
          ? 'https://music.youtube.com'
          : _YtmWebLoginSheetState.googleSignInUrl;
      unawaited(_navigateTo(target));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.cookiesCleared),
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

  Widget _buildDeadWebViewCard(PulsrPalette p) {
    final sessionInterruptedTitle = context.l10n.webSessionInterruptedTitle;
    final sessionInterruptedDesc = context.l10n.webSessionInterruptedDesc;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_problem_rounded, color: p.warning, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              sessionInterruptedTitle,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: AppFontSize.title,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              sessionInterruptedDesc,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.caption,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () {
                _setStateSafe(() {
                  _deadHandleHits = 0;
                  _webViewGone = false;
                  _pollState = _AuthPollState.idle;
                  _pollIntervalSeconds = 2;
                  _authPollAttempts = 0;
                });
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.l10n.retry),
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: p.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showManualCookieDialog(BuildContext context) async {
    final p = context.palette;
    final l10n = context.l10n;
    final textController = TextEditingController();
    String? errorText;
    var busy = false;

    await PulsrDialogHelper.showCustomDialog<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => PulsrDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.15),
                  borderRadius: AppRadii.r10All,
                ),
                child: Icon(Icons.vpn_key_rounded, color: p.accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Text(
                  context.l10n.importCookiesManual,
                  style: TextStyle(
                      fontSize: AppFontSize.bodyLarge,
                      fontWeight: FontWeight.w800),
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
                  context.l10n.googleBlockHelp,
                  style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.label,
                      height: 1.4),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: textController,
                  maxLines: 4,
                  enabled: !busy,
                  style: TextStyle(
                      color: p.textPrimary,
                      fontSize: AppFontSize.label,
                      fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'SAPISID=...; __Secure-3PSID=...; SID=...',
                    hintStyle: TextStyle(
                        color: p.textTertiary, fontSize: AppFontSize.caption),
                    filled: true,
                    fillColor: p.surfaceContainer,
                    errorText: errorText,
                    border: OutlineInputBorder(
                      borderRadius: AppRadii.r10All,
                      borderSide: BorderSide(color: p.hairline),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: p.onAccent,
              ),
              onPressed: busy
                  ? null
                  : () async {
                      final input = textController.text.trim();
                      if (input.isEmpty) {
                        setDialogState(
                            () => errorText = l10n.browsePleaseEnterCookieText);
                        return;
                      }
                      final accountService = getIt<YtmAccountService>();
                      // Normalise first: a DevTools paste arrives with newlines, a
                      // `Cookie:` prefix and per-cookie attributes, and the shape
                      // check has to run on what will actually be sent. The old
                      // substring trim of `cookie:` left all of that in place.
                      final cookieStr =
                          YtmAccountService.normalizeCookieHeader(input);
                      if (!YtmAccountService.looksLikeSignedInCookies(
                          cookieStr)) {
                        setDialogState(
                            () => errorText = l10n.browseMissingSessionCookies);
                        return;
                      }
                      // Snapshot the jar we may have to put back: saveSession
                      // overwrites secure storage, pushes the new cookies into the
                      // native store and burns the current poToken, so a paste that
                      // turns out to be expired used to leave the app signed in to a
                      // dead session with no way back.
                      final previous = accountService.cookies;
                      setDialogState(() {
                        busy = true;
                        errorText = null;
                      });
                      final saved = await accountService.saveSession(cookieStr);
                      final verdict = saved
                          ? await accountService.validateSessionDetailed()
                          : SessionValidationResult.invalid;
                      if (verdict == SessionValidationResult.valid) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          _setStateSafe(() {
                            _isLoggedIn = true;
                            _detectedCookies = cookieStr;
                          });
                          Navigator.of(context).pop(true);
                        }
                        return;
                      }
                      if (verdict == SessionValidationResult.invalid) {
                        // Roll back rather than keep a jar YouTube rejected.
                        if (previous != null && previous.isNotEmpty) {
                          await accountService.saveSession(previous);
                        } else {
                          await accountService.logout();
                        }
                      }
                      if (!ctx.mounted) return;
                      setDialogState(() {
                        busy = false;
                        errorText = verdict == SessionValidationResult.invalid
                            ? l10n.browseCookiesRejected
                            // `unknown` is a network failure or an IP block, not a
                            // verdict on the cookies: reporting "invalid" here sent
                            // people off to re-copy a jar that was fine.
                            : l10n.browseCookieVerifyOffline;
                      });
                    },
              child: Text(busy ? l10n.browseChecking : l10n.browseConnect),
            ),
          ],
        ),
      ),
    );
    // Disposed once the dialog is gone rather than never: the sheet outlives it,
    // so every manual-import attempt used to leak its controller.
    textController.dispose();
  }
}
