// lib/core/widgets/pulsr_scroll_edge_fade.dart
import 'package:material_ui/material_ui.dart';
import '../constants/app_colors.dart';

/// Fades the trailing edge (and optionally leading edge) of horizontally
/// scrolling content so a clipped chip, tab, or filter reads as "more to the
/// right" instead of "broken layout".
///
/// LTR fades the right edge; RTL fades the left edge. When [fadeColor] is
/// provided (recommended for strips over solid backgrounds), it overlays an
/// [IgnorePointer] gradient box with zero offscreen `saveLayer` cost. When
/// [fadeColor] is null, it falls back to a [ShaderMask] for translucent or
/// patterned surfaces.
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
    this.fadeColor,
  });

  final Widget child;

  /// Width of the faded strip in logical pixels.
  final double extent;

  /// Set false when the strip is known to fit (e.g. four evenly-sized tabs).
  final bool enabled;

  /// Optionally fades the leading edge as well for centered carousels.
  final bool fadeLeading;

  /// Solid background colour behind the scrollable strip. When non-null, avoids
  /// allocating a [ShaderMask] offscreen `saveLayer` on every scroll frame.
  final Color? fadeColor;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final solidColor = fadeColor;
    if (solidColor != null) {
      final transparent = solidColor.withValues(alpha: 0.0);
      final mid = solidColor.withValues(alpha: 0.55);
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          child,
          if (fadeLeading)
            PositionedDirectional(
              top: 0,
              bottom: 0,
              start: 0,
              width: extent,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: AlignmentDirectional.centerStart,
                      end: AlignmentDirectional.centerEnd,
                      colors: [solidColor, mid, transparent],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          PositionedDirectional(
            top: 0,
            bottom: 0,
            end: 0,
            width: extent,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [transparent, mid, solidColor],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
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
              AppColors.fadeStopTransparent,
              AppColors.fadeStopMid,
              AppColors.fadeStopOpaque,
              AppColors.fadeStopOpaque,
              AppColors.fadeStopMid,
              AppColors.fadeStopTransparent,
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
            AppColors.fadeStopOpaque,
            AppColors.fadeStopOpaque,
            AppColors.fadeStopMid,
            AppColors.fadeStopTransparent,
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
