// lib/core/widgets/pulsr_bottom_sheet.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../constants/app_radii.dart';
import '../performance/gpu_budget.dart';
import '../theme/aura_theme.dart';
import '../utils/adaptive.dart';
import '../utils/l10n_extensions.dart';
import 'pulsr_dialog.dart';
import 'pulsr_modal_tracker.dart';

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
/// - Automatically adapts to centered dialog when in landscape on short phone screens
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
  }) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    // Landscape phone: present as centered dialog to avoid bottom sheet clipping/distortion
    if (isLandscape && size.height < 480) {
      final maxW = math.min(size.width * 0.94, 760.0);
      final maxH = math.min(size.height * 0.94, size.height - 16.0);
      return PulsrDialogHelper.showCustomDialog<T>(
        context,
        useRootNavigator: useRootNavigator,
        barrierDismissible: isDismissible,
        builder: (ctx) {
          final built = builder(ctx);
          final inner =
              (!wrapWithContainer || built is PulsrBottomSheetContainer)
                  ? (built is PulsrBottomSheetContainer && !built.isDialog
                      ? PulsrBottomSheetContainer(
                          isDialog: true,
                          showDragHandle: false,
                          leading: built.leading,
                          title: built.title,
                          titleText: built.titleText,
                          subtitle: built.subtitle,
                          trailing: built.trailing,
                          child: built.child,
                        )
                      : built)
                  : PulsrBottomSheetContainer(
                      isDialog: true,
                      showDragHandle: false,
                      child: built,
                    );
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxW,
                maxHeight: maxH,
              ),
              child: Dialog(
                backgroundColor: Colors.transparent,
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
      backgroundColor: Colors.transparent,
      barrierColor: barrierColor ?? AppColors.scrimAt(p.isDark ? 0.62 : 0.40),
      builder: (ctx) {
        final built = builder(ctx);
        if (!wrapWithContainer || built is PulsrBottomSheetContainer) {
          return built;
        }
        return PulsrBottomSheetContainer(
          showDragHandle: showDragHandle,
          child: built,
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
  });

  Widget _buildHeader(
    BuildContext context,
    PulsrPalette p,
    Widget headerTitle, {
    required bool effectiveIsDialog,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s20,
            vertical: showDragHandle && !effectiveIsDialog
                ? AppSpacing.s8
                : AppSpacing.sm,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.sm),
              ],
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
                    HapticFeedback.lightImpact();
                    Navigator.of(context).maybePop();
                  },
                ),
            ],
          ),
        ),
        Divider(color: p.hairline, height: 1),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = context.isTablet;
    final maxSheetWidth = isTablet ? 620.0 : double.infinity;
    final headerTitle = title ?? (titleText != null ? Text(titleText!) : null);

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
              headerTitle,
              effectiveIsDialog: parentScope.isDialog || isDialog,
            ),
          Flexible(
            child: Material(
              color: Colors.transparent,
              child: child,
            ),
          ),
        ],
      );
    }

    final baseSurfaceColor = GpuBudget.isGpuSaverActive
        ? p.surfaceContainer
        : (p.isDark
            ? p.surfaceContainer.withValues(alpha: 0.96)
            : p.surfaceContainer.withValues(alpha: 0.98));

    final topBlendColor = Color.alphaBlend(
      p.accent.withValues(alpha: p.isDark ? 0.045 : 0.025),
      baseSurfaceColor,
    );

    final effectiveBorderRadius = isDialog
        ? AppRadii.dialogRadius
        : (isTablet ? AppRadii.r28All : AppRadii.bottomSheetRadius);

    final sheetSurface = RepaintBoundary(
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
              color: AppColors.scrimAt(p.isDark ? 0.42 : 0.12),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        margin: (!isDialog && isTablet)
            ? const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.s20,
                0,
                AppSpacing.s20,
                AppSpacing.md,
              )
            : EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: effectiveBorderRadius,
          child: PulsrSheetScope(
            isDialog: isDialog,
            child: Stack(
              children: [
                // Top specular refraction hairline
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
                          AppColors.specularAt(p.isDark ? 0.36 : 0.60),
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
                                          .withValues(alpha: 0.24),
                                  borderRadius: AppRadii.full,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s8),
                        ],
                        if (headerTitle != null)
                          _buildHeader(
                            context,
                            p,
                            headerTitle,
                            effectiveIsDialog: isDialog,
                          ),
                        Flexible(
                          child: Material(
                            color: Colors.transparent,
                            child: child,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
            maxWidth: maxSheetWidth,
            maxHeight: sheetMaxH,
          ),
          child: sheetSurface,
        ),
      ),
    );
  }
}
