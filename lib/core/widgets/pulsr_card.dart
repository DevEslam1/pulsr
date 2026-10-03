import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import 'package:pulsr/core/constants/app_colors.dart';

/// {@category DesignSystem}
enum PulsrCardElevation {
  none,
  low,
  medium,
  high,
}

/// Standardized card component adhering to Pulsr design tokens:
/// [AppRadii.card] (18), [p.surfaceContainer], [p.hairline] border,
/// tokenized [PulsrCardElevation], and desktop hover effects.
class PulsrCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final PulsrCardElevation elevation;
  final List<BoxShadow>? boxShadow;
  final Clip clipBehavior;
  final bool enableHoverScale;

  const PulsrCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin,
    this.onTap,
    this.onLongPress,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppRadii.card,
    this.elevation = PulsrCardElevation.none,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
    this.enableHoverScale = true,
  });

  @override
  State<PulsrCard> createState() => _PulsrCardState();
}

class _PulsrCardState extends State<PulsrCard> {
  bool _isHovered = false;

  List<BoxShadow>? _resolveShadows(PulsrPalette p) {
    if (widget.boxShadow != null) return widget.boxShadow;

    switch (widget.elevation) {
      case PulsrCardElevation.none:
        return _isHovered
            ? [
                BoxShadow(
                  color: AppColors.scrimAt(p.isDark ? 0.20 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                )
              ]
            : null;
      case PulsrCardElevation.low:
        return [
          BoxShadow(
            color: AppColors.scrimAt(
                (_isHovered ? 0.28 : 0.20) * (p.isDark ? 1.0 : 0.35)),
            blurRadius: _isHovered ? 12 : 8,
            offset: Offset(0, _isHovered ? 3 : 2),
          ),
        ];
      case PulsrCardElevation.medium:
        return [
          BoxShadow(
            color: AppColors.scrimAt(
                (_isHovered ? 0.38 : 0.30) * (p.isDark ? 1.0 : 0.35)),
            blurRadius: _isHovered ? 20 : 14,
            offset: Offset(0, _isHovered ? 6 : 4),
          ),
          BoxShadow(
            color: p.accent.withValues(alpha: p.isDark ? 0.05 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 1),
          ),
        ];
      case PulsrCardElevation.high:
        return [
          BoxShadow(
            color: AppColors.scrimAt(
                (_isHovered ? 0.50 : 0.42) * (p.isDark ? 1.0 : 0.35)),
            blurRadius: _isHovered ? 28 : 22,
            offset: Offset(0, _isHovered ? 10 : 7),
          ),
          BoxShadow(
            color: p.accent.withValues(alpha: p.isDark ? 0.10 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 2),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = widget.backgroundColor ?? p.surfaceContainer;
    final border = Border.all(
      color: widget.borderColor ?? p.hairline,
      width: 1.0,
    );
    final radius = BorderRadius.circular(widget.borderRadius);
    final shadows = _resolveShadows(p);

    Widget card = AnimatedContainer(
      duration: context.motionMs(180),
      curve: context.motionCurve(Curves.easeOutCubic),
      margin: widget.margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: border,
        boxShadow: shadows,
      ),
      clipBehavior: widget.clipBehavior,
      child: widget.padding != null
          ? Padding(padding: widget.padding!, child: widget.child)
          : widget.child,
    );

    final isTappable = widget.onTap != null || widget.onLongPress != null;

    if (isTappable) {
      card = Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: radius,
          child: card,
        ),
      );
    }

    if (widget.enableHoverScale && isTappable) {
      card = MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedScale(
          scale: _isHovered && context.motionEnabled ? 1.02 : 1.0,
          duration: context.motionMs(180),
          curve: context.motionCurve(Curves.easeOutCubic),
          child: card,
        ),
      );
    }

    return card;
  }
}
