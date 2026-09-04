import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';

class PulsrBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const PulsrBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
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
    const navRadius = BorderRadius.vertical(top: Radius.circular(26));

    return Container(
      decoration: BoxDecoration(
        borderRadius: navRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.35 : 0.08),
            blurRadius: 18,
            spreadRadius: 0,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: navRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: p.surface.withValues(alpha: p.isDark ? 0.90 : 0.96),
              borderRadius: navRadius,
            ),
            child: SafeArea(
              top: false,
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    for (int i = 0; i < _getItems(context).length; i++)
                      Expanded(
                        child: _NavTabItem(
                          item: _getItems(context)[i],
                          isSelected: currentIndex == i,
                          p: p,
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
    );
  }
}

class _NavTabItem extends StatelessWidget {
  final ({IconData activeIcon, IconData icon, String label}) item;
  final bool isSelected;
  final PulsrPalette p;
  final VoidCallback onTap;

  const _NavTabItem({
    required this.item,
    required this.isSelected,
    required this.p,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected
                    ? p.accent.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedScale(
                scale: isSelected ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: Icon(
                  isSelected ? item.activeIcon : item.icon,
                  size: 22,
                  color: isSelected ? p.accent : p.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? p.accent
                    : p.textTertiary.withValues(alpha: 0.8),
                letterSpacing: 0.15,
                fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
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
    );
  }
}
