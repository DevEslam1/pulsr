// lib/core/widgets/pulsr_bottom_sheet.dart
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_blur.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_strokes.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../constants/app_radii.dart';
import '../motion/pulsr_motion.dart';
import '../responsive/pulsr_layout_metrics.dart';
import '../theme/aura_theme.dart';
import '../utils/adaptive.dart';
import '../utils/l10n_extensions.dart';
import 'pulsr_dialog.dart';
import 'pulsr_modal_tracker.dart';

import '../utils/pulsr_haptics.dart';

/// {@category DesignSystem}
/// Shared scope marker so nested sheet containers ([PulsrBottomSheetContainer]
/// and `PulsrAdaptiveSheet`) never render duplicate outer chrome, borders, or
/// drag handles when composed together.
class PulsrSheetScope extends InheritedWidget {
  final bool isDialog;

  const PulsrSheetScope({
    super.key,
    required this.isDialog,
    required super.child,
  });

  static PulsrSheetScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PulsrSheetScope>();

  @override
  bool updateShouldNotify(covariant PulsrSheetScope oldWidget) =>
      oldWidget.isDialog != isDialog;
}

/// {@category DesignSystem}
/// Centralized bottom sheet entry-points and container for the entire app.
///
/// Features:
/// - Guaranteed integration with [PulsrModalTracker] to hide/restore the mini player dock smoothly
/// - Native Apple/Google sheet drag handle pill with top specular refraction hairline
/// - Responsive width clamping on tablet & desktop (`maxWidth: 620`)
/// - 120fps-optimized surface elevation and hairline border
/// - Edge-to-edge safe area handling
/// - Centered dialog on expanded tablet windows (>=840dp), desktops and short
///   landscape viewports, using the same policy as [PulsrAdaptiveSheet]
/// - Full-bleed builders (`wrapWithContainer: false`) keep their own surface
///   and stay bottom sheets at every size
class PulsrSheetHelper {
  /// Opens a unified modal bottom sheet with automatic mini player dock tracking.
  static Future<T?> showPulsrSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    bool useRootNavigator = true,
    bool isDismissible = true,
    bool enableDrag = true,
    Color? barrierColor,
    bool showDragHandle = true,
    bool wrapWithContainer = true,
    bool showDialogCloseButton = true,
  }) {
    // Only builder-owned chrome is promoted to a centered dialog. A builder
    // that set `wrapWithContainer: false` owns its full sheet surface, drag
    // handle and safe area, so re-wrapping it as a dialog would double the
    // chrome; those stay bottom sheets on every size.
    if (wrapWithContainer && PulsrSheetMetrics.shouldPresentAsDialog(context)) {
      final effectiveBarrier = barrierColor ??
          AppColors.scrimAt(context.palette.isDark ? 0.62 : 0.40);
      return PulsrDialogHelper.showCustomDialog<T>(
        context,
        useRootNavigator: useRootNavigator,
        barrierDismissible: isDismissible,
        barrierColor: effectiveBarrier,
        builder: (ctx) {
          final built = builder(ctx);
          final media = MediaQuery.of(ctx);
          final keyboardInset = media.viewInsets.bottom;
          final availableHeight = math.max(
            AppSpacing.s56,
            media.size.height -
                keyboardInset -
                media.padding.vertical -
                AppSpacing.xs,
          );
          final effectiveMaxHeight = math.min(
            PulsrSheetMetrics.dialogMaxHeight(ctx),
            availableHeight,
          );
          final Widget inner;
          if (built is PulsrBottomSheetContainer) {
            inner = built.isDialog
                ? built
                : PulsrBottomSheetContainer(
                    isDialog: true,
                    showDragHandle: false,
                    showDialogCloseButton:
                        showDialogCloseButton && built.showDialogCloseButton,
                    leading: built.leading,
                    title: built.title,
                    titleText: built.titleText,
                    subtitle: built.subtitle,
                    trailing: built.trailing,
                    child: built.child,
                  );
          } else {
            inner = PulsrBottomSheetContainer(
              isDialog: true,
              showDragHandle: false,
              showDialogCloseButton: showDialogCloseButton,
              child: built,
            );
          }
          return AnimatedPadding(
            duration: ctx.motion(PulsrMotion.state),
            curve: ctx.motionCurve(PulsrMotion.enter),
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: PulsrSheetMetrics.dialogMaxWidth(ctx),
                  maxHeight: effectiveMaxHeight,
                ),
                child: Dialog(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadii.dialogRadius,
                    child: Material(
                      color: Colors.transparent,
                      child: inner,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    // Modal counting is handled exclusively by the root [PulsrModalObserver]
    // (see pulsr_modal_tracker.dart) for sheets pushed on the root navigator.
    // A non-root navigator is invisible to that observer, so track it manually
    // (mirrors PulsrDialogHelper.showCustomDialog) to keep the mini-player dock
    // hidden while the sheet is open — and never double-count.
    final trackManually = !useRootNavigator;
    if (trackManually) PulsrModalTracker.push();
    final p = context.palette;

    final future = showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      // Sheets belong to the same transition family as routes instead of
      // Material's untokenized default.
      sheetAnimationStyle: AnimationStyle(
        duration: context.motion(PulsrDurations.page),
        reverseDuration: context.motion(PulsrDurations.layout),
      ),
      backgroundColor: Colors.transparent,
      barrierColor: barrierColor ?? AppColors.scrimAt(p.isDark ? 0.62 : 0.40),
      builder: (ctx) {
        final built = builder(ctx);
        final sheetWidget =
            (!wrapWithContainer || built is PulsrBottomSheetContainer)
                ? built
                : PulsrBottomSheetContainer(
                    showDragHandle: showDragHandle,
                    child: built,
                  );
        if (!isDismissible) {
          return PulsrModalBackGuard(child: sheetWidget);
        }
        return PulsrModalBackGuard(
          child: Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  label: MaterialLocalizations.of(ctx).modalBarrierDismissLabel,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      PulsrHaptics.lightImpact();
                      Navigator.of(ctx).maybePop();
                    },
                  ),
                ),
              ),
              sheetWidget,
            ],
          ),
        );
      },
    );
    return trackManually ? future.whenComplete(PulsrModalTracker.pop) : future;
  }
}

/// A responsive, frosted-glass container wrapper for all bottom sheets.
/// Automatically clamps width on tablet and desktop, adds top squircle corners,
/// top drag handle pill, and edge-to-edge safe area padding.
typedef PulsrBottomSheet = PulsrBottomSheetContainer;

class PulsrBottomSheetContainer extends StatelessWidget {
  final Widget child;
  final bool showDragHandle;
  final bool isDialog;
  final Widget? leading;
  final Widget? title;
  final String? titleText;
  final Widget? subtitle;
  final Widget? trailing;
  final bool showDialogCloseButton;

  const PulsrBottomSheetContainer({
    super.key,
    required this.child,
    this.showDragHandle = true,
    this.isDialog = false,
    this.leading,
    this.title,
    this.titleText,
    this.subtitle,
    this.trailing,
    this.showDialogCloseButton = true,
  });

  Widget _buildHeader(
    BuildContext context,
    PulsrPalette p,
    Widget? headerTitle, {
    required bool effectiveIsDialog,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s20,
            vertical: headerTitle == null
                ? 0
                : (showDragHandle && !effectiveIsDialog
                    ? AppSpacing.s8
                    : AppSpacing.sm),
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
    final isTablet = context.isTablet;
    final maxSheetWidth = PulsrSheetMetrics.sheetMaxWidth(context);
    final headerTitle = title ?? (titleText != null ? Text(titleText!) : null);

    final parentScope = PulsrSheetScope.maybeOf(context);
    if (parentScope != null) {
      return FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (headerTitle != null)
              FocusTraversalOrder(
                order: const NumericFocusOrder(1.0),
                child: _buildHeader(
                  context,
                  p,
                  headerTitle,
                  effectiveIsDialog: parentScope.isDialog || isDialog,
                ),
              ),
            Flexible(
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(2.0),
                child: Material(
                  color: Colors.transparent,
                  child: child,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isHighContrast =
        (MediaQuery.maybeOf(context)?.highContrast ?? false) ||
            p.isHighContrast;

    // Real material: enough translucency for the backdrop to read through,
    // but never below the legibility floor. High Contrast and GPU Saver stay
    // solid so text contrast is never compromised.
    final rawSurface = p.isDark ? p.surfaceContainer : p.surfaceElevated;
    final baseSurfaceColor = (!AppBlur.canBlur(context) || isHighContrast)
        ? rawSurface
        : rawSurface.withValues(alpha: p.isDark ? 0.88 : 0.94);

    final topBlendColor = isHighContrast
        ? baseSurfaceColor
        : Color.alphaBlend(
            p.accent.withValues(alpha: p.isDark ? 0.045 : 0.025),
            baseSurfaceColor,
          );

    final effectiveBorderRadius = isDialog
        ? AppRadii.dialogRadius
        : (isTablet ? AppRadii.r28All : AppRadii.bottomSheetRadius);

    final sheetSurface = Padding(
      padding: (!isDialog && isTablet)
          ? const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.s20,
              0,
              AppSpacing.s20,
              AppSpacing.md,
            )
          : EdgeInsets.zero,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: effectiveBorderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: AppBlur.chip,
              sigmaY: AppBlur.chip,
            ),
            enabled: !isHighContrast && AppBlur.canBlur(context),
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
                  color: isHighContrast
                      ? p.borderStrong
                      : (p.isDark
                          ? AppColors.specularAt(p.isAmoled ? 0.16 : 0.11)
                          : p.hairline),
                  width: isHighContrast ? 1.5 : AppStrokes.hairline,
                ),
              ),
              child: PulsrSheetScope(
            isDialog: isDialog,
            child: Stack(
              children: [
                // Top specular refraction hairline
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
                              (p.isDark ? 0.34 : 0.60) * p.specularScale,
                            ),
                            AppColors.specularAt(0.0),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                SafeArea(
                  top: false,
                  left: false,
                  right: false,
                  bottom: !isDialog,
                  child: Material(
                    type: MaterialType.transparency,
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: Column(
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
                                    color:
                                        (p.isDark ? Colors.white : Colors.black)
                                            .withValues(
                                      alpha: isHighContrast ? 0.58 : 0.26,
                                    ),
                                    borderRadius: AppRadii.full,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s8),
                          ],
                          if (headerTitle != null ||
                              (isDialog &&
                                  showDialogCloseButton &&
                                  trailing == null))
                            FocusTraversalOrder(
                              order: const NumericFocusOrder(1.0),
                              child: _buildHeader(
                                context,
                                p,
                                headerTitle,
                                effectiveIsDialog: isDialog,
                              ),
                            ),
                          Flexible(
                            child: FocusTraversalOrder(
                              order: const NumericFocusOrder(2.0),
                              child: Material(
                                color: Colors.transparent,
                                child: child,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    ),
    );

    if (isDialog) {
      return sheetSurface;
    }

    // Lift the sheet above the software keyboard and cap its height to the
    // space that actually remains, so text-field sheets never hide their
    // inputs or overflow behind the IME.
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final availableHeight = math.max(
      AppSpacing.s56,
      media.size.height - keyboardInset - media.padding.top - AppSpacing.xs,
    );
    final sheetMaxH =
        math.min(Adaptive.sheetMaxHeight(context), availableHeight);
    final insetDuration = context.motion(PulsrMotion.state);

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedPadding(
        duration: insetDuration,
        curve: context.motionCurve(PulsrMotion.enter),
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxSheetWidth,
            maxHeight: sheetMaxH,
          ),
          child: sheetSurface,
        ),
      ),
    );
  }
}
