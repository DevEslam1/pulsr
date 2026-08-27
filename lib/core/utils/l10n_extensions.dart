// lib/core/utils/l10n_extensions.dart
import 'package:flutter/widgets.dart';
import '../../l10n/generated/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? lookupAppLocalizations(const Locale('en'));
  AppLocalizations? get l10nOrNull => AppLocalizations.of(this);
}
