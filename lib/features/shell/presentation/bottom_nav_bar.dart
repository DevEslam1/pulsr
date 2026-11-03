import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../core/motion/pulsr_motion.dart';
import '../../../core/performance/gpu_budget.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import 'nav_destinations.dart';

class PulsrBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback? onSwipeDown;
  final VoidCallback? onSwipeUp;
  final bool includeSafeArea;
  final bool iconOnly;
  final bool enableBlur;

  const PulsrBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onSwipeDown,
    this.onSwipeUp,
    this.includeSafeArea = true,
    this.iconOnly = false,
    this.enableBlur = false,
  });

  @override
  State<PulsrBottomNavBar> createState() => _PulsrBottomNavBarState();
}

class _PulsrBottomNavBarState extends State<PulsrBottomNavBar> {
  double _dragDy = 0;
  final ValueNotifier<double> _visualDyNotifier = ValueNotifier<double>(0.0);
  int _lastDragUpdateMs = 0;

  @override
  void dispose() {
    _visualDyNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = context.isTablet;
    final items = pulsrDestinations(context);

    final double maxBarWidth = isTablet ? 640.0 : 540.0;
    final double barHeight = widget.iconOnly ? 48.0 : (isTablet ? 68.0 : 64.0);
    final navRadius = isTablet
        ? AppRadii.r28All
        : (widget.iconOnly ? AppRadii.r20All : AppRadii.r24All);

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: widget.includeSafeArea,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          isTablet ? 24 : 12,
          3,
          isTablet ? 24 : 12,
          isTablet ? 12 : 8,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBarWidth),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart: (_) {
                _dragDy = 0;
                _lastDragUpdateMs = 0;
              },
              onVerticalDragUpdate: (d) {
                _dragDy += d.delta.dy;
                final now = DateTime.now().millisecondsSinceEpoch;
                if (now - _lastDragUpdateMs < 16) return;
                _lastDragUpdateMs = now;
                final target = (_dragDy * 0.20).clamp(-8.0, 8.0);
                if ((target - _visualDyNotifier.value).abs() > 0.5) {
                  _visualDyNotifier.value = target;
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
                _visualDyNotifier.value = 0;
              },
              onVerticalDragCancel: () {
                _dragDy = 0;
                _visualDyNotifier.value = 0;
              },
              child: ValueListenableBuilder<double>(
                valueListenable: _visualDyNotifier,
                builder: (context, visualDy, child) {
                  final isDraggingDock = visualDy.abs() > 0.5;
                  return AnimatedContainer(
                    duration: context.motionMs(120),
                    curve: context.motionCurve(Curves.easeOutCubic),
                    transform: Matrix4.translationValues(0, visualDy, 0),
                    height: barHeight,
                    decoration: BoxDecoration(
                      borderRadius: navRadius,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: p.isDark ? 0.38 : 0.09),
                          blurRadius: 18,
                          spreadRadius: -2,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: p.accent.withValues(
                            alpha: isDraggingDock
                                ? (p.isDark ? 0.14 : 0.08)
                                : (p.isDark ? 0.05 : 0.02),
                          ),
                          blurRadius: 14,
                          spreadRadius: -4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: navRadius,
                      child: Builder(
                        builder: (context) {
                          final navContainer = DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: navRadius,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  p.surfaceContainerHigh.withValues(
                                    alpha: widget.enableBlur ? 0.88 : 1.0,
                                  ),
                                  p.surfaceContainer.withValues(
                                    alpha: widget.enableBlur ? 0.84 : 1.0,
                                  ),
                                ],
                              ),
                              border: Border.all(
                                color: isDraggingDock
                                    ? p.accent.withValues(alpha: 0.35)
                                    : p.hairline,
                                width: 1.0,
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Subtle top inner specular highlight hairline
                                Positioned(
                                  top: 0,
                                  left: 24,
                                  right: 24,
                                  child: IgnorePointer(
                                    child: Container(
                                      height: 1,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white.withValues(alpha: 0.0),
                                            (p.isDark
                                                    ? Colors.white
                                                    : Colors.black)
                                                .withValues(
                                                    alpha:
                                                        p.isDark ? 0.12 : 0.04),
                                            Colors.white.withValues(alpha: 0.0),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Top gesture grab handle pill
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: IgnorePointer(
                                    child: AnimatedContainer(
                                      duration: context.motionMs(160),
                                      margin: const EdgeInsets.only(top: 3.5),
                                      width: isDraggingDock ? 32 : 24,
                                      height: 2.5,
                                      decoration: BoxDecoration(
                                        color: isDraggingDock
                                            ? p.accent.withValues(alpha: 0.65)
                                            : p.textTertiary
                                                .withValues(alpha: 0.24),
                                        borderRadius: AppRadii.r2All,
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xs,
                                    vertical: AppSpacing.xxs,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      for (int i = 0; i < items.length; i++)
                                        Expanded(
                                          child: _NavTabItem(
                                            item: items[i],
                                            index: i,
                                            isSelected:
                                                widget.currentIndex == i,
                                            p: p,
                                            isTablet: isTablet,
                                            iconOnly: widget.iconOnly,
                                            onTap: () => widget.onTap(i),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (!widget.enableBlur ||
                              GpuBudget.isGpuSaverActive) {
                            return navContainer;
                          }
                          return BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: navContainer,
                          );
                        },
                      ),
                    ),
                  );
                },
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
  final int index;
  final bool isSelected;
  final PulsrPalette p;
  final bool isTablet;
  final bool iconOnly;
  final VoidCallback onTap;

  const _NavTabItem({
    required this.item,
    required this.index,
    required this.isSelected,
    required this.p,
    required this.isTablet,
    required this.iconOnly,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double iconSize = isTablet ? 24.0 : 22.0;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final itemRadius = isTablet ? AppRadii.r22All : AppRadii.r18All;

    return Semantics(
      selected: isSelected,
      button: true,
      label: item.label,
      sortKey: OrdinalSortKey(index.toDouble()),
      child: Tooltip(
        message: item.label,
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            borderRadius: itemRadius,
            splashColor: p.accent.withValues(alpha: 0.12),
            highlightColor: Colors.transparent,
            child: AnimatedContainer(
              duration: context.motionMs(220),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
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
                          p.accent.withValues(alpha: p.isDark ? 0.24 : 0.18),
                          p.accent.withValues(alpha: p.isDark ? 0.08 : 0.05),
                        ],
                      )
                    : null,
                borderRadius: itemRadius,
                border: Border.all(
                  color: isSelected
                      ? p.accent.withValues(alpha: 0.38)
                      : Colors.transparent,
                  width: 1.1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: p.accent.withValues(alpha: 0.20),
                          blurRadius: 10,
                          spreadRadius: -2,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: iconOnly
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: context.motionMs(220),
                          curve: context.motionCurve(Curves.easeOutCubic),
                          height: 2,
                          width: isSelected ? 14 : 0,
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: p.accent,
                            borderRadius: AppRadii.r2All,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: p.accent.withValues(alpha: 0.55),
                                      blurRadius: 5,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        AnimatedScale(
                          scale: isSelected ? 1.12 : 1.0,
                          duration: context.motionMs(200),
                          curve: Curves.easeOutBack,
                          child: Icon(
                            isSelected ? item.activeIcon : item.icon,
                            size: iconSize,
                            color: isSelected ? p.accent : p.textTertiary,
                          ),
                        ),
                      ],
                    )
                  : MediaQuery.withClampedTextScaling(
                      minScaleFactor: 0.8,
                      maxScaleFactor: 1.4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Selection LED capsule: grows and lights up when active.
                          AnimatedContainer(
                            duration: context.motionMs(220),
                            curve: context.motionCurve(Curves.easeOutCubic),
                            height: 2.2,
                            width: isSelected ? 18 : 5,
                            margin:
                                const EdgeInsets.only(bottom: AppSpacing.s2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? p.accent
                                  : p.textTertiary.withValues(alpha: 0.22),
                              borderRadius: AppRadii.r2All,
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
                          const SizedBox(height: 1.5),
                          AnimatedDefaultTextStyle(
                            duration: context.motionMs(200),
                            style: TextStyle(
                              fontSize: isTablet
                                  ? AppFontSize.label
                                  : AppFontSize.caption,
                              height: 1.1,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: isSelected
                                  ? p.accent
                                  : p.textTertiary.withValues(alpha: 0.85),
                              letterSpacing: isRtl ? 0 : AppTracking.label,
                              fontFamily: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.fontFamily,
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
