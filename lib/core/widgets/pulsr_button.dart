import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../theme/aura_theme.dart';
import 'pulsr_pressable.dart';

/// {@category DesignSystem}
enum PulsrButtonVariant {
  /// Solid prominent accent background with high-contrast text.
  primary,

  /// Neutral container surface with subtle hairline border.
  secondary,

  /// Soft accent background tint (12-16% alpha) with accent text.
  tonal,

  /// Borderless flat button with text primary.
  ghost,

  /// High-visibility error/warning styling for destructive actions.
  destructive,
}

enum PulsrButtonSize {
  /// Compact visual height (36dp) with a 48dp interactive target.
  sm,

  /// Standard visual height (44dp) with a 48dp interactive target.
  md,

  /// Prominent call-to-action button (height 52dp).
  lg,
}

/// Unified button component for the Pulsr design system.
class PulsrButton extends StatelessWidget {
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

  double get _height {
    switch (size) {
      case PulsrButtonSize.sm:
        return 36.0;
      case PulsrButtonSize.md:
        return 44.0;
      case PulsrButtonSize.lg:
        return 52.0;
    }
  }

  double get _fontSize {
    switch (size) {
      case PulsrButtonSize.sm:
        return AppFontSize.label;
      case PulsrButtonSize.md:
        return AppFontSize.body;
      case PulsrButtonSize.lg:
        return AppFontSize.bodyLarge;
    }
  }

  double get _iconSize {
    switch (size) {
      case PulsrButtonSize.sm:
        return 16.0;
      case PulsrButtonSize.md:
        return 18.0;
      case PulsrButtonSize.lg:
        return 22.0;
    }
  }

  EdgeInsets get _padding {
    switch (size) {
      case PulsrButtonSize.sm:
        return const EdgeInsets.symmetric(horizontal: AppSpacing.sm);
      case PulsrButtonSize.md:
        return const EdgeInsets.symmetric(horizontal: AppSpacing.md);
      case PulsrButtonSize.lg:
        return const EdgeInsets.symmetric(horizontal: AppSpacing.lg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null && !loading;

    final Color bg;
    final Color fg;
    final Border? border;

    switch (variant) {
      case PulsrButtonVariant.primary:
        bg = enabled ? p.accent : p.accent.withValues(alpha: 0.35);
        fg = p.textOnAccent;
        border = null;
        break;
      case PulsrButtonVariant.secondary:
        bg = p.surfaceContainer;
        fg = enabled ? p.textPrimary : p.textTertiary;
        border = Border.all(color: p.hairline, width: 1.0);
        break;
      case PulsrButtonVariant.tonal:
        bg = enabled ? p.accentSoft : p.accentSoft.withValues(alpha: 0.4);
        fg = enabled ? p.accent : p.accent.withValues(alpha: 0.5);
        border = null;
        break;
      case PulsrButtonVariant.ghost:
        bg = Colors.transparent;
        fg = enabled ? p.textPrimary : p.textTertiary;
        border = null;
        break;
      case PulsrButtonVariant.destructive:
        bg = enabled ? p.errorSoft : p.errorSoft.withValues(alpha: 0.4);
        fg = enabled ? p.error : p.error.withValues(alpha: 0.5);
        border = Border.all(
          color: enabled ? p.error.withValues(alpha: 0.5) : p.hairline,
          width: 1.0,
        );
        break;
    }

    final labelWidget = Text(
      label,
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

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          SizedBox(
            width: _iconSize,
            height: _iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ] else if (icon != null) ...[
          Icon(icon, size: _iconSize, color: fg),
          const SizedBox(width: AppSpacing.xs),
        ],
        if (expand) Flexible(child: labelWidget) else labelWidget,
      ],
    );

    final visual = Container(
      constraints: BoxConstraints(minHeight: _height),
      padding: _padding.add(
        const EdgeInsets.symmetric(vertical: AppSpacing.s10),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.r12All,
        border: border,
      ),
      child: content,
    );

    // Keep the compact visual size but expand the interactive bounds to the
    // 48dp platform minimum so small buttons remain comfortably tappable.
    final buttonWidget = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppSpacing.minTouchTarget,
      ),
      child: Center(
        widthFactor: expand ? null : 1.0,
        child: visual,
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: PulsrPressable(
        onTap: enabled ? onPressed : null,
        child: buttonWidget,
      ),
    );
  }
}
