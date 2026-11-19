import 'package:material_ui/material_ui.dart';

import '../constants/app_radii.dart';
import '../theme/aura_theme.dart';

/// The single Hero tag for the Now Playing *surface* (not the artwork).
///
/// The artwork already has its own tag chain (`nowPlayingArtHeroTag(mode)`);
/// this one carries the card/background so opening the player reads as one
/// object growing out of the mini player rather than a page sliding over it.
const String nowPlayingSurfaceHeroTag = 'np_surface';

/// Flight shuttle for [nowPlayingSurfaceHeroTag].
///
/// The shuttle deliberately paints only the rounded surface — not the source or
/// destination child. Flying a whole screen through the overlay is expensive
/// and produces a snapshot that cannot react to theme changes; a plain rounded
/// box that un-rounds as it grows gives the continuity cue at a fraction of the
/// cost, while the artwork flies separately on top.
Widget nowPlayingSurfaceFlightShuttleBuilder(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutCubic,
  );
  return AnimatedBuilder(
    animation: curved,
    builder: (context, _) {
      final t = curved.value.clamp(0.0, 1.0);
      final palette = context.palette;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadii.r24 * (1.0 - t)),
        ),
      );
    },
  );
}
