import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/pulsr_logo.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';

class LandscapeSidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool isExtended;
  final VoidCallback onToggleExtended;
  final VoidCallback? onOpenNowPlaying;
  final VoidCallback? onToggleSideInspector;
  final bool isSideInspectorOpen;

  const LandscapeSidebar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.isExtended,
    required this.onToggleExtended,
    this.onOpenNowPlaying,
    this.onToggleSideInspector,
    this.isSideInspectorOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = isExtended ? 240.0 : 76.0;
    final targetContentWidth = isExtended ? 240.0 : 76.0;

    final primaryItems = [
      (
        index: 0,
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: context.l10n.navHome,
      ),
      (
        index: 1,
        icon: Icons.library_music_outlined,
        activeIcon: Icons.library_music_rounded,
        label: context.l10n.navLibrary,
      ),
      (
        index: 2,
        icon: Icons.search_rounded,
        activeIcon: Icons.search_rounded,
        label: context.l10n.navSearch,
      ),
    ];

    final secondaryItems = [
      (
        index: 3,
        icon: Icons.queue_music_outlined,
        activeIcon: Icons.queue_music_rounded,
        label: context.l10n.navPlaylists,
      ),
      (
        index: 4,
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded,
        label: context.l10n.navSettings,
      ),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: width,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(
          right: BorderSide(
            color: p.hairline.withValues(alpha: p.isDark ? 0.35 : 0.16),
            width: 1,
          ),
        ),
      ),
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: targetContentWidth,
                height: constraints.maxHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Brand Header ──────────────────────────────────────────
                    _SidebarBrandHeader(
                      isExtended: isExtended,
                      onToggle: onToggleExtended,
                      p: p,
                    ),

                    const SizedBox(height: 6),

                    // ── Main Scrollable Nav List ──────────────────────────────
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.symmetric(
                          horizontal: isExtended ? 12 : 8,
                          vertical: 4,
                        ),
                        children: [
                          if (isExtended)
                            _SectionHeader(title: 'BROWSE', p: p),
                          for (final item in primaryItems) ...[
                            _SidebarNavItem(
                              icon: item.icon,
                              activeIcon: item.activeIcon,
                              label: item.label,
                              isSelected: currentIndex == item.index,
                              isExtended: isExtended,
                              p: p,
                              onTap: () {
                                if (currentIndex != item.index) {
                                  HapticFeedback.selectionClick();
                                  onDestinationSelected(item.index);
                                }
                              },
                            ),
                            const SizedBox(height: 4),
                          ],

                          const SizedBox(height: 10),
                          if (isExtended)
                            _SectionHeader(title: 'COLLECTION', p: p)
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: p.hairline.withValues(alpha: 0.3),
                              ),
                            ),

                          for (final item in secondaryItems) ...[
                            _SidebarNavItem(
                              icon: item.icon,
                              activeIcon: item.activeIcon,
                              label: item.label,
                              isSelected: currentIndex == item.index,
                              isExtended: isExtended,
                              p: p,
                              onTap: () {
                                if (currentIndex != item.index) {
                                  HapticFeedback.selectionClick();
                                  onDestinationSelected(item.index);
                                }
                              },
                            ),
                            const SizedBox(height: 4),
                          ],

                          // Optional Side Inspector (Queue/Lyrics) Shortcut
                          if (onToggleSideInspector != null) ...[
                            const SizedBox(height: 10),
                            if (isExtended)
                              _SectionHeader(title: 'PANEL', p: p)
                            else
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: p.hairline.withValues(alpha: 0.3),
                                ),
                              ),
                            _SidebarNavItem(
                              icon: Icons.vertical_split_outlined,
                              activeIcon: Icons.vertical_split_rounded,
                              label: 'Side Panel',
                              isSelected: isSideInspectorOpen,
                              isExtended: isExtended,
                              p: p,
                              trailingBadge:
                                  isExtended && isSideInspectorOpen ? 'ON' : null,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onToggleSideInspector!();
                              },
                            ),
                          ],
                        ],
                      ),
                    ),

                    // ── Bottom Section: Active Song Badge & Collapse Toggle ────
                    _SidebarBottomSection(
                      isExtended: isExtended,
                      p: p,
                      onOpenNowPlaying: onOpenNowPlaying,
                      onToggleExtended: onToggleExtended,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SidebarBrandHeader extends StatelessWidget {
  final bool isExtended;
  final VoidCallback onToggle;
  final PulsrPalette p;

  const _SidebarBrandHeader({
    required this.isExtended,
    required this.onToggle,
    required this.p,
  });

  @override
  Widget build(BuildContext context) {
    if (!isExtended) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Center(
          child: GestureDetector(
            onTap: onToggle,
            child: Tooltip(
              message: 'Expand sidebar',
              child: PulsrLogo(
                size: 32,
                color: p.accent,
                glowColor: p.glow,
                animate: false,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
      child: ClipRect(
        child: Row(
          children: [
            PulsrLogo(
              size: 32,
              color: p.accent,
              glowColor: p.glow,
              animate: false,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PULSR',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.4,
                      fontSize: 15.5,
                    ),
                  ),
                  Text(
                    'STUDIO AUDIO',
                    style: TextStyle(
                      color: p.accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      fontSize: 9.0,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Collapse sidebar',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.keyboard_double_arrow_left_rounded,
                color: p.textTertiary,
              ),
              onPressed: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final PulsrPalette p;

  const _SectionHeader({required this.title, required this.p});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10.0,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: p.textTertiary.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final bool isExtended;
  final PulsrPalette p;
  final VoidCallback onTap;
  final String? trailingBadge;

  const _SidebarNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.isExtended,
    required this.p,
    required this.onTap,
    this.trailingBadge,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = p.accent;

    if (!isExtended) {
      return Center(
        child: Tooltip(
          message: label,
          waitDuration: const Duration(milliseconds: 350),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              splashColor: activeColor.withValues(alpha: 0.15),
              highlightColor: Colors.transparent,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor.withValues(alpha: p.isDark ? 0.18 : 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: isSelected
                      ? Border.all(
                          color: activeColor.withValues(alpha: 0.35),
                          width: 1.2,
                        )
                      : Border.all(color: Colors.transparent, width: 1.2),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.20),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: AnimatedScale(
                    scale: isSelected ? 1.08 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      isSelected ? activeIcon : icon,
                      size: 23,
                      color: isSelected ? activeColor : p.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: activeColor.withValues(alpha: 0.12),
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: p.isDark ? 0.14 : 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(
                    color: activeColor.withValues(alpha: 0.30),
                    width: 1.0,
                  )
                : Border.all(color: Colors.transparent, width: 1.0),
          ),
          child: ClipRect(
            child: Row(
              children: [
                // Indicator Bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 3.5,
                  height: isSelected ? 18 : 0,
                  decoration: BoxDecoration(
                    color: isSelected ? activeColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.6),
                              blurRadius: 5,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),

                // Icon
                AnimatedScale(
                  scale: isSelected ? 1.06 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    isSelected ? activeIcon : icon,
                    size: 21,
                    color: isSelected ? activeColor : p.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),

                // Label
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? activeColor : p.textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),

                // Trailing Badge (e.g. Side Panel 'ON')
                if (trailingBadge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: activeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      trailingBadge!,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: activeColor,
                        letterSpacing: 0.8,
                      ),
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

class _SidebarBottomSection extends StatelessWidget {
  final bool isExtended;
  final PulsrPalette p;
  final VoidCallback? onOpenNowPlaying;
  final VoidCallback onToggleExtended;

  const _SidebarBottomSection({
    required this.isExtended,
    required this.p,
    required this.onOpenNowPlaying,
    required this.onToggleExtended,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.currentSong?.id != curr.currentSong?.id ||
          prev.currentSong?.title != curr.currentSong?.title ||
          prev.isPlaying != curr.isPlaying,
      builder: (context, state) {
        final song = state.currentSong;

        return Padding(
          padding: EdgeInsets.fromLTRB(
            isExtended ? 12 : 8,
            8,
            isExtended ? 12 : 8,
            12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Now Playing Mini Badge (if active song exists)
              if (song != null) ...[
                if (!isExtended)
                  Tooltip(
                    message: '${song.title} - ${song.artist}',
                    child: GestureDetector(
                      onTap: onOpenNowPlaying,
                      child: Container(
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: state.isPlaying
                                ? p.accent.withValues(alpha: 0.6)
                                : p.hairline,
                            width: 1.2,
                          ),
                          boxShadow: state.isPlaying
                              ? [
                                  BoxShadow(
                                    color: p.accent.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: CachedArtwork(
                            id: song.id,
                            remoteUrl: song.remoteArtworkUrl,
                            type: ArtworkType.AUDIO,
                            size: 44,
                            borderRadius: 11,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: onOpenNowPlaying,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: p.hairline.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: ClipRect(
                        child: Row(
                          children: [
                            CachedArtwork(
                              id: song.id,
                              remoteUrl: song.remoteArtworkUrl,
                              type: ArtworkType.AUDIO,
                              size: 28,
                              borderRadius: 6,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: p.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (state.isPlaying)
                              Icon(
                                Icons.graphic_eq_rounded,
                                size: 16,
                                color: p.accent,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],

              // Expand / Collapse Bottom Trigger (for collapsed mode)
              if (!isExtended)
                IconButton(
                  tooltip: 'Expand sidebar',
                  iconSize: 20,
                  icon: Icon(
                    Icons.keyboard_double_arrow_right_rounded,
                    color: p.textTertiary,
                  ),
                  onPressed: onToggleExtended,
                ),
            ],
          ),
        );
      },
    );
  }
}
