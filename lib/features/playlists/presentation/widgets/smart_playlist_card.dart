// lib/features/playlists/presentation/widgets/smart_playlist_card.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/db/app_database.dart';

/// A smart playlist card matching the [PlaylistSuggestionCard] aesthetic for the
/// horizontal rail on [PlaylistsScreen].
class SmartPlaylistCard extends StatelessWidget {
  final PlaylistsTableData playlist;
  final int songCount;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final List<PopupMenuEntry<String>> Function(BuildContext)? menuItems;
  final void Function(String)? onMenuSelected;

  const SmartPlaylistCard({
    super.key,
    required this.playlist,
    required this.songCount,
    required this.onTap,
    this.isSelected = false,
    this.onLongPress,
    this.menuItems,
    this.onMenuSelected,
  });

  static String _describePlaylist(BuildContext context, String name) {
    final lower = name.toLowerCase();
    if (lower.contains('recently added')) {
      return 'Tracks added to your library in the last 30 days';
    } else if (lower.contains('most played')) {
      return 'Your top most-played tracks on repeat';
    } else if (lower.contains('recently played')) {
      return 'Your recent playback listening history';
    } else if (lower.contains('long track')) {
      return 'Long tracks and extended mixes over 5 minutes';
    } else if (lower.contains('forgotten')) {
      return 'Tracks you loved but haven\'t listened to recently';
    } else if (lower.contains('top rated') || lower.contains('star')) {
      return 'Your highest rated and starred favorite tracks';
    } else if (lower.contains('chill')) {
      return 'Relaxing, mellow tracks for unwinding';
    } else if (lower.contains('workout') || lower.contains('energy')) {
      return 'High-energy tracks to keep your workout moving';
    } else if (lower.contains('lossless') ||
        lower.contains('hi-res') ||
        lower.contains('audiophile')) {
      return 'High-fidelity lossless tracks in your library';
    } else if (lower.contains('90s')) {
      return 'Classic tracks and nostalgia from the 1990s';
    }
    return 'Dynamic auto-updating smart playlist based on rules';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final description = _describePlaylist(context, playlist.name);

    return Semantics(
      button: true,
      selected: isSelected,
      label: playlist.name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          onLongPress: onLongPress,
          borderRadius: AppRadii.r18All,
          child: AnimatedContainer(
            duration: context.motion(PulsrMotion.state),
            width: 244,
            padding: const EdgeInsets.all(AppSpacing.s14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    p.accent.withValues(alpha: p.isDark ? 0.10 : 0.06),
                    p.surfaceContainer,
                  ),
                  p.surfaceContainer,
                ],
              ),
              borderRadius: AppRadii.r18All,
              border: Border.all(
                color: isSelected ? p.accent : p.hairline,
                width: isSelected ? 2.0 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: p.glow.withValues(alpha: 0.32),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.14),
                        borderRadius: AppRadii.r8All,
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: p.accent,
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? p.accent : p.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: AppFontSize.bodySmall,
                        ),
                      ),
                    ),
                    if (menuItems != null)
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 18,
                          color: p.textTertiary,
                        ),
                        onSelected: onMenuSelected,
                        itemBuilder: menuItems!,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.label,
                    height: 1.3,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s6,
                        vertical: AppSpacing.s2,
                      ),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.12),
                        borderRadius: AppRadii.r6All,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 10,
                            color: p.accent,
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            context.l10n.browseSmart.toUpperCase(),
                            style: TextStyle(
                              color: p.accent,
                              fontSize: AppFontSize.micro,
                              fontWeight: FontWeight.w800,
                              letterSpacing: AppTracking.wide,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        context.l10n.tracksCount(songCount),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.play_circle_filled_rounded,
                      size: 20,
                      color: p.accent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

