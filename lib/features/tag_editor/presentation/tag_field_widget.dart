// lib/features/tag_editor/tag_field_widget.dart
import 'package:flutter/material.dart';
import '../../../../../core/theme/aura_theme.dart';

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
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: initialValue,
            onChanged: onChanged,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hintText ?? 'Enter $label',
              hintStyle: TextStyle(
                color: p.textSecondary,
                fontSize: 13,
              ),
              prefixIcon: icon != null
                  ? Icon(icon, color: p.textSecondary, size: 20)
                  : null,
              filled: true,
              fillColor: p.surfaceContainer,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: p.accent, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

