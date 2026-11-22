import 'dart:math' as math;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_scroll_edge_fade.dart';
import '../../../../core/widgets/pulsr_section_header.dart';
import 'discovery_chip.dart';

/// Beat 3 on [HomeScreen]: Consolidated horizontal "Studio Tools" rail.
///
/// Unifies quick library/streaming shortcuts and audio/library studio tools
/// into one calm horizontal rail at the bottom of Home.
class StudioToolsRail extends StatelessWidget {
  final bool online;
  final bool showYtm;
  final VoidCallback onMore;

  const StudioToolsRail({
    super.key,
    required this.onMore,
    this.online = false,
    this.showYtm = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
    final railHeight = math.max(48.0, (48.0 * textScale).roundToDouble());

    final items =
        <({IconData icon, String label, Color color, VoidCallback onTap})>[
      if (online) ...[
        (
          icon: Icons.explore_rounded,
          label: context.l10n.ytmExplore,
          color: p.accent,
          onTap: () => context.push('/ytm-explore'),
        ),
        (
          icon: Icons.downloading_rounded,
          label: context.l10n.downloadsTitle,
          color: p.accent,
          onTap: () => context.push('/downloads'),
        ),
      ] else ...[
        (
          icon: Icons.person_rounded,
          label: context.l10n.artists,
          color: p.accent,
          onTap: () => context.push('/library?tab=artists'),
        ),
        (
          icon: Icons.album_rounded,
          label: context.l10n.albums,
          color: p.accent,
          onTap: () => context.push('/library?tab=albums'),
        ),
        (
          icon: Icons.folder_rounded,
          label: context.l10n.folders,
          color: p.accent,
          onTap: () => context.push('/library?tab=folders'),
        ),
        (
          icon: Icons.calendar_month_rounded,
          label: context.l10n.decades,
          color: p.accent,
          onTap: () => context.push('/year'),
        ),
        if (showYtm)
          (
            icon: Icons.downloading_rounded,
            label: context.l10n.downloadsTitle,
            color: p.accent,
            onTap: () => context.push('/downloads'),
          ),
      ],
      (
        icon: Icons.radio_rounded,
        label: context.l10n.radioTitle,
        color: p.accent,
        onTap: () => context.push('/radio'),
      ),
      (
        icon: Icons.queue_music_rounded,
        label: context.l10n.queue,
        color: p.accent,
        onTap: () => context.push('/queue'),
      ),
      (
        icon: Icons.group_rounded,
        label: context.l10n.partyListenTogether,
        color: p.accent,
        onTap: () => context.push('/party'),
      ),
      (
        icon: Icons.grid_view_rounded,
        label: context.l10n.artworkWall,
        color: p.accent,
        onTap: () => context.push('/artwork-grid'),
      ),
      (
        icon: Icons.insights_rounded,
        label: context.l10n.browseLibraryStats,
        color: p.warning,
        onTap: () => context.push('/library-stats'),
      ),
      (
        icon: Icons.cleaning_services_rounded,
        label: context.l10n.duplicateCleaner,
        color: p.success,
        onTap: () => context.push('/duplicate-finder'),
      ),
      (
        icon: Icons.palette_rounded,
        label: context.l10n.themeStudio,
        color: p.favorite,
        onTap: () => context.push('/theme-studio'),
      ),
    ];

    return Column(
      key: const ValueKey('home_studio_tools_rail'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PulsrSectionHeader(
          title: context.l10n.browseMoreTools,
          actionLabel: context.l10n.browseSeeAll,
          onAction: onMore,
        ),
        SizedBox(
          height: railHeight,
          child: PulsrScrollEdgeFade(
            extent: 44,
            child: ListView.separated(
              key: const ValueKey('studio_tools_horizontal_list'),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsetsDirectional.only(
                start: Adaptive.pagePadding(context),
                end: Adaptive.pagePadding(context) + AppSpacing.md,
              ),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppSpacing.s10),
              itemBuilder: (context, index) {
                final item = items[index];
                return Center(
                  child: DiscoveryChip(
                    icon: item.icon,
                    label: item.label,
                    iconColor: item.color,
                    onTap: item.onTap,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
