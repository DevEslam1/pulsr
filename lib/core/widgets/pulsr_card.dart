import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';

/// {@category DesignSystem}
enum PulsrCardElevation {
  none,
  low,
  medium,
  high,
}

/// Visual presentation variant for [PulsrCard].
enum PulsrCardVariant {
  /// Standard solid container using `p.surfaceContainer`.
  filled,

  /// Outlined container using transparent/subtle background and hairline border.
  outlined,

  /// Prominent surface using `p.surfaceElevated` with soft elevation shadow.
  elevated,

  /// Frosted glass surface using backdrop blur filter and translucent tint.
  glass,
}

/// Standardized universal surface container adhering to Pulsr design tokens:
/// [AppRadii.card] (18), [p.surfaceContainer], [p.hairline] border,
/// tokenized [PulsrElevation], and desktop hover effects.
class PulsrCard extends StatefulWidget {
  final Widget child;
  final PulsrCardVariant variant;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
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
    this.variant = PulsrCardVariant.filled,
    this.padding = const EdgeInsets.all(AppSpacing.cardPad),
    this.margin,
    this.onTap,
    this.onLongPress,
    this.selected = false,
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

  Color _resolveBackground(PulsrPalette p) {
    if (widget.backgroundColor != null) return widget.backgroundColor!;
    if (widget.selected) {
      return p.accentSoft;
    }
    switch (widget.variant) {
      case PulsrCardVariant.filled:
        return p.surfaceContainer;
      case PulsrCardVariant.outlined:
        return Colors.transparent;
      case PulsrCardVariant.elevated:
        return p.surfaceElevated;
      case PulsrCardVariant.glass:
        return p.surfaceOverlay;
    }
  }

  Color _resolveBorderColor(PulsrPalette p) {
    if (widget.borderColor != null) return widget.borderColor!;
    if (widget.selected) return p.accent;
    if (_isHovered) return p.borderStrong;
    switch (widget.variant) {
      case PulsrCardVariant.filled:
        return p.borderSubtle;
      case PulsrCardVariant.outlined:
        return p.hairline;
      case PulsrCardVariant.elevated:
        return p.hairline;
      case PulsrCardVariant.glass:
        return p.isDark ? AppColors.specularAt(0.15) : AppColors.scrimAt(0.08);
    }
  }

  List<BoxShadow>? _resolveShadows(PulsrPalette p) {
    if (widget.boxShadow != null) return widget.boxShadow;

    // Use variant-directed elevation if not manually set
    if (widget.elevation == PulsrCardElevation.none) {
      if (widget.variant == PulsrCardVariant.elevated) {
        return _isHovered
            ? PulsrElevation.level2(context)
            : PulsrElevation.level1(context);
      }
      return _isHovered ? PulsrElevation.level1(context) : null;
    }

    switch (widget.elevation) {
      case PulsrCardElevation.none:
        return _isHovered ? PulsrElevation.level1(context) : null;
      case PulsrCardElevation.low:
        return _isHovered
            ? PulsrElevation.level2(context)
            : PulsrElevation.level1(context);
      case PulsrCardElevation.medium:
        return _isHovered
            ? PulsrElevation.level3(context)
            : PulsrElevation.level2(context);
      case PulsrCardElevation.high:
        return _isHovered
            ? PulsrElevation.level4(context)
            : PulsrElevation.level3(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = _resolveBackground(p);
    final border = Border.all(
      color: _resolveBorderColor(p),
      width: widget.selected ? 1.5 : 1.0,
    );
    final radius = AppRadii.circular(widget.borderRadius);
    final shadows = _resolveShadows(p);

    Widget content = widget.padding != null
        ? Padding(padding: widget.padding!, child: widget.child)
        : widget.child;

    final isTappable = widget.onTap != null || widget.onLongPress != null;

    if (isTappable) {
      content = Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: radius,
          child: content,
        ),
      );
    }

    if (widget.variant == PulsrCardVariant.glass && context.motionEnabled) {
      content = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: content,
        ),
      );
    }

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
      child: content,
    );

    if (widget.enableHoverScale && isTappable) {
      card = MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedScale(
          scale: _isHovered && context.motionEnabled ? 1.015 : 1.0,
          duration: context.motionMs(180),
          curve: context.motionCurve(Curves.easeOutCubic),
          child: card,
        ),
      );
    }

    return card;
  }
}
