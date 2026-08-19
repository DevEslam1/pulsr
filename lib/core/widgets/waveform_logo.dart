// lib/core/widgets/waveform_logo.dart
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class WaveformLogo extends StatelessWidget {
  final double size;
  final Color? color;
  final bool animate;

  const WaveformLogo({
    super.key,
    this.size = 32,
    this.color,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? AppColors.primary;
    final barHeights = [0.35, 0.65, 1.0, 0.75, 0.45];

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveSize = size.isFinite && size > 0
            ? size
            : (constraints.biggest.shortestSide.isFinite && constraints.biggest.shortestSide > 0
                ? constraints.biggest.shortestSide
                : 48.0);

        return SizedBox(
          width: effectiveSize,
          height: effectiveSize,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(5, (index) {
              final barHeightRatio = barHeights[index];
              return Container(
                width: effectiveSize * 0.12,
                height: effectiveSize * barHeightRatio,
                decoration: BoxDecoration(
                  color: themeColor,
                  borderRadius: BorderRadius.circular(effectiveSize * 0.06),
                  boxShadow: [
                    BoxShadow(
                      color: themeColor.withValues(alpha: 0.3),
                      blurRadius: 4,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
