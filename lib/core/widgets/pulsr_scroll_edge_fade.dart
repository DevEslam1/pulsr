// lib/core/widgets/pulsr_scroll_edge_fade.dart
import 'package:flutter/material.dart';

/// Fades the trailing edge (and optionally leading edge) of horizontally
/// scrolling content so a clipped chip, tab, or filter reads as "more to the
/// right" instead of "broken layout".
///
/// LTR fades the right edge; RTL fades the left edge. The fade is a
/// [ShaderMask] over the child, so it costs no extra paint layer and works with
/// any scrollable (ListView, SingleChildScrollView, TabBar).
///
/// Use this around every horizontal strip that can overflow:
/// Home discovery chips, Search filters, Settings categories, Library tabs.
class PulsrScrollEdgeFade extends StatelessWidget {
  const PulsrScrollEdgeFade({
    super.key,
    required this.child,
    this.extent = 28,
    this.enabled = true,
    this.fadeLeading = false,
  });

  final Widget child;

  /// Width of the faded strip in logical pixels.
  final double extent;

  /// Set false when the strip is known to fit (e.g. four evenly-sized tabs).
  final bool enabled;

  /// Optionally fades the leading edge as well for centered carousels.
  final bool fadeLeading;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final fade = rect.width <= 0
            ? 1.0
            : (extent / rect.width).clamp(0.0, 0.45).toDouble();

        if (fadeLeading) {
          return LinearGradient(
            begin: isRtl ? Alignment.centerRight : Alignment.centerLeft,
            end: isRtl ? Alignment.centerLeft : Alignment.centerRight,
            colors: const [
              Color(0x00FFFFFF),
              Color(0xB3FFFFFF),
              Color(0xFFFFFFFF),
              Color(0xFFFFFFFF),
              Color(0xB3FFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: [
              0.0,
              fade * 0.55,
              fade,
              1.0 - fade,
              1.0 - (fade * 0.55),
              1.0,
            ],
          ).createShader(rect);
        }

        // Eased 4-stop alpha falloff prevents a visible hard line where the fade begins
        return LinearGradient(
          begin: isRtl ? Alignment.centerRight : Alignment.centerLeft,
          end: isRtl ? Alignment.centerLeft : Alignment.centerRight,
          colors: const [
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0xB3FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [
            0.0,
            1.0 - fade,
            1.0 - (fade * 0.45),
            1.0,
          ],
        ).createShader(rect);
      },
      child: child,
    );
  }
}
