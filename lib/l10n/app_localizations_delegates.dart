// Localization delegates wired to the same material_ui/cupertino_ui widget
// libraries the app renders with. The generated delegate list still points at
// the deprecated `flutter_localizations` delegates, whose
// `MaterialLocalizations` type does not match `material_ui`; using them makes
// non-English locales fail at runtime.
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:material_ui/material_ui.dart';

import 'generated/app_localizations.dart';

const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];
