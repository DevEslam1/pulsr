// lib/core/widgets/pulsr_text_field.dart
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';

/// {@category DesignSystem}
/// Standardized text input field for the Pulsr design system.
class PulsrTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? hint;
  final String? label;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscure;
  final TextInputType type;
  final String? error;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;

  const PulsrTextField({
    super.key,
    this.controller,
    this.hint,
    this.label,
    this.prefixIcon,
    this.suffix,
    this.obscure = false,
    this.type = TextInputType.text,
    this.error,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
  }) : assert(
            !obscure || maxLines == 1, 'obscure fields must use maxLines == 1');

  @override
  State<PulsrTextField> createState() => _PulsrTextFieldState();
}

class _PulsrTextFieldState extends State<PulsrTextField> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _isFocused = _focusNode.hasFocus;
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted && _isFocused != _focusNode.hasFocus) {
      setState(() => _isFocused = _focusNode.hasFocus);
    }
  }

  @override
  void didUpdateWidget(covariant PulsrTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      if (_ownsFocusNode) {
        _focusNode.dispose();
        _ownsFocusNode = false;
      }
      if (widget.focusNode != null) {
        _focusNode = widget.focusNode!;
      } else {
        _focusNode = FocusNode();
        _ownsFocusNode = true;
      }
      _isFocused = _focusNode.hasFocus;
      _focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasError = widget.error != null && widget.error!.isNotEmpty;
    final activeTone = hasError ? p.error : p.accent;

    final border = OutlineInputBorder(
      borderRadius: AppRadii.r14All,
      borderSide: BorderSide(
        color: p.isDark ? AppColors.specularAt(0.12) : p.borderSubtle,
        width: 1.0,
      ),
    );

    final focusedBorder = OutlineInputBorder(
      borderRadius: AppRadii.r14All,
      borderSide: BorderSide(color: p.accent, width: 1.5),
    );

    final errorBorder = OutlineInputBorder(
      borderRadius: AppRadii.r14All,
      borderSide: BorderSide(color: p.error, width: 1.4),
    );

    final focusedErrorBorder = OutlineInputBorder(
      borderRadius: AppRadii.r14All,
      borderSide: BorderSide(color: p.error, width: 1.6),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.s4,
              bottom: AppSpacing.s6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: context.motionMs(160),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.label,
                      color: hasError
                          ? p.error
                          : (_isFocused ? p.accent : p.textSecondary),
                    ),
                    child: Text(widget.label!),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedContainer(
                  duration: context.motionMs(180),
                  width: _isFocused || hasError ? 5.0 : 0.0,
                  height: _isFocused || hasError ? 5.0 : 0.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeTone,
                  ),
                ),
              ],
            ),
          ),
        ],
        AnimatedContainer(
          duration: context.motionMs(180),
          curve: context.motionCurve(PulsrMotion.enter),
          decoration: BoxDecoration(
            borderRadius: AppRadii.r14All,
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: activeTone.withValues(
                        alpha: p.isDark ? 0.18 : 0.10,
                      ),
                      blurRadius: 14,
                      spreadRadius: -2,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: p.isDark ? 0.14 : 0.03,
                      ),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            obscureText: widget.obscure,
            keyboardType: widget.type,
            maxLines: widget.maxLines,
            readOnly: widget.readOnly,
            onTap: widget.onTap,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
            cursorColor: activeTone,
            cursorWidth: 1.8,
            cursorRadius: const Radius.circular(2),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(
                fontFamily: 'Manrope',
                fontSize: AppFontSize.body,
                fontWeight: FontWeight.w500,
                color: p.textTertiary,
              ),
              prefixIcon: widget.prefixIcon != null
                  ? AnimatedScale(
                      scale: _isFocused ? 1.08 : 1.0,
                      duration: context.motionMs(180),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        widget.prefixIcon,
                        size: 20.0,
                        color: hasError
                            ? p.error
                            : (_isFocused ? p.accent : p.textSecondary),
                      ),
                    )
                  : null,
              suffixIcon: widget.suffix,
              filled: true,
              fillColor:
                  _isFocused ? p.surfaceContainerHigh : p.surfaceContainer,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              enabledBorder: border,
              focusedBorder: focusedBorder,
              errorBorder: errorBorder,
              focusedErrorBorder: focusedErrorBorder,
              errorText: widget.error,
              errorStyle: TextStyle(
                fontFamily: 'Manrope',
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w700,
                color: p.error,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
