// lib/core/widgets/pulsr_dialog.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/aura_theme.dart';
import '../constants/app_radii.dart';
import 'pulsr_modal_tracker.dart';

/// Uniform dialog entry-points used across the app.
///
/// Every dialog opened through [showPulsrDialog] is registered in
/// [PulsrModalTracker], which lets the app shell hide the mini player
/// dock while any dialog is on screen.
class PulsrDialogHelper {
  static Future<T?> showPulsrDialog<T>(
    BuildContext context, {
    Widget? title,
    Widget? content,
    List<Widget>? actions,
    bool useRootNavigator = true,
    bool barrierDismissible = true,
  }) {
    PulsrModalTracker.push();
    final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
    return navigator
        .push<T>(DialogRoute<T>(
          context: context,
          barrierDismissible: barrierDismissible,
          builder: (_) => PulsrDialog(
            title: title,
            content: content,
            actions: actions,
          ),
        ))
        .whenComplete(PulsrModalTracker.pop);
  }
}

/// A premium, consistent dialog container for the whole app.
///
/// Uses rounded corners, a soft surface tint and unified typography so all
/// confirm/settings dialogs share one look & feel.
class PulsrDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  const PulsrDialog({super.key, this.title, this.content, this.actions});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Dialog(
      backgroundColor: p.surface,
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.dialogRadius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.titleLarge,
                  child: title!,
                ),
              ),
            if (content != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    24, title != null ? 12 : 24, 24, 16),
                child: content!,
              ),
            if (actions != null && actions!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
