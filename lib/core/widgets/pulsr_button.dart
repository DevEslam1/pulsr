// lib/core/widgets/pulsr_button.dart
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import 'pulsr_pressable.dart';

/// {@category DesignSystem}
enum PulsrButtonVariant {
  primary,
  secondary,
  tonal,
  ghost,
  destructive,
}

enum PulsrButtonSize {
  sm,
  md,
  lg,
}

/// Unified button component for the Pulsr design system.
class PulsrButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final PulsrButtonVariant variant;
  final PulsrButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool expand;

  const PulsrButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = PulsrButtonVariant.primary,
    this.size = PulsrButtonSize.md,
    this.icon,
    this.loading = false,
    this.expand = false,
  });

  @override
  State<PulsrButton> createState() => _PulsrButtonState();
}

class _PulsrButtonState extends State<PulsrButton> {
  bool _hovered = false;

  double get _height {
    switch (widget.size) {
      case PulsrButtonSize.sm:
        return 36.0;
      case PulsrButtonSize.md:
        return 44.0;
      case PulsrButtonSize.lg:
        return 52.0;
    }
  }

  double get _fontSize {
    switch (widget.size) {
      case PulsrButtonSize.sm:
        return AppFontSize.label;
      case PulsrButtonSize.md:
        return AppFontSize.body;
      case PulsrButtonSize.lg:
        return AppFontSize.bodyLarge;
    }
  }

  double get _iconSize {
    switch (widget.size) {
      case PulsrButtonSize.sm:
        return 16.0;
      case PulsrButtonSize.md:
        return 18.0;
      case PulsrButtonSize.lg:
        return 21.0;
    }
  }

  EdgeInsets get _padding {
    switch (widget.size) {
      case PulsrButtonSize.sm:
        return const EdgeInsets.symmetric(horizontal: AppSpacing.s14);
      case PulsrButtonSize.md:
        return const EdgeInsets.symmetric(horizontal: AppSpacing.s18);
      case PulsrButtonSize.lg:
        return const EdgeInsets.symmetric(horizontal: AppSpacing.lg);
    }
  }

  BorderRadius get _radius {
    switch (widget.size) {
      case PulsrButtonSize.sm:
        return AppRadii.r10All;
      case PulsrButtonSize.md:
        return AppRadii.r12All;
      case PulsrButtonSize.lg:
        return AppRadii.r14All;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = widget.onPressed != null && !widget.loading;

    Color bg;
    Color fg;
    Border? border;
    Gradient? gradient;
    List<BoxShadow>? shadows;

    switch (widget.variant) {
      case PulsrButtonVariant.primary:
        final baseAccent =
            enabled ? p.accent : p.accent.withValues(alpha: 0.32);
        bg = baseAccent;
        fg = enabled ? p.textOnAccent : p.textOnAccent.withValues(alpha: 0.6);
        if (enabled) {
          final topHighlight =
              Color.lerp(baseAccent, Colors.white, _hovered ? 0.18 : 0.12)!;
          gradient = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topHighlight, baseAccent],
          );
          border = Border.all(
            color: AppColors.specularAt(p.isDark ? 0.22 : 0.30),
            width: 0.8,
          );
          shadows = [
            BoxShadow(
              color: p.accent.withValues(alpha: _hovered ? 0.38 : 0.24),
              blurRadius: _hovered ? 16 : 12,
              spreadRadius: -2,
              offset: const Offset(0, 4),
            ),
          ];
        }
        break;

      case PulsrButtonVariant.secondary:
        bg = _hovered && enabled ? p.surfaceContainerHigh : p.surfaceContainer;
        fg = enabled ? p.textPrimary : p.textTertiary;
        border = Border.all(
          color: _hovered && enabled ? p.borderStrong : p.hairline,
          width: 1.0,
        );
        break;

      case PulsrButtonVariant.tonal:
        bg = enabled
            ? (_hovered
                ? p.accent.withValues(alpha: p.isDark ? 0.24 : 0.18)
                : p.accentSoft)
            : p.accentSoft.withValues(alpha: 0.4);
        fg = enabled ? p.accent : p.accent.withValues(alpha: 0.45);
        border = Border.all(
          color: enabled
              ? p.accent.withValues(alpha: _hovered ? 0.35 : 0.18)
              : Colors.transparent,
          width: 1.0,
        );
        break;

      case PulsrButtonVariant.ghost:
        bg = _hovered && enabled
            ? (p.isDark ? AppColors.specularAt(0.06) : AppColors.scrimAt(0.05))
            : Colors.transparent;
        fg = enabled ? p.textPrimary : p.textTertiary;
        border = null;
        break;

      case PulsrButtonVariant.destructive:
        bg = enabled
            ? (_hovered ? p.error.withValues(alpha: 0.22) : p.errorSoft)
            : p.errorSoft.withValues(alpha: 0.35);
        fg = enabled ? p.error : p.error.withValues(alpha: 0.45);
        border = Border.all(
          color: enabled ? p.error.withValues(alpha: 0.45) : p.hairline,
          width: 1.0,
        );
        break;
    }

    final labelWidget = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Manrope',
        fontSize: _fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: AppTracking.title,
        color: fg,
        height: 1.1,
      ),
    );

    final hasLeading = widget.loading || widget.icon != null;

    final Widget content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (hasLeading) ...[
          AnimatedSwitcher(
            duration: context.motionMs(180),
            child: widget.loading
                ? SizedBox(
                    key: const ValueKey('loading'),
                    width: _iconSize,
                    height: _iconSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  )
                : Icon(
                    widget.icon,
                    key: ValueKey(widget.icon),
                    size: _iconSize,
                    color: fg,
                  ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        if (widget.expand) Flexible(child: labelWidget) else labelWidget,
      ],
    );

    final visual = AnimatedContainer(
      duration: context.motionMs(150),
      curve: Curves.easeOutCubic,
      constraints: BoxConstraints(minHeight: _height),
      padding: _padding.add(
        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      ),
      decoration: BoxDecoration(
        color: gradient == null ? bg : null,
        gradient: gradient,
        borderRadius: _radius,
        border: border,
        boxShadow: shadows,
      ),
      child: content,
    );

    final buttonWidget = MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSpacing.minTouchTarget,
        ),
        child: Center(
          widthFactor: widget.expand ? null : 1.0,
          child: visual,
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: PulsrPressable(
        focusBorderRadius: _radius,
        onTap: enabled ? widget.onPressed : null,
        child: buttonWidget,
      ),
    );
  }
}
