import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../theme/aura_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/pulsr_bottom_sheet.dart';
import '../widgets/pulsr_dialog.dart';
import 'breakpoints.dart';
import 'pulsr_layout_metrics.dart';
import 'responsive_values.dart';

/// Adaptive modal presenter that displays:
/// - Modal bottom sheet on [PulsrBreakpoint.compact] (portrait phone)
/// - Centered floating dialog on [PulsrBreakpoint.medium], [PulsrBreakpoint.expanded], [PulsrBreakpoint.large], or phone landscape
class PulsrResponsiveSheet {
  /// Opens an adaptive sheet/dialog based on the current screen breakpoint.
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget Function(BuildContext context) builder,
    Widget? title,
    String? titleText,
    bool isDismissible = true,
    bool enableDrag = true,
    bool isScrollControlled = true,
    double? maxWidth,
    double? maxHeight,
  }) {
    final breakpoint = context.breakpoint;
    final isDialogMode =
        !breakpoint.isCompact || PulsrLayoutMetrics.shouldUseDialogForSheet(context);

    if (!isDialogMode) {
      // Bottom Sheet on compact portrait screens
      return PulsrSheetHelper.showPulsrSheet<T>(
        context: context,
        isDismissible: isDismissible,
        enableDrag: enableDrag,
        isScrollControlled: isScrollControlled,
        builder: (ctx) => PulsrResponsiveSheetContainer(
          isDialogMode: false,
          title: title ?? (titleText != null ? Text(titleText) : null),
          child: builder(ctx),
        ),
      );
    } else {
      // Floating Centered Dialog on medium and larger screens, or phone landscape
      return PulsrDialogHelper.showCustomDialog<T>(
        context,
        barrierDismissible: isDismissible,
        builder: (ctx) {
          final double effectiveMaxWidth = maxWidth ??
              ctx.responsive.value(
                compact: 400.0,
                medium: 500.0,
                expanded: 560.0,
                large: 620.0,
              );

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: effectiveMaxWidth,
                maxHeight: maxHeight ?? MediaQuery.sizeOf(ctx).height * 0.85,
              ),
              child: Dialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.lg,
                ),
                child: PulsrResponsiveSheetContainer(
                  isDialogMode: true,
                  title: title ?? (titleText != null ? Text(titleText) : null),
                  child: builder(ctx),
                ),
              ),
            ),
          );
        },
      );
    }
  }
}

/// A container that formats sheet contents appropriately for bottom sheet or dialog mode.
class PulsrResponsiveSheetContainer extends StatelessWidget {
  final Widget child;
  final Widget? title;
  final bool isDialogMode;
  final bool showCloseButton;

  const PulsrResponsiveSheetContainer({
    super.key,
    required this.child,
    this.title,
    this.isDialogMode = false,
    this.showCloseButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (isDialogMode) {
      return GlassContainer(
        borderRadius: AppRadii.dialogRadius,
        opacity: p.isDark ? 0.90 : 0.95,
        blur: 16.0,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.55 : 0.22),
            blurRadius: 36,
            spreadRadius: 0,
            offset: const Offset(0, 14),
          ),
        ],
        child: ClipRRect(
          borderRadius: AppRadii.dialogRadius,
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null || showCloseButton)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        if (title != null)
                          Expanded(
                            child: DefaultTextStyle.merge(
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: AppFontSize.title,
                                fontWeight: FontWeight.w800,
                              ),
                              child: title!,
                            ),
                          ),
                        if (showCloseButton)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 22),
                            onPressed: () => Navigator.of(context).pop(),
                            constraints: const BoxConstraints(
                              minWidth: AppSpacing.minTouchTarget,
                              minHeight: AppSpacing.minTouchTarget,
                            ),
                          ),
                      ],
                    ),
                  ),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      );
    }

    // Bottom sheet mode
    return PulsrBottomSheetContainer(
      title: title,
      child: child,
    );
  }
}
