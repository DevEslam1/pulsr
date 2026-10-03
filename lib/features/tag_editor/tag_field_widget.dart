// lib/features/tag_editor/tag_field_widget.dart
import 'package:flutter/material.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class TagFieldWidget extends StatefulWidget {
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
  State<TagFieldWidget> createState() => _TagFieldWidgetState();
}

class _TagFieldWidgetState extends State<TagFieldWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void didUpdateWidget(covariant TagFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.initialValue ?? '';
    // P0-5: `TextFormField(initialValue:)` only seeds the field once, so undo
    // and auto-fill updates never reached it. Adopt the new model value here.
    // The guard against an identical value prevents a feedback loop with
    // [onChanged]-driven cubit emissions (which carry the text we already have).
    if (incoming == _controller.text) return;
    _controller.value = TextEditingValue(
      text: incoming,
      selection: TextSelection.collapsed(offset: incoming.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.bodySmall,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          TextFormField(
            controller: _controller,
            onChanged: widget.onChanged,
            keyboardType: widget.keyboardType,
            maxLines: widget.maxLines,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: widget.hintText ??
                  '${context.l10n.browseEnter} ${widget.label}',
              hintStyle: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.bodySmall,
              ),
              prefixIcon: widget.icon != null
                  ? Icon(widget.icon, color: p.textSecondary, size: 20)
                  : null,
              filled: true,
              fillColor: p.surfaceContainer,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.s14),
              border: OutlineInputBorder(
                borderRadius: AppRadii.r14All,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.r14All,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadii.r14All,
                borderSide: BorderSide(color: p.accent, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
