import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_scroll_edge_fade.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'discovery_chip.dart';

/// The single shortcut chip row on Home. Replaces the previous two stacked
/// rows (library chips + tools chips) so the screen has one browse strip.
/// [online] swaps the library shortcuts for streaming ones.
class QuickDiscoveryHeader extends StatelessWidget {
  final bool online;
  final bool showYtm;
  final VoidCallback onMore;

  const QuickDiscoveryHeader({
    super.key,
    required this.onMore,
    this.online = false,
    this.showYtm = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = <({IconData icon, String label, VoidCallback onTap})>[
      if (online) ...[
        (
          icon: Icons.explore_rounded,
          label: context.l10n.ytmExplore,
          onTap: () => context.push('/ytm-explore'),
        ),
        (
          icon: Icons.downloading_rounded,
          label: context.l10n.downloadsTitle,
          onTap: () => context.push('/downloads'),
        ),
      ] else ...[
        (
          icon: Icons.person_rounded,
          label: context.l10n.artists,
          onTap: () => context.push('/library?tab=artists'),
        ),
        (
          icon: Icons.album_rounded,
          label: context.l10n.albums,
          onTap: () => context.push('/library?tab=albums'),
        ),
        (
          icon: Icons.folder_rounded,
          label: context.l10n.folders,
          onTap: () => context.push('/library?tab=folders'),
        ),
        (
          icon: Icons.calendar_month_rounded,
          label: context.l10n.decades,
          onTap: () => context.push('/year'),
        ),
        if (showYtm)
          (
            icon: Icons.downloading_rounded,
            label: context.l10n.downloadsTitle,
            onTap: () => context.push('/downloads'),
          ),
      ],
      (
        icon: Icons.radio_rounded,
        label: context.l10n.radioTitle,
        onTap: () => context.push('/radio'),
      ),
      (
        icon: Icons.queue_music_rounded,
        label: context.l10n.queue,
        onTap: () => context.push('/queue'),
      ),
    ];

    return SizedBox(
      height: 48.0,
      child: Row(
        children: [
          Expanded(
            child: PulsrScrollEdgeFade(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsetsDirectional.only(
                  start: Adaptive.pagePadding(context),
                  end: AppSpacing.sm,
                ),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.s8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return DiscoveryChip(
                    icon: item.icon,
                    label: item.label,
                    iconColor: p.accent,
                    onTap: item.onTap,
                  );
                },
              ),
            ),
          ),
          // "More" stays pinned so the overflow tools are always one tap away
          // instead of sitting at the end of a hidden horizontal scroll.
          Padding(
            padding: EdgeInsetsDirectional.only(
              end: Adaptive.pagePadding(context),
            ),
            child: SizedBox(
              height: 48.0,
              child: DiscoveryChip(
                icon: Icons.apps_rounded,
                label: context.l10n.browseMoreTools,
                iconColor: p.textSecondary,
                onTap: onMore,
                compact: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
