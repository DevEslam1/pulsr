// lib/core/responsive/two_pane_scaffold.dart
import 'package:flutter/material.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../theme/aura_theme.dart';
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
            'Select an item to view details',
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
        final computedMasterWidth = masterWidth ??
            (totalWidth * listWidthRatio).clamp(280.0, 480.0);

        Widget body = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: computedMasterWidth,
              child: effectiveMaster,
            ),
            if (hinge != null && hinge.bounds.width > 0)
              SizedBox(width: hinge.bounds.width)
            else if (showDivider)
              VerticalDivider(width: 1, thickness: 1, color: p.hairline),
            Expanded(
              child: effectiveDetail,
            ),
          ],
        );

        if (applyDockPadding) {
          body = ValueListenableBuilder<double>(
            valueListenable: PulsrDockTracker.dockHeight,
            builder: (context, dockHeight, child) {
              return Padding(
                padding: EdgeInsets.only(bottom: dockHeight),
                child: child,
              );
            },
            child: body,
          );
        }

        return body;
      },
    );
  }
}
