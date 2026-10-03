part of 'ytm_web_login_sheet.dart';

/// Ensures that any YouTube Music URL carries explicit gl/hl parameters
/// derived from the device locale (YtmLocale, EG/en fallback).
String _withGeoParams(String url) {
  if (!url.contains('music.youtube.com')) return url;
  return YtmLocale.withLocaleParams(url);
}

bool _shouldScanGeoBlockUrl(String url) {
  if (url.isEmpty) return false;
  final lower = url.toLowerCase();
  return lower.contains('music.youtube.com') || lower.contains('youtube.com');
}

extension _YtmGeoBlockBanner on _YtmWebLoginSheetState {
  Future<bool> _scanPageForGeoBlock(InAppWebViewController controller) async {
    try {
      final url = (await controller.getUrl())?.toString() ?? '';
      if (!_shouldScanGeoBlockUrl(url)) return false;

      final raw = await controller.evaluateJavascript(source: '''
(() => {
  try {
    var text = (document.body && (document.body.innerText || document.body.textContent)) || '';
    var lower = text.toLowerCase();
    return lower.includes('not available in your area') ||
           lower.includes('not available in your country') ||
           lower.includes("isn't available in your country") ||
           lower.includes("isn't available in your region") ||
           lower.includes('not available in your region') ||
           lower.includes('غير متوفر في منطقتك') ||
           lower.includes('غير متاح في منطقتك');
  } catch (e) { return false; }
})()''');
      return raw == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _forceEgRegionReload() async {
    if (mounted) _setStateSafe(() => _isGeoBlocked = false);
    try {
      final cookieManager = CookieManager.instance();
      await cookieManager.setCookie(
        url: WebUri('https://music.youtube.com'),
        name: 'PREF',
        value: YtmLocale.prefCookieValue(),
        domain: '.youtube.com',
        path: '/',
      );
    } catch (_) {}
    await _navigateTo(YtmLocale.homeUrl());
  }

  Widget _buildGeoBlockBanner(PulsrPalette p) {
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      padding: const EdgeInsets.all(AppSpacing.s10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.r10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public_off_rounded, color: p.warning, size: 17),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  context.l10n.ytmRestricted,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            context.l10n.ipOutsideYtm,
            style: TextStyle(
                fontSize: AppFontSize.caption, color: p.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _forceEgRegionReload,
                icon: const Text('🇪🇬',
                    style: TextStyle(fontSize: AppFontSize.label)),
                label: Text(context.l10n.forceEgypt,
                    style: TextStyle(fontSize: AppFontSize.caption)),
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s10, vertical: AppSpacing.xxs),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              OutlinedButton.icon(
                onPressed: () => _navigateTo('https://www.youtube.com'),
                icon: const Icon(Icons.video_library_rounded, size: 13),
                label: Text(context.l10n.openYtWeb,
                    style: TextStyle(fontSize: AppFontSize.caption)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s10, vertical: AppSpacing.xxs),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
