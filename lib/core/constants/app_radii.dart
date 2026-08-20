import 'package:flutter/material.dart';

abstract class AppRadii {
  static const double tile = 14.0;
  static const double card = 18.0;
  static const double button = 14.0;
  static const double artwork = 20.0;
  static const double bottomSheet = 28.0;
  static const double chip = 10.0;
  static const double miniPlayer = 20.0;
  static const double dialog = 26.0;

  static const BorderRadius tileRadius = BorderRadius.all(Radius.circular(tile));
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(card));
  static const BorderRadius buttonRadius = BorderRadius.all(Radius.circular(button));
  static const BorderRadius artworkRadius = BorderRadius.all(Radius.circular(artwork));
  static const BorderRadius bottomSheetRadius = BorderRadius.vertical(top: Radius.circular(bottomSheet));
  static const BorderRadius chipRadius = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius miniPlayerRadius = BorderRadius.all(Radius.circular(miniPlayer));
  static const BorderRadius dialogRadius = BorderRadius.all(Radius.circular(dialog));
}
