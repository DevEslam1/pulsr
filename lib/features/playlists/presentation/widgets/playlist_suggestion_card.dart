import 'package:flutter/material.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/playlist_suggestions_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';

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
    return Semantics(
      button: true,
      label: suggestion.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.r16All,
        child: Container(
          width: 230,
          padding: const EdgeInsets.all(AppSpacing.s14),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: AppRadii.r16All,
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: p.accent, size: 18),
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
                    color: p.textSecondary, fontSize: AppFontSize.label),
              ),
              const Spacer(),
              Text(
                context.l10n.tapToCreate(suggestion.songs.length),
                style: TextStyle(
                    color: p.textTertiary, fontSize: AppFontSize.caption),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
