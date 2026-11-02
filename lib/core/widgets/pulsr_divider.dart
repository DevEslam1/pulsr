// lib/core/widgets/pulsr_divider.dart
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
  final bool fadeEnds;

  const PulsrDivider({
    super.key,
    this.vertical = false,
    this.indent,
    this.endIndent,
    this.thickness = 1.0,
    this.color,
    this.fadeEnds = false,
  });

  const PulsrDivider.inset({
    super.key,
    this.indent = 72.0,
    this.endIndent,
    this.thickness = 1.0,
    this.color,
    this.fadeEnds = false,
  }) : vertical = false;

  const PulsrDivider.gradient({
    super.key,
    this.vertical = false,
    this.indent,
    this.endIndent,
    this.thickness = 1.0,
    this.color,
  }) : fadeEnds = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lineColor = color ?? p.hairline;

    if (fadeEnds) {
      if (vertical) {
        return Padding(
          padding: EdgeInsets.only(
            top: indent ?? 0.0,
            bottom: endIndent ?? 0.0,
          ),
          child: SizedBox(
            width: thickness,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    lineColor,
                    lineColor,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.2, 0.8, 1.0],
                ),
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: EdgeInsetsDirectional.only(
          start: indent ?? 0.0,
          end: endIndent ?? 0.0,
        ),
        child: SizedBox(
          height: thickness,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [
                  Colors.transparent,
                  lineColor,
                  lineColor,
                  Colors.transparent,
                ],
                stops: const [0.0, 0.15, 0.85, 1.0],
              ),
            ),
          ),
        ),
      );
    }

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
