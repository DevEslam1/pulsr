// lib/features/shell/presentation/widgets/shortcut_help_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';

/// Modal bottom sheet listing all desktop and tablet keyboard shortcut bindings.
///
/// Follows the same aesthetic list pattern as [DockStylePickerSheet].
class ShortcutHelpSheet extends StatelessWidget {
  const ShortcutHelpSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const ShortcutHelpSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;

    final shortcuts = <_ShortcutItemData>[
      _ShortcutItemData(
        keyLabel: 'Space',
        title: l10n.shortcutPlayPause,
        description: l10n.shortcutPlayPauseDesc,
        icon: Icons.play_arrow_rounded,
      ),
      _ShortcutItemData(
        keyLabel: '→',
        title: l10n.shortcutSeekForward,
        description: l10n.shortcutSeekForwardDesc,
        icon: Icons.forward_10_rounded,
      ),
      _ShortcutItemData(
        keyLabel: '←',
        title: l10n.shortcutSeekBackward,
        description: l10n.shortcutSeekBackwardDesc,
        icon: Icons.replay_10_rounded,
      ),
      _ShortcutItemData(
        keyLabel: '↑',
        title: l10n.shortcutVolumeUp,
        description: l10n.shortcutVolumeUpDesc,
        icon: Icons.volume_up_rounded,
      ),
      _ShortcutItemData(
        keyLabel: '↓',
        title: l10n.shortcutVolumeDown,
        description: l10n.shortcutVolumeDownDesc,
        icon: Icons.volume_down_rounded,
      ),
      _ShortcutItemData(
        keyLabel: 'N',
        title: l10n.shortcutNext,
        description: l10n.shortcutNextDesc,
        icon: Icons.skip_next_rounded,
      ),
      _ShortcutItemData(
        keyLabel: 'P',
        title: l10n.shortcutPrevious,
        description: l10n.shortcutPreviousDesc,
        icon: Icons.skip_previous_rounded,
      ),
      _ShortcutItemData(
        keyLabel: 'F',
        title: l10n.shortcutFavorite,
        description: l10n.shortcutFavoriteDesc,
        icon: Icons.favorite_rounded,
      ),
      _ShortcutItemData(
        keyLabel: 'M',
        title: l10n.shortcutMute,
        description: l10n.shortcutMuteDesc,
        icon: Icons.volume_off_rounded,
      ),
      _ShortcutItemData(
        keyLabel: 'L',
        title: l10n.shortcutLyrics,
        description: l10n.shortcutLyricsDesc,
        icon: Icons.lyrics_rounded,
      ),
      _ShortcutItemData(
        keyLabel: 'Q',
        title: l10n.shortcutQueue,
        description: l10n.shortcutQueueDesc,
        icon: Icons.queue_music_rounded,
      ),
      _ShortcutItemData(
        keyLabel: '?',
        title: l10n.shortcutHelp,
        description: l10n.shortcutHelpDesc,
        icon: Icons.help_outline_rounded,
      ),
    ];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.shortcutHelpTitle,
                style: TextStyle(
                  fontSize: AppFontSize.titleLarge,
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                l10n.shortcutHelpSubtitle,
                style: TextStyle(
                  fontSize: AppFontSize.bodySmall,
                  fontWeight: FontWeight.w500,
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: shortcuts.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (context, index) {
                    final item = shortcuts[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.s10,
                      ),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer.withValues(alpha: 0.6),
                        borderRadius: AppRadii.r14All,
                        border: Border.all(color: p.hairline),
                      ),
                      child: Row(
                        children: [
                          Container(
                            constraints: const BoxConstraints(minWidth: 38),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s8,
                              vertical: AppSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: p.surfaceContainerHigh,
                              borderRadius: AppRadii.r8All,
                              border: Border.all(
                                color: p.hairline.withValues(alpha: 0.8),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              item.keyLabel,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w800,
                                color: p.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: TextStyle(
                                    fontSize: AppFontSize.body,
                                    fontWeight: FontWeight.w700,
                                    color: p.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.description,
                                  style: TextStyle(
                                    fontSize: AppFontSize.label,
                                    fontWeight: FontWeight.w500,
                                    color: p.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Icon(item.icon, size: 20, color: p.textTertiary),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutItemData {
  final String keyLabel;
  final String title;
  final String description;
  final IconData icon;

  const _ShortcutItemData({
    required this.keyLabel,
    required this.title,
    required this.description,
    required this.icon,
  });
}
