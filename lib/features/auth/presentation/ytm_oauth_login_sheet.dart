// lib/features/auth/presentation/ytm_oauth_login_sheet.dart
//
// Captcha-free YouTube Music sign-in using Google's OAuth 2.0 device flow.
//
// Google refuses embedded-WebView sign-in for many accounts (the "This browser
// or app may not be secure" interstitial / captcha). This sheet never loads a
// Google page in-app: it shows a short code that the user enters at
// google.com/device on their own browser, then polls for the token. That is the
// flow Google supports for TV / limited-input devices, so it cannot be flagged
// as an automated browser.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_oauth_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/pulsr_haptics.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_progress.dart';
import '../../../core/widgets/pulsr_toast.dart';

class YtmOAuthLoginSheet extends StatefulWidget {
  const YtmOAuthLoginSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<bool>(
      context: context,
      enableDrag: false,
      wrapWithContainer: false,
      builder: (_) => const YtmOAuthLoginSheet(),
    );
  }

  @override
  State<YtmOAuthLoginSheet> createState() => _YtmOAuthLoginSheetState();
}

class _YtmOAuthLoginSheetState extends State<YtmOAuthLoginSheet> {
  OAuthDeviceCode? _code;
  String? _error;
  bool _busy = true;
  bool _success = false;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = await YtmOAuthService.shared.requestDeviceCode();
      if (!mounted) return;
      setState(() {
        _code = code;
        _busy = false;
      });
      final ok = await YtmOAuthService.shared.pollForToken(
        code,
        isCancelled: () => _cancelled || !mounted,
      );
      if (!mounted || _cancelled) return;
      if (!ok) {
        setState(() {
          _error = context.l10n.browseOauthExpired;
          _busy = false;
        });
        return;
      }
      await getIt<YtmAccountService>().adoptOAuthSession();
      if (!mounted) return;
      setState(() {
        _success = true;
        _busy = false;
      });
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop(true);
    } on OAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'access_denied'
            ? context.l10n.browseOauthAccessDenied
            : '${context.l10n.browseOauthGoogleError}: ${e.code}';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.browseOauthStartFailed;
        _busy = false;
      });
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    await PulsrHaptics.lightImpact();
    if (mounted) {
      PulsrToast.show(
        context,
        message: '$label ${context.l10n.browseCopied}',
        isSuccess: true,
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _copyCodeAndOpenBrowser(String code, String url) async {
    await Clipboard.setData(ClipboardData(text: code));
    await PulsrHaptics.lightImpact();
    if (mounted) {
      PulsrToast.show(
        context,
        message: '${context.l10n.browseCode} ${context.l10n.browseCopied}',
        isSuccess: true,
        duration: const Duration(seconds: 2),
      );
    }
    try {
      final uri = WebUri(url);
      await InAppBrowser.openWithSystemBrowser(url: uri);
    } catch (e) {
      debugPrint('[YtmOAuth] Failed to open system browser: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: Adaptive.sheetConstraints(context).maxWidth),
        child: Container(
          padding: EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, bottomInset + 24),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
            border: Border.all(color: p.hairline),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.textTertiary.withValues(alpha: 0.3),
                      borderRadius: AppRadii.r2All,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s20),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.tv_rounded, color: p.accent, size: 24),
                    ),
                    const SizedBox(width: AppSpacing.s14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.signInGoogleTv,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.title,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            context.l10n.noCaptchaDesc,
                            style: TextStyle(
                                color: p.textSecondary,
                                fontSize: AppFontSize.label),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s20),
                if (_success)
                  _statusTile(p, Icons.check_circle_rounded, p.accent,
                      context.l10n.browseSignedInLoading)
                else if (_error != null)
                  _errorBody(p)
                else
                  _codeBody(p),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusTile(PulsrPalette p, IconData icon, Color color, String text) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: AppRadii.r14All,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: p.textPrimary, fontSize: AppFontSize.body)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBody(PulsrPalette p) {
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusTile(p, Icons.error_outline_rounded, p.error, _error!),
          const SizedBox(height: AppSpacing.s14),
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(context.l10n.tryAgain,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeBody(PulsrPalette p) {
    if (_busy || _code == null) {
      return Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s28),
          child: Center(
            child: PulsrProgressBar.circular(
              size: AppSpacing.s28,
              strokeWidth: 2,
              color: p.accent,
            ),
          ),
        ),
      );
    }
    final code = _code!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.oauthStep1,
          style: TextStyle(
              color: p.textSecondary, fontSize: AppFontSize.bodySmall),
        ),
        const SizedBox(height: AppSpacing.xs),
        _copyRow(p, code.verificationUrl, context.l10n.browseAddress),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: () =>
              _copyCodeAndOpenBrowser(code.userCode, code.verificationUrl),
          icon: const Icon(Icons.open_in_browser_rounded, size: 18),
          label: const Text('Copy code & open browser',
              style: TextStyle(fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
          ),
        ),
        const SizedBox(height: AppSpacing.s18),
        Text(
          context.l10n.oauthStep2,
          style: TextStyle(
              color: p.textSecondary, fontSize: AppFontSize.bodySmall),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s18),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: AppRadii.r14All,
            border: Border.all(color: p.hairline),
          ),
          child: Center(
            child: Text(
              code.userCode,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: AppFontSize.display,
                fontWeight: FontWeight.w800,
                letterSpacing: AppTracking.widest,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        OutlinedButton.icon(
          onPressed: () => _copy(code.userCode, context.l10n.browseCode),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text(context.l10n.copyCode,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            foregroundColor: p.textPrimary,
            side: BorderSide(color: p.hairline),
            minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
          ),
        ),
        const SizedBox(height: AppSpacing.s14),
        Semantics(
          liveRegion: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: AppSpacing.s14,
                height: 14,
                child: PulsrProgressBar.circular(
                  size: AppSpacing.s14,
                  strokeWidth: 2,
                  color: p.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.s10),
              Text(
                context.l10n.waitingApproval,
                style: TextStyle(
                    color: p.textTertiary, fontSize: AppFontSize.label),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _copyRow(PulsrPalette p, String value, String label) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.s14, AppSpacing.xxs, AppSpacing.xxs, AppSpacing.xxs),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.r14All,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.bodySmall,
                  height: 1.3),
            ),
          ),
          IconButton(
            constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget),
            onPressed: () => _copy(value, label),
            icon: Icon(Icons.copy_rounded, color: p.accent, size: 20),
            tooltip: context.l10n.browseCopy,
          ),
        ],
      ),
    );
  }
}
