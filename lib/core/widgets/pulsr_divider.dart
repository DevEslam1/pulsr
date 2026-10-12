import 'package:flutter/material.dart';
import '../theme/aura_theme.dart';

/// {@category DesignSystem}
/// Consistent separator line for Pulsr, adhering to [PulsrPalette.hairline].
class PulsrDivider extends StatelessWidget {
  final bool vertical;
  final double? indent;
  final double? endIndent;
  final double thickness;
  final Color? color;

  const PulsrDivider({
    super.key,
    this.vertical = false,
    this.indent,
    this.endIndent,
    this.thickness = 1.0,
    this.color,
  });

  const PulsrDivider.inset({
    super.key,
    this.indent = 72.0,
    this.endIndent,
    this.thickness = 1.0,
    this.color,
  }) : vertical = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lineColor = color ?? p.hairline;

    if (vertical) {
      return VerticalDivider(
        width: thickness,
        thickness: thickness,
        indent: indent,
        endIndent: endIndent,
        color: lineColor,
      );
    }

    return Divider(
      height: thickness,
      thickness: thickness,
      indent: indent,
      endIndent: endIndent,
      color: lineColor,
    );
  }
}
