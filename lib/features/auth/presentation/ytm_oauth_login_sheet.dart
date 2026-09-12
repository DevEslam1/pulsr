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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_oauth_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';

class YtmOAuthLoginSheet extends StatefulWidget {
  const YtmOAuthLoginSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
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
          _error = 'The code expired before it was approved. Try again.';
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
            ? 'Access was denied on the Google page.'
            : 'Google returned an error: ${e.code}';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not start the Google sign-in. Check your connection.';
        _busy = false;
      });
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label copied'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: Adaptive.sheetConstraints(context).maxWidth),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, 16, 24, bottomInset + 24),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sign in with Google TV',
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'No captcha — approve on another device',
                            style: TextStyle(
                                color: p.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_success)
                  _statusTile(p, Icons.check_circle_rounded, p.accent,
                      'Signed in. Loading your library…')
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: TextStyle(color: p.textPrimary, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _errorBody(PulsrPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusTile(p, Icons.error_outline_rounded, p.error, _error!),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _busy ? null : _start,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Try again',
              style: TextStyle(fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _codeBody(PulsrPalette p) {
    if (_busy || _code == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final code = _code!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '1. On your phone or computer, open this address:',
          style: TextStyle(color: p.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        _copyRow(p, code.verificationUrl, 'Address'),
        const SizedBox(height: 18),
        Text(
          '2. Enter this code:',
          style: TextStyle(color: p.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.hairline),
          ),
          child: Center(
            child: Text(
              code.userCode,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _copy(code.userCode, 'Code'),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy code',
              style: TextStyle(fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            foregroundColor: p.textPrimary,
            side: BorderSide(color: p.hairline),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Waiting for approval…',
              style: TextStyle(color: p.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _copyRow(PulsrPalette p, String value, String label) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                  color: p.textPrimary, fontSize: 13, height: 1.3),
            ),
          ),
          IconButton(
            onPressed: () => _copy(value, label),
            icon: Icon(Icons.copy_rounded, color: p.accent, size: 20),
            tooltip: 'Copy',
          ),
        ],
      ),
    );
  }
}
