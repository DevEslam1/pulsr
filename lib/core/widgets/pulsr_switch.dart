// lib/core/widgets/pulsr_switch.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../motion/pulsr_motion.dart';
import '../services/sound_feedback_service.dart';
import '../theme/aura_theme.dart';
import 'pulsr_pressable.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';

/// {@category DesignSystem}
enum PulsrSwitchSize {
  small,
  medium,
}

/// A unified, flagship-grade tactile toggle inspired by Apple iOS & Material 3.
///
/// Features:
/// - Smooth spring motion on track fill and thumb slide
/// - Dynamic luminous glow when active
/// - Hairline border when inactive for crisp contrast on dark/light surfaces
/// - Tactile micro-haptics on toggle
/// - Full accessibility semantics and Reduce Motion support
class PulsrSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? activeTrackColor;
  final Color? inactiveTrackColor;
  final Color? thumbColor;
  final PulsrSwitchSize size;
  final double width;
  final double height;

  const PulsrSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.thumbColor,
    this.size = PulsrSwitchSize.medium,
    double? width,
    double? height,
  })  : width = width ?? (size == PulsrSwitchSize.small ? 38.0 : 48.0),
        height = height ?? (size == PulsrSwitchSize.small ? 22.0 : 28.0);

  const PulsrSwitch.small({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.thumbColor,
    double? width,
    double? height,
  })  : size = PulsrSwitchSize.small,
        width = width ?? 38.0,
        height = height ?? 22.0;

  @override
  State<PulsrSwitch> createState() => _PulsrSwitchState();
}

class _PulsrSwitchState extends State<PulsrSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slideAnimation;
  bool _isPressed = false;
  bool _focused = false;

  bool get isEnabled => widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 220),
    );
    _slideAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(PulsrSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (!context.motionEnabled) {
        _controller.value = widget.value ? 1.0 : 0.0;
      } else {
        if (widget.value) {
          _controller.forward();
        } else {
          _controller.reverse();
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!isEnabled) return;
    HapticFeedback.lightImpact();
    SoundFeedbackService.playToggle();
    widget.onChanged!(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final activeFill =
        widget.activeTrackColor ?? widget.activeColor ?? p.accent;
    final inactiveFill = widget.inactiveTrackColor ??
        (p.isDark ? AppColors.specularAt(0.10) : AppColors.scrimAt(0.08));
    final thumbFill = widget.thumbColor ?? Colors.white;

    final thumbRadius = (widget.height - 6.0) / 2.0;
    final maxSlide = widget.width - widget.height;
    final direction =
        Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;

    return FocusableActionDetector(
      enabled: isEnabled,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _toggle();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      child: Semantics(
        toggled: widget.value,
        enabled: isEnabled,
        onTap: isEnabled ? _toggle : null,
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTapDown:
              isEnabled ? (_) => setState(() => _isPressed = true) : null,
          onTapUp: isEnabled
              ? (_) {
                  setState(() => _isPressed = false);
                  _toggle();
                }
              : null,
          onTapCancel:
              isEnabled ? () => setState(() => _isPressed = false) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppSpacing.minTouchTarget,
              minHeight: AppSpacing.minTouchTarget,
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Opacity(
                opacity: isEnabled ? 1.0 : 0.45,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final t = _controller.value;
                    final currentColor =
                        Color.lerp(inactiveFill, activeFill, t)!;

                    return Container(
                      width: widget.width,
                      height: widget.height,
                      padding: const EdgeInsets.all(3.0),
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.circular(widget.height / 2.0),
                        color: currentColor,
                        border: Border.all(
                          color: _focused
                              ? p.accent
                              : t > 0.5
                                  ? activeFill.withValues(alpha: 0.20)
                                  : p.hairline,
                          width: _focused ? 2.0 : 1.0,
                        ),
                        boxShadow: t > 0.01
                            ? [
                                BoxShadow(
                                  color: activeFill.withValues(alpha: 0.30 * t),
                                  blurRadius: 10 * t,
                                  spreadRadius: -1 * t,
                                  offset: Offset(0, 2 * t),
                                ),
                              ]
                            : null,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Transform.translate(
                          offset: Offset(
                              direction * _slideAnimation.value * maxSlide, 0),
                          child: AnimatedContainer(
                            duration: context.motionMs(140),
                            width: _isPressed
                                ? thumbRadius * 2.3
                                : thumbRadius * 2.0,
                            height: thumbRadius * 2.0,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: thumbFill,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.scrimAt(0.22),
                                  blurRadius: 4.0,
                                  offset: const Offset(0, 1.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A unified settings/dialog row containing a [PulsrSwitch] with modern typography,
/// tactile press response, and optional feature info action.
class PulsrSwitchListTile extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry? contentPadding;
  final VoidCallback? onInfoTap;
  final String? disabledReason;

  const PulsrSwitchListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.contentPadding,
    this.onInfoTap,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDisabled = onChanged == null || disabledReason != null;

    return PulsrPressable(
      onTap: isDisabled ? onInfoTap : () => onChanged?.call(!value),
      pressedScale: 0.985,
      child: Padding(
        padding: contentPadding ??
            const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.s10),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.s14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            fontSize: AppFontSize.body,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                            letterSpacing: AppTracking.title,
                          ),
                          child: title,
                        ),
                      ),
                      if (onInfoTap != null) ...[
                        const SizedBox(width: AppSpacing.s6),
                        GestureDetector(
                          onTap: onInfoTap,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.s2),
                            child: Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: p.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: p.textSecondary,
                        height: 1.3,
                      ),
                      child: subtitle!,
                    ),
                  ],
                  if (disabledReason != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      disabledReason!,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600,
                        color: p.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PulsrSwitch(
              value: value,
              onChanged: isDisabled ? null : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
