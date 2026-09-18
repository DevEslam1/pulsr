// lib/core/widgets/pulsr_segmented_control.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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

  const PulsrSegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (segments.length < 2) return const SizedBox.shrink();

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.r16),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.s6),
            Expanded(
              child: _SegmentButton(
                segment: segments[i],
                isSelected: selectedIndex == i,
                onTap: () {
                  if (selectedIndex != i) {
                    HapticFeedback.selectionClick();
                    onChanged(i);
                  }
                },
              ),
            ),
          ],
        ],
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
    final content = AnimatedContainer(
      duration: context.motionMs(200),
      curve: context.motionCurve(Curves.easeOutCubic),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.s10),
      decoration: BoxDecoration(
        color: isSelected ? p.accentContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.r12),
        border: Border.all(
          color: isSelected ? p.accent.withValues(alpha: 0.38) : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            segment.icon,
            size: 16,
            color: isSelected ? p.accent : p.textSecondary,
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
                fontSize: AppFontSize.bodySmall,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? p.accent : p.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      selected: isSelected,
      button: true,
      label: segment.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}
