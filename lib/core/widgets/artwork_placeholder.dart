// lib/core/widgets/artwork_placeholder.dart
import 'package:flutter/material.dart';
import '../theme/aura_theme.dart';
import 'waveform_logo.dart';

class ArtworkPlaceholder extends StatelessWidget {
  final double size;
  final double borderRadius;
  final IconData? icon;

  const ArtworkPlaceholder({
    super.key,
    this.size = 56.0,
    this.borderRadius = 12.0,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isBounded = size.isFinite && size > 0;
        final effectiveSize = isBounded
            ? size
            : (constraints.biggest.shortestSide.isFinite &&
                    constraints.biggest.shortestSide > 0
                ? constraints.biggest.shortestSide
                : 56.0);

        final effectiveBorderRadius =
            borderRadius.isFinite ? borderRadius : 12.0;

        return Container(
          width: isBounded ? effectiveSize : null,
          height: isBounded ? effectiveSize : null,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(effectiveBorderRadius),
            gradient: LinearGradient(
              colors: [
                p.surfaceContainer,
                p.surfaceContainerHigh,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: p.hairline.withValues(alpha: 0.8),
              width: 1,
            ),
          ),
          child: Center(
            child: icon != null
                ? Icon(
                    icon,
                    color: p.accent.withValues(alpha: 0.8),
                    size: effectiveSize * 0.45,
                  )
                : WaveformLogo(
                    size: effectiveSize * 0.45,
                    color: p.accent.withValues(alpha: 0.8),
                  ),
          ),
        );
      },
    );
  }
}
