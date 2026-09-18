// lib/features/tag_editor/tag_field_widget.dart
import 'package:flutter/material.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class TagFieldWidget extends StatelessWidget {
  final String label;
  final String? initialValue;
  final ValueChanged<String> onChanged;
  final IconData? icon;
  final TextInputType keyboardType;
  final int maxLines;
  final String? hintText;

  const TagFieldWidget({
    super.key,
    required this.label,
    this.initialValue,
    required this.onChanged,
    this.icon,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.bodySmall,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          TextFormField(
            initialValue: initialValue,
            onChanged: onChanged,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hintText ?? '${context.l10n.browseEnter} $label',
              hintStyle: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.bodySmall,
              ),
              prefixIcon: icon != null
                  ? Icon(icon, color: p.textSecondary, size: 20)
                  : null,
              filled: true,
              fillColor: p.surfaceContainer,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.r14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.r14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.r14),
                borderSide: BorderSide(color: p.accent, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
