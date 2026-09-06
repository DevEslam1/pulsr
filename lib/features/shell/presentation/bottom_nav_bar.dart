import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';

class PulsrBottomNavBar extends StatelessWidget {
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

  List<({IconData activeIcon, IconData icon, String label})> _getItems(
          BuildContext context) =>
      [
        (
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: context.l10n.navHome
        ),
        (
          icon: Icons.library_music_outlined,
          activeIcon: Icons.library_music_rounded,
          label: context.l10n.navLibrary
        ),
        (
          icon: Icons.search_rounded,
          activeIcon: Icons.search_rounded,
          label: context.l10n.navSearch
        ),
        (
          icon: Icons.queue_music_outlined,
          activeIcon: Icons.queue_music_rounded,
          label: context.l10n.navPlaylists
        ),
        (
          icon: Icons.settings_outlined,
          activeIcon: Icons.settings_rounded,
          label: context.l10n.navSettings
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = context.isTablet;
    final items = _getItems(context);

    final double maxBarWidth = isTablet ? 620.0 : 540.0;
    final double barHeight = isTablet ? 68.0 : 64.0;
    final navRadius = BorderRadius.circular(isTablet ? 34 : 28);

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: includeSafeArea,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 24 : 14,
          2,
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
              onVerticalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v > 180) {
                  onSwipeDown?.call();
                } else if (v < -180) {
                  onSwipeUp?.call();
                }
              },
              child: SizedBox(
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
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (int i = 0; i < items.length; i++)
                            Expanded(
                              child: _NavTabItem(
                                item: items[i],
                                isSelected: currentIndex == i,
                                p: p,
                                isTablet: isTablet,
                                onTap: () {
                                  if (currentIndex != i) {
                                    HapticFeedback.selectionClick();
                                    onTap(i);
                                  }
                                },
                              ),
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
  final ({IconData activeIcon, IconData icon, String label}) item;
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(isTablet ? 22 : 18),
          splashColor: p.accent.withValues(alpha: 0.12),
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 10 : 6,
              vertical: 4,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: isSelected ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    isSelected ? item.activeIcon : item.icon,
                    size: iconSize,
                    color: isSelected ? p.accent : p.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: isTablet ? 11.5 : 10.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    color: isSelected
                        ? p.accent
                        : p.textTertiary.withValues(alpha: 0.85),
                    letterSpacing: 0.2,
                    fontFamily:
                        Theme.of(context).textTheme.bodySmall?.fontFamily,
                  ),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
