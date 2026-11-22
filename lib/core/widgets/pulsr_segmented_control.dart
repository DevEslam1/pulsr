// lib/core/widgets/pulsr_segmented_control.dart
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import 'pulsr_pressable.dart';

import '../utils/pulsr_haptics.dart';
/// {@category DesignSystem}
/// One option in a [PulsrSegmentedControl].
class PulsrSegment {
  final String label;
  final IconData icon;
  final int? count;

  const PulsrSegment({required this.label, required this.icon, this.count});
}

/// The app's single segmented control (Local/Online, Favorites tabs, playlist
/// filters). Replaces the four hand-rolled copies so the pill geometry, motion
/// and colours stay identical everywhere.
class PulsrSegmentedControl extends StatelessWidget {
  final List<PulsrSegment> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry? margin;
  final bool slidingIndicator;

  /// Measures segment labels and proportions segment widths to their
  /// content so labels are not truncated mid-word ("Syst..."). Segment
  /// icons are dropped and content is scaled uniformly down only when the
  /// available width is still too small. Opt-in; the default keeps the
  /// classic equal-width behaviour.
  final bool fitLabels;

  const PulsrSegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.margin,
    this.slidingIndicator = true,
    this.fitLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (segments.length < 2) return const SizedBox.shrink();

    final clampedIndex = selectedIndex.clamp(0, segments.length - 1);

    if (slidingIndicator) {
      return Container(
        margin: margin,
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: AppRadii.r20All,
          border: Border.all(color: p.hairline),
        ),
        child: ClipRRect(
          borderRadius: AppRadii.r20All,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final innerWidth = constraints.maxWidth;
              final segmentWidth = innerWidth / segments.length;

              // fitLabels: proportion segment widths to measured label
              // widths, dropping icons first when they no longer fit.
              var weights = List<int>.filled(segments.length, 1);
              var includeIcons = true;
              if (fitLabels) {
                final withIcons = _measuredWeights(context, withIcons: true);
                final totalWithIcons =
                    withIcons.fold<int>(0, (a, b) => a + b) / 100.0;
                includeIcons = totalWithIcons <= innerWidth;
                weights = includeIcons
                    ? withIcons
                    : _measuredWeights(context, withIcons: false);
              }
              final totalWeight = weights.fold<int>(0, (a, b) => a + b);
              double fractionStart(int index) {
                var sum = 0;
                for (var k = 0; k < index; k++) {
                  sum += weights[k];
                }
                return totalWeight == 0 ? 0 : sum / totalWeight;
              }

              return Stack(
                children: [
                  // Pill indicator matching Equalizer / AutoEq / Spatial & DSP
                  AnimatedPositionedDirectional(
                    duration: context.motionMs(260),
                    curve: context.motionCurve(Curves.easeOutCubic),
                    start: fitLabels
                        ? fractionStart(clampedIndex) * innerWidth
                        : clampedIndex * segmentWidth,
                    top: 0,
                    bottom: 0,
                    width: fitLabels
                        ? (weights[clampedIndex] / totalWeight) * innerWidth
                        : segmentWidth,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: p.accent,
                          borderRadius: AppRadii.r16All,
                        ),
                      ),
                    ),
                  ),
                  // Segments row
                  Row(
                    children: [
                      for (var i = 0; i < segments.length; i++)
                        Expanded(
                          flex: fitLabels ? weights[i] : 1,
                          child: Semantics(
                            selected: clampedIndex == i,
                            // Tell screen readers this is "1 of N" rather than
                            // a standalone selected button.
                            inMutuallyExclusiveGroup: true,
                            button: true,
                            label: segments[i].label,
                            onTap: () => onChanged(i),
                            excludeSemantics: true,
                            child: PulsrPressable(
                              pressedScale: 0.97,
                              enableHaptics: false,
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (clampedIndex != i) {
                                  PulsrHaptics.selectionClick();
                                  onChanged(i);
                                }
                              },
                              child: fitLabels
                                  ? _fitContent(
                                      context,
                                      i,
                                      clampedIndex,
                                      includeIcons,
                                    )
                                  : Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.xs,
                                        vertical: AppSpacing.s10,
                                      ),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minHeight:
                                              AppSpacing.minTouchTarget - 20,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              segments[i].icon,
                                              size: 16,
                                              color: clampedIndex == i
                                                  ? p.onAccent
                                                  : p.textSecondary,
                                            ),
                                            const SizedBox(
                                                width: AppSpacing.s6),
                                            Flexible(
                                              child: Text(
                                                segments[i].count != null
                                                    ? '${segments[i].label} (${segments[i].count})'
                                                    : segments[i].label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: AppFontSize.label,
                                                  fontWeight: clampedIndex == i
                                                      ? FontWeight.w700
                                                      : FontWeight.w600,
                                                  color: clampedIndex == i
                                                      ? p.onAccent
                                                      : p.textSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r20All,
        border: Border.all(color: p.hairline),
      ),
      child: ClipRRect(
        borderRadius: AppRadii.r20All,
        child: Row(
          children: [
            for (var i = 0; i < segments.length; i++)
              Expanded(
                child: _SegmentButton(
                  segment: segments[i],
                  isSelected: clampedIndex == i,
                  onTap: () {
                    if (clampedIndex != i) {
                      PulsrHaptics.selectionClick();
                      onChanged(i);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Measured flex weights for [fitLabels]: proportional to each
  /// segment's rendered label width (plus padding, and icon width when
  /// [withIcons]).
  List<int> _measuredWeights(BuildContext context, {required bool withIcons}) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    const style = TextStyle(
      fontSize: AppFontSize.label,
      fontWeight: FontWeight.w700,
    );
    return [
      for (final segment in segments)
        _measureLabel(
          text: segment.count != null
              ? '${segment.label} (${segment.count})'
              : segment.label,
          style: style,
          scaler: scaler,
          direction: direction,
          withIcons: withIcons,
        ),
    ];
  }

  int _measureLabel({
    required String text,
    required TextStyle style,
    required TextScaler scaler,
    required TextDirection direction,
    required bool withIcons,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      maxLines: 1,
      textScaler: scaler,
    )..layout();
    final width = painter.width +
        AppSpacing.sm * 2 +
        (withIcons ? 16 + AppSpacing.s6 : 0);
    painter.dispose();
    return math.max(1, (width * 100).round() + 1);
  }

  /// Segment content for [fitLabels]: laid out at its natural size and
  /// scaled down uniformly (never truncated mid-word) when space runs
  /// out.
  Widget _fitContent(
    BuildContext context,
    int index,
    int selectedIndex,
    bool includeIcons,
  ) {
    final p = context.palette;
    final segment = segments[index];
    final isSelected = selectedIndex == index;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.s10,
        ),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: AppSpacing.minTouchTarget - 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (includeIcons) ...[
                Icon(
                  segment.icon,
                  size: 16,
                  color: isSelected ? p.onAccent : p.textSecondary,
                ),
                const SizedBox(width: AppSpacing.s6),
              ],
              Text(
                segment.count != null
                    ? '${segment.label} (${segment.count})'
                    : segment.label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? p.onAccent : p.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final PulsrSegment segment;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.segment,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: AnimatedContainer(
          duration: context.motionMs(200),
          curve: context.motionCurve(Curves.easeOutCubic),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.s6,
          ),
          decoration: BoxDecoration(
            color: isSelected ? p.accent : Colors.transparent,
            borderRadius: AppRadii.r16All,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                segment.icon,
                size: 16,
                color: isSelected ? p.onAccent : p.textSecondary,
              ),
              const SizedBox(width: AppSpacing.s6),
              Flexible(
                child: Text(
                  segment.count != null
                      ? '${segment.label} (${segment.count})'
                      : segment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? p.onAccent : p.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      selected: isSelected,
      button: true,
      inMutuallyExclusiveGroup: true,
      label: segment.label,
      onTap: onTap,
      excludeSemantics: true,
      child: PulsrPressable(
        enableHaptics: false,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}
