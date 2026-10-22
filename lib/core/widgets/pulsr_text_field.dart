import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../theme/aura_theme.dart';

/// {@category DesignSystem}
/// Standardized text input field for the Pulsr design system.
///
/// Features unified surface styling, smooth focus transitions, icon adornments,
/// and responsive error formatting.
class PulsrTextField extends StatelessWidget {
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
  }) : assert(!obscure || maxLines == 1,
            'obscure fields must use maxLines == 1');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final border = OutlineInputBorder(
      borderRadius: AppRadii.r12All,
      borderSide: BorderSide(color: p.borderSubtle, width: 1.0),
    );

    final focusedBorder = OutlineInputBorder(
      borderRadius: AppRadii.r12All,
      borderSide: BorderSide(color: p.accent, width: 1.6),
    );

    final errorBorder = OutlineInputBorder(
      borderRadius: AppRadii.r12All,
      borderSide: BorderSide(color: p.error, width: 1.4),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.s4,
              bottom: AppSpacing.s6,
            ),
            child: Text(
              label!,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: AppFontSize.label,
                fontWeight: FontWeight.w700,
                color: p.textSecondary,
              ),
            ),
          ),
        ],
        TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          obscureText: obscure,
          keyboardType: type,
          maxLines: maxLines,
          readOnly: readOnly,
          onTap: onTap,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: AppFontSize.body,
            fontWeight: FontWeight.w500,
            color: p.textPrimary,
          ),
          cursorColor: p.accent,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: 'Manrope',
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w400,
              color: p.textTertiary,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 20.0, color: p.textSecondary)
                : null,
            suffixIcon: suffix,
            filled: true,
            fillColor: p.surfaceContainer,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            enabledBorder: border,
            focusedBorder: focusedBorder,
            errorBorder: errorBorder,
            focusedErrorBorder: errorBorder,
            errorText: error,
            errorStyle: TextStyle(
              fontFamily: 'Manrope',
              fontSize: AppFontSize.caption,
              color: p.error,
            ),
          ),
        ),
      ],
    );
  }
}
