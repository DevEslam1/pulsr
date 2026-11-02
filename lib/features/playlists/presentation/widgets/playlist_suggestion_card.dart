// lib/features/playlists/presentation/widgets/playlist_suggestion_card.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/playlist_suggestions_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';

/// One AI/heuristic playlist suggestion shown in the horizontal rail.
///
/// Extracted from `playlists_screen.dart` to keep that screen under the
/// fat-file ratchet; the card is self-contained and has no screen state.
class PlaylistSuggestionCard extends StatelessWidget {
  final PlaylistSuggestion suggestion;
  final VoidCallback onTap;

  const PlaylistSuggestionCard({
    super.key,
    required this.suggestion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final previewSongs = suggestion.songs.take(3).toList();

    return Semantics(
      button: true,
      label: suggestion.title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: AppRadii.r18All,
          child: Container(
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
              border: Border.all(color: p.hairline),
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
                        suggestion.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: AppFontSize.bodySmall,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  suggestion.description,
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
                    if (previewSongs.isNotEmpty) ...[
                      SizedBox(
                        width: 24.0 + (previewSongs.length - 1) * 14.0,
                        height: 24,
                        child: Stack(
                          children: [
                            for (var i = 0; i < previewSongs.length; i++)
                              PositionedDirectional(
                                start: i * 14.0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: p.surfaceContainer,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: CachedArtwork(
                                    id: previewSongs[i].id,
                                    albumId: previewSongs[i].albumId,
                                    remoteUrl:
                                        previewSongs[i].remoteArtworkUrl ??
                                            previewSongs[i].artworkUri,
                                    type: ArtworkType.AUDIO,
                                    size: 21,
                                    borderRadius: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Expanded(
                      child: Text(
                        context.l10n.tapToCreate(suggestion.songs.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.accent,
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.add_circle_rounded,
                      size: 18,
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
