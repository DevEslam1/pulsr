import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../theme/aura_theme.dart';

/// Standardized card component adhering to Pulsr design tokens:
/// [AppRadii.card] (16), [p.surfaceContainer], [p.hairline] border, and optional elevation.
class PulsrCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final List<BoxShadow>? boxShadow;
  final Clip clipBehavior;

  const PulsrCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppRadii.card,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = backgroundColor ?? p.surfaceContainer;
    final border = Border.all(
      color: borderColor ?? p.hairline,
      width: 1.0,
    );
    final radius = BorderRadius.circular(borderRadius);

    Widget card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: border,
        boxShadow: boxShadow,
      ),
      clipBehavior: clipBehavior,
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );

    if (onTap != null) {
      card = InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: card,
      );
    }

    return card;
  }
}
