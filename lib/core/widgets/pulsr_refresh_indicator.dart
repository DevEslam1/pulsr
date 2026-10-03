// lib/core/widgets/pulsr_refresh_indicator.dart
import 'package:flutter/material.dart';
import '../theme/aura_theme.dart';
import '../utils/pulsr_haptics.dart';

/// {@category DesignSystem}
/// A branded pull-to-refresh indicator adhering to Pulsr design tokens,
/// providing tactile haptic feedback on trigger, themed accent indicator,
/// and surface container backdrop.
class PulsrRefreshIndicator extends StatelessWidget {
  final Widget child;
  final RefreshCallback onRefresh;
  final double displacement;
  final double edgeOffset;
  final Color? color;
  final Color? backgroundColor;
  final String? semanticLabel;

  const PulsrRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.displacement = 40.0,
    this.edgeOffset = 0.0,
    this.color,
    this.backgroundColor,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return RefreshIndicator(
      color: color ?? p.accent,
      backgroundColor: backgroundColor ?? p.surfaceContainer,
      displacement: displacement,
      edgeOffset: edgeOffset,
      semanticsLabel: semanticLabel,
      onRefresh: () async {
        PulsrHaptics.light();
        await onRefresh();
      },
      child: child,
    );
  }
}
