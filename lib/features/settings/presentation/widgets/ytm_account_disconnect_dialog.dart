// lib/features/settings/presentation/widgets/ytm_account_disconnect_dialog.dart
import 'package:flutter/material.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/ytm_account_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../auth/presentation/ytm_web_login_sheet.dart';

/// Account management / disconnect dialog for a connected YouTube Music account.
///
/// Both the settings screen and the online settings section open this. They used
/// to carry verbatim copies, which drifted apart the moment either was touched —
/// and neither disabled its button while [YtmAccountService.logout] ran, so a
/// double tap started a second logout over the first. That second pass races the
/// first one's WebView cookie deletion and native clear, and can re-import the
/// jar the first pass was still tearing down.
Future<void> showYtmAccountDisconnectDialog(BuildContext context) {
  final account = getIt<YtmAccountService>();
  final p = context.palette;
  return showDialog<void>(
    context: context,
    builder: (ctx) => _YtmAccountDisconnectDialog(
      account: account,
      // The snackbar has to outlive the dialog's own context.
      hostContext: context,
      surface: p.surfaceContainerHigh,
      titleColor: p.textPrimary,
      bodyColor: p.textSecondary,
      accent: p.accent,
      error: p.error,
    ),
  );
}

class _YtmAccountDisconnectDialog extends StatefulWidget {
  final YtmAccountService account;
  final BuildContext hostContext;
  final Color surface;
  final Color titleColor;
  final Color bodyColor;
  final Color accent;
  final Color error;

  const _YtmAccountDisconnectDialog({
    required this.account,
    required this.hostContext,
    required this.surface,
    required this.titleColor,
    required this.bodyColor,
    required this.accent,
    required this.error,
  });

  @override
  State<_YtmAccountDisconnectDialog> createState() =>
      _YtmAccountDisconnectDialogState();
}

class _YtmAccountDisconnectDialogState
    extends State<_YtmAccountDisconnectDialog> {
  bool _busy = false;

  Future<void> _disconnect() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.account.logout();
    } finally {
      if (mounted) Navigator.pop(context);
      if (widget.hostContext.mounted) {
        ScaffoldMessenger.of(widget.hostContext).showSnackBar(
          const SnackBar(content: Text('Disconnected from YouTube Music')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.surface,
      title: Text(context.l10n.ytmAccount,
          style: TextStyle(color: widget.titleColor)),
      content: Text(
        'Connected as: ${widget.account.accountName ?? "User"}\n\n'
        'Manage your YouTube Music account or disconnect from this device.',
        style: TextStyle(color: widget.bodyColor),
      ),
      actions: [
        TextButton.icon(
          onPressed: _busy
              ? null
              : () {
                  Navigator.pop(context);
                  YtmWebLoginSheet.show(
                    widget.hostContext,
                    isBrowseMode: true,
                  );
                },
          icon: Icon(Icons.language_rounded, size: 18, color: widget.accent),
          label: Text(context.l10n.openWebPlayer,
              style: TextStyle(color: widget.accent)),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.l10n.cancel,
              style: TextStyle(color: widget.bodyColor)),
        ),
        FilledButton(
          onPressed: _busy ? null : _disconnect,
          style: FilledButton.styleFrom(backgroundColor: widget.error),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.disconnect),
        ),
      ],
    );
  }
}
