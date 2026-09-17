import 'package:flutter/material.dart';

abstract class AppRadii {
  static const double tile = 14.0;
  static const double card = 18.0;
  static const double button = 14.0;
  static const double artwork = 20.0;
  static const double bottomSheet = 28.0;
  static const double chip = 10.0;
  static const double miniPlayer = 24.0;
  static const double dialog = 26.0;

  // ── Numeric scale ───────────────────────────────────────────────────────
  // Value-named tokens so every hand-tuned radius in the app can reference a
  // single source instead of repeating a literal. Prefer the semantic tokens
  // above for new work.
  static const double r2 = 2.0;
  static const double r4 = 4.0;
  static const double r6 = 6.0;
  static const double r8 = 8.0;
  static const double r10 = 10.0;
  static const double r12 = 12.0;
  static const double r14 = 14.0;
  static const double r16 = 16.0;
  static const double r18 = 18.0;
  static const double r20 = 20.0;
  static const double r22 = 22.0;
  static const double r24 = 24.0;
  static const double r28 = 28.0;
  static const double r32 = 32.0;

  static const BorderRadius tileRadius =
      BorderRadius.all(Radius.circular(tile));
  static const BorderRadius cardRadius =
      BorderRadius.all(Radius.circular(card));
  static const BorderRadius buttonRadius =
      BorderRadius.all(Radius.circular(button));
  static const BorderRadius artworkRadius =
      BorderRadius.all(Radius.circular(artwork));
  static const BorderRadius bottomSheetRadius =
      BorderRadius.vertical(top: Radius.circular(bottomSheet));
  static const BorderRadius chipRadius =
      BorderRadius.all(Radius.circular(chip));
  static const BorderRadius miniPlayerRadius =
      BorderRadius.all(Radius.circular(miniPlayer));
  static const BorderRadius dialogRadius =
      BorderRadius.all(Radius.circular(dialog));
  static const BorderRadius full =
      BorderRadius.all(Radius.circular(999.0));

  // ── Continuous Curvature / Squircles (iOS HIG) ──────────────────────────
  /// Multiplier to match visual curvature of continuous superellipses to circular radii.
  static const double squircleMultiplier = 2.2;

  static ShapeBorder squircle(double radius, {BorderSide side = BorderSide.none}) =>
      ContinuousRectangleBorder(
        borderRadius: BorderRadius.circular(radius * squircleMultiplier),
        side: side,
      );

  static const ContinuousRectangleBorder squircleTile =
      ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(tile * squircleMultiplier)),
  );

  static const ContinuousRectangleBorder squircleCard =
      ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(card * squircleMultiplier)),
  );

  static const ContinuousRectangleBorder squircleArtwork =
      ContinuousRectangleBorder(
    borderRadius:
        BorderRadius.all(Radius.circular(artwork * squircleMultiplier)),
  );

  static const ContinuousRectangleBorder squircleMiniPlayer =
      ContinuousRectangleBorder(
    borderRadius:
        BorderRadius.all(Radius.circular(miniPlayer * squircleMultiplier)),
  );

  static const ContinuousRectangleBorder squircleDialog =
      ContinuousRectangleBorder(
    borderRadius:
        BorderRadius.all(Radius.circular(dialog * squircleMultiplier)),
  );

  static const ContinuousRectangleBorder squircleBottomSheet =
      ContinuousRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(bottomSheet * squircleMultiplier),
    ),
  );

  static const ContinuousRectangleBorder squirclePill =
      ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(999.0)),
  );
}
