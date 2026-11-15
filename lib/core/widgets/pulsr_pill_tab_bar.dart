// lib/core/widgets/pulsr_pill_tab_bar.dart
import 'package:flutter/material.dart';

import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../responsive/pulsr_layout_metrics.dart';
import '../theme/aura_theme.dart';
import 'pulsr_scroll_edge_fade.dart';

/// {@category DesignSystem}
/// Canonical pill-styled [TabBar] matching the Equalizer / AutoEq / Spatial & DSP
/// tab bar design across the app.
class PulsrPillTabBar extends StatelessWidget {
  final TabController controller;
  final List<Widget> tabs;
  final bool isScrollable;
  final TabAlignment? tabAlignment;
  final EdgeInsetsGeometry? labelPadding;
  final ScrollPhysics? physics;
  final bool scrollEdgeFade;
  final EdgeInsetsGeometry? margin;
  final Key? tabBarKey;

  const PulsrPillTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.isScrollable = false,
    this.tabAlignment,
    this.labelPadding,
    this.physics,
    this.scrollEdgeFade = false,
    this.margin,
    this.tabBarKey,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final effectiveAlignment =
        tabAlignment ?? (isScrollable ? TabAlignment.start : TabAlignment.fill);
    final effectiveLabelPadding = labelPadding ??
        (isScrollable
            ? const EdgeInsets.symmetric(horizontal: AppSpacing.md)
            : EdgeInsets.zero);

    Widget tabBar = TabBar(
      key: tabBarKey,
      controller: controller,
      isScrollable: isScrollable,
      tabAlignment: effectiveAlignment,
      labelPadding: effectiveLabelPadding,
      indicator: BoxDecoration(
        color: p.accent,
        borderRadius: AppRadii.r20All,
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: p.onAccent,
      unselectedLabelColor: p.textSecondary,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: AppFontSize.label,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: AppFontSize.label,
      ),
      dividerColor: Colors.transparent,
      splashBorderRadius: AppRadii.r20All,
      physics: physics,
      tabs: tabs,
    );

    if (scrollEdgeFade) {
      tabBar = PulsrScrollEdgeFade(
        enabled: true,
        child: tabBar,
      );
    }

    return Container(
      margin: margin,
      width: double.infinity,
      height: PulsrLayoutMetrics.fieldHeight(context),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r20All,
        border: Border.all(color: p.hairline),
      ),
      child: ClipRRect(
        borderRadius: AppRadii.r20All,
        child: tabBar,
      ),
    );
  }
}
