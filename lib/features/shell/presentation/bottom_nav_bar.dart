// lib/features/shell/presentation/bottom_nav_bar.dart
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class PulsrBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const PulsrBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.outline,
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onTap,
          backgroundColor: Colors.transparent,
          indicatorColor: AppColors.primary.withValues(alpha: 0.18),
          elevation: 0,
          height: 64,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.home_rounded, color: AppColors.primary),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.library_music_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.library_music_rounded, color: AppColors.primary),
              label: 'Library',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_rounded, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.search_rounded, color: AppColors.primary),
              label: 'Search',
            ),
            NavigationDestination(
              icon: Icon(Icons.queue_music_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.queue_music_rounded, color: AppColors.primary),
              label: 'Playlists',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.settings_rounded, color: AppColors.primary),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
