// lib/core/widgets/pulsr_bottom_sheet.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../theme/aura_theme.dart';
import '../utils/adaptive.dart';
import 'pulsr_modal_tracker.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// Centralized bottom sheet entry-points and container for the entire app.
///
/// Features:
/// - Guaranteed integration with [PulsrModalTracker] to hide/restore the mini player dock smoothly
/// - Native Apple/Google sheet drag handle pill
/// - Responsive width clamping on tablet & desktop (`maxWidth: 580`)
/// - Frosted translucent backdrop blur and hairline border
/// - Edge-to-edge safe area handling
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
    PulsrModalTracker.push();
    final p = context.palette;

    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: Colors.transparent,
      barrierColor: barrierColor ??
          Colors.black.withValues(alpha: p.isDark ? 0.60 : 0.40),
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
    ).whenComplete(PulsrModalTracker.pop);
  }
}

/// A responsive, frosted-glass container wrapper for all bottom sheets.
/// Automatically clamps width on tablet and desktop, adds top squircle corners,
/// top drag handle pill, and edge-to-edge safe area padding.
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
    final maxSheetWidth = isTablet ? 580.0 : double.infinity;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxSheetWidth),
        child: Container(
          decoration: BoxDecoration(
            color: p.isDark
                ? p.surface.withValues(alpha: 0.92)
                : p.surface.withValues(alpha: 0.96),
            borderRadius: isTablet
                ? BorderRadius.circular(AppRadii.r28)
                : AppRadii.bottomSheetRadius,
            border: Border.all(
              color: p.hairline,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: p.isDark ? 0.50 : 0.16),
                blurRadius: 36,
                spreadRadius: 0,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          margin: isTablet
              ? const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, 0, AppSpacing.s20, AppSpacing.lg)
              : EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: isTablet
                ? BorderRadius.circular(AppRadii.r28)
                : AppRadii.bottomSheetRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top drag pill
                    if (showDragHandle) ...[
                      const SizedBox(height: AppSpacing.s10),
                      Center(
                        child: Container(
                          width: 38,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: (p.isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.18),
                            borderRadius: AppRadii.full,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s10),
                    ],

                    // Optional Header
                    if (title != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(

                            horizontal: AppSpacing.s20, vertical: AppSpacing.s6),
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

                    // Sheet Body
                    Flexible(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
