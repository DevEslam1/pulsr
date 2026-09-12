// lib/core/widgets/pulsr_dialog.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_radii.dart';
import '../theme/aura_theme.dart';
import 'glass_container.dart';
import 'pulsr_modal_tracker.dart';

/// Uniform dialog entry-points used across the entire app.
///
/// Every dialog opened through [PulsrDialogHelper] is guaranteed to use the
/// root navigator and register in [PulsrModalTracker], which cleanly slides
/// and hides the mini player dock while the dialog is visible.
class PulsrDialogHelper {
  /// General custom dialog builder with Apple Music frosted styling.
  static Future<T?> showPulsrDialog<T>(
    BuildContext context, {
    Widget? icon,
    Widget? title,
    Widget? content,
    List<Widget>? actions,
    bool useRootNavigator = true,
    bool barrierDismissible = true,
  }) {
    return showCustomDialog<T>(
      context,
      useRootNavigator: useRootNavigator,
      barrierDismissible: barrierDismissible,
      builder: (_) => PulsrDialog(
        icon: icon,
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }

  /// Shows a custom dialog with modal tracking to guarantee the mini player stays hidden.
  static Future<T?> showCustomDialog<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool useRootNavigator = true,
    bool barrierDismissible = true,
  }) {
    PulsrModalTracker.push();
    final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
    return navigator
        .push<T>(DialogRoute<T>(
          context: context,
          barrierDismissible: barrierDismissible,
          barrierColor: Colors.black.withValues(alpha: 0.55),
          builder: builder,
        ))
        .whenComplete(PulsrModalTracker.pop);
  }

  /// Premium confirmation dialog (e.g. Delete, Reset, Confirm Action).
  static Future<bool?> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    IconData? icon = Icons.help_outline_rounded,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
  }) {
    return showPulsrDialog<bool>(
      context,
      icon: icon != null
          ? Icon(
              icon,
              size: 28,
              color: isDestructive
                  ? Theme.of(context).colorScheme.error
                  : context.palette.accent,
            )
          : null,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: Text(
        message,
        style: TextStyle(
          color: context.palette.textSecondary,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: context.palette.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: Text(cancelLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        FilledButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context, rootNavigator: true).pop(true);
          },
          style: FilledButton.styleFrom(
            backgroundColor: isDestructive
                ? context.palette.error
                : context.palette.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            confirmLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  /// Premium text input dialog (e.g. Playlist Name, Radio Station, Preset).
  static Future<String?> showInputDialog(
    BuildContext context, {
    required String title,
    String? message,
    String? initialText,
    String? hintText,
    IconData? icon = Icons.edit_rounded,
    String confirmLabel = 'Save',
    String cancelLabel = 'Cancel',
    TextInputType keyboardType = TextInputType.text,
  }) {
    return showCustomDialog<String>(
      context,
      builder: (_) => _PulsrInputDialog(
        title: title,
        message: message,
        initialText: initialText,
        hintText: hintText,
        icon: icon,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        keyboardType: keyboardType,
      ),
    );
  }
}

class _PulsrInputDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String? initialText;
  final String? hintText;
  final IconData? icon;
  final String confirmLabel;
  final String cancelLabel;
  final TextInputType keyboardType;

  const _PulsrInputDialog({
    required this.title,
    this.message,
    this.initialText,
    this.hintText,
    this.icon,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.keyboardType,
  });

  @override
  State<_PulsrInputDialog> createState() => _PulsrInputDialogState();
}

class _PulsrInputDialogState extends State<_PulsrInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      HapticFeedback.lightImpact();
      Navigator.of(context, rootNavigator: true).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulsrDialog(
      icon: widget.icon != null
          ? Icon(widget.icon, size: 28, color: p.accent)
          : null,
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(
                widget.message!,
                style: TextStyle(color: p.textSecondary, fontSize: 13.5),
              ),
              const SizedBox(height: 14),
            ],
            Container(
              decoration: BoxDecoration(
                color: p.surfaceContainerHigh.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.hairline),
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: widget.keyboardType,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(color: p.textTertiary, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
          style: TextButton.styleFrom(
            foregroundColor: p.textSecondary,
          ),
          child: Text(widget.cancelLabel,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            widget.confirmLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// A premium, consistent frosted-glass dialog container for the whole app.
///
/// Features rounded corners (24px), subtle hairline border, soft glow shadow,
/// and frosted translucent backdrop.
class PulsrDialog extends StatelessWidget {
  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  const PulsrDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassContainer(
          borderRadius: AppRadii.dialogRadius,
          opacity: p.isDark ? 0.88 : 0.94,
          blur: 14.0,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: p.isDark ? 0.50 : 0.18),
              blurRadius: 32,
              spreadRadius: 0,
              offset: const Offset(0, 12),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Optional top icon badge
              if (icon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: p.accentContainer.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: p.accent.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: icon,
                    ),
                  ),
                ),
              ],

              // Dialog Title
              if (title != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    icon != null ? 14 : 24,
                    24,
                    0,
                  ),
                  child: DefaultTextStyle.merge(
                    textAlign: icon != null ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                    child: title!,
                  ),
                ),

              // Dialog Content
              if (content != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    title != null ? 14 : 24,
                    24,
                    16,
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 14,
                      height: 1.45,
                    ),
                    child: content!,
                  ),
                ),

              // Action Buttons
              if (actions != null && actions!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions!
                        .map((w) => Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: w,
                            ))
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
