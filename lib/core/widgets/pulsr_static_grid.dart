import 'package:flutter/material.dart';

/// {@category DesignSystem}
/// A static, non-scrollable grid layout implemented via [Column], [Row], and [AspectRatio]/[SizedBox].
///
/// Unlike [GridView.builder] with `shrinkWrap: true` and [NeverScrollableScrollPhysics],
/// this widget does not instantiate an internal [Scrollable] or [RenderViewport].
/// It avoids the Flutter framework assertion error:
/// "Vertical viewport was given unbounded height"
/// when placed inside a parent [ListView], [SingleChildScrollView], or unconstrained flex box.
class PulsrStaticGrid extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double? childAspectRatio;
  final double? mainAxisExtent;
  final EdgeInsetsGeometry? padding;
  final IndexedWidgetBuilder itemBuilder;

  const PulsrStaticGrid({
    super.key,
    required this.itemCount,
    required this.crossAxisCount,
    this.crossAxisSpacing = 0,
    this.mainAxisSpacing = 0,
    this.childAspectRatio,
    this.mainAxisExtent,
    this.padding,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 0 || crossAxisCount <= 0) return const SizedBox.shrink();
    final rowCount = (itemCount / crossAxisCount).ceil();

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int r = 0; r < rowCount; r++) ...[
          if (r > 0) SizedBox(height: mainAxisSpacing),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int c = 0; c < crossAxisCount; c++) ...[
                if (c > 0) SizedBox(width: crossAxisSpacing),
                Expanded(
                  child: (r * crossAxisCount + c < itemCount)
                      ? _buildItem(context, r * crossAxisCount + c)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );

    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    return content;
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = itemBuilder(context, index);
    if (mainAxisExtent != null) {
      return SizedBox(
        height: mainAxisExtent,
        child: item,
      );
    }
    return AspectRatio(
      aspectRatio: childAspectRatio ?? 1.0,
      child: item,
    );
  }
}
