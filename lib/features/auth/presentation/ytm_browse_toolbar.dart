part of 'ytm_web_login_sheet.dart';

extension _YtmBrowseToolbar on _YtmWebLoginSheetState {
  List<Widget> _buildBrowseToolbar(PulsrPalette p) {
    return [
      Row(
        children: [
          IconButton(
            constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            tooltip: context.l10n.browseBack,
            onPressed: _canGoBack ? _goBack : null,
          ),
          IconButton(
            constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget),
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            tooltip: context.l10n.browseForward,
            onPressed: _canGoForward ? _goForward : null,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
              decoration: BoxDecoration(
                color: p.surfaceContainerHigh,
                borderRadius: AppRadii.r10All,
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_rounded, size: 13, color: p.accent),
                  const SizedBox(width: AppSpacing.s6),
                  Expanded(
                    child: Text(
                      _currentUrl.replaceFirst('https://', ''),
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.label,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          IconButton(
            constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget),
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: context.l10n.browseRefresh,
            onPressed: _reloadPage,
          ),
          IconButton(
            constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget),
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: context.l10n.browseClose,
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
              horizontal: AppSpacing.xxs, vertical: AppSpacing.s2),
          children: [
            _navChip(
              label: context.l10n.browseHome,
              icon: Icons.home_rounded,
              url: YtmLocale.homeUrl(),
              p: p,
            ),
            const SizedBox(width: AppSpacing.s6),
            _navChip(
              label: context.l10n.browseExplore,
              icon: Icons.explore_rounded,
              url: YtmLocale.withLocaleParams(
                  'https://music.youtube.com/explore'),
              p: p,
            ),
            const SizedBox(width: AppSpacing.s6),
            _navChip(
              label: context.l10n.navLibrary,
              icon: Icons.library_music_rounded,
              url: YtmLocale.withLocaleParams(
                  'https://music.youtube.com/library'),
              p: p,
            ),
            const SizedBox(width: AppSpacing.s6),
            _navChip(
              label: context.l10n.likedMusic,
              icon: Icons.favorite_rounded,
              url: YtmLocale.withLocaleParams(
                  'https://music.youtube.com/playlist?list=LM'),
              p: p,
            ),
            const SizedBox(width: AppSpacing.s6),
            _navChip(
              label: context.l10n.newReleases,
              icon: Icons.fiber_new_rounded,
              url: YtmLocale.withLocaleParams(
                  'https://music.youtube.com/new_releases'),
              p: p,
            ),
            const SizedBox(width: AppSpacing.s6),
            _navChip(
              label: context.l10n.history,
              icon: Icons.history_rounded,
              url: YtmLocale.withLocaleParams(
                  'https://music.youtube.com/history'),
              p: p,
            ),
            const SizedBox(width: AppSpacing.s6),
            _navChip(
              label: context.l10n.browseYoutubeWeb,
              icon: Icons.video_library_rounded,
              url: 'https://www.youtube.com',
              p: p,
            ),
            const SizedBox(width: AppSpacing.s6),
            _navChip(
              label: context.l10n.browseEgyptMode,
              icon: Icons.public_rounded,
              // Explicit EG, not the device locale: this chip exists to force
              // the Egyptian catalog when the device (or VPN) is elsewhere.
              // It used to reuse homeUrl(), which made it a duplicate of Home
              // and a no-op for the case it is labelled for.
              url: 'https://music.youtube.com/?gl=EG&hl=en',
              p: p,
            ),
          ],
        ),
      ),
    ];
  }

  /// Whether [url] is the page currently shown.
  ///
  /// A raw string compare misses every chip: navigation appends `gl`/`hl`, so
  /// `_currentUrl` is `…/explore?gl=EG&hl=en` while the chip's label URL is
  /// `…/explore`. Compare host + path and require the chip's own query to be a
  /// subset of the current one.
  bool _isCurrentUrl(String url) {
    if (_currentUrl == url) return true;
    final current = Uri.tryParse(_currentUrl);
    final target = Uri.tryParse(url);
    if (current == null || target == null) return false;
    if (current.host != target.host || current.path != target.path) {
      return false;
    }
    for (final param in target.queryParameters.entries) {
      if (current.queryParameters[param.key] != param.value) return false;
    }
    return true;
  }

  Widget _navChip({
    required String label,
    required IconData icon,
    required String url,
    required PulsrPalette p,
  }) {
    final isCurrent = _isCurrentUrl(url);

    return InkWell(
      onTap: () => _navigateTo(url),
      borderRadius: AppRadii.r8All,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
        decoration: BoxDecoration(
          color: isCurrent ? p.accentContainer : p.surfaceContainerHigh,
          borderRadius: AppRadii.r8All,
          border: Border.all(
            color: isCurrent ? p.accent : p.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isCurrent ? p.accent : p.textSecondary),
            const SizedBox(width: AppSpacing.s6),
            Text(
              label,
              style: TextStyle(
                color: isCurrent ? p.accent : p.textPrimary,
                fontSize: AppFontSize.caption,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
