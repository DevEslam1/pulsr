// lib/core/widgets/waveform_logo.dart
import 'package:flutter/material.dart';

class WaveformLogo extends StatefulWidget {
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
  State<WaveformLogo> createState() => _WaveformLogoState();
}

class _WaveformLogoState extends State<WaveformLogo>
    with TickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      )..repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(WaveformLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate && _controller == null) {
        _controller = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 800),
        )..repeat(reverse: true);
      } else if (!widget.animate) {
        _controller?.dispose();
        _controller = null;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.color ?? Colors.white;
    final barHeights = [0.35, 0.65, 1.0, 0.75, 0.45];

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveSize = widget.size.isFinite && widget.size > 0
            ? widget.size
            : (constraints.biggest.shortestSide.isFinite &&
                    constraints.biggest.shortestSide > 0
                ? constraints.biggest.shortestSide
                : 48.0);

        return SizedBox(
          width: effectiveSize,
          height: effectiveSize,
          child: _controller != null
              ? AnimatedBuilder(
                  animation: _controller!,
                  builder: (context, _) {
                    final t = _controller!.value;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final pulse = 0.85 + (t * 0.3) * ((index % 3) + 1) / 3;
                        final barHeightRatio = barHeights[index] * pulse;
                        return _buildBar(
                            effectiveSize, barHeightRatio, themeColor);
                      }),
                    );
                  },
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return _buildBar(
                        effectiveSize, barHeights[index], themeColor);
                  }),
                ),
        );
      },
    );
  }

  Widget _buildBar(
      double effectiveSize, double barHeightRatio, Color themeColor) {
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
  }
}
