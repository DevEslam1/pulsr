// lib/core/widgets/pulsr_adaptive_sheet.dart
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_colors.dart';

import '../constants/app_blur.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../motion/pulsr_motion.dart';
import '../responsive/pulsr_layout_metrics.dart';
import '../responsive/pulsr_responsive_tokens.dart';
import '../theme/aura_theme.dart';
import '../utils/adaptive.dart';
import '../utils/l10n_extensions.dart';
import 'pulsr_bottom_sheet.dart';
import 'pulsr_dialog.dart';

import '../utils/pulsr_haptics.dart';

/// {@category DesignSystem}
/// Viewport-aware adaptive modal container and launcher.
///
/// Automatically switches between:
/// - Compact bottom sheet on phone portrait (88% max height)
/// - Floating centered dialog on short landscape phones
/// - Contained bottom sheet on medium tablet portrait
/// - Centered floating dialog on expanded/large windows (>=840dp) and desktop,
///   with the shared [PulsrSheetMetrics] width for each tier
class PulsrAdaptiveSheet extends StatelessWidget {
  final Widget child;
  final Widget? leading;
  final Widget? title;
  final String? titleText;
  final Widget? subtitle;
  final Widget? trailing;
  final bool showDragHandle;
  final bool isDialog;
  final bool showDialogCloseButton;
  final double? maxWidth;
  final double? maxHeight;

  const PulsrAdaptiveSheet({
    super.key,
    required this.child,
    this.leading,
    this.title,
    this.titleText,
    this.subtitle,
    this.trailing,
    this.showDragHandle = true,
    this.isDialog = false,
    this.showDialogCloseButton = true,
    this.maxWidth,
    this.maxHeight,
  });

  /// Opens an adaptive sheet or dialog according to current viewport metrics.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    Widget? leading,
    Widget? title,
    String? titleText,
    Widget? subtitle,
    Widget? trailing,
    bool isDismissible = true,
    bool enableDrag = true,
    bool useRootNavigator = true,
    bool showDialogCloseButton = true,
    double? maxWidth,
    double? maxHeight,
  }) {
    final vp = PulsrViewport.of(context);
    final isDialogMode = PulsrSheetMetrics.shouldPresentAsDialog(context);

    if (!isDialogMode) {
      // Bottom sheet on phone portrait and tablet portrait
      return PulsrSheetHelper.showPulsrSheet<T>(
        context: context,
        useRootNavigator: useRootNavigator,
        isDismissible: isDismissible,
        enableDrag: enableDrag,
        wrapWithContainer: false,
        builder: (ctx) => PulsrAdaptiveSheet(
          isDialog: false,
          leading: leading,
          title: title,
          titleText: titleText,
          subtitle: subtitle,
          trailing: trailing,
          showDialogCloseButton: showDialogCloseButton,
          maxWidth: maxWidth ?? PulsrSheetMetrics.sheetMaxWidth(context),
          maxHeight: maxHeight ?? Adaptive.sheetMaxHeight(context),
          child: builder(ctx),
        ),
      );
    } else {
      // Centered dialog mode on landscape phones, tablet landscape, and desktop
      final dialogWidth = maxWidth ?? PulsrSheetMetrics.dialogMaxWidth(context);
      final dialogHeight =
          maxHeight ?? PulsrSheetMetrics.dialogMaxHeight(context);

      return PulsrDialogHelper.showCustomDialog<T>(
        context,
        useRootNavigator: useRootNavigator,
        barrierDismissible: isDismissible,
        builder: (ctx) {
          final media = MediaQuery.of(ctx);
          final keyboardInset = media.viewInsets.bottom;
          final availableH = math.max(
            AppSpacing.s56,
            media.size.height -
                keyboardInset -
                media.padding.vertical -
                (vp.isShortHeight ? AppSpacing.sm : AppSpacing.lg),
          );
          final effectiveMaxH = math.min(dialogHeight, availableH);

          return AnimatedPadding(
            duration: ctx.motion(PulsrMotion.state),
            curve: ctx.motionCurve(PulsrMotion.enter),
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dialogWidth,
                  maxHeight: effectiveMaxH,
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
                        leading: leading,
                        title: title,
                        titleText: titleText,
                        subtitle: subtitle,
                        trailing: trailing,
                        showDragHandle: false,
                        showDialogCloseButton: showDialogCloseButton,
                        child: builder(ctx),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
  }

  Widget _buildHeader(
    BuildContext context,
    PulsrPalette p,
    PulsrViewport vp,
    Widget? headerTitle, {
    required bool effectiveIsDialog,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: vp.isShortHeight ? AppSpacing.sm : AppSpacing.s20,
            vertical: headerTitle == null
                ? 0
                : (vp.isShortHeight ? AppSpacing.xs : AppSpacing.sm),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: headerTitle == null
                    ? const SizedBox.shrink()
                    : Column(
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
                                fontWeight: FontWeight.w500,
                              ),
                              child: subtitle!,
                            ),
                          ],
                        ],
                      ),
              ),
              if (trailing != null) trailing!,
              if (effectiveIsDialog && trailing == null)
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: p.textSecondary,
                  ),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () {
                    PulsrHaptics.lightImpact();
                    Navigator.of(context).maybePop();
                  },
                ),
            ],
          ),
        ),
        if (headerTitle != null) Divider(color: p.hairline, height: 1),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final vp = PulsrViewport.of(context);
    final headerTitle = title ?? (titleText != null ? Text(titleText!) : null);

    // Avoid double-wrapping if nested inside another PulsrSheetScope.
    final parentScope = PulsrSheetScope.maybeOf(context);
    if (parentScope != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headerTitle != null)
            _buildHeader(
              context,
              p,
              vp,
              headerTitle,
              effectiveIsDialog: parentScope.isDialog || isDialog,
            ),
          Flexible(
            child: Material(
              type: MaterialType.transparency,
              child: child,
            ),
          ),
        ],
      );
    }

    final isHighContrast =
        (MediaQuery.maybeOf(context)?.highContrast ?? false) ||
            p.isHighContrast;

    final rawSurface = p.isDark ? p.surface : p.surfaceElevated;
    final baseSurfaceColor = (!AppBlur.canBlur(context) || isHighContrast)
        ? rawSurface
        : rawSurface.withValues(alpha: p.isDark ? 0.96 : 0.98);

    final topBlendColor = isHighContrast
        ? baseSurfaceColor
        : Color.alphaBlend(
            p.accent.withValues(alpha: p.isDark ? 0.045 : 0.025),
            baseSurfaceColor,
          );

    final effectiveBorderRadius = isDialog
        ? AppRadii.dialogRadius
        : (vp.isTablet ? AppRadii.r28All : AppRadii.bottomSheetRadius);

    final Widget content = PulsrSheetScope(
      isDialog: isDialog,
      child: Stack(
        children: [
          // Specular top edge highlight
          if (!isHighContrast && p.specularScale > 0)
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
                      AppColors.specularAt(
                        (p.isDark ? 0.36 : 0.62) * p.specularScale,
                      ),
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
                const SizedBox(height: AppSpacing.s10),
                Center(
                  child: Semantics(
                    label: context.l10n.sheetDragHandle,
                    hint: context.l10n.sheetDragDownToDismiss,
                    child: Container(
                      width: AppSpacing.s40,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: (p.isDark ? Colors.white : Colors.black)
                            .withValues(alpha: isHighContrast ? 0.58 : 0.26),
                        borderRadius: AppRadii.full,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
              ],
              if (headerTitle != null ||
                  (isDialog && showDialogCloseButton && trailing == null))
                _buildHeader(
                  context,
                  p,
                  vp,
                  headerTitle,
                  effectiveIsDialog: isDialog,
                ),
              Flexible(
                child: SafeArea(
                  top: false,
                  left: false,
                  right: false,
                  bottom: !isDialog,
                  // Give ListTile content a Material ancestor so its ink and tile
                  // background paint above the sheet's decorated Container instead of
                  // tripping Flutter's "invisible ListTile background" assertion.
                  child: Material(
                    type: MaterialType.transparency,
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final sheet = RepaintBoundary(
      child: Container(
        margin: (!isDialog && vp.isTablet)
            ? const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.s20,
                0,
                AppSpacing.s20,
                AppSpacing.md,
              )
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topBlendColor, baseSurfaceColor],
            stops: const [0.0, 0.35],
          ),
          borderRadius: effectiveBorderRadius,
          border: Border.all(
            color: isHighContrast
                ? p.borderStrong
                : (p.isDark
                    ? AppColors.specularAt(p.isAmoled ? 0.16 : 0.11)
                    : p.hairline),
            width: isHighContrast ? 1.5 : 1.0,
          ),
          boxShadow: PulsrElevation.level3(context),
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
    final insetDuration = context.motion(PulsrMotion.state);

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedPadding(
        duration: insetDuration,
        curve: context.motionCurve(PulsrMotion.enter),
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
