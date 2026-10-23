// lib/core/widgets/pulsr_bottom_sheet.dart
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../theme/aura_theme.dart';
import '../utils/adaptive.dart';
import '../utils/l10n_extensions.dart';
import '../performance/gpu_budget.dart';
import 'pulsr_dialog.dart';
import 'pulsr_modal_tracker.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

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
                  ? built
                  : PulsrBottomSheetContainer(
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

class _PulsrBottomSheetScope extends InheritedWidget {
  const _PulsrBottomSheetScope({required super.child});

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;
}

/// A responsive, frosted-glass container wrapper for all bottom sheets.
/// Automatically clamps width on tablet and desktop, adds top squircle corners,
/// top drag handle pill, and edge-to-edge safe area padding.
typedef PulsrBottomSheet = PulsrBottomSheetContainer;

class PulsrBottomSheetContainer extends StatelessWidget {
  final Widget child;
  final bool showDragHandle;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;

  const PulsrBottomSheetContainer({
    super.key,
    required this.child,
    this.showDragHandle = true,
    this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = context.isTablet;
    final maxSheetWidth = isTablet ? 620.0 : double.infinity;

    final isNested =
        context.dependOnInheritedWidgetOfExactType<_PulsrBottomSheetScope>() !=
            null;
    if (isNested) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s20, vertical: AppSpacing.s8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle.merge(
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.title,
                            fontWeight: FontWeight.w800,
                            letterSpacing: AppTracking.title,
                          ),
                          child: title!,
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
                ],
              ),
            ),
            Divider(color: p.hairline, height: 1),
          ],
          Flexible(
            child: Material(
              color: Colors.transparent,
              child: child,
            ),
          ),
        ],
      );
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

    final effectiveBorderRadius =
        isTablet ? AppRadii.r28All : AppRadii.bottomSheetRadius;

    final navGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        GpuBudget.isGpuSaverActive
            ? p.surface
            : p.surface.withValues(alpha: p.isDark ? 0.78 : 0.88),
        GpuBudget.isGpuSaverActive
            ? p.surfaceContainer
            : p.surfaceContainer.withValues(alpha: p.isDark ? 0.72 : 0.84),
      ],
    );

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
          child: RepaintBoundary(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: effectiveBorderRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: p.isDark ? 0.40 : 0.12),
                    blurRadius: 24,
                    spreadRadius: 0,
                    offset: const Offset(0, -4),
                  ),
                  BoxShadow(
                    color: p.accent
                        .withValues(alpha: p.isDark ? 0.08 : 0.04),
                    blurRadius: 18,
                    spreadRadius: -2,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              margin: isTablet
                  ? const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.s20, 0, AppSpacing.s20, AppSpacing.md)
                  : EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: effectiveBorderRadius,
                child: Builder(
                  builder: (context) {
                    final sheetContent = Container(
                      decoration: BoxDecoration(
                        gradient: navGradient,
                        borderRadius: effectiveBorderRadius,
                        border: Border.all(
                          color: p.isDark
                              ? AppColors.specularStrong
                              : AppColors.scrimAt(0.08),
                          width: 1.2,
                        ),
                      ),
                      child: _PulsrBottomSheetScope(
                        child: SafeArea(
                          top: false,
                          left: false,
                          right: false,
                          child: Material(
                            type: MaterialType.transparency,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Top drag pill
                                if (showDragHandle) ...[
                                  const SizedBox(height: AppSpacing.s10),
                                  Center(
                                    child: Semantics(
                                      label: context.l10n.sheetDragHandle,
                                      hint: context.l10n.sheetDragDownToDismiss,
                                      child: Container(
                                        width: AppSpacing.s40,
                                        height: 4.5,
                                        decoration: BoxDecoration(
                                          color: (p.isDark
                                                  ? Colors.white
                                                  : Colors.black)
                                              .withValues(alpha: 0.22),
                                          borderRadius: AppRadii.full,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s8),
                                ],

                                // Optional Header
                                if (title != null) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.s20,
                                        vertical: AppSpacing.s8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              DefaultTextStyle.merge(
                                                style: TextStyle(
                                                  color: p.textPrimary,
                                                  fontSize: AppFontSize.title,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing:
                                                      AppTracking.title,
                                                ),
                                                child: title!,
                                              ),
                                              if (subtitle != null) ...[
                                                const SizedBox(
                                                    height: AppSpacing.s2),
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
                                      ],
                                    ),
                                  ),
                                  Divider(color: p.hairline, height: 1),
                                ],

                                // Sheet Body
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
                      ),
                    );

                    if (GpuBudget.isGpuSaverActive) {
                      return sheetContent;
                    }
                    return BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: sheetContent,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
