part of 'ytm_web_login_sheet.dart';

extension _YtmWebLoginShell on _YtmWebLoginSheetState {
  Widget _buildLoadingBar(PulsrPalette p) {
    return ValueListenableBuilder<double>(
      valueListenable: _progressNotifier,
      builder: (context, progress, _) {
        if (!_isLoading && progress >= 1.0) {
          return const SizedBox.shrink();
        }
        return Semantics(
          label: context.l10n.pageLoadingProgress,
          value: _isLoading ? null : '${(progress * 100).round()}%',
          child: LinearProgressIndicator(
            value: _isLoading ? null : progress,
            backgroundColor: p.surfaceContainer,
            color: p.accent,
            minHeight: 2.5,
          ),
        );
      },
    );
  }

  Widget _buildWebViewBody(PulsrPalette p, bool isBrowse) {
    if (_settings == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CircularProgressIndicator(),
        ),
      );
    }

    // The recovery and dead-session cards are overlays, not replacements.
    // Unmounting the InAppWebView disposes its native controller, and every
    // recovery action (clear cookies, switch identity, reload) then runs
    // against a dead handle: the reload silently does nothing and the rebuilt
    // view reopens the page that caused the block. Keeping the view mounted
    // means those actions reach the real WebView; only a genuinely dead handle
    // needs a new instance, which _restartWebView() produces via the key.
    final showBlockCard = !isBrowse && _blockExhausted;
    final showDeadCard = !showBlockCard &&
        (_webViewGone ||
            _deadHandleHits >= _YtmWebLoginSheetState._maxDeadHandleHits);

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          child: InAppWebView(
            key: ValueKey<int>(_webViewInstance),
            initialUrlRequest: URLRequest(
              url: WebUri(_currentUrl),
            ),
            initialSettings: _settings,
            initialUserScripts: _YtmWebLoginSheetState._antiFingerPrintScripts,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                EagerGestureRecognizer.new,
              ),
            },
            onWebViewCreated: (controller) {
              _webViewController = controller;
              _webViewGone = false;
              _deadHandleHits = 0;
              // A fresh native instance is a fresh poll epoch. The
              // old code only reset the counters when it *thought*
              // the view was gone, so a rebuilt WebView could inherit
              // `dead`/`done` and never auto-detect the login.
              _pollState = _AuthPollState.idle;
              _pollIntervalSeconds = 2;
              _authPollAttempts = 0;
              unawaited(_checkIfLoggedIn().then((loggedIn) {
                if (!loggedIn && mounted && !_disposed) {
                  _scheduleNextAuthPoll();
                }
              }));
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
                // Popup navigation must obey the same allowlist as
                // top-level navigation; otherwise a page-triggered
                // window.open can escape the login sandbox.
                if (YtmWebLoginSheet.evaluateNavigation(url) ==
                    NavigationActionPolicy.CANCEL) {
                  return false;
                }
                await controller.loadUrl(urlRequest: URLRequest(url: url));
              }
              // We navigated the current WebView ourselves, so the
              // platform's pending popup transport must be cancelled.
              // Returning true tells the plugin the popup was handled
              // by a new window, which it never was — the transport
              // stayed in `windowWebViewMessages` forever and the
              // page waited on a window that would never open.
              return false;
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              final policy = YtmWebLoginSheet.evaluateNavigation(uri);
              if (policy == NavigationActionPolicy.CANCEL) {
                if (uri != null) {
                  final urlLower = uri.toString().toLowerCase();
                  if (urlLower.startsWith('market://') ||
                      urlLower.startsWith('intent://') ||
                      urlLower.contains('play.google.com')) {
                    if (!widget.isBrowseMode && !urlLower.contains('music')) {
                      unawaited(
                          _navigateTo(_YtmWebLoginSheetState.googleSignInUrl));
                    } else {
                      unawaited(_navigateTo('https://music.youtube.com'));
                    }
                  }
                }
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
            onLoadStart: (controller, url) async {
              if (mounted) {
                _setStateSafe(() => _isLoading = true);
              }
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
                    : _YtmWebLoginSheetState.googleSignInUrl;
                unawaited(_navigateTo(fallback));
                return;
              }
            },
            onProgressChanged: (controller, progress) {
              if (_disposed) return;
              // F-17: no setState — progress ticks only rebuild
              // the ValueListenableBuilder bar above.
              _progressNotifier.value = progress / 100;
            },
            onLoadStop: (controller, url) async {
              if (mounted) {
                _setStateSafe(() => _isLoading = false);
              }
              await _updateNavState();
              final urlStr = url?.toString() ?? '';
              final urlLower = urlStr.toLowerCase();

              // Fail-safe: if loaded page landed on Google Play, bounce back to YouTube Music
              if (urlLower.contains('play.google.com')) {
                debugPrint(
                    '[YtmWebLogin] onLoadStop landed on play.google.com, bouncing to music.youtube.com');
                final fallback = widget.isBrowseMode
                    ? 'https://music.youtube.com'
                    : _YtmWebLoginSheetState.googleSignInUrl;
                unawaited(_navigateTo(fallback));
                return;
              }

              final parsedUrl = Uri.tryParse(urlStr);
              final host = parsedUrl?.host ?? '';

              // Check for Geo-block ("not available in your area" / "not available in your country")
              if (urlLower.contains('music.youtube.com')) {
                final isGeoBlocked = await _scanPageForGeoBlock(controller);
                if (mounted && _isGeoBlocked != isGeoBlocked) {
                  _setStateSafe(() => _isGeoBlocked = isGeoBlocked);
                }
              } else {
                if (mounted && _isGeoBlocked) {
                  _setStateSafe(() => _isGeoBlocked = false);
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
              if (_YtmWebLoginSheetState._isCookieMismatchUrl(urlStr)) {
                if (_isLoggedIn) {
                  _isLoggedIn = false;
                  _detectedCookies = null;
                  if (mounted) _setStateSafe(() {});
                }
                _handleCookieMismatch();
                return;
              }

              // Do not capture on Google Sign-In or EU consent screens before the user finishes
              if (_YtmWebLoginSheetState._isAuthInProgressUrl(urlStr) ||
                  host == 'consent.youtube.com' ||
                  host == 'consent.google.com' ||
                  host.startsWith('consent.')) {
                return;
              }

              if (host.endsWith('youtube.com') || host == 'youtu.be') {
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
              if (mounted) {
                _setStateSafe(() => _isLoading = false);
              }
            },
            onUpdateVisitedHistory: (controller, url, isReload) async {
              await _updateNavState();
              final urlStr = url?.toString() ?? '';
              if (urlStr.isNotEmpty &&
                  !_YtmWebLoginSheetState._isCookieMismatchUrl(urlStr) &&
                  !_YtmWebLoginSheetState._isAuthInProgressUrl(urlStr)) {
                await _checkIfLoggedIn(urlStr);
              }
            },
          ),
        ),
        if (showBlockCard) _overlayCard(p, _buildBlockRecoveryCard(p)),
        if (showDeadCard) _overlayCard(p, _buildDeadWebViewCard(p)),
      ],
    );
  }

  /// Opaque card over the live WebView so the page behind it stays mounted.
  /// The tap handler makes the empty card area absorb input, otherwise taps
  /// would fall through to the page the card is covering.
  Widget _overlayCard(PulsrPalette p, Widget child) => Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: ColoredBox(color: p.surface, child: child),
        ),
      );
}
