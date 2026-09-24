import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/theme/aura_theme.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import '../../../core/utils/adaptive.dart';
import 'nav_destinations.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class PulsrBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback? onSwipeDown;
  final VoidCallback? onSwipeUp;
  final bool includeSafeArea;

  const PulsrBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onSwipeDown,
    this.onSwipeUp,
    this.includeSafeArea = true,
  });

  @override
  State<PulsrBottomNavBar> createState() => _PulsrBottomNavBarState();
}

class _PulsrBottomNavBarState extends State<PulsrBottomNavBar> {
  double _dragDy = 0;
  double _visualDy = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = context.isTablet;
    final items = pulsrDestinations(context);

    final double maxBarWidth = isTablet ? 640.0 : 540.0;
    final double barHeight = isTablet ? 68.0 : 64.0;
    final navRadius = BorderRadius.circular(isTablet ? 28 : 24);

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: widget.includeSafeArea,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          isTablet ? 24 : 14,
          3,
          isTablet ? 24 : 14,
          isTablet ? 12 : 8,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBarWidth),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart: (_) => _dragDy = 0,
              onVerticalDragUpdate: (d) {
                _dragDy += d.delta.dy;
                final target = (_dragDy * 0.20).clamp(-8.0, 8.0);
                if ((target - _visualDy).abs() > 0.5) {
                  setState(() => _visualDy = target);
                }
              },
              onVerticalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (_dragDy > 20 || v > 80) {
                  widget.onSwipeDown?.call();
                } else if (_dragDy < -20 || v < -80) {
                  widget.onSwipeUp?.call();
                }
                _dragDy = 0;
                if (_visualDy != 0) {
                  setState(() => _visualDy = 0);
                }
              },
              onVerticalDragCancel: () {
                _dragDy = 0;
                if (_visualDy != 0) {
                  setState(() => _visualDy = 0);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(0, _visualDy, 0),
                height: barHeight,
                child: Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    borderRadius: navRadius,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: p.isDark ? 0.40 : 0.12),
                        blurRadius: 24,
                        spreadRadius: 0,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: p.accent.withValues(alpha: p.isDark ? 0.10 : 0.05),
                        blurRadius: 18,
                        spreadRadius: -2,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: navRadius,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: navRadius,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              p.surface.withValues(alpha: p.isDark ? 0.78 : 0.88),
                              p.surfaceContainer
                                  .withValues(alpha: p.isDark ? 0.72 : 0.84),
                            ],
                          ),
                          border: Border.all(
                            color: p.isDark
                                ? Colors.white.withValues(alpha: 0.14)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 1.2,
                          ),
                        ),
                        padding:
                            const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                margin: const EdgeInsets.only(top: 2),
                                width: 24,
                                height: 2.5,
                                decoration: BoxDecoration(
                                  color: p.textTertiary.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(1.5),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                for (int i = 0; i < items.length; i++)
                                  Expanded(
                                    child: _NavTabItem(
                                      item: items[i],
                                      isSelected: widget.currentIndex == i,
                                      p: p,
                                      isTablet: isTablet,
                                      onTap: () {
                                        if (widget.currentIndex != i) {
                                          HapticFeedback.selectionClick();
                                          widget.onTap(i);
                                        }
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTabItem extends StatelessWidget {
  final PulsrDestination item;
  final bool isSelected;
  final PulsrPalette p;
  final bool isTablet;
  final VoidCallback onTap;

  const _NavTabItem({
    required this.item,
    required this.isSelected,
    required this.p,
    required this.isTablet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double iconSize = isTablet ? 24.0 : 22.0;

    return Semantics(
      selected: isSelected,
      button: true,
      label: item.label,
      child: Tooltip(
        message: item.label,
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(isTablet ? 22 : 18),
            splashColor: p.accent.withValues(alpha: 0.12),
            highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: context.motionMs(250),
            curve: context.motionCurve(Curves.easeOutCubic),
            padding: EdgeInsets.symmetric(

              horizontal: isTablet ? 10 : 6,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        p.accent.withValues(alpha: 0.22),
                        p.accent.withValues(alpha: 0.08),
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(isTablet ? 22 : 18),
              border: isSelected
                  ? Border.all(
                      color: p.accent.withValues(alpha: 0.38),
                      width: 1.2,
                    )
                  : Border.all(color: Colors.transparent, width: 1.2),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: p.accent.withValues(alpha: 0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: MediaQuery.withClampedTextScaling(
              minScaleFactor: 0.8,
              maxScaleFactor: 1.15,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Selection indicator capsule: grows and lights up when active.
                  AnimatedContainer(
                    duration: context.motionMs(220),
                    curve: context.motionCurve(Curves.easeOutCubic),
                    height: 2,
                    width: isSelected ? 18 : 6,
                    margin: const EdgeInsets.only(bottom: AppSpacing.s2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? p.accent
                          : p.textTertiary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(AppRadii.r2),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: p.accent.withValues(alpha: 0.55),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  AnimatedScale(
                    scale: isSelected ? 1.08 : 1.0,
                    duration: context.motionMs(220),
                    curve: context.motionCurve(Curves.easeOutBack),
                    child: Icon(
                      isSelected ? item.activeIcon : item.icon,
                      size: iconSize,
                      color: isSelected ? p.accent : p.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  AnimatedDefaultTextStyle(
                    duration: context.motionMs(200),
                    style: TextStyle(
                      fontSize: isTablet ? AppFontSize.label : AppFontSize.tiny,
                      height: 1.1,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected
                          ? p.accent
                          : p.textTertiary.withValues(alpha: 0.85),
                      letterSpacing: AppTracking.label,
                      fontFamily:
                          Theme.of(context).textTheme.bodySmall?.fontFamily,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        item.label,
                        maxLines: 1,
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
    );
  }
}
