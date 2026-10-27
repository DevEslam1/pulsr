// lib/core/widgets/pulsr_adaptive_sheet.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../performance/gpu_budget.dart';
import '../responsive/breakpoints.dart';
import '../responsive/pulsr_responsive_tokens.dart';
import '../theme/aura_theme.dart';
import 'pulsr_bottom_sheet.dart';
import 'pulsr_dialog.dart';
import 'package:pulsr/core/constants/app_colors.dart';

/// {@category DesignSystem}
/// Viewport-aware adaptive modal container and launcher.
///
/// Automatically switches between:
/// - Compact bottom sheet on phone portrait (85% max height)
/// - Floating centered dialog on landscape phones (compact height < 500dp)
/// - Contained bottom sheet on tablet portrait (max width 600dp, 70% max height)
/// - Centered floating dialog on tablet landscape and large screens (max width 580dp)
class PulsrAdaptiveSheet extends StatelessWidget {
  final Widget child;
  final Widget? title;
  final String? titleText;
  final Widget? subtitle;
  final Widget? trailing;
  final bool showDragHandle;
  final bool isDialog;
  final double? maxWidth;
  final double? maxHeight;

  const PulsrAdaptiveSheet({
    super.key,
    required this.child,
    this.title,
    this.titleText,
    this.subtitle,
    this.trailing,
    this.showDragHandle = true,
    this.isDialog = false,
    this.maxWidth,
    this.maxHeight,
  });

  /// Opens an adaptive sheet or dialog according to current viewport metrics.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    Widget? title,
    String? titleText,
    Widget? subtitle,
    Widget? trailing,
    bool isDismissible = true,
    bool enableDrag = true,
    double? maxWidth,
    double? maxHeight,
  }) {
    final vp = PulsrViewport.of(context);
    final isDialogMode = vp.isShortHeight ||
        vp.isLandscape ||
        vp.sizeClass >= PulsrBreakpoint.expanded ||
        vp.deviceClass == PulsrDeviceClass.desktop;

    if (!isDialogMode) {
      // Bottom sheet on phone portrait and tablet portrait
      return PulsrSheetHelper.showPulsrSheet<T>(
        context: context,
        isDismissible: isDismissible,
        enableDrag: enableDrag,
        wrapWithContainer: false,
        builder: (ctx) => PulsrAdaptiveSheet(
          isDialog: false,
          title: title,
          titleText: titleText,
          subtitle: subtitle,
          trailing: trailing,
          maxWidth: maxWidth ?? (vp.isTablet ? 600.0 : double.infinity),
          maxHeight: maxHeight ?? (vp.height * (vp.isTablet ? 0.72 : 0.85)),
          child: builder(ctx),
        ),
      );
    } else {
      // Centered dialog mode on landscape phones, tablet landscape, and desktop
      final dialogWidth = maxWidth ??
          (vp.isShortHeight ? 500.0 : (vp.isTablet ? 580.0 : 420.0));
      final dialogHeight =
          maxHeight ?? (vp.height * (vp.isShortHeight ? 0.88 : 0.75));

      return PulsrDialogHelper.showCustomDialog<T>(
        context,
        barrierDismissible: isDismissible,
        builder: (ctx) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dialogWidth,
              maxHeight: dialogHeight,
            ),
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: EdgeInsets.symmetric(
                horizontal: vp.pagePadding,
                vertical: vp.isShortHeight ? AppSpacing.xs : AppSpacing.md,
              ),
              child: ClipRRect(
                borderRadius: AppRadii.dialogRadius,
                child: Material(
                  color: Colors.transparent,
                  child: PulsrAdaptiveSheet(
                    isDialog: true,
                    title: title,
                    titleText: titleText,
                    subtitle: subtitle,
                    trailing: trailing,
                    showDragHandle: false,
                    child: builder(ctx),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final vp = PulsrViewport.of(context);
    final headerTitle = title ?? (titleText != null ? Text(titleText!) : null);

    final baseSurfaceColor = GpuBudget.isGpuSaverActive
        ? p.surface
        : (p.isDark
            ? p.surface.withValues(alpha: 0.96)
            : p.surface.withValues(alpha: 0.98));

    final topBlendColor = Color.alphaBlend(
      p.accent.withValues(alpha: p.isDark ? 0.045 : 0.025),
      baseSurfaceColor,
    );

    final effectiveBorderRadius = isDialog
        ? AppRadii.dialogRadius
        : (vp.isTablet ? AppRadii.r28All : AppRadii.bottomSheetRadius);

    final Widget content = Stack(
      children: [
        // Specular top edge highlight
        PositionedDirectional(
          top: 0,
          start: 24,
          end: 24,
          height: 1.2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.specularAt(0.0),
                  AppColors.specularAt(p.isDark ? 0.38 : 0.65),
                  AppColors.specularAt(0.0),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDragHandle && !isDialog) ...[
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Container(
                  width: AppSpacing.s40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: (p.isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.22),
                    borderRadius: AppRadii.full,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (headerTitle != null) ...[
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: vp.isShortHeight ? AppSpacing.sm : AppSpacing.md,
                  vertical: vp.isShortHeight ? AppSpacing.xs : AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DefaultTextStyle.merge(
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.title,
                              fontWeight: FontWeight.w800,
                              letterSpacing: AppTracking.title,
                            ),
                            child: headerTitle,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: AppSpacing.s2),
                            DefaultTextStyle.merge(
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: AppFontSize.label,
                              ),
                              child: subtitle!,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) trailing!,
                    if (isDialog && trailing == null)
                      IconButton(
                        constraints: const BoxConstraints(
                            minWidth: AppSpacing.minTouchTarget,
                            minHeight: AppSpacing.minTouchTarget),
                        icon: Icon(Icons.close_rounded,
                            size: 20, color: p.textSecondary),
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).pop(),
                      ),
                  ],
                ),
              ),
              Divider(color: p.hairline, height: 1),
            ],
            Flexible(
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                // Give ListTile content a Material ancestor so its ink and tile
                // background paint above the sheet's decorated Container instead of
                // tripping Flutter's "invisible ListTile background" assertion.
                child: Material(type: MaterialType.transparency, child: child),
              ),
            ),
          ],
        ),
      ],
    );

    final sheet = RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topBlendColor, baseSurfaceColor],
            stops: const [0.0, 0.35],
          ),
          borderRadius: effectiveBorderRadius,
          border: Border.all(
            color: p.isDark ? Colors.white.withValues(alpha: 0.10) : p.hairline,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.scrimAt(p.isDark ? 0.45 : 0.14),
              blurRadius: 22,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: effectiveBorderRadius,
          child: content,
        ),
      ),
    );

    if (isDialog) return sheet;

    // Bottom-sheet mode applies both bounds and lifts the sheet above the IME.
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final availableHeight = math.max(
      AppSpacing.s56,
      media.size.height - keyboardInset - media.padding.top - AppSpacing.xs,
    );
    final effectiveMaxHeight = maxHeight == null
        ? availableHeight
        : math.min(maxHeight!, availableHeight);
    final insetDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedPadding(
        duration: insetDuration,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth ?? double.infinity,
            maxHeight: effectiveMaxHeight,
          ),
          child: sheet,
        ),
      ),
    );
  }
}
