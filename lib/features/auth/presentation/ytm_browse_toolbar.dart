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
            onPressed: _canGoBack
                ? () async {
                    await _webViewController?.goBack();
                    await _updateNavState();
                  }
                : null,
          ),
          IconButton(
            constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget),
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            tooltip: context.l10n.browseForward,
            onPressed: _canGoForward
                ? () async {
                    await _webViewController?.goForward();
                    await _updateNavState();
                  }
                : null,
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
            onPressed: () => _webViewController?.reload(),
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
              url: YtmLocale.homeUrl(),
              p: p,
            ),
          ],
        ),
      ),
    ];
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
