// lib/core/widgets/pulsr_dialog.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../constants/app_radii.dart';
import '../motion/pulsr_motion.dart';
import '../responsive/responsive_values.dart';
import '../theme/aura_theme.dart';
import '../utils/l10n_extensions.dart';
import 'glass_container.dart';
import 'pulsr_modal_tracker.dart';

/// {@category DesignSystem}
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
    // The root PulsrModalObserver (installed on the root navigator) already
    // counts DialogRoutes via didPush/didPop. Only track manually for a
    // non-root navigator it can't observe, otherwise the dialog is counted
    // twice.
    final trackManually = !useRootNavigator;
    if (trackManually) PulsrModalTracker.push();
    final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
    final future = navigator.push<T>(
      DialogRoute<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        barrierColor: AppColors.scrimAt(0.58),
        builder: builder,
      ),
    );
    return trackManually ? future.whenComplete(PulsrModalTracker.pop) : future;
  }

  /// Premium confirmation dialog (e.g. Delete, Reset, Confirm Action).
  static Future<bool?> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    IconData? icon = Icons.help_outline_rounded,
    String? confirmLabel,
    String? cancelLabel,
    bool isDestructive = false,
  }) {
    final confirm = confirmLabel ?? context.l10n.confirm;
    final cancel = cancelLabel ?? context.l10n.cancel;
    final p = context.palette;
    final activeTone =
        isDestructive ? Theme.of(context).colorScheme.error : p.accent;

    return showPulsrDialog<bool>(
      context,
      icon: icon != null
          ? Icon(
              icon,
              size: 26,
              color: activeTone,
            )
          : null,
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: AppFontSize.title,
        ),
      ),
      content: Text(
        message,
        style: TextStyle(
          color: p.textSecondary,
          fontSize: AppFontSize.body,
          height: 1.45,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: p.textSecondary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r12All,
            ),
          ),
          child: Text(
            cancel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton(
          onPressed: () {
            if (isDestructive) {
              if (confirm.toLowerCase().contains('delete') ||
                  title.toLowerCase().contains('delete')) {
                HapticFeedback.heavyImpact();
              } else {
                HapticFeedback.mediumImpact();
              }
            } else {
              HapticFeedback.selectionClick();
            }
            Navigator.of(context, rootNavigator: true).pop(true);
          },
          style: FilledButton.styleFrom(
            backgroundColor: isDestructive ? p.error : p.accent,
            foregroundColor: isDestructive ? Colors.white : p.onAccent,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s20,
              vertical: AppSpacing.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r12All,
            ),
          ),
          child: Text(
            confirm,
            style: const TextStyle(fontWeight: FontWeight.w800),
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
    String? confirmLabel,
    String? cancelLabel,
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
        confirmLabel: confirmLabel ?? context.l10n.save,
        cancelLabel: cancelLabel ?? context.l10n.cancel,
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
  late final FocusNode _focusNode;
  bool _isFocused = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode()
      ..addListener(() {
        if (mounted && _isFocused != _focusNode.hasFocus) {
          setState(() => _isFocused = _focusNode.hasFocus);
        }
      });
  }

  @override
  void dispose() {
    _focusNode.dispose();
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
          ? Icon(widget.icon, size: 26, color: p.accent)
          : null,
      title: Text(
        widget.title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: AppFontSize.title,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(
                widget.message!,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.bodySmall,
                ),
              ),
              const SizedBox(height: AppSpacing.s14),
            ],
            AnimatedContainer(
              duration: context.motionMs(180),
              decoration: BoxDecoration(
                color: p.surfaceContainer.withValues(
                  alpha: p.isDark ? 0.72 : 0.90,
                ),
                borderRadius: AppRadii.r14All,
                border: Border.all(
                  color: _isFocused
                      ? p.accent
                      : (p.isDark ? AppColors.specularAt(0.14) : p.hairline),
                  width: _isFocused ? 1.4 : 1.0,
                ),
                boxShadow: _isFocused
                    ? [
                        BoxShadow(
                          color: p.accent.withValues(alpha: 0.16),
                          blurRadius: 12,
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                keyboardType: widget.keyboardType,
                cursorColor: p.accent,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.callout,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    color: p.textTertiary,
                    fontSize: AppFontSize.body,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s14,
                    vertical: AppSpacing.sm + 2,
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
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r12All,
            ),
          ),
          child: Text(
            widget.cancelLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s20,
              vertical: AppSpacing.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r12All,
            ),
          ),
          child: Text(
            widget.confirmLabel,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// A premium, consistent frosted-glass dialog container for the whole app.
///
/// Features rounded corners (24px), subtle specular border, soft glow shadow,
/// and frosted translucent backdrop.
class PulsrDialog extends StatelessWidget {
  final dynamic icon;
  final dynamic title;
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

    Widget? iconWidget;
    Color badgeColor = p.accent;
    if (icon is Icon) {
      final ic = icon as Icon;
      iconWidget = ic;
      if (ic.color != null) badgeColor = ic.color!;
    } else if (icon is Widget) {
      iconWidget = icon as Widget;
    } else if (icon is IconData) {
      iconWidget = Icon(icon as IconData, size: 26, color: p.accent);
    }

    Widget? titleWidget;
    if (title is Widget) {
      titleWidget = title as Widget;
    } else if (title is String) {
      titleWidget = Text(title as String);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: context.responsive.value(
            compact: 400.0,
            medium: 480.0,
            expanded: 540.0,
          ),
        ),
        child: GlassContainer.fromPreset(
          preset: GlassPreset.dialog,
          specularHighlight: true,
          borderRadius: AppRadii.dialogRadius,
          color: p.surfaceContainerHigh,
          border: Border.all(
            color: p.isDark ? AppColors.specularAt(0.16) : p.hairline,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.12),
              blurRadius: 28,
              spreadRadius: 0,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: badgeColor.withValues(alpha: p.isDark ? 0.12 : 0.06),
              blurRadius: 20,
              spreadRadius: -4,
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Optional top icon badge with studio halo
              if (iconWidget != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.lg),
                  child: Center(
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            badgeColor.withValues(alpha: 0.22),
                            badgeColor.withValues(alpha: 0.08),
                          ],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.38),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: badgeColor.withValues(alpha: 0.20),
                            blurRadius: 14,
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: iconWidget,
                    ),
                  ),
                ),
              ],

              // Dialog Title
              if (titleWidget != null)
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.lg,
                    iconWidget != null ? 14 : 24,
                    AppSpacing.lg,
                    0,
                  ),
                  child: DefaultTextStyle.merge(
                    textAlign:
                        iconWidget != null ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: AppFontSize.title,
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.title,
                    ),
                    child: titleWidget,
                  ),
                ),

              // Dialog Content
              if (content != null)
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.lg,
                      title != null ? 12 : 24,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: DefaultTextStyle.merge(
                      textAlign: iconWidget != null && titleWidget != null
                          ? TextAlign.center
                          : TextAlign.start,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.body,
                        height: 1.45,
                      ),
                      child: content!,
                    ),
                  ),
                ),

              // Action Buttons
              if (actions != null && actions!.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.s20,
                    AppSpacing.xs,
                    AppSpacing.s20,
                    AppSpacing.s18,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: actions!,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
