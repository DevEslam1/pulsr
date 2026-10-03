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
    return _settings == null
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CircularProgressIndicator(),
            ),
          )
        : (!isBrowse && _blockExhausted)
            ? _buildBlockRecoveryCard(p)
            : (_webViewGone ||
                    _deadHandleHits >=
                        _YtmWebLoginSheetState._maxDeadHandleHits)
                ? _buildDeadWebViewCard(p)
                : ClipRRect(
                    child: InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri(_currentUrl),
                      ),
                      initialSettings: _settings,
                      initialUserScripts:
                          _YtmWebLoginSheetState._antiFingerPrintScripts,
                      gestureRecognizers: const <Factory<
                          OneSequenceGestureRecognizer>>{
                        Factory<OneSequenceGestureRecognizer>(
                          EagerGestureRecognizer.new,
                        ),
                      },
                      onWebViewCreated: (controller) {
                        _webViewController = controller;
                        final wasGone = _webViewGone;
                        _webViewGone = false;
                        // A fresh native instance: check immediately if already logged in,
                        // otherwise resume auth poll loop.
                        if (wasGone) {
                          _pollIntervalSeconds = 2;
                          _authPollAttempts = 0;
                        }
                        unawaited(_checkIfLoggedIn().then((loggedIn) {
                          if (!loggedIn && mounted && !_disposed && wasGone) {
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
                          await controller.loadUrl(
                              urlRequest: URLRequest(url: url));
                        }
                        return true;
                      },
                      shouldOverrideUrlLoading:
                          (controller, navigationAction) async {
                        final uri = navigationAction.request.url;
                        final policy = YtmWebLoginSheet.evaluateNavigation(uri);
                        if (policy == NavigationActionPolicy.CANCEL) {
                          if (uri != null) {
                            final urlLower = uri.toString().toLowerCase();
                            if (urlLower.startsWith('market://') ||
                                urlLower.startsWith('intent://') ||
                                urlLower.contains('play.google.com')) {
                              if (!widget.isBrowseMode &&
                                  !urlLower.contains('music')) {
                                unawaited(_navigateTo(
                                    _YtmWebLoginSheetState.googleSignInUrl));
                              } else {
                                unawaited(
                                    _navigateTo('https://music.youtube.com'));
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
                          final isGeoBlocked =
                              await _scanPageForGeoBlock(controller);
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
                        if (_YtmWebLoginSheetState._isCookieMismatchUrl(
                            urlStr)) {
                          if (_isLoggedIn) {
                            _isLoggedIn = false;
                            _detectedCookies = null;
                            if (mounted) _setStateSafe(() {});
                          }
                          _handleCookieMismatch();
                          return;
                        }

                        // Do not capture on Google Sign-In or EU consent screens before the user finishes
                        if (_YtmWebLoginSheetState._isAuthInProgressUrl(
                                urlStr) ||
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
                        if (mounted) {
                          _setStateSafe(() => _isLoading = false);
                        }
                      },
                      onUpdateVisitedHistory:
                          (controller, url, isReload) async {
                        await _updateNavState();
                        final urlStr = url?.toString() ?? '';
                        if (urlStr.isNotEmpty &&
                            !_YtmWebLoginSheetState._isCookieMismatchUrl(
                                urlStr) &&
                            !_YtmWebLoginSheetState._isAuthInProgressUrl(
                                urlStr)) {
                          await _checkIfLoggedIn(urlStr);
                        }
                      },
                    ),
                  );
  }
}
