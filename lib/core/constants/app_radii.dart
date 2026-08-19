// lib/core/constants/app_radii.dart
import 'package:flutter/material.dart';

abstract class AppRadii {
  static const double card = 16.0;
  static const double button = 14.0;
  static const double bottomSheet = 24.0;
  static const double chip = 10.0;
  static const double miniPlayer = 18.0;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(card));
  static const BorderRadius buttonRadius = BorderRadius.all(Radius.circular(button));
  static const BorderRadius bottomSheetRadius = BorderRadius.vertical(top: Radius.circular(bottomSheet));
  static const BorderRadius chipRadius = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius miniPlayerRadius = BorderRadius.all(Radius.circular(miniPlayer));
}
