// lib/features/player/presentation/themes/player_artwork_semantics.dart
//
// Cover-art accessibility for the now-playing themes.
//
// Extracted from player_theme_chrome.dart (which is ratcheted at 70,368
// logical bytes) so the shared chrome keeps only the visual/structural widgets
// that every theme composes. Re-exported from the chrome library, so themes
// keep importing a single file.
import 'package:material_ui/material_ui.dart';

import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/db/app_database.dart';

/// Screen-reader label for the cover art shown by the now-playing themes.
///
/// Composed from the track metadata (no dedicated ARB key exists for it) so
/// assistive tech announces which artwork is on screen, and falls back to the
/// generic "Album artwork" string when there is no title to describe.
String playerArtworkSemanticLabel(
  BuildContext context,
  SongsTableData? song,
) {
  final title = (song?.title ?? '').trim();
  if (title.isEmpty) return context.l10n.albumArtworkLabel;
  final artist = (song?.artist ?? '').trim();
  final description = artist.isEmpty ? title : '$title — $artist';
  return '$description, ${context.l10n.albumArtworkLabel}';
}

/// Wraps a rendered cover in an `image` semantics node labelled with the
/// current track, so screen readers never meet an unlabelled artwork node.
///
/// [container] keeps the node separate from the surrounding stage gestures;
/// [excludeSemantics] drops the generic label [CachedArtwork] publishes so the
/// track-specific label is the only one announced.
class PlayerArtworkSemantics extends StatelessWidget {
  final SongsTableData? song;
  final Widget child;

  const PlayerArtworkSemantics({
    super.key,
    required this.song,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      image: true,
      excludeSemantics: true,
      label: playerArtworkSemanticLabel(context, song),
      child: child,
    );
  }
}
