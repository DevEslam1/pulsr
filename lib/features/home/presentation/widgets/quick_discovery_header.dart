import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:pulsr/core/constants/app_colors.dart';
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
    final items = <({IconData icon, String label, Color color, VoidCallback onTap})>[
      if (online) ...[
        (
          icon: Icons.explore_rounded,
          label: context.l10n.ytmExplore,
          color: p.primary,
          onTap: () => context.push('/ytm-explore'),
        ),
        (
          icon: Icons.downloading_rounded,
          label: context.l10n.downloadsTitle,
          color: p.success,
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
          color: p.error,
          onTap: () => context.push('/library?tab=albums'),
        ),
        (
          icon: Icons.folder_rounded,
          label: context.l10n.folders,
          color: AppColors.mint,
          onTap: () => context.push('/library?tab=folders'),
        ),
        (
          icon: Icons.calendar_month_rounded,
          label: context.l10n.decades,
          color: p.warning,
          onTap: () => context.push('/year'),
        ),
        (
          icon: Icons.history_rounded,
          label: context.l10n.recentlyAdded,
          color: p.info,
          onTap: () => context.push('/recents'),
        ),
        if (showYtm)
          (
            icon: Icons.downloading_rounded,
            label: context.l10n.downloadsTitle,
            color: p.success,
            onTap: () => context.push('/downloads'),
          ),
      ],
      (
        icon: Icons.radio_rounded,
        label: context.l10n.radioTitle,
        color: p.warning,
        onTap: () => context.push('/radio'),
      ),
      (
        icon: Icons.queue_music_rounded,
        label: context.l10n.queue,
        color: p.info,
        onTap: () => context.push('/queue'),
      ),
      (
        icon: Icons.apps_rounded,
        label: context.l10n.browseMoreTools,
        color: p.textSecondary,
        onTap: onMore,
      ),
    ];

    return SizedBox(
      height: 48.0,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: Adaptive.pagePadding(context),
        ),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = items[index];
          return DiscoveryChip(
            icon: item.icon,
            label: item.label,
            iconColor: item.color,
            onTap: item.onTap,
          );
        },
      ),
    );
  }
}
