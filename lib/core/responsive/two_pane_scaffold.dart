// lib/core/responsive/two_pane_scaffold.dart
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../theme/aura_theme.dart';
import '../utils/l10n_extensions.dart';
import '../widgets/pulsr_dock_tracker.dart';
import 'pulsr_responsive_tokens.dart';

/// Reusable two-pane master-detail container with automatic foldable hinge awareness.
typedef TwoPaneScaffold = PulsrTwoPaneScaffold;

class PulsrTwoPaneScaffold extends StatelessWidget {
  final Widget? master;
  final Widget? detail;
  final Widget? listPane;
  final Widget? detailPane;
  final double? masterWidth;
  final double listWidthRatio;
  final bool showDivider;
  final Widget? placeholder;
  final bool applyDockPadding;

  const PulsrTwoPaneScaffold({
    super.key,
    this.master,
    this.detail,
    this.listPane,
    this.detailPane,
    this.masterWidth,
    this.listWidthRatio = 0.35,
    this.showDivider = true,
    this.placeholder,
    this.applyDockPadding = true,
  });

  Widget _buildPlaceholder(BuildContext context) {
    if (placeholder != null) return placeholder!;
    final p = context.palette;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.touch_app_outlined,
              size: 48,
              color: p.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.twoPaneSelectItem,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.callout,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final vp = PulsrViewport.of(context);
    final hinge = vp.hinge;

    final effectiveMaster = listPane ?? master ?? const SizedBox();
    final effectiveDetail = detailPane ?? detail ?? _buildPlaceholder(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final hasVerticalHinge = hinge != null &&
            hinge.bounds.width > 0 &&
            hinge.bounds.height > hinge.bounds.width &&
            hinge.bounds.width < totalWidth;

        final maxAllowedMaster = math.max(
          0.0,
          totalWidth - (hasVerticalHinge ? hinge.bounds.width : 0.0) - 80.0,
        );
        double baseMaster =
            masterWidth ?? (totalWidth * listWidthRatio).clamp(280.0, 480.0);
        // When a foldable has a vertical hinge and no fixed masterWidth is
        // requested, align the split directly onto the physical hinge seam
        // whenever both panes keep comfortable reading widths (>= 240dp).
        if (hasVerticalHinge && masterWidth == null) {
          final leadingShellOffset = math.max(0.0, vp.width - totalWidth);
          final isRtl = Directionality.of(context) == TextDirection.rtl;
          final hingeStart = isRtl
              ? (vp.width - hinge.bounds.right) - leadingShellOffset
              : hinge.bounds.left - leadingShellOffset;
          final trailingSpace = totalWidth - hingeStart - hinge.bounds.width;
          if (hingeStart >= 240.0 && trailingSpace >= 240.0) {
            baseMaster = hingeStart;
          }
        }
        final computedMasterWidth = baseMaster.clamp(0.0, maxAllowedMaster);

        Widget body = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: computedMasterWidth,
              child: effectiveMaster,
            ),
            if (hasVerticalHinge)
              SizedBox(width: hinge.bounds.width)
            else if (showDivider)
              VerticalDivider(width: 1, thickness: 1, color: p.hairline),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.isDark
                      ? p.surfaceContainer.withValues(alpha: 0.65)
                      : p.surface,
                  borderRadius: AppRadii.r20All,
                  border: Border.all(color: p.hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: effectiveDetail,
              ),
            ),
          ],
        );

        if (applyDockPadding) {
          final scoped =
              context.dependOnInheritedWidgetOfExactType<PulsrDockScope>();
          final safeBottom = MediaQuery.paddingOf(context).bottom;
          if (scoped != null) {
            final effectiveBottom =
                scoped.height > 0 ? (scoped.height + safeBottom) : safeBottom;
            body = Padding(
              padding: EdgeInsets.only(bottom: effectiveBottom),
              child: body,
            );
          } else {
            body = ValueListenableBuilder<double>(
              valueListenable: PulsrDockTracker.dockHeight,
              builder: (context, dockHeight, child) {
                final effectiveBottom =
                    dockHeight > 0 ? (dockHeight + safeBottom) : safeBottom;
                return Padding(
                  padding: EdgeInsets.only(bottom: effectiveBottom),
                  child: child,
                );
              },
              child: body,
            );
          }
        }

        return body;
      },
    );
  }
}
