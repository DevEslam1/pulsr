part of 'ytm_web_login_sheet.dart';

extension _YtmLoginFormView on _YtmWebLoginSheetState {
  Widget _buildLoginHeader(PulsrPalette p) {
    // LOGIN HEADER
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          _isLoggedIn ? Icons.check_circle_rounded : Icons.cloud_sync_rounded,
          color: _isLoggedIn ? p.success : p.error,
          size: 22,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isLoggedIn
                    ? context.l10n.browseLoggedInSuccessfully
                    : context.l10n.browseSignInToYtm,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.body,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                _isLoggedIn
                    ? context.l10n.browseAccountConnectedDone
                    : context.l10n.browseConnectToSync,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _isLoggedIn ? p.success : p.textSecondary,
                  fontSize: AppFontSize.caption,
                  fontWeight: _isLoggedIn ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s6),
        // Action Controls
        if (_isLoggedIn) ...[
          FilledButton.icon(
            onPressed: _forceSaveAndFinish,
            icon: const Icon(
              Icons.check_rounded,
              size: 15,
              color: Colors.white,
            ),
            label: Text(
              context.l10n.doneAction,
              style: TextStyle(
                fontSize: AppFontSize.label,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: p.success,
              elevation: 2,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10,
                vertical: AppSpacing.s6,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.r8),
              ),
            ),
          ),
        ] else ...[
          FilledButton(
            onPressed: _forceSaveAndFinish,
            style: FilledButton.styleFrom(
              backgroundColor: p.surfaceContainerHigh,
              foregroundColor: p.textPrimary,
              elevation: 0,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10,
                vertical: AppSpacing.s6,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.r8),
                side: BorderSide(color: p.hairline),
              ),
            ),
            child: Text(
              context.l10n.doneAction,
              style: TextStyle(
                fontSize: AppFontSize.label,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: context.l10n.browseRefreshPage,
            padding: const EdgeInsets.all(AppSpacing.s6),
            constraints: const BoxConstraints(),
            onPressed: () => _webViewController?.reload(),
          ),
          const SizedBox(width: AppSpacing.s2),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 18),
            tooltip: context.l10n.browseMoreOptions,
            padding: const EdgeInsets.all(AppSpacing.s6),
            constraints: const BoxConstraints(),
            onSelected: (action) {
              switch (action) {
                case 'ytm_web':
                  _navigateTo('https://music.youtube.com');
                  break;
                case 'manual_cookies':
                  _showManualCookieDialog(context);
                  break;
                case 'clear_cache':
                  _clearCookiesAndReset();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'ytm_web',
                child: Row(
                  children: [
                    Icon(Icons.music_note_rounded,
                        size: 18, color: p.textSecondary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(context.l10n.openYtmWeb),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'manual_cookies',
                child: Row(
                  children: [
                    Icon(Icons.vpn_key_rounded,
                        size: 18, color: p.textSecondary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(context.l10n.importCookiesManual),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear_cache',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services_rounded,
                        size: 18, color: p.textSecondary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(context.l10n.clearCacheReset),
                  ],
                ),
              ),
            ],
          ),
        ],
        const SizedBox(width: AppSpacing.s2),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 18),
          tooltip: context.l10n.browseClose,
          padding: const EdgeInsets.all(AppSpacing.s6),
          constraints: const BoxConstraints(),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }

  Widget _buildLoggedInBanner(PulsrPalette p) {
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: p.success.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.r10),
        border: Border.all(color: p.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 18, color: p.success),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              context.l10n.loginDetected,
              style: TextStyle(
                fontSize: AppFontSize.label,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHintBanner(PulsrPalette p) {
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.r8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: p.warning),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              context.l10n.confirmAccount,
              style:
                  TextStyle(fontSize: AppFontSize.label, color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockStatusBanner(PulsrPalette p) {
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.r8),
        border: Border.all(color: p.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: AppSpacing.s14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              _blockStatus!,
              style: TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
